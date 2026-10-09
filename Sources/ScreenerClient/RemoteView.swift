import AppKit
import SwiftUI
import MetalKit
import CoreImage
import ScreenerCore

/// Forward shortcuts to the remote desktop only while the desktop has keyboard focus.
@objc(ScreenerApplication) final class ScreenerApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if let remote = keyWindow?.firstResponder as? RemoteView, remote.capturesShortcuts,
            [.keyDown, .keyUp, .flagsChanged].contains(event.type) {
            if event.type == .keyDown, event.keyCode == 53, event.modifierFlags.contains([.control, .option]) {
                remote.releaseFocus(); return
            }
            remote.forwardKey(event); return
        }
        super.sendEvent(event)
    }
}

final class RemoteView: MTKView, MTKViewDelegate {
    var sendInput: ((InputEvent) -> Void)?
    var capturesShortcuts = true
    var onReleaseFocus: (() -> Void)?
    private var image: CVPixelBuffer?
    private var imageSize = CGSize(width: 3840, height: 2160)
    private var context: CIContext?
    private var commandQueue: MTLCommandQueue?
    private var pressedKeys = Set<UInt16>()
    private var pressedButtons = Set<Int>()
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        if let device { context = CIContext(mtlDevice: device, options: [.cacheIntermediates:false]); commandQueue = device.makeCommandQueue() }
        framebufferOnly = false; colorPixelFormat = .bgra8Unorm; clearColor = MTLClearColorMake(0.025, 0.035, 0.045, 1)
        isPaused = true; enableSetNeedsDisplay = false; autoResizeDrawable = true; delegate = self
        wantsLayer = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(image: CVPixelBuffer?) {
        self.image = image
        if let image { imageSize = CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image)) }
        draw()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let commandBuffer = commandQueue?.makeCommandBuffer(), let context else { return }
        let outputBounds = CGRect(origin: .zero, size: drawableSize)
        var output = CIImage(color: CIColor(red: 0.025, green: 0.035, blue: 0.045)).cropped(to: outputBounds)
        if let image {
            let source = CIImage(cvPixelBuffer: image)
            let fitted = ScreenGeometry.fit(content: source.extent.size, in: outputBounds)
            let scaled = source.transformed(by: CGAffineTransform(scaleX: fitted.width / source.extent.width, y: fitted.height / source.extent.height))
                .transformed(by: CGAffineTransform(translationX: fitted.minX, y: fitted.minY))
            output = scaled.composited(over: output)
        }
        context.render(output, to: drawable.texture, commandBuffer: commandBuffer, bounds: outputBounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        commandBuffer.present(drawable); commandBuffer.commit()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    private func point(_ event: NSEvent, clamp: Bool = false) -> CGPoint? {
        let location = convert(event.locationInWindow, from: nil)
        let fitted = ScreenGeometry.fit(content: imageSize, in: bounds)
        if clamp, fitted.width > 0, fitted.height > 0 {
            return CGPoint(x: min(1, max(0, (location.x - fitted.minX) / fitted.width)), y: min(1, max(0, (location.y - fitted.minY) / fitted.height)))
        }
        return ScreenGeometry.normalized(location, in: fitted)
    }
    private func mouse(_ event: NSEvent, action: InputEvent.Action, button: Int = 0) {
        guard image != nil, let point = point(event, clamp: action == .up || !pressedButtons.isEmpty) else { return }
        if action == .down { window?.makeFirstResponder(self); pressedButtons.insert(button) }
        if action == .up { pressedButtons.remove(button) }
        sendInput?(InputEvent(action, x: point.x, y: point.y, button: button, modifiers: UInt64(event.modifierFlags.rawValue),
            deltaX: action == .down || action == .up ? Double(event.clickCount) : 0))
    }
    override func mouseMoved(with event: NSEvent) { mouse(event, action: .move) }
    override func mouseDragged(with event: NSEvent) { mouse(event, action: .move) }
    override func rightMouseDragged(with event: NSEvent) { mouse(event, action: .move) }
    override func otherMouseDragged(with event: NSEvent) { mouse(event, action: .move) }
    override func mouseDown(with event: NSEvent) { mouse(event, action: .down) }
    override func mouseUp(with event: NSEvent) { mouse(event, action: .up) }
    override func rightMouseDown(with event: NSEvent) { mouse(event, action: .down, button: 1) }
    override func rightMouseUp(with event: NSEvent) { mouse(event, action: .up, button: 1) }
    override func otherMouseDown(with event: NSEvent) { mouse(event, action: .down, button: 2) }
    override func otherMouseUp(with event: NSEvent) { mouse(event, action: .up, button: 2) }
    override func scrollWheel(with event: NSEvent) {
        guard let point = point(event) else { return }
        let factor: Double = event.hasPreciseScrollingDeltas ? 1 : 12
        sendInput?(InputEvent(.scroll, x: point.x, y: point.y, modifiers: UInt64(event.modifierFlags.rawValue),
            deltaX: event.scrollingDeltaX * factor, deltaY: event.scrollingDeltaY * factor))
    }
    func forwardKey(_ event: NSEvent) {
        guard image != nil else { return }
        let action: InputEvent.Action = event.type == .flagsChanged ? .flags : event.type == .keyUp ? .keyUp : .keyDown
        if action == .keyDown { pressedKeys.insert(event.keyCode) }
        if action == .keyUp { pressedKeys.remove(event.keyCode) }
        sendInput?(InputEvent(action, keyCode: event.keyCode, modifiers: UInt64(event.modifierFlags.rawValue)))
    }
    override func keyDown(with event: NSEvent) { forwardKey(event) }
    override func keyUp(with event: NSEvent) { forwardKey(event) }
    override func flagsChanged(with event: NSEvent) { forwardKey(event) }
    override func resignFirstResponder() -> Bool {
        for key in pressedKeys { sendInput?(InputEvent(.keyUp, keyCode: key)) }
        for button in pressedButtons { sendInput?(InputEvent(.up, button: button)) }
        sendInput?(InputEvent(.flags, keyCode: 0)); pressedKeys.removeAll(); pressedButtons.removeAll()
        return super.resignFirstResponder()
    }
    func releaseFocus() { window?.makeFirstResponder(nil); onReleaseFocus?() }
}
struct RemoteDesktop: NSViewRepresentable {
    @ObservedObject var model: ClientModel
    func makeNSView(context: Context) -> RemoteView {
        let view = RemoteView(); view.sendInput = { [weak model] event in model?.sendInput(event) }
        view.onReleaseFocus = { [weak model] in model?.captureShortcuts = false }
        return view
    }
    func updateNSView(_ view: RemoteView, context: Context) {
        view.capturesShortcuts = model.captureShortcuts
        view.update(image: model.image)
    }
}
