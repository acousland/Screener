import SwiftUI
import AppKit
import ScreenerUI
import ScreenerCore

@main struct ScreenerClientApp: App {
    @StateObject private var model = ClientModel()
    @StateObject private var updater = UpdateController()
    var body: some Scene {
        WindowGroup("Screener", id: "client") { ClientView(model: model).frame(minWidth: 780, minHeight: 540) }
            .defaultSize(width: 1200, height: 800)
            .commands {
                UpdateCommands(updater: updater)
                CommandGroup(replacing: .newItem) { }
                CommandMenu("View") {
                    Toggle("Transparent Mode", isOn: $model.transparentMode)
                        .keyboardShortcut("t", modifiers: [.control, .option])
                }
                CommandMenu("Connection") {
                    Button("Disconnect") { model.disconnect() }.disabled(!model.connected && !model.connecting)
                    Toggle("Send Keyboard Shortcuts to Mini", isOn: $model.captureShortcuts)
                    Button("Send Clipboard Text to Mini") { model.sendClipboard() }.disabled(!model.connected)
                    Button("Get Clipboard Text from Mini") { model.receiveClipboard() }.disabled(!model.connected)
                }
            }
    }
}
private struct ClientView: View {
    @ObservedObject var model: ClientModel
    @StateObject private var windowState = ClientWindowState()
    private var transparent: Bool { model.transparentMode && windowState.fullScreen && model.connected }
    var body: some View {
        VStack(spacing: 0) {
            if model.connected || model.connecting {
                if !transparent {
                HStack(spacing: 14) {
                    Image(systemName: "display.2").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) { Text(model.desktop?.name ?? model.host).font(.callout.weight(.semibold)); Text(model.status).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let desktop = model.desktop {
                        Picker("Scaling", selection: Binding(get: { desktop.currentMode }, set: { model.setScaling($0) })) {
                            ForEach(desktop.modes) { mode in Text(mode.label).tag(mode.id) }
                        }.frame(width: 250)
                        Menu { Button("Send clipboard text to mini") { model.sendClipboard() }; Button("Get clipboard text from mini") { model.receiveClipboard() } } label: { Image(systemName: "doc.on.clipboard") }
                            .help("Share clipboard text")
                        Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Full screen")
                    }
                    Button("Disconnect") { model.disconnect() }
                }.padding(14).background(.bar)
                }
                ZStack {
                    RemoteDesktop(model: model, transparent: transparent)
                    if model.image == nil { VStack(spacing: 12) { ProgressView(); Text(model.status).foregroundStyle(.secondary) }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
                }
                if !transparent {
                HStack {
                    Text("Control–Option–Esc releases keyboard shortcuts").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Toggle("Remote shortcuts", isOn: $model.captureShortcuts).toggleStyle(.checkbox).font(.caption)
                }.padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
                }
            } else {
                connectionForm
            }
            if let error = model.error, !transparent {
                HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); Text(error).font(.callout).textSelection(.enabled); Spacer(); Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    .padding(14).background(.orange.opacity(0.08))
            }
        }
        .ignoresSafeArea(transparent ? .container : [], edges: .all)
        .background(ClientWindowReader(state: windowState))
        .onChange(of: transparent) { _, enabled in
            if enabled { model.captureShortcuts = true }
            windowState.setTransparent(enabled)
        }
    }
    private var connectionForm: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                ScreenerMark()
                Text("A bigger view\nof your mini.").font(.system(size: 34, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("A 4K desktop. Your preferred scaling.\nYour MacBook keyboard and trackpad.").font(.title3).foregroundStyle(.secondary).lineSpacing(5)
                Spacer()
                Label("Encrypted, direct connection", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
                Text("Screener Client").font(.caption).foregroundStyle(.tertiary)
            }.padding(36).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.055))
            VStack(alignment: .leading, spacing: 20) {
                Text("Connect to your Mac mini").font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nearby servers").font(.callout.weight(.medium))
                    Picker("Nearby servers", selection: Binding(get: { model.selectedServer }, set: { model.selectServer($0) })) {
                        Text(model.servers.isEmpty ? "Searching…" : "Enter an address manually").tag("")
                        ForEach(model.servers) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mini address").font(.callout.weight(.medium))
                    TextField("mac-mini.local or 192.168.1.10", text: $model.host)
                        .textFieldStyle(.roundedBorder).onChange(of: model.host) { _, _ in if !model.servers.contains(where: { $0.id == model.selectedServer && $0.name == model.host }) { model.selectedServer = "" } }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection key").font(.callout.weight(.medium))
                    SecureField("Paste from Screener Server", text: $model.connectionKey).textFieldStyle(.roundedBorder)
                    Text("On the mini, start Screener Server and choose Copy Connection Key.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Picker("Frame rate", selection: $model.fps) { Text("30 fps").tag(30); Text("60 fps").tag(60) }
                    Picker("Quality", selection: $model.bitrate) { Text("25 Mbps").tag(25); Text("45 Mbps").tag(45); Text("75 Mbps").tag(75) }
                }
                Toggle("Reconnect after a dropped connection", isOn: $model.reconnectAutomatically).font(.callout)
                Button { model.connect() } label: { Text("Connect").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.teal)
                    .disabled(model.host.isEmpty || model.connectionKey.isEmpty)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.padding(36).frame(width: 425)
        }.frame(maxHeight: .infinity)
    }
}
