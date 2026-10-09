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
            window.contentView = NSHostingView(rootView: SessionControlsView(model: model, keyboard: model.keyboardCapture, windows: self))
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
    @ObservedObject var keyboard: KeyboardCaptureController
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
                    Picker("Quality", selection: $model.bitrate) { Text("25 Mbps").tag(25); Text("45 Mbps").tag(45); Text("75 Mbps").tag(75); Text("100 Mbps").tag(100) }
                    Picker("Video detail", selection: $model.maximumVideoHeight) {
                        Text("Full · up to 4K").tag(2160); Text("Balanced · 1440p").tag(1440); Text("Fast · 1080p").tag(1080)
                    }.disabled(model.connected && !model.supportsVideoDetail)
                    Text("Lower detail reduces video work while keeping the desktop workspace size. Full gives the sharpest text.")
                        .font(.caption).foregroundStyle(.secondary)
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
                Section("Audio") {
                    Toggle("Play mini audio on this Mac", isOn: Binding(get: { model.audioEnabled }, set: { model.setAudioEnabled($0) }))
                        .disabled(model.applyingStreamSettings || (model.connected && !model.supportsAudio))
                    Toggle("Mute mini speakers", isOn: Binding(get: { model.muteHostAudio }, set: { model.setMuteHostAudio($0) }))
                        .disabled(!model.audioEnabled || model.applyingStreamSettings || (model.connected && !model.supportsHostMute))
                    Text(model.connected && !model.supportsHostMute
                        ? "Update Server to 0.1.5 or later to mute its speakers."
                        : "Mute the mini's output while forwarding audio. Its previous mute state is restored when forwarding stops.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Volume")
                        Slider(value: $model.audioVolume, in: 0...1).disabled(!model.audioEnabled)
                        Text("\(Int(model.audioVolume * 100))%").monospacedDigit().frame(width: 40)
                    }
                    Text(model.connected && !model.supportsAudio
                        ? "Update Screener Server to 0.1.4 or later to hear the mini."
                        : "System audio plays through this Mac's selected output. Volume affects this Mac only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Session") {
                    Toggle("Game Mouse", isOn: Binding(get: { model.gameMouse }, set: { model.setGameMouse($0) }))
                        .disabled(!model.connected || !model.supportsGameMouse)
                    HStack {
                        Text("Mouse sensitivity")
                        Slider(value: $model.mouseSensitivity, in: 0.25...3)
                        Text(String(format: "%.2f×", model.mouseSensitivity)).monospacedDigit().frame(width: 50)
                    }.disabled(!model.gameMouse)
                    Text("Relative movement for first-person games. Click the viewer to lock the pointer. Control–Option–G toggles; Control–Option–Esc releases.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Responsive Cursor", isOn: Binding(get: { model.responsiveCursor }, set: { model.setResponsiveCursor($0) }))
                        .disabled(model.applyingStreamSettings || (model.connected && !model.supportsResponsiveCursor))
                    Text(model.connected && !model.supportsResponsiveCursor
                        ? "Update Screener Server to 0.1.4 or later for a responsive cursor."
                        : "Move the pointer locally without waiting for video. Turn off for the mini's exact cursor shapes.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Transparent Mode in full screen", isOn: $model.transparentMode)
                    Toggle("Send keyboard shortcuts to mini", isOn: $model.captureShortcuts)
                    if model.captureShortcuts && !keyboard.available {
                        Text("Allow Accessibility for Screener Client to send system shortcuts such as Command–Space to the mini.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Allow Shortcut Capture…") { keyboard.requestAccess() }
                        if keyboard.permissionGranted {
                            Text("Quit and reopen Screener Client if shortcut capture is still unavailable.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
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
