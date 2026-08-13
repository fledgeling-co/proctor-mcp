// ProctorUnlock — a SecurityAgent authorization mechanism.
//
// This code runs inside the system's authorization host (a platform binary) as
// part of evaluating `system.login.screensaver` — the right macOS checks when
// someone unlocks a locked session. Its single mechanism, "allow", answers one
// question: is the Proctor agent currently holding an authorized unlock turn?
// If so it grants this branch of the right; otherwise it denies, and because
// the rule is k-of-n=1 with `use-login-window-ui` still present, macOS falls
// through to the normal password/Touch ID prompt. Nobody is ever locked out by
// this mechanism failing — the worst case is the ordinary login screen.
//
// The trust boundary is the socket, so it is checked on both sides:
//   - This mechanism verifies the broker it connected to is the real Proctor
//     agent (signing id app.fledgeling.procter, team H4HGFL52W7), so a rogue
//     local process squatting the path cannot authorize an unlock.
//   - The broker verifies its peer is a platform binary anchored to Apple,
//     which is what this code is once loaded into the authorization host.
//
// Everything here is fail-closed and time-bounded. A missing socket, a slow
// broker, a peer that fails the code requirement, any error at all — all return
// Deny within a hard deadline, so a normal human unlock is never delayed and
// never blocked. The 17.5-minute login stall that OpenAI's equivalent produced
// came from a mechanism that sat in the path without a deadline; this one has
// one.

#include <Security/AuthorizationPlugin.h>
#include <Security/SecCode.h>
#include <Security/SecRequirement.h>
#include <CoreFoundation/CoreFoundation.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/errno.h>
#include <sys/time.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <os/log.h>

// Kept in step with the agent's broker. If either end changes, both change.
#define PU_SOCKET_PATH   "/tmp/app.fledgeling.procter/unlock.sock"
#define PU_BROKER_REQ    "identifier \"app.fledgeling.procter\" and anchor apple generic and certificate leaf[subject.OU] = H4HGFL52W7"
#define PU_DEADLINE_MS   600      // hard cap on the whole handshake
#define PU_REQUEST       "PROCTOR-UNLOCK-QUERY\n"
#define PU_REPLY_ALLOW   "ALLOW"

static os_log_t pu_log(void) {
    static os_log_t l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ l = os_log_create("app.fledgeling.procter", "unlock"); });
    return l;
}

// One mechanism instance. The engine hands back whatever MechanismCreate stores.
typedef struct {
    const AuthorizationCallbacks *callbacks;
    AuthorizationEngineRef engine;
} MechanismContext;

// LOCAL_PEERTOKEN gives us the connected peer's audit token, which SecCode can
// turn into a code object we can hold to a requirement. This is the whole basis
// of trusting the other end of the socket.
static Boolean peer_satisfies(int fd, const char *requirementText) {
    audit_token_t token;
    socklen_t len = sizeof(token);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) != 0 || len != sizeof(token)) {
        os_log_error(pu_log(), "unlock: cannot read peer audit token errno=%d", errno);
        return false;
    }
    CFDataRef tokenData = CFDataCreate(NULL, (const UInt8 *)&token, sizeof(token));
    if (!tokenData) return false;
    const void *keys[] = { kSecGuestAttributeAudit };
    const void *vals[] = { tokenData };
    CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, vals, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(tokenData);
    if (!attrs) return false;

    SecCodeRef code = NULL;
    OSStatus st = SecCodeCopyGuestWithAttributes(NULL, attrs, kSecCSDefaultFlags, &code);
    CFRelease(attrs);
    if (st != errSecSuccess || !code) {
        os_log_error(pu_log(), "unlock: cannot make peer code object status=%d", (int)st);
        if (code) CFRelease(code);
        return false;
    }
    CFStringRef reqStr = CFStringCreateWithCString(NULL, requirementText, kCFStringEncodingUTF8);
    SecRequirementRef req = NULL;
    st = SecRequirementCreateWithString(reqStr, kSecCSDefaultFlags, &req);
    if (reqStr) CFRelease(reqStr);
    if (st != errSecSuccess || !req) {
        os_log_error(pu_log(), "unlock: bad requirement status=%d", (int)st);
        if (code) CFRelease(code);
        if (req) CFRelease(req);
        return false;
    }
    st = SecCodeCheckValidity(code, kSecCSDefaultFlags, req);
    CFRelease(code);
    CFRelease(req);
    if (st != errSecSuccess) {
        os_log_error(pu_log(), "unlock: peer failed the Proctor requirement status=%d", (int)st);
        return false;
    }
    return true;
}

