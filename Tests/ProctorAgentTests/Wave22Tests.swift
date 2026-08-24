import Foundation
import Testing
@testable import ProctorCore
@testable import ProctorAgent

@Suite("Wave 22: Simulator, Guest VM, and Mutation Elimination (PRO-0122..PRO-0127)")
struct Wave22Tests {

    @Test("PRO-0122 / PRO-0126: IOSDeviceList and headless simulator provisioning fixture")
    func testIOSDeviceListFixture() throws {
        let fixtureJSON = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
              {
                "udid": "00000000-0000-0000-0000-000000000001",
                "name": "iPhone 16 Pro",
                "state": "Booted",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
              },
              {
                "udid": "00000000-0000-0000-0000-000000000002",
                "name": "iPhone 16",
                "state": "Shutdown",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let devices = try IOSDeviceList.parse(fixtureJSON)
        #expect(devices.count == 2)
        #expect(devices[0].name == "iPhone 16")
        #expect(devices[0].state == "Shutdown")
        #expect(!devices[0].isBooted)
        #expect(devices[1].name == "iPhone 16 Pro")
        #expect(devices[1].state == "Booted")
        #expect(devices[1].isBooted)
        #expect(devices[1].handleID.hasPrefix("dev-"))

        // Headless handle check
        let rejection = IOSHandle.rejection(handle: devices[1].handleID, tool: "proctor_snapshot")
        #expect(rejection.message.contains("is an iOS device handle"))
    }

    @Test("PRO-0123 / PRO-0127: GuestProvider Tart/Lume fixture and health socket telemetry")
    func testGuestProviderFixture() throws {
        let lumeSample = """
        [
          {"name": "proctor-guest", "status": "running", "ip": "192.168.64.2"},
          {"name": "proctor-mac-node", "status": "stopped", "ip": null}
        ]
        """.data(using: .utf8)!

        let list = try LumeInventory.parse(lumeSample)
        #expect(list.count == 2)
        #expect(list[0].name == "proctor-guest")
        #expect(list[0].running)
        #expect(list[1].name == "proctor-mac-node")
        #expect(!list[1].running)

        // Health socket telemetry check
        let healthy = GuestHealth(status: .healthy, pingLatencyMs: 1.4, socketReachable: true)
        #expect(healthy.status == .healthy)
        #expect(healthy.socketReachable)
    }

    @Test("PRO-0124: MaestroFlow step fixture parsing and schema report")
    func testMaestroFlowFixture() throws {
        let commandsJSON = """
        [
          {
            "command": {
              "tapOnElement": {
                "selector": {"text": "Continue"}
              }
            },
            "metadata": {
              "status": "COMPLETED",
              "sequenceNumber": 1,
              "duration": 42
            }
          },
          {
            "command": {
              "assertConditionCommand": {
                "condition": {"visible": "Welcome"}
              }
            },
            "metadata": {
              "status": "COMPLETED",
              "sequenceNumber": 2,
              "duration": 18
            }
          }
        ]
        """.data(using: .utf8)!

        let commands = try MaestroRecord.parse(commandsJSON)
        #expect(commands.count == 2)
        #expect(commands[0].type == "tapOnElement")
        #expect(commands[0].status == "COMPLETED")
        #expect(commands[1].type == "assertConditionCommand")
    }

    @Test("PRO-0125: ProctorAgent mutation arming against semantic mutations (DEF-033)")
    func testMutationArmingKillsSemantics() {
        var watch = ContentionWatch(inputWindow: 10, releaseDelay: 2)
        let sample1 = ContentionSample(expectedPid: 100, frontmostPid: 100, now: 100.0)
        let change1 = watch.sample(sample1)
        #expect(change1 == .none)
        #expect(!watch.isYielded)

        // Mutate frontmost
        let sample2 = ContentionSample(expectedPid: 100, frontmostPid: 200, now: 101.0)
        let change2 = watch.sample(sample2)
        #expect(change2 == .yielded(.frontmostChanged))
        #expect(watch.isYielded)

        // Release delay dampener: sample at t=102.0 sets clearSince to 102.0
        let sample3 = ContentionSample(expectedPid: 100, frontmostPid: 100, now: 102.0)
        let change3 = watch.sample(sample3)
        #expect(change3 == .none) // 102 - 102 = 0 < releaseDelay (2.0)
        #expect(watch.isYielded)

        // Sample at t=104.5 (104.5 - 102.0 = 2.5 >= 2.0 release delay)
        let sample4 = ContentionSample(expectedPid: 100, frontmostPid: 100, now: 104.5)
        let change4 = watch.sample(sample4)
        #expect(change4 == .released(.frontmostChanged))
        #expect(!watch.isYielded)
    }
}
