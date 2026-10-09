import SwiftUI
import AppKit
import ScreenerUI
import ScreenerCore

@main struct ScreenerServerApp: App {
    @StateObject private var model = ServerModel()
    @StateObject private var updater = UpdateController()
    var body: some Scene {
        WindowGroup("Screener Server", id: "server") { ServerView(model: model).frame(minWidth: 590, minHeight: 670) }
            .defaultSize(width: 650, height: 760)
            .commands { UpdateCommands(updater: updater) }
        MenuBarExtra("Screener Server", systemImage: model.streaming ? "display.2" : "display") {
            ServerMenu(model: model, updater: updater)
        }
    }
}
private struct ServerMenu: View {
    @ObservedObject var model: ServerModel
    @ObservedObject var updater: UpdateController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Button("Open Screener Server") { openWindow(id: "server"); NSApp.activate(ignoringOtherApps: true) }
        if model.running || model.starting { Button("Stop Server") { model.stop() } }
        else { Button("Start Server") { Task { await model.start() } } }
        Button("Check for Updates…") { updater.check() }.disabled(!updater.available)
        Divider(); Button("Quit Screener Server") { model.stop(); NSApp.terminate(nil) }
    }
}
private struct ServerView: View {
    @ObservedObject var model: ServerModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    ScreenerMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your mini, wherever you work.").font(.title2.weight(.semibold))
                        Text("Screener Server").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack { StatusPill(model.streaming ? "Sharing" : model.running ? "Available" : "Stopped", active: model.running); Text(model.status).font(.callout).foregroundStyle(.secondary); Spacer() }
                if let error = model.error {
                    HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); Text(error).font(.callout); Spacer(); Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(14).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                GroupBox("Monitor") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Picker("Share", selection: Binding(get: { model.selectedDisplay }, set: { model.chooseDisplay($0) })) {
                                if model.displays.isEmpty { Text("Create a virtual monitor").tag(UInt32(0)) }
                                ForEach(model.displays) { display in Text(display.name).tag(display.id) }
                            }
                            Button("Create Virtual Monitor") { model.createVirtual() }
                        }
                        if let desktop = model.desktop {
                            Picker("Desktop scaling", selection: Binding(get: { desktop.currentMode }, set: { model.setScaling($0) })) {
                                ForEach(desktop.modes) { mode in Text(mode.label).tag(mode.id) }
                            }
                            Text("\(desktop.streamWidth) × \(desktop.streamHeight) stream · \(desktop.logicalWidth) × \(desktop.logicalHeight) workspace")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Open macOS Display Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!) }
                            .buttonStyle(.link)
                        Text("The virtual monitor stays available while Screener Server is open, including after the MacBook disconnects.").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                GroupBox("Connect from your MacBook") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Address", value: "\(model.networkAddress):\(SecureParameters.port)")
                            .textSelection(.enabled)
                        Text("Open Screener Client, choose this mini, and paste its connection key.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Copy Connection Key") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.secretCode, forType: .string) }
                                .disabled(model.secretCode.isEmpty)
                            Button(model.keyVisible ? "Hide Key" : "Show Key") { model.keyVisible.toggle() }.disabled(model.secretCode.isEmpty)
                            Spacer(); Button("New Key") { model.rotateKey() }.disabled(model.clientName != nil || model.secretCode.isEmpty)
                        }
                        if model.keyVisible { Text(model.secretCode).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                        if model.clientName != nil { Button("Disconnect MacBook") { model.disconnectViewer() } }
                    }.padding(10)
                }
                GroupBox("Permissions & preferences") {
                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow("Screen Recording", granted: model.screenPermission, action: model.requestScreenPermission)
                        permissionRow("Accessibility · keyboard and mouse", granted: model.controlPermission, action: model.requestControlPermission)
                        Toggle("Allow clipboard text sharing", isOn: $model.clipboardEnabled)
                            .onChange(of: model.clipboardEnabled) { _, value in UserDefaults.standard.set(value, forKey: "allowClipboard") }
                        Toggle("Open at Login", isOn: Binding(get: { model.loginItem }, set: { model.setLoginItem($0) }))
                        Text("Run the server in your logged-in desktop session. After granting Screen Recording, macOS may ask you to quit and reopen it.").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                HStack {
                    Text("Encrypted · local network · Apple silicon").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.running || model.starting { Button("Stop Server") { model.stop() } }
                    else { Button("Start Server") { Task { await model.start() } }.buttonStyle(.borderedProminent).tint(.teal) }
                }
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack { Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? Color.teal : .secondary); Text(title); Spacer(); if !granted { Button("Grant Access", action: action) } }
    }
}
