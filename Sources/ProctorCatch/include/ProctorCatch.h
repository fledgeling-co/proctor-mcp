#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Run `body`, converting an Objective-C exception into a returned description.
///
/// Swift has no way to catch an `NSException`, and AppKit still raises them: a
/// drawing pass that hits one aborts the process. That is the wrong failure mode
/// for the run HUD, which is a supervision surface — an annotation must not be
/// able to kill the thing it annotates, and taking the agent down with it also
/// takes down the run and the MCP server every connected session is using.
///
/// Returns nil when `body` completed. Otherwise the returned string carries the
/// exception's name, reason and call stack, so the next occurrence identifies
/// itself instead of leaving only a stack in a crash report.
///
/// This catches exceptions, which is all it claims. A memory fault or a Swift
/// runtime trap is not an exception and still ends the process, correctly.
NSString *_Nullable ProctorCatchNSException(void(NS_NOESCAPE ^ _Nonnull body)(void));

NS_ASSUME_NONNULL_END
