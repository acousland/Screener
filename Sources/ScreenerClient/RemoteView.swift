import AppKit
import SwiftUI
import MetalKit
import CoreImage
import ScreenerCore

/// Forward shortcuts to the remote desktop only while the desktop has keyboard focus.
@objc(ScreenerApplication) final class ScreenerApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if keyWindow?.firstResponder is RemoteView, event.type == .keyUp,
            ShortcutRouting.isLocalControl(keyCode: event.keyCode, modifiers: UInt64(event.modifierFlags.rawValue)) { return }
        if let remote = keyWindow?.firstResponder as? RemoteView, event.type == .keyDown,
            event.modifierFlags.intersection([.control, .option, .command, .shift]) == [.control, .option] {
            if event.keyCode == 17 { remote.onToggleTransparent?(); return }
            if event.keyCode == 1 { remote.onShowSessionControls?(); return }
            if event.keyCode == 5 { remote.onToggleGameMouse?(); return }
            if event.keyCode == 53 {
                let exitFullScreen = remote.transparent
                remote.releaseFocus()
                if exitFullScreen { keyWindow?.toggleFullScreen(nil) }
                return
            }
        }
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
    var onToggleTransparent: (() -> Void)?
    var onShowSessionControls: (() -> Void)?
    var onToggleGameMouse: (() -> Void)?
    var onGameMouseError: ((String) -> Void)?
    var mouseSensitivity = 1.0
    private var gameMouse = false
    private var relativeMouseLocked = false
    private weak var lockedWindow: NSWindow?
    private var previousAcceptsMouseMoved = false
    private var spaceObserver: NSObjectProtocol?
    var transparent = false
    private var cursorEmbedded = true
    private var cursorHidden = false
    private var windowObservers: [NSObjectProtocol] = []
    private var image: CVPixelBuffer?
    var readyForKeyboard: Bool { image != nil }
    private var imageSize = CGSize(width: 3840, height: 2160)
    private var context: CIContext?
    private var commandQueue: MTLCommandQueue?
    private var pressedKeys = Set<UInt16>()
    private var pressedButtons = Set<Int>()
    private var lastPointer = CGPoint(x: 0.5, y: 0.5)
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        if let device { context = CIContext(mtlDevice: device, options: [.cacheIntermediates:false]); commandQueue = device.makeCommandQueue() }
        framebufferOnly = false; colorPixelFormat = .bgra8Unorm; clearColor = MTLClearColorMake(0.025, 0.035, 0.045, 1)
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        isPaused = true; enableSetNeedsDisplay = false; autoResizeDrawable = true; delegate = self
        wantsLayer = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(image: CVPixelBuffer?, cursorEmbedded: Bool) {
        if self.cursorEmbedded != cursorEmbedded {
            self.cursorEmbedded = cursorEmbedded
            window?.invalidateCursorRects(for: self)
        }
        self.image = image
        if let image { imageSize = CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image)) }
        draw()
        updateLocalCursor()
    }
    func setTransparent(_ enabled: Bool) {
        let entering = enabled && !transparent
        transparent = enabled
        if entering, window?.isKeyWindow == true { window?.makeFirstResponder(self) }
        updateLocalCursor()
    }
    func setGameMouse(_ enabled: Bool) {
        guard enabled != gameMouse else { return }
        gameMouse = enabled
        releaseHeldInput()
        if !enabled { restoreLocalCursor() }
        updateLocalCursor()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        releaseCapture()
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers.removeAll()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if note.name == NSWindow.willCloseNotification || note.name == NSWindow.didResignKeyNotification {
                            self?.releaseCapture()
                        }
                        else { self?.updateLocalCursor() }
                    }
                })
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if note.name != NSApplication.didBecomeActiveNotification { self?.releaseCapture() }
                        else { self?.updateLocalCursor() }
                    }
                })
            }
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.releaseCapture(); self?.updateLocalCursor() }
            }
        }
        updateLocalCursor()
    }
    private func updateLocalCursor() {
        let fitted = ScreenGeometry.fit(content: imageSize, in: bounds)
        let inside = window.map { fitted.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        let focused = image != nil && NSApp.isActive && window?.isOnActiveSpace == true && window?.isKeyWindow == true && window?.firstResponder === self && (inside || relativeMouseLocked)
        if focused, gameMouse, !relativeMouseLocked, let window {
            let result = CGAssociateMouseAndMouseCursorPosition(0)
            if result == .success {
                relativeMouseLocked = true; lockedWindow = window
                previousAcceptsMouseMoved = window.acceptsMouseMovedEvents; window.acceptsMouseMovedEvents = true
            } else {
                gameMouse = false; onGameMouseError?("Could not lock the local mouse (\(result.rawValue)). Click the viewer and try Game Mouse again.")
            }
        }
        let hide = focused && (cursorEmbedded || relativeMouseLocked)
        if hide, !cursorHidden { NSCursor.hide(); cursorHidden = true }
        else if !hide { restoreLocalCursor() }
        if focused, !cursorEmbedded, !relativeMouseLocked { NSCursor.arrow.set() }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if !cursorEmbedded, !gameMouse { addCursorRect(ScreenGeometry.fit(content: imageSize, in: bounds), cursor: .arrow) }
    }
    func restoreLocalCursor() {
        if relativeMouseLocked {
            CGAssociateMouseAndMouseCursorPosition(1); relativeMouseLocked = false
            lockedWindow?.acceptsMouseMovedEvents = previousAcceptsMouseMoved; lockedWindow = nil
        }
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
    }
    override func mouseEntered(with event: NSEvent) { updateLocalCursor() }
    override func mouseExited(with event: NSEvent) { if relativeMouseLocked { releaseHeldInput() }; restoreLocalCursor() }
    override func cursorUpdate(with event: NSEvent) { updateLocalCursor() }
    override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); updateLocalCursor(); return accepted }
    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if relativeMouseLocked { CGAssociateMouseAndMouseCursorPosition(1) }
        if cursorHidden { NSCursor.unhide() }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let commandBuffer = commandQueue?.makeCommandBuffer(), let context else { return }
        let outputBounds = CGRect(origin: .zero, size: drawableSize)
        let background = transparent ? CIColor.black : CIColor(red: 0.025, green: 0.035, blue: 0.045)
        var output = CIImage(color: background).cropped(to: outputBounds)
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
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect], owner: self, userInfo: nil)
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
        guard image != nil else { return }
        let relative = relativeMouseLocked
        guard let point = relative ? CGPoint(x: 0.5, y: 0.5) : point(event, clamp: action == .up || !pressedButtons.isEmpty) else { return }
        lastPointer = point
        if action == .down { window?.makeFirstResponder(self); pressedButtons.insert(button) }
        if action == .up { pressedButtons.remove(button) }
        let movement = relative && action == .move
        let dx = movement ? min(10000, max(-10000, event.deltaX * mouseSensitivity)) : action == .down || action == .up ? Double(event.clickCount) : 0
        let dy = movement ? min(10000, max(-10000, event.deltaY * mouseSensitivity)) : 0
        sendInput?(InputEvent(action, x: point.x, y: point.y, button: button, modifiers: UInt64(event.modifierFlags.rawValue),
            deltaX: dx, deltaY: dy, relativeMouse: relative))
    }
    override func mouseMoved(with event: NSEvent) { updateLocalCursor(); mouse(event, action: .move) }
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
        guard let point = relativeMouseLocked ? CGPoint(x: 0.5, y: 0.5) : point(event) else { return }
        let factor: Double = event.hasPreciseScrollingDeltas ? 1 : 12
        sendInput?(InputEvent(.scroll, x: point.x, y: point.y, modifiers: UInt64(event.modifierFlags.rawValue),
            deltaX: event.scrollingDeltaX * factor, deltaY: event.scrollingDeltaY * factor, relativeMouse: relativeMouseLocked))
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
        releaseCapture()
        return super.resignFirstResponder()
    }
    func releaseCapture() { releaseHeldInput(); restoreLocalCursor() }
    private func releaseHeldInput() {
        for key in pressedKeys { sendInput?(InputEvent(.keyUp, keyCode: key)) }
        for button in pressedButtons { sendInput?(InputEvent(.up, x: lastPointer.x, y: lastPointer.y, button: button, relativeMouse: relativeMouseLocked)) }
        sendInput?(InputEvent(.flags, keyCode: 0)); pressedKeys.removeAll(); pressedButtons.removeAll()
    }
    func releaseFocus() { window?.makeFirstResponder(nil); onReleaseFocus?() }
}
struct RemoteDesktop: NSViewRepresentable {
    @ObservedObject var model: ClientModel
    var transparent: Bool
    var showSessionControls: () -> Void
    func makeNSView(context: Context) -> RemoteView {
        let view = RemoteView(); view.sendInput = { [weak model] event in model?.sendInput(event) }
        view.onReleaseFocus = { [weak model] in model?.captureShortcuts = false; model?.setGameMouse(false) }
        view.onToggleTransparent = { [weak model] in model?.transparentMode.toggle() }
        view.onToggleGameMouse = { [weak model] in guard let model else { return }; model.setGameMouse(!model.gameMouse) }
        view.onGameMouseError = { [weak model] text in model?.setGameMouse(false); model?.error = text }
        return view
    }
    func updateNSView(_ view: RemoteView, context: Context) {
        view.capturesShortcuts = model.captureShortcuts
        view.onShowSessionControls = showSessionControls
        view.setTransparent(transparent)
        view.update(image: model.image, cursorEmbedded: model.cursorEmbedded)
        view.mouseSensitivity = model.mouseSensitivity
        view.setGameMouse(model.gameMouse)
    }
    static func dismantleNSView(_ view: RemoteView, coordinator: ()) { view.releaseCapture() }
}
