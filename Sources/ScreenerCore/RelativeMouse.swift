import CoreGraphics

/// Preserve sub-pixel movement while providing the integer deltas used by Cocoa games.
public struct RelativeMouseMotion {
    private var remainderX: Double = 0
    private var remainderY: Double = 0
    public init() {}
    public mutating func event(source: CGEventSource?, type: CGEventType, location: CGPoint, button: CGMouseButton,
        deltaX: Double, deltaY: Double) -> CGEvent? {
        guard deltaX.isFinite, deltaY.isFinite, abs(deltaX) <= 10000, abs(deltaY) <= 10000,
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else { return nil }
        let x = deltaX + remainderX, y = deltaY + remainderY
        let wholeX = Int64(x.rounded(.towardZero)), wholeY = Int64(y.rounded(.towardZero))
        remainderX = x - Double(wholeX); remainderY = y - Double(wholeY)
        event.setIntegerValueField(.mouseEventDeltaX, value: wholeX)
        event.setIntegerValueField(.mouseEventDeltaY, value: wholeY)
        event.setDoubleValueField(.eventUnacceleratedPointerMovementX, value: deltaX)
        event.setDoubleValueField(.eventUnacceleratedPointerMovementY, value: deltaY)
        return event
    }
}
