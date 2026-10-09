import XCTest
import CoreGraphics
import AppKit
@testable import ScreenerCore

final class RelativeMouseTests: XCTestCase {
    func testCocoaReceivesRelativeDeltasAtConstantPointerPosition() throws {
        var motion = RelativeMouseMotion()
        let point = CGPoint(x: 300, y: 400)
        let event = try XCTUnwrap(motion.event(source: nil, type: .mouseMoved, location: point, button: .left, deltaX: 12, deltaY: -7))
        XCTAssertEqual(event.location, point)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaX), 12)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaY), -7)
        XCTAssertEqual(event.getDoubleValueField(.eventUnacceleratedPointerMovementX), 12)
        XCTAssertEqual(event.getDoubleValueField(.eventUnacceleratedPointerMovementY), -7)
        let cocoa = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(cocoa.deltaX, 12); XCTAssertEqual(cocoa.deltaY, -7)
        let drag = try XCTUnwrap(motion.event(source: nil, type: .rightMouseDragged, location: point, button: .right, deltaX: -5, deltaY: 2))
        XCTAssertEqual(drag.type, .rightMouseDragged); XCTAssertEqual(drag.location, point)
    }
    func testSmallMovementsAccumulateWithoutDriftOrNonFiniteValues() throws {
        var motion = RelativeMouseMotion(); var x: Int64 = 0, y: Int64 = 0
        for _ in 0..<100 {
            let event = try XCTUnwrap(motion.event(source: nil, type: .mouseMoved, location: .zero, button: .left, deltaX: 0.25, deltaY: -0.5))
            x += event.getIntegerValueField(.mouseEventDeltaX); y += event.getIntegerValueField(.mouseEventDeltaY)
        }
        XCTAssertEqual(x, 25); XCTAssertEqual(y, -50)
        XCTAssertNil(motion.event(source: nil, type: .mouseMoved, location: .zero, button: .left, deltaX: .nan, deltaY: 0))
        XCTAssertNil(motion.event(source: nil, type: .mouseMoved, location: .zero, button: .left, deltaX: 10001, deltaY: 0))
    }
    func testRelativeInputCapabilityAndLegacyDecoding() throws {
        let legacy = try WireMessage(.input, payload: Data(#"{"action":"move","x":0.5,"y":0.5,"button":0,"keyCode":0,"modifiers":0,"deltaX":0,"deltaY":0}"#.utf8)).decode(InputEvent.self)
        XCTAssertNil(legacy.relativeMouse); XCTAssertTrue(legacy.valid)
        let input = InputEvent(.move, x: 0.5, y: 0.5, deltaX: 12, deltaY: -7, relativeMouse: true)
        let decoded = try WireMessage(.input, value: input).decode(InputEvent.self)
        XCTAssertTrue(decoded.valid); XCTAssertEqual(decoded.relativeMouse, true); XCTAssertEqual(decoded.deltaY, -7)
        XCTAssertFalse(InputEvent(.keyDown, relativeMouse: true).valid)
        let oldDesktop = DesktopInfo(name: "Mini", streamWidth: 1920, streamHeight: 1080, logicalWidth: 1920, logicalHeight: 1080, currentMode: 42, modes: [])
        XCTAssertNil(try WireMessage(.desktop, value: oldDesktop).decode(DesktopInfo.self).relativeMouseSupported)
        XCTAssertFalse(ShortcutRouting.capture(appActive: true, windowActive: true, desktopReady: true, enabled: true, keyCode: 5,
            modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue))
    }
    func testFullPanelModesFitIncludingNotchStripWithinVideoLimit() {
        for (width, height, label) in [(1512,982,"14″ full screen"), (1728,1117,"16″ full screen")] {
            let mode = DisplayModeInfo(id: 1, width: width, height: height, pixelWidth: width * 2, pixelHeight: height * 2)
            XCTAssertEqual(mode.aspectRatioLabel, label); XCTAssertTrue(mode.label.contains(label))
            for cap in [1080,1440,2160] {
                let stream = ScreenGeometry.streamSize(width: width * 2, height: height * 2, maximumHeight: cap)
                XCTAssertLessThanOrEqual(stream.0, 3840); XCTAssertLessThanOrEqual(stream.1, cap)
                let viewport = CGRect(x: 0, y: 0, width: width, height: height)
                let fitted = ScreenGeometry.fit(content: CGSize(width: stream.0, height: stream.1), in: viewport)
                XCTAssertLessThanOrEqual(abs(fitted.width - viewport.width), 2)
                XCTAssertLessThanOrEqual(abs(fitted.height - viewport.height), 2)
            }
        }
    }
}