// Ask the broker whether an unlock turn is authorized right now. Returns true
// only on a verified peer AND an explicit allow reply, within the deadline.
// Every other path returns false — fail-closed by construction.
static Boolean broker_authorizes_unlock(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return false;

    // Bound the whole exchange. Non-blocking connect guarded by select, then
    // send/recv timeouts, so no step can hang the login path.
    struct timeval tv = { .tv_sec = 0, .tv_usec = PU_DEADLINE_MS * 1000 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, PU_SOCKET_PATH, sizeof(addr.sun_path) - 1);

    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (rc != 0 && errno == EINPROGRESS) {
        fd_set wset; FD_ZERO(&wset); FD_SET(fd, &wset);
        struct timeval ctv = { .tv_sec = 0, .tv_usec = PU_DEADLINE_MS * 1000 };
        if (select(fd + 1, NULL, &wset, NULL, &ctv) <= 0) { close(fd); return false; }
        int soerr = 0; socklen_t sl = sizeof(soerr);
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
        if (soerr != 0) { close(fd); return false; }
    } else if (rc != 0) {
        close(fd); return false;
    }
    fcntl(fd, F_SETFL, flags); // back to blocking, now bounded by SO_*TIMEO

    if (!peer_satisfies(fd, PU_BROKER_REQ)) { close(fd); return false; }

    if (send(fd, PU_REQUEST, strlen(PU_REQUEST), 0) < 0) { close(fd); return false; }

    char buf[64];
    ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
    close(fd);
    if (n <= 0) return false;
    buf[n] = '\0';
    Boolean allow = (strncmp(buf, PU_REPLY_ALLOW, strlen(PU_REPLY_ALLOW)) == 0);
    os_log(pu_log(), "unlock: broker reply=%{public}s -> %{public}s", buf, allow ? "ALLOW" : "DENY");
    return allow;
}

// ---- AuthorizationPlugin ABI ----

static OSStatus MechanismCreate(AuthorizationPluginRef inPlugin,
                                AuthorizationEngineRef inEngine,
                                AuthorizationMechanismId mechanismId,
                                AuthorizationMechanismRef *outMechanism) {
    (void)inPlugin; (void)mechanismId;
    MechanismContext *ctx = calloc(1, sizeof(MechanismContext));
    if (!ctx) return errAuthorizationInternal;
    ctx->callbacks = *(const AuthorizationCallbacks **)inPlugin;
    ctx->engine = inEngine;
    *outMechanism = ctx;
    return errAuthorizationSuccess;
}

static OSStatus MechanismInvoke(AuthorizationMechanismRef inMechanism) {
    MechanismContext *ctx = (MechanismContext *)inMechanism;
    AuthorizationResult result =
        broker_authorizes_unlock() ? kAuthorizationResultAllow : kAuthorizationResultDeny;
    // Always return success from Invoke itself; the *result* is how we vote.
    // Undefined/failure here could wedge the evaluation, so we never do that.
    return ctx->callbacks->SetResult(ctx->engine, result);
}

static OSStatus MechanismDeactivate(AuthorizationMechanismRef inMechanism) {
    MechanismContext *ctx = (MechanismContext *)inMechanism;
    return ctx->callbacks->DidDeactivate(ctx->engine);
}

static OSStatus MechanismDestroy(AuthorizationMechanismRef inMechanism) {
    free(inMechanism);
    return errAuthorizationSuccess;
}

static OSStatus PluginDestroy(AuthorizationPluginRef inPlugin) {
    free(inPlugin);
    return errAuthorizationSuccess;
}

// The engine keeps the callbacks pointer as the first word of the plugin object
// so MechanismCreate can recover it (see the cast above).
static AuthorizationPluginInterface gInterface = {
    kAuthorizationPluginInterfaceVersion,
    PluginDestroy,
    MechanismCreate,
    MechanismInvoke,
    MechanismDeactivate,
    MechanismDestroy,
};

OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks,
                                   AuthorizationPluginRef *outPlugin,
                                   const AuthorizationPluginInterface **outPluginInterface) {
    const AuthorizationCallbacks **plugin = malloc(sizeof(AuthorizationCallbacks *));
    if (!plugin) return errAuthorizationInternal;
    *plugin = callbacks;
    *outPlugin = plugin;
    *outPluginInterface = &gInterface;
    return errAuthorizationSuccess;
}
