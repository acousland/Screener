import XCTest
@testable import ScreenerCore

final class AudioOutputMuteTests: XCTestCase {
    private final class Output: AudioOutputControl {
        var states: [String: Bool] = ["speakers": false, "headphones": false]
        var writes: [(String, Bool)] = []
        var failWrites = false
        var beforeWrite: ((String, Bool) -> Void)?
        func defaultOutputUID() throws -> String { "speakers" }
        func isMuted(_ uid: String) throws -> Bool {
            guard let state = states[uid] else { throw ScreenerError.message("Disconnected") }; return state
        }
        func setMuted(_ muted: Bool, for uid: String) throws {
            beforeWrite?(uid, muted)
            if failWrites { throw ScreenerError.message("Output rejected change") }
            states[uid] = muted; writes.append((uid, muted))
        }
    }
    func testRestoresOwnedMuteAndPreservesExistingMute() throws {
        let output = Output(); var journal: [String: Bool] = [:]
        let lease = AudioOutputMuteLease(output: output) { journal = $0 }
        output.beforeWrite = { uid, muted in if muted { XCTAssertEqual(journal[uid], false) } }
        try lease.transition(to: "speakers")
        XCTAssertEqual(output.states["speakers"], true)
        try lease.transition(to: nil)
        XCTAssertEqual(output.states["speakers"], false); XCTAssertTrue(journal.isEmpty)
        let writes = output.writes.count
        output.states["speakers"] = true
        try lease.transition(to: "speakers"); try lease.transition(to: nil)
        XCTAssertEqual(output.states["speakers"], true); XCTAssertEqual(output.writes.count, writes)
    }
    func testOutputSwitchRestoresPreviousDeviceAndMutesNewDevice() throws {
        let output = Output()
        let lease = AudioOutputMuteLease(output: output) { _ in }
        try lease.transition(to: "speakers"); try lease.transition(to: "headphones")
        XCTAssertEqual(output.states["speakers"], false); XCTAssertEqual(output.states["headphones"], true)
        XCTAssertEqual(output.writes.map(\.0), ["speakers", "speakers", "headphones"])
        XCTAssertEqual(output.writes.map(\.1), [true, false, true])
        try lease.transition(to: nil); XCTAssertEqual(output.states["headphones"], false)
    }
    func testManualUnmuteRelinquishesOwnership() throws {
        let output = Output(); var journal: [String: Bool] = [:]
        let lease = AudioOutputMuteLease(output: output) { journal = $0 }
        try lease.transition(to: "speakers")
        output.states["speakers"] = false // The user changes Sound settings.
        try lease.transition(to: "speakers")
        XCTAssertTrue(journal.isEmpty)
        output.states["speakers"] = true // A later user mute belongs to the user.
        try lease.transition(to: nil)
        XCTAssertEqual(output.states["speakers"], true); XCTAssertEqual(output.writes.count, 1)
    }
    func testFailedRestorationIsRecoveredAfterRelaunch() throws {
        let output = Output(); var journal: [String: Bool] = [:]
        let lease = AudioOutputMuteLease(output: output) { journal = $0 }
        try lease.transition(to: "speakers"); output.failWrites = true
        XCTAssertThrowsError(try lease.transition(to: nil)); XCTAssertEqual(journal["speakers"], false)
        output.failWrites = false
        let reopened = AudioOutputMuteLease(output: output, pending: journal) { journal = $0 }
        try reopened.transition(to: nil)
        XCTAssertEqual(output.states["speakers"], false); XCTAssertTrue(journal.isEmpty)
    }
    func testDisconnectedOutputRestoresWhenItReturns() throws {
        let output = Output(); var journal: [String: Bool] = [:]
        let lease = AudioOutputMuteLease(output: output) { journal = $0 }
        try lease.transition(to: "speakers"); output.states.removeValue(forKey: "speakers")
        XCTAssertThrowsError(try lease.transition(to: "headphones"))
        XCTAssertEqual(output.states["headphones"], true); XCTAssertEqual(journal["speakers"], false)
        output.states["speakers"] = true
        try lease.transition(to: "headphones")
        XCTAssertEqual(output.states["speakers"], false); XCTAssertNil(journal["speakers"])
        try lease.transition(to: nil); XCTAssertTrue(journal.isEmpty)
    }
    func testFailedMuteLeavesNoOwnedChange() {
        let output = Output(); var journal: [String: Bool] = [:]
        let lease = AudioOutputMuteLease(output: output) { journal = $0 }
        output.failWrites = true
        XCTAssertThrowsError(try lease.transition(to: "speakers"))
        XCTAssertEqual(output.states["speakers"], false); XCTAssertTrue(journal.isEmpty)
    }
    func testMuteNegotiationRemainsOptionalForOlderPeers() throws {
        let oldHello = try WireMessage(.hello, value: ClientHello(name: "Old client", audioEnabled: true)).decode(ClientHello.self)
        XCTAssertNil(oldHello.muteHostAudio)
        let hello = try WireMessage(.hello, value: ClientHello(name: "New client", audioEnabled: true, muteHostAudio: true)).decode(ClientHello.self)
        XCTAssertEqual(hello.muteHostAudio, true); XCTAssertTrue(hello.valid)
        let config = try WireMessage(.configure, value: ConfigureDisplay(modeID: 42, muteHostAudio: false)).decode(ConfigureDisplay.self)
        XCTAssertEqual(config.muteHostAudio, false); XCTAssertNil(config.audioEnabled); XCTAssertTrue(config.valid)
        let oldDesktop = DesktopInfo(name: "Mini", streamWidth: 1920, streamHeight: 1080, logicalWidth: 1920, logicalHeight: 1080, currentMode: 42, modes: [], audioEnabled: true)
        XCTAssertNil(try WireMessage(.desktop, value: oldDesktop).decode(DesktopInfo.self).muteHostAudio)
        let current = DesktopInfo(name: "Mini", streamWidth: 1920, streamHeight: 1080, logicalWidth: 1920, logicalHeight: 1080, currentMode: 42, modes: [], audioEnabled: true, muteHostAudio: true)
        XCTAssertEqual(try WireMessage(.desktop, value: current).decode(DesktopInfo.self).muteHostAudio, true)
    }
}
