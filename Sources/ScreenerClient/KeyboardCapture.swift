import AppKit
import ApplicationServices
import SwiftUI
import ScreenerCore

/// Intercept system shortcuts only while a connected remote desktop has keyboard focus.
@MainActor final class KeyboardCaptureController: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var permissionGranted = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        refresh()
    }
    private func refresh() {
        permissionGranted = AXIsProcessTrusted()
        if !permissionGranted {
            if let tap { CFMachPortInvalidate(tap) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            tap = nil; source = nil; available = false
            return
        }
        if let tap, CFMachPortIsValid(tap) { available = true; return }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let controller = Unmanaged<KeyboardCaptureController>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return Unmanaged.passUnretained(event)
                    }
                    guard let window = NSApp.keyWindow, let remote = window.firstResponder as? RemoteView,
                        ShortcutRouting.capture(appActive: NSApp.isActive, windowActive: window.isOnActiveSpace,
                            desktopReady: remote.readyForKeyboard, enabled: remote.capturesShortcuts,
                            keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)), modifiers: event.flags.rawValue),
                        let key = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
                    remote.forwardKey(key)
                    return nil
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { available = false; return }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        available = true
    }
    deinit {
        timer?.invalidate()
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
