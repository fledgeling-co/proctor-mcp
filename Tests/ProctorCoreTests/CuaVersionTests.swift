import Testing
import Foundation
@testable import ProctorCore

// PRO-0044, slice 5. The supported window, and the strings a driver might print.
//
// The range was chosen from documentation rather than from contact — the driver
// is not installed on the machine this was written on, and installing it as a
// side effect is forbidden. So this file pins the arithmetic and the parsing;
// the capability probe is what checks the choice against a real build.

@Suite("Cua version gate")
struct CuaVersionTests {

    @Test("the shapes a version can arrive in all parse")
    func parsesTheUsualShapes() {
        #expect(CuaVersion.parse("0.13.2") == CuaVersion(major: 0, minor: 13, patch: 2))
        #expect(CuaVersion.parse("v0.13.2") == CuaVersion(major: 0, minor: 13, patch: 2))
        #expect(CuaVersion.parse("cua-driver 0.13.2\n") == CuaVersion(major: 0, minor: 13, patch: 2))
        // A two-part version is a real thing a tool prints.
        #expect(CuaVersion.parse("0.13") == CuaVersion(major: 0, minor: 13, patch: 0))
    }

    @Test("a pre-release keeps its tail rather than being rounded to a release")
    func prereleaseSurvivesParsing() {
        let nightly = CuaVersion.parse("0.14.0-nightly.20260815")
        #expect(nightly?.prerelease == "nightly.20260815")
        #expect(nightly?.description == "0.14.0-nightly.20260815")
    }

    @Test("nothing parseable is nil, not a lenient guess")
    func unreadableIsNil() {
        // A build whose version cannot be read is exactly as unsupported as one
        // outside the range. Guessing "probably fine" would defeat the gate on
        // precisely the builds most likely to be strange.
        #expect(CuaVersion.parse("") == nil)
        #expect(CuaVersion.parse("dev") == nil)
        #expect(CuaVersion.parse("cua-driver (unknown build)") == nil)
    }

    @Test("the supported window is one minor version, inclusive at the floor")
    func rangeHolds() {
        #expect(CuaVersion(major: 0, minor: 13, patch: 0).isSupported)
        #expect(CuaVersion(major: 0, minor: 13, patch: 99).isSupported)
        #expect(!CuaVersion(major: 0, minor: 12, patch: 9).isSupported)
        #expect(!CuaVersion(major: 0, minor: 14, patch: 0).isSupported)
        #expect(!CuaVersion(major: 1, minor: 0, patch: 0).isSupported)
    }

    @Test("a nightly of the next minor is not the current one")
    func nightlyOfTheNextMinorIsRefused() {
        // The trap in a naive range check, and the reason pre-releases are
        // refused outright: semver sorts a pre-release BELOW its own release, so
        // an upper bound of `< 0.14.0` would have admitted a build of 0.14, which
        // is the one thing that bound exists to keep out.
        let nightly = CuaVersion(major: 0, minor: 14, patch: 0, prerelease: "nightly")
        #expect(nightly < CuaVersion(major: 0, minor: 14, patch: 0))
        #expect(!nightly.isSupported)
    }

    @Test("a release candidate for the floor is below the floor")
    func candidateForTheFloorIsRefused() {
        let rc = CuaVersion(major: 0, minor: 13, patch: 0, prerelease: "rc1")
        #expect(rc < CuaVersion.lowestSupported)
        #expect(!rc.isSupported)
    }

    @Test("a pre-release inside the range is still refused")
    func prereleaseInsideTheRangeIsRefused() {
        // Nothing about "0.13.5" being in the window makes a build that is not
        // yet 0.13.5 into one. The driver ships a nightly channel, so this is a
        // build somebody will actually have; the override is how they run it, and
        // taking it stamps the record.
        #expect(!CuaVersion(major: 0, minor: 13, patch: 5, prerelease: "nightly.1").isSupported)
        #expect(CuaVersion(major: 0, minor: 13, patch: 5).isSupported)
    }
}
