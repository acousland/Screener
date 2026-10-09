import AppKit
import SwiftUI
import ScreenerCore

/// An ordinary desktop window: it stays in its Space when the viewer enters full screen.
@MainActor final class SessionControlsWindowController: ObservableObject {
    private var window: NSWindow?
    private weak var desktopWindow: NSWindow?

    func attachDesktop(_ window: NSWindow?) { desktopWindow = window }

    func toggle(model: ClientModel) {
        if let window, window.isKeyWindow { returnToDesktop() }
        else { show(model: model) }
    }

    func show(model: ClientModel, activate: Bool = true) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Session Controls"
            window.identifier = NSUserInterfaceItemIdentifier("ScreenerSessionControls")
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.collectionBehavior = [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
            window.contentView = NSHostingView(rootView: SessionControlsView(model: model, windows: self))
            window.contentMinSize = NSSize(width: 400, height: 560)
            window.center()
            window.setFrameAutosaveName("ScreenerSessionControls")
            self.window = window
        }
        guard let window else { return }
        if activate {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else if !window.isVisible {
            // Open behind the viewer before its full-screen transition, keeping input on the viewer.
            window.orderBack(nil)
        }
    }

    func returnToDesktop() {
        guard let desktopWindow else { return }
        desktopWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct SessionControlsView: View {
    @ObservedObject var model: ClientModel
    let windows: SessionControlsWindowController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "display.2").font(.title2).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.desktop?.name ?? "Screener").font(.headline)
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            Divider()
            Form {
                Section("Display") {
                    if let desktop = model.desktop {
                        Picker("Resolution", selection: Binding(get: { desktop.currentMode }, set: { model.setScaling($0) })) {
                            ForEach(desktop.modes) { Text($0.label).tag($0.id) }
                        }
                        .disabled(model.applyingStreamSettings)
                        LabeledContent("Video size", value: "\(desktop.streamWidth) × \(desktop.streamHeight)")
                        Text("Resolution changes apply to the running session.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Connect to the mini to change its resolution.").foregroundStyle(.secondary)
                    }
                }
                Section("Video") {
                    Picker("Frame rate", selection: $model.fps) { Text("30 fps").tag(30); Text("60 fps").tag(60) }
                    Picker("Quality", selection: $model.bitrate) { Text("25 Mbps").tag(25); Text("45 Mbps").tag(45); Text("75 Mbps").tag(75) }
                    if model.connected {
                        Button(model.applyingStreamSettings ? "Applying…" : "Apply Video Settings") { model.applyStreamSettings() }
                            .disabled(!model.streamSettingsChanged || model.applyingStreamSettings)
                        Text(model.supportsLiveStreamSettings
                            ? "Video pauses briefly while the new settings take effect. Your connection stays open."
                            : "Update Screener Server to 0.1.2 or later to change video settings during a session.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("These settings will be used on your next connection.").font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(model.applyingStreamSettings || (model.connected && !model.supportsLiveStreamSettings))
                Section("Session") {
                    Toggle("Transparent Mode in full screen", isOn: $model.transparentMode)
                    Toggle("Send keyboard shortcuts to mini", isOn: $model.captureShortcuts)
                    Toggle("Reconnect after a dropped connection", isOn: $model.reconnectAutomatically)
                }
                Section("Clipboard") {
                    Button("Send Clipboard Text to Mini") { model.sendClipboard() }
                    Button("Get Clipboard Text from Mini") { model.receiveClipboard() }
                    Text("Enable clipboard sharing in Screener Server first.").font(.caption).foregroundStyle(.secondary)
                }.disabled(!model.connected)
                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                        Button("Dismiss") { model.error = nil }
                    }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("Disconnect") { model.disconnect() }.disabled(!model.connected && !model.connecting)
                Spacer()
                Button("Return to Desktop") { windows.returnToDesktop() }
                    .keyboardShortcut("s", modifiers: [.control, .option])
            }.padding(16)
            Text("Control–Option–S switches between the remote desktop and these controls.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 16)
        }
    }
}
