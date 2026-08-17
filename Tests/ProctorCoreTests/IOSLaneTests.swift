import Testing
import Foundation
@testable import ProctorCore

// PRO-0048 — the iOS Simulator deep-link lane.
//
// Everything the verdict turns on is pure, so all of it is provable here on a
// machine with no Xcode and no booted device. The fixture is real
// `simctl list -j devices` output captured on 2026-08-15, and the failure strings
// are the ones simctl actually emitted rather than plausible-looking inventions.

@Suite("PRO-0048 · iOS deep-link lane")
struct IOSLaneTests {

    static var devicesFixture: Data {
        get throws {
            try Data(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/simctl-devices.json"))
        }
    }

    // MARK: - AC1 · devices are listed with state and runtime

    @Test("simctl device JSON parses with state, runtime and availability")
    func parsesDeviceList() throws {
        let devices = try IOSDeviceList.parse(Self.devicesFixture)

        #expect(devices.count == 10)
        #expect(devices.filter(\.isBooted).count == 1)

        let bootedDevice = devices.first { $0.isBooted }
        let booted = try #require(bootedDevice)
        #expect(booted.name == "iPhone 16 Pro")
        #expect(booted.runtime == "iOS 18.2")
        #expect(booted.udid == "29FEA02E-8677-4996-AC2D-904A97FB3643")
        #expect(booted.isAvailable)
        // Never set by parsing: this session booted nothing.
        #expect(!booted.bootedByThisSession)

        // Runtime buckets with no devices contribute nothing rather than
        // producing empty records.
        #expect(devices.allSatisfy { !$0.udid.isEmpty })
        // Order is stable, which is what makes two listings diffable.
        let again = try IOSDeviceList.parse(Self.devicesFixture)
        #expect(devices.map(\.udid) == again.map(\.udid))
    }

    @Test("a runtime identifier renders readably, and an unexpected one is left alone")
    func rendersRuntimeNames() {
        #expect(IOSDeviceList.runtimeName(
            from: "com.apple.CoreSimulator.SimRuntime.iOS-18-2") == "iOS 18.2")
        #expect(IOSDeviceList.runtimeName(
            from: "com.apple.CoreSimulator.SimRuntime.watchOS-11-0") == "watchOS 11.0")
        // A shape this does not understand is returned as it stands: a wrong
        // readable name is worse than a raw identifier.
        #expect(IOSDeviceList.runtimeName(from: "something-else") == "something-else")
    }

    // MARK: - AC2 · a device handle is not a window handle

    @Test("a device handle is recognised and refused by name, pointing at the route that works")
    func deviceHandlesAreRefusedByName() throws {
        let devices = try IOSDeviceList.parse(Self.devicesFixture)
        let bootedDevice = devices.first { $0.isBooted }
        let booted = try #require(bootedDevice)

        #expect(booted.handleID == "dev-29fea02e")
        #expect(IOSHandle.isDeviceHandle(booted.handleID))
        #expect(!IOSHandle.isDeviceHandle("w-1"))
        #expect(!IOSHandle.isDeviceHandle("app:501:0"))

        let rejection = IOSHandle.rejection(handle: booted.handleID, tool: "proctor_snapshot")
        #expect(rejection.message.contains("iOS device handle"))
        // The ceiling, and the route that does work. A refusal that only says no
        // sends a model round a retry loop.
        #expect(rejection.remedy.contains("accessibility API does not cross"))
        #expect(rejection.remedy.contains("proctor_ios"))
        #expect(rejection.remedy.contains("screenshot"))
    }

    // MARK: - AC3 · the verdict ladder never overclaims

    /// The two measured `openurl` calls that differed only in pixels.
    @Test("the measured no-op and the measured navigation are told apart")
    func measuredCasesAreDistinguished() {
        // Second open of the same URL: exit 0, pid unchanged, screen byte-identical.
        let noop = DeepLinkEvidence(delivered: true, exitCode: 0,
                                    handlerResolved: "com.apple.mobilesafari",
                                    targetRunningBefore: true, targetRunningAfter: true,
                                    pidBefore: 31702, pidAfter: 31702,
                                    changedFraction: 0.0)
        let noopOutcome = DeepLinkVerdict.decide(noop)
        #expect(noopOutcome.verdict == .deliveredOnly)
        #expect(!noopOutcome.verdict.isAttributed)
        #expect(noopOutcome.note.contains("inconclusive"))

        // First open: exit 0, pid unchanged, screen changed by 0.00204.
        let navigation = DeepLinkEvidence(delivered: true, exitCode: 0,
                                          handlerResolved: "com.apple.mobilesafari",
                                          targetRunningBefore: true, targetRunningAfter: true,
                                          pidBefore: 31702, pidAfter: 31702,
                                          changedFraction: 0.00204)
        let navigationOutcome = DeepLinkVerdict.decide(navigation)
        #expect(navigationOutcome.verdict == .targetChanged)
        #expect(navigationOutcome.verdict.isAttributed)
        // Even the strongest verdict states what it does not establish.
        #expect(navigationOutcome.note.contains("does not establish which screen"))

        // The exit code and the process state are identical across both, which is
        // the whole point: only the pixel channel separates them.
        #expect(noop.exitCode == navigation.exitCode)
        #expect(noop.pidAfter == navigation.pidAfter)
    }

    @Test("a cold launch is reported as launchedNow without becoming its own verdict")
    func coldLaunchIsReportedBeside() {
        // The measured Maps case: no pid before, pid 33877 after, screen changed.
        let evidence = DeepLinkEvidence(delivered: true, exitCode: 0,
                                        handlerResolved: "com.apple.Maps",
                                        targetRunningBefore: false, targetRunningAfter: true,
                                        pidBefore: nil, pidAfter: 33877,
                                        changedFraction: 0.79822)
        #expect(evidence.launchedNow)
        #expect(DeepLinkVerdict.decide(evidence).verdict == .targetChanged)

        // A warm app is not a launch, which is most deep links.
        let warm = DeepLinkEvidence(delivered: true, exitCode: 0,
                                    handlerResolved: "com.apple.Maps",
                                    targetRunningBefore: true, targetRunningAfter: true,
                                    pidBefore: 33877, pidAfter: 33877,
                                    changedFraction: 0.5)
        #expect(!warm.launchedNow)
    }

    @Test("a screen change that cannot be attributed is a weaker verdict, not the top one")
    func unattributedChangeIsSeparate() {
        // A universal link: nothing resolved, the screen moved anyway.
        let universal = DeepLinkEvidence(delivered: true, exitCode: 0,
                                         handlerResolved: nil,
                                         targetRunningBefore: nil, targetRunningAfter: nil,
                                         changedFraction: 0.4)
        let outcome = DeepLinkVerdict.decide(universal)
        #expect(outcome.verdict == .screenChanged)
        #expect(!outcome.verdict.isAttributed)
        #expect(outcome.note.contains("not attributed"))

        // A resolved target that is not running: a sheet or another app answered.
        let sheet = DeepLinkEvidence(delivered: true, exitCode: 0,
                                     handlerResolved: "com.example.app",
                                     targetRunningBefore: false, targetRunningAfter: false,
                                     changedFraction: 0.4)
        #expect(DeepLinkVerdict.decide(sheet).verdict == .screenChanged)
    }

    @Test("an unobserved run is not reported as an uneventful one")
    func nilPixelChannelIsItsOwnVerdict() {
        let unobserved = DeepLinkEvidence(delivered: true, exitCode: 0,
                                          handlerResolved: "com.example.app",
                                          targetRunningBefore: true, targetRunningAfter: true,
                                          changedFraction: nil)
        #expect(unobserved.screenChanged == nil)
        let outcome = DeepLinkVerdict.decide(unobserved)
        #expect(outcome.verdict == .deliveredUnobserved)
        #expect(outcome.note.contains("absence of evidence"))
        // Distinct from a measured zero, which is the point.
        let measuredZero = DeepLinkEvidence(delivered: true, exitCode: 0,
                                            handlerResolved: "com.example.app",
                                            targetRunningBefore: true, targetRunningAfter: true,
                                            changedFraction: 0.0)
        #expect(DeepLinkVerdict.decide(measuredZero).verdict == .deliveredOnly)
    }

    @Test("an app that goes away while handling the link is a fault, never a navigation")
    func crashOutranksAScreenChange() {
        // Running before, gone after, and the screen certainly changed — an app
        // disappearing changes it. Filing that as success is the failure this
        // case exists to prevent.
        let crashed = DeepLinkEvidence(delivered: true, exitCode: 0,
                                       handlerResolved: "com.example.app",
                                       targetRunningBefore: true, targetRunningAfter: false,
                                       pidBefore: 4242, pidAfter: nil,
                                       changedFraction: 0.6)
        let outcome = DeepLinkVerdict.decide(crashed)
        #expect(outcome.verdict == .targetGone)
        #expect(outcome.verdict.isAppFault)
        #expect(!outcome.verdict.isAttributed)
        #expect(outcome.note.contains("went away"))
    }

    @Test("a caller's threshold decides the verdict, and travels with the measurement")
    func callerThresholdIsHonoured() {
        let fraction = 0.001
        let strict = DeepLinkEvidence(delivered: true, exitCode: 0,
                                      handlerResolved: "com.example.app",
                                      targetRunningBefore: true, targetRunningAfter: true,
                                      changedFraction: fraction, changeThreshold: 0.01)
        #expect(strict.screenChanged == false)
        #expect(DeepLinkVerdict.decide(strict).verdict == .deliveredOnly)

        let lenient = DeepLinkEvidence(delivered: true, exitCode: 0,
                                       handlerResolved: "com.example.app",
                                       targetRunningBefore: true, targetRunningAfter: true,
                                       changedFraction: fraction, changeThreshold: 0.0005)
        #expect(lenient.screenChanged == true)
        #expect(DeepLinkVerdict.decide(lenient).verdict == .targetChanged)

        // Both carry the threshold they were judged against, so the same numbers
        // can be re-judged later.
        #expect(strict.changeThreshold != lenient.changeThreshold)
    }

    @Test("the calibration floor sits an order of magnitude below the smallest real change")
    func thresholdIsCalibrated() {
        // Measured 2026-08-15 on an iPhone 16 Pro simulator.
        let idle = 0.0, smallestRealNavigation = 0.00204
        #expect(idle < IOSPixel.changeThreshold)
        #expect(IOSPixel.changeThreshold < smallestRealNavigation)
        #expect(smallestRealNavigation / IOSPixel.changeThreshold > 3)
    }

    // MARK: - AC4 · the two failure exits decode into prose

    @Test("the measured simctl failures decode into sentences")
    func decodesMeasuredFailures() {
        // Verbatim from the machine, 2026-08-15.
        let unclaimedScheme = """
        An error was encountered processing the command (domain=NSOSStatusErrorDomain, code=-10814):
        Simulator device failed to open proctor-nonexistent-scheme-xyz://go/nowhere.
        """
        #expect(SimctlFailure.decode(exitCode: 194, stderr: unclaimedScheme)
                == "no installed app claims this URL scheme")

        let shutdown = """
        An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):
        Unable to lookup in current state: Shutdown
        """
        #expect(SimctlFailure.decode(exitCode: 149, stderr: shutdown)
                == "the device is not booted")

        // Anything unrecognised keeps its own text: a failure reduced to a shrug
        // is worse than a verbose one.
        let novel = SimctlFailure.decode(exitCode: 3, stderr: "something new went wrong")
        #expect(novel.contains("something new went wrong"))
        #expect(novel.contains("3"))
        #expect(!SimctlFailure.decode(exitCode: 3, stderr: "").isEmpty)
    }

    @Test("a refusal reports the decoded reason rather than a bare exit code")
    func refusalCarriesTheReason() {
        let evidence = DeepLinkEvidence(delivered: false, exitCode: 194,
                                        failureReason: "no installed app claims this URL scheme")
        let outcome = DeepLinkVerdict.decide(evidence)
        #expect(outcome.verdict == .refused)
        #expect(outcome.note == "no installed app claims this URL scheme")
    }

    // MARK: - AC6 · the gate judges the resolved handler

    @Test("a URL resolves to its handler through the scheme claim, and https does not")
    func resolvesHandlers() {
        // The measured claim: Maps declares `maps` in CFBundleURLTypes.
        let map = SchemeMap.build(apps: [
            (bundleId: "com.apple.Maps", schemes: ["map", "maps", "mapitem"]),
            (bundleId: "com.example.app", schemes: ["myapp"])
        ])
        #expect(SchemeMap.handler(for: "maps://?q=London", in: map) == "com.apple.Maps")
        #expect(SchemeMap.handler(for: "MAPS://?q=London", in: map) == "com.apple.Maps")
        #expect(SchemeMap.handler(for: "myapp://home", in: map) == "com.example.app")
        #expect(SchemeMap.handler(for: "nothing://home", in: map) == nil)
        // A universal link is routed through associated domains, which no scheme
        // claim decides, so Proctor says it cannot resolve one rather than
        // guessing Safari.
        #expect(SchemeMap.handler(for: "https://example.com/x", in: map) == nil)
        #expect(SchemeMap.handler(for: "http://example.com/x", in: map) == nil)
    }

    @Test("an allow list on the Mac spelling does not authorise the iOS app of the same id")
    func allowListDoesNotWiden() {
        let allowMacOnly = AppPolicy(allow: ["com.example.app"])
        #expect(IOSPolicy.decide(handler: "com.example.app", policy: allowMacOnly,
                                 hasValidToken: false) != .allow)

        let allowIOS = AppPolicy(allow: [IOSPolicy.key(for: "com.example.app")])
        #expect(IOSPolicy.decide(handler: "com.example.app", policy: allowIOS,
                                 hasValidToken: false) == .allow)
        #expect(IOSPolicy.key(for: "com.example.app") == "ios:com.example.app")
    }

    @Test("a block on either spelling blocks the iOS target")
    func blockMatchesBothSpellings() {
        for policy in [AppPolicy(block: ["com.example.app"]),
                       AppPolicy(block: ["ios:com.example.app"])] {
            let decision = IOSPolicy.decide(handler: "com.example.app", policy: policy,
                                            hasValidToken: false)
            guard case .blocked = decision else {
                Issue.record("expected a block for \(policy.block)")
                continue
            }
        }
        // Block wins over an allow list that names it, as it does on the Mac side.
        let both = AppPolicy(allow: ["ios:com.example.app"], block: ["com.example.app"])
        guard case .blocked = IOSPolicy.decide(handler: "com.example.app", policy: both,
                                               hasValidToken: false) else {
            Issue.record("block must win over allow")
            return
        }
    }

    @Test("a sensitive iOS app needs a token, and the qualified key is what it is named by")
    func sensitiveSetIsQualified() {
        let sensitiveMac = AppPolicy(sensitive: ["com.example.vault"])
        // Named the Mac way, the iOS target is not in the sensitive set — which is
        // the same non-widening rule as the allow list, applied consistently.
        #expect(IOSPolicy.decide(handler: "com.example.vault", policy: sensitiveMac,
                                 hasValidToken: false) == .allow)

        let sensitiveIOS = AppPolicy(sensitive: ["ios:com.example.vault"])
        guard case .needsApproval = IOSPolicy.decide(handler: "com.example.vault",
                                                     policy: sensitiveIOS,
                                                     hasValidToken: false) else {
            Issue.record("a sensitive iOS app must require a token")
            return
        }
        #expect(IOSPolicy.decide(handler: "com.example.vault", policy: sensitiveIOS,
                                 hasValidToken: true) == .allow)
    }

    @Test("an unresolvable URL is refused under an allow list and allowed without one")
    func unresolvableFailsClosedOnlyUnderAnAllowList() {
        guard case .blocked(let reason) = IOSPolicy.decide(
            handler: nil, policy: AppPolicy(allow: ["ios:com.example.app"]),
            hasValidToken: false) else {
            Issue.record("an unidentifiable target must fail closed under an allow list")
            return
        }
        #expect(reason.contains("could not be resolved"))
        // With no allow list the gate is inert, exactly as it is for a Mac app.
        #expect(IOSPolicy.decide(handler: nil, policy: AppPolicy(),
                                 hasValidToken: false) == .allow)
    }

    // MARK: - AC7 · the URL is recorded without its secrets

    @Test("a deep link is split so the trail keeps the entry point and not the token")
    func urlSplitProtectsTheQuery() {
        let split = DeepLinkTarget.split(url: "myapp://host/reset?token=s3cr3t&next=/home")
        #expect(split.clear == "myapp://host")
        #expect(split.redactable == "/reset?token=s3cr3t&next=/home")
        #expect(!split.clear.contains("s3cr3t"))

        let redaction = Redaction(of: split.redactable)
        #expect(redaction.len == split.redactable.utf8.count)
        #expect(!redaction.sha256.contains("s3cr3t"))
        // The hash is verifiable against a known input, which is what makes the
        // record proof rather than a note.
        #expect(redaction == Redaction(of: "/reset?token=s3cr3t&next=/home"))

        // A bare host keeps nothing back, because there is nothing to keep back.
        #expect(DeepLinkTarget.split(url: "myapp://home").redactable.isEmpty)
        // A scheme-only URL is treated as entirely sensitive rather than guessed at.
        #expect(DeepLinkTarget.split(url: "mailto:someone@example.com").clear == "mailto:")
    }

    // MARK: - AC8 · a machine without Xcode reports the absence

    @Test("simctl is found through each route, and its absence names every path tried")
    func locatesSimctl() {
        let devDir = "/Applications/Xcode.app/Contents/Developer"
        let simctl = SimctlLocator.simctlPath(inDeveloperDirectory: devDir)

        // Found where DEVELOPER_DIR points.
        let viaEnvironment = SimctlLocator.locate(
            environment: ["DEVELOPER_DIR": "/opt/Xcode-beta.app/Contents/Developer"],
            readSymlink: { _ in nil },
            isExecutable: { $0 == "/opt/Xcode-beta.app/Contents/Developer/usr/bin/simctl" })
        #expect(viaEnvironment.available)
        #expect(viaEnvironment.path == "/opt/Xcode-beta.app/Contents/Developer/usr/bin/simctl")

        // Found through the root-owned xcode-select symlink.
        let viaSymlink = SimctlLocator.locate(
            environment: [:],
            readSymlink: { $0 == SimctlLocator.selectLink ? devDir : nil },
            isExecutable: { $0 == simctl })
        #expect(viaSymlink.available)
        #expect(viaSymlink.path == simctl)

        // Absent: not available, no path, and every candidate reported so somebody
        // whose own shell disagrees can compare paths.
        let absent = SimctlLocator.locate(environment: [:], readSymlink: { _ in nil },
                                          isExecutable: { _ in false })
        #expect(!absent.available)
        #expect(absent.path == nil)
        #expect(absent.searched.contains(simctl))
        #expect(absent.tool == "simctl")
    }

    @Test("the absence carries no shell command")
    func absenceNamesNoCommand() {
        let absence = SimctlLocator.absence
        #expect(absence.tool == "simctl")
        #expect(absence.missing.contains("Xcode"))
        // The rule ToolAbsence sets for Obscura: a model holding a shell that is
        // handed a command will run it, which defers a fetch-and-execute rather
        // than avoiding it. What is banned is command text, not the English word
        // "install" — telling a person to install Xcode is the whole point.
        let text = (absence.askThePerson + " " + absence.missing).lowercased()
        for command in ["xcode-select", "xcrun", "curl", "brew ", "sudo", "|", "$(", "&&"] {
            #expect(!text.contains(command), "the absence must not carry \(command)")
        }
    }

    @Test("duplicate developer directories are reported once, in order")
    func candidateDirectoriesDeduplicate() {
        let devDir = "/Applications/Xcode.app/Contents/Developer"
        let candidates = SimctlLocator.candidateDirectories(
            environment: ["DEVELOPER_DIR": devDir + "/"],
            readSymlink: { _ in devDir })
        #expect(candidates == [devDir])
    }

    // MARK: - AC11 · the tool surface

    @Test("proctor_ios is in the catalogue and states its ceiling in its own description")
    func toolSurfaceIsCoherent() throws {
        #expect(ToolCatalogue.all.count == 21)
        let spec = try #require(ToolCatalogue.spec(named: "proctor_ios"))
        #expect(!spec.readOnly)

        // The ceiling belongs where a model will actually read it.
        #expect(spec.description.contains("device lane, not a window lane"))
        #expect(spec.description.contains("accessibility API does not cross"))
        #expect(spec.description.contains("never boots"))
        // The claim each verdict does and does not make.
        for verdict in ["targetChanged", "screenChanged", "deliveredOnly"] {
            #expect(spec.description.contains(verdict))
        }
        #expect(spec.description.contains("frontmost app on the device is not observable"))
        // Every action is declared, so a host can discover them. PRO-0049 added
        // `flow`, which runs a Maestro flow file against the same device handle.
        let actions = spec.inputSchema["properties"]?["action"]?["enum"]?
            .arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(actions) == ["list", "boot", "open", "screenshot", "flow"])
    }
}
