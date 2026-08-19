import Foundation
import Testing
@testable import ProctorCore


// Added 2026-08-20 during PRO-0066, for a defect found by the wave rather than
// caused by it.

@Suite("Simctl listings that are not listings")
struct SimctlTruncatedListingTests {

    @Test("a truncated listing is a named refusal, not a decoder's error escaping")
    func truncatedIsRefused() {
        // The failure this closes: a loaded parallel run killed simctl mid-write,
        // the decoder threw `Unexpected end of file`, and the raw DecodingError
        // travelled out to the caller — which is neither "here are the devices"
        // nor "there is no device here", the two answers this parser promises.
        let truncated = Data(#"{"devices": {"iOS 18.2": [{"udid": "abc""#.utf8)
        #expect(throws: AgentError.self) {
            _ = try IOSDeviceList.parse(truncated)
        }
        do {
            _ = try IOSDeviceList.parse(truncated)
        } catch let error as AgentError {
            #expect(error.code == .actionFailed)
            #expect(error.message.contains("not a device listing"))
            #expect(error.remedy != nil, "a refusal a caller cannot act on is a bare denial")
        } catch {
            Issue.record("expected an AgentError, got \(type(of: error))")
        }
    }

    @Test("empty output is refused the same way, and says how much arrived")
    func emptyIsRefused() {
        do {
            _ = try IOSDeviceList.parse(Data())
        } catch let error as AgentError {
            #expect(error.message.contains("0 bytes"))
        } catch {
            Issue.record("expected an AgentError, got \(type(of: error))")
        }
    }

    @Test("a well-formed listing still parses")
    func wellFormedStillWorks() throws {
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-2":[{"udid":"U1","name":"iPhone 16 Pro","state":"Booted","isAvailable":true}]}}"#
        let devices = try IOSDeviceList.parse(Data(json.utf8))
        #expect(devices.count == 1)
        #expect(devices[0].udid == "U1")
        #expect(devices[0].state == "Booted")
    }
}
