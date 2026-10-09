import AppKit
import SwiftUI

@MainActor final class ClientWindowState: ObservableObject {
    @Published private(set) var fullScreen = false
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var transparent = false
    private var savedPresentation: NSApplication.PresentationOptions?
    private var savedTitle: NSWindow.TitleVisibility?
    private var savedTitlebarTransparency = false
    private var savedFullSizeContent = false
    private var savedButtons: [(NSButton, Bool)] = []

    func attach(_ window: NSWindow?) {
        guard self.window !== window else { return }
        restore()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        self.window = window
        fullScreen = window?.styleMask.contains(.fullScreen) == true
        guard let window else { return }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                     NSWindow.willExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if note.name == NSWindow.willExitFullScreenNotification || note.name == NSWindow.willCloseNotification {
                        self.fullScreen = false; self.restore()
                    } else {
                        self.fullScreen = window.styleMask.contains(.fullScreen)
                        self.apply()
                    }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        apply()
    }

    func setTransparent(_ enabled: Bool) { transparent = enabled; apply() }

    private func apply() {
        guard transparent, fullScreen, NSApp.isActive, let window, window.isKeyWindow else { restore(); return }
        if savedPresentation == nil {
            savedPresentation = NSApp.presentationOptions
            savedTitle = window.titleVisibility
            savedTitlebarTransparency = window.titlebarAppearsTransparent
            savedFullSizeContent = window.styleMask.contains(.fullSizeContentView)
            savedButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap {
                guard let button = window.standardWindowButton($0) else { return nil }
                return (button, button.isHidden)
            }
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        savedButtons.forEach { $0.0.isHidden = true }
        var presentation = NSApp.presentationOptions
        presentation.subtract([.autoHideMenuBar, .autoHideDock, .autoHideToolbar])
        presentation.formUnion([.hideMenuBar, .hideDock])
        NSApp.presentationOptions = presentation
    }

    private func restore() {
        guard let presentation = savedPresentation else { return }
        NSApp.presentationOptions = presentation
        savedPresentation = nil
        if let window, let title = savedTitle {
            window.titleVisibility = title
            window.titlebarAppearsTransparent = savedTitlebarTransparency
            if !savedFullSizeContent { window.styleMask.remove(.fullSizeContentView) }
        }
        savedButtons.forEach { $0.0.isHidden = $0.1 }
        savedButtons.removeAll(); savedTitle = nil
    }

    func detach() { attach(nil) }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

struct ClientWindowReader: NSViewRepresentable {
    let state: ClientWindowState
    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView(); view.onWindowChanged = { [weak state] in state?.attach($0) }; return view
    }
    func updateNSView(_ view: ReaderView, context: Context) { }
    static func dismantleNSView(_ view: ReaderView, coordinator: ()) { view.onWindowChanged?(nil) }
    final class ReaderView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self else { return }; self.onWindowChanged?(self.window) }
        }
    }
}
