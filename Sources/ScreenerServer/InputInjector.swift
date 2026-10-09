import AppKit
import ApplicationServices
import ScreenerCore

@MainActor final class InputInjector {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var keys = Set<UInt16>()
    private var buttons = Set<Int>()
    private var lastPoint = CGPoint.zero
    private var lastModifiers: UInt64 = 0
    private var relativeMotion = RelativeMouseMotion()
    private var relativeActive = false
    var allowed: Bool { AXIsProcessTrusted() }
    func apply(_ input: InputEvent, displayID: CGDirectDisplayID) {
        guard input.valid, allowed else { return }
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let relative = input.relativeMouse == true
        if [.move, .down, .up, .scroll].contains(input.action), relative != relativeActive {
            relativeMotion = RelativeMouseMotion(); relativeActive = relative
        }
        let current = CGEvent(source: nil)?.location ?? lastPoint
        let point = relative ? (bounds.contains(current) ? current : CGPoint(x: bounds.midX, y: bounds.midY))
            : CGPoint(x: bounds.minX + min(input.x * bounds.width, bounds.width - 1), y: bounds.minY + min(input.y * bounds.height, bounds.height - 1))
        let flags = CGEventFlags(rawValue: input.modifiers & 0x00ff0000)
        var event: CGEvent?
        let button = CGMouseButton(rawValue: UInt32(input.button)) ?? .left
        switch input.action {
        case .move:
            lastPoint = point
            let pressed = buttons.sorted().first
            let type: CGEventType = pressed == 0 ? .leftMouseDragged : pressed == 1 ? .rightMouseDragged : pressed != nil ? .otherMouseDragged : .mouseMoved
            let mouseButton = CGMouseButton(rawValue: UInt32(pressed ?? 0)) ?? .left
            if relative {
                event = relativeMotion.event(source: source, type: type, location: point, button: mouseButton, deltaX: input.deltaX, deltaY: input.deltaY)
            } else { event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: mouseButton) }
        case .down, .up:
            lastPoint = point
            let down = input.action == .down
            if down { buttons.insert(input.button) } else { buttons.remove(input.button) }
            let type: CGEventType = input.button == 0 ? (down ? .leftMouseDown : .leftMouseUp) : input.button == 1 ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
            event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
            event?.setIntegerValueField(.mouseEventClickState, value: max(1, min(3, Int64(input.deltaX))))
        case .scroll:
            event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(input.deltaY), wheel2: Int32(input.deltaX), wheel3: 0)
            event?.location = point
        case .keyDown, .keyUp:
            let down = input.action == .keyDown
            if down { keys.insert(input.keyCode) } else { keys.remove(input.keyCode) }
            event = CGEvent(keyboardEventSource: source, virtualKey: input.keyCode, keyDown: down)
        case .flags:
            event = CGEvent(keyboardEventSource: source, virtualKey: input.keyCode, keyDown: false)
            event?.type = .flagsChanged
            lastModifiers = input.modifiers
        }
        event?.flags = flags; event?.post(tap: .cghidEventTap)
    }
    func releaseAll() {
        for key in keys { CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap) }
        for button in buttons {
            let type: CGEventType = button == 0 ? .leftMouseUp : button == 1 ? .rightMouseUp : .otherMouseUp
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: lastPoint, mouseButton: CGMouseButton(rawValue: UInt32(button)) ?? .left)?.post(tap: .cghidEventTap)
        }
        if lastModifiers != 0 {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            event?.type = .flagsChanged; event?.flags = []; event?.post(tap: .cghidEventTap)
        }
        keys.removeAll(); buttons.removeAll(); lastModifiers = 0
        relativeMotion = RelativeMouseMotion(); relativeActive = false
    }
}
