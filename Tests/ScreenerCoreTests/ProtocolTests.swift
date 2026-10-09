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
}
