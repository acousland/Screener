import XCTest
@testable import ScreenerCore

final class ProtocolTests: XCTestCase {
    func testArbitraryPacketBoundariesAndCoalescing() throws {
        let payload = Data((0..<4096).map { UInt8($0 % 251) })
        let messages = [WireMessage(.video, payload: payload), WireMessage(.ping), WireMessage(.clipboard, payload: Data("こんにちは".utf8))]
        let wire = messages.reduce(Data()) { $0 + $1.framed() }
        for stride in [1, 2, 3, 4, 5, 31, 1024, wire.count] {
            var parser = MessageParser(); var decoded: [WireMessage] = []
            var offset = 0
            while offset < wire.count { let end = min(wire.count, offset + stride); decoded += try parser.append(Data(wire[offset..<end])); offset = end }
            XCTAssertEqual(decoded.map(\.kind), messages.map(\.kind)); XCTAssertEqual(decoded.map(\.payload), messages.map(\.payload))
        }
    }
    func testRejectsInvalidLengthsAndUnknownKinds() {
        for bytes: [UInt8] in [[0,0,0,0], [1,0,0,1], [255,255,255,255], [0,0,0,1,255]] {
            var parser = MessageParser(); XCTAssertThrowsError(try parser.append(Data(bytes)))
        }
    }
    func testVideoTimestampAndContentRoundTrip() throws {
        let bytes = Data([0,0,0,4,1,2,3,4])
        for timestamp in [UInt64(0), 123456789, UInt64.max] {
            let decoded = try VideoPacket.decode(VideoPacket.encode(bytes, timestamp: timestamp, keyframe: true))
            XCTAssertEqual(decoded.bytes, bytes); XCTAssertEqual(decoded.timestamp, timestamp); XCTAssertTrue(decoded.keyframe)
        }
        XCTAssertThrowsError(try VideoPacket.decode(Data(repeating: 0, count: 9)))
    }
    func testInputValidationRejectsMalformedCoordinatesAndKeys() {
        XCTAssertTrue(InputEvent(.move, x: 0.25, y: 0.75).valid)
        for event in [InputEvent(.move, x: -.infinity), InputEvent(.move, y: .nan), InputEvent(.move, x: 1.01),
            InputEvent(.scroll, deltaY: 10001), InputEvent(.keyDown, keyCode: 999), InputEvent(.down, button: -1)] { XCTAssertFalse(event.valid) }
    }
    func testLetterboxingAndRetinaModes() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let fit = ScreenGeometry.fit(content: CGSize(width: 3840, height: 2160), in: bounds)
        XCTAssertEqual(fit.width, 1000, accuracy: 0.0001); XCTAssertEqual(fit.height, 562.5, accuracy: 0.0001); XCTAssertEqual(fit.minY, 118.75, accuracy: 0.0001)
        XCTAssertNil(ScreenGeometry.normalized(CGPoint(x: 500, y: 20), in: fit))
        let center = ScreenGeometry.normalized(CGPoint(x: 500, y: 400), in: fit)
        XCTAssertEqual(center?.x, 0.5); XCTAssertEqual(center?.y, 0.5)
        let size = ScreenGeometry.streamSize(width: 6016, height: 3384)
        XCTAssertEqual(size.0, 3840); XCTAssertEqual(size.1, 2160)
        let portrait = ScreenGeometry.streamSize(width: 2160, height: 3840)
        XCTAssertEqual(portrait.0, 1214); XCTAssertEqual(portrait.1, 2160)
    }
    func testConnectionKeysAreStrongAndStrictlyParsed() throws {
        let key = try PairingSecret(); XCTAssertEqual(key.bytes.count, 32)
        XCTAssertEqual(try PairingSecret(code: key.code.uppercased()), key)
        XCTAssertEqual(try PairingSecret(code: " \(key.code)\n"), key)
        XCTAssertNotEqual(try PairingSecret(), key)
        for code in ["1234", "", String(repeating: "g", count: 64), String(repeating: "0", count: 65)] { XCTAssertThrowsError(try PairingSecret(code: code)) }
    }
    func testMacBookAspectRatioSurvivesHiDPIDownsampling() {
        for (width, height) in [(1280,800), (1440,900), (1512,945), (1680,1050), (1728,1080),
            (1920,1200), (2240,1400), (2560,1600), (3008,1880), (3360,2100)] {
            let size = ScreenGeometry.streamSize(width: width * 2, height: height * 2)
            XCTAssertLessThanOrEqual(size.0, 3840); XCTAssertLessThanOrEqual(size.1, 2160)
            XCTAssertEqual(size.0 % 2, 0); XCTAssertEqual(size.1 % 2, 0)
            XCTAssertEqual(Double(size.0) / Double(size.1), 1.6, accuracy: 0.000001, "\(width) × \(height)")
            let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1080)
            let fitted = ScreenGeometry.fit(content: CGSize(width: size.0, height: size.1), in: bounds)
            XCTAssertEqual(fitted.minX, bounds.minX, accuracy: 0.000001); XCTAssertEqual(fitted.minY, bounds.minY, accuracy: 0.000001)
            XCTAssertEqual(fitted.width, bounds.width, accuracy: 0.000001); XCTAssertEqual(fitted.height, bounds.height, accuracy: 0.000001)
        }
        let maximum = ScreenGeometry.streamSize(width: 6720, height: 4200)
        XCTAssertEqual(maximum.0, 3456); XCTAssertEqual(maximum.1, 2160)
    }
    func testHelloRejectsUnsupportedVersionsAndRates() throws {
        XCTAssertTrue(ClientHello(name: "MacBook").valid)
        XCTAssertFalse(ClientHello(name: "MacBook", fps: 240).valid)
        XCTAssertFalse(ClientHello(name: "MacBook", bitrate: 1000).valid)
    }
    func testDecodeQueueHasBoundedCapacity() {
        let budget = DecodeBudget(limit: 2)
        XCTAssertTrue(budget.reserve()); XCTAssertTrue(budget.reserve()); XCTAssertFalse(budget.reserve())
        budget.release(); XCTAssertTrue(budget.reserve()); XCTAssertFalse(budget.reserve())
    }
    func testLiveConfigurationValidatesOptionalStreamSettings() throws {
        XCTAssertTrue(ConfigureDisplay(modeID: 42).valid)
        let config = ConfigureDisplay(modeID: 42, fps: 30, bitrate: 75)
        let decoded = try WireMessage(.configure, value: config).decode(ConfigureDisplay.self)
        XCTAssertEqual(decoded.modeID, 42); XCTAssertEqual(decoded.framesPerSecond, 30); XCTAssertEqual(decoded.megabitsPerSecond, 75)
        XCTAssertTrue(decoded.valid)
        for config in [ConfigureDisplay(modeID: 42, fps: 0), ConfigureDisplay(modeID: 42, fps: 240),
            ConfigureDisplay(modeID: 42, bitrate: 9), ConfigureDisplay(modeID: 42, fps: 60, bitrate: 101)] { XCTAssertFalse(config.valid) }
    }
    func testConfigurationRemainsCompatibleWithResolutionOnlyMessages() throws {
        let legacy = try WireMessage(.configure, payload: Data(#"{"modeID":42}"#.utf8)).decode(ConfigureDisplay.self)
        XCTAssertEqual(legacy.modeID, 42); XCTAssertNil(legacy.framesPerSecond); XCTAssertNil(legacy.megabitsPerSecond); XCTAssertTrue(legacy.valid)
        struct LegacyConfiguration: Decodable { let modeID: Int32 }
        let compatible = try WireMessage(.configure, value: ConfigureDisplay(modeID: 42, fps: 30, bitrate: 25)).decode(LegacyConfiguration.self)
        XCTAssertEqual(compatible.modeID, 42)
    }
    func testDesktopAdvertisesLiveControlsWithoutBreakingOlderMessages() throws {
        let original = DesktopInfo(name: "Mini", streamWidth: 3840, streamHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, currentMode: 42, modes: [])
        let legacy = try WireMessage(.desktop, value: original).decode(DesktopInfo.self)
        XCTAssertNil(legacy.framesPerSecond); XCTAssertNil(legacy.megabitsPerSecond)
        let updated = DesktopInfo(name: "Mini", streamWidth: 3840, streamHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, currentMode: 42, modes: [], framesPerSecond: 60, megabitsPerSecond: 45)
        let current = try WireMessage(.desktop, value: updated).decode(DesktopInfo.self)
        XCTAssertEqual(current.framesPerSecond, 60); XCTAssertEqual(current.megabitsPerSecond, 45)
        struct LegacyDesktop: Decodable { let currentMode: Int32; let streamWidth: Int }
        let compatible = try WireMessage(.desktop, value: updated).decode(LegacyDesktop.self)
        XCTAssertEqual(compatible.currentMode, 42); XCTAssertEqual(compatible.streamWidth, 3840)
    }
}
