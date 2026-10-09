import SwiftUI
import ScreenerCore

struct ServerSetupView: View {
    @ObservedObject var model: ClientModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.serverStatus?.name ?? model.host).font(.title2.weight(.semibold))
                    Text("Securely paired · Server setup").foregroundStyle(.secondary)
                }
                Spacer()
                if model.applyingServerCommand { ProgressView().controlSize(.small) }
            }.padding(24)
            Divider()
            Form {
                if let info = model.serverStatus {
                    Section("Screen") {
                        Picker("Share", selection: Binding(get: { info.selectedDisplay }, set: { model.selectDisplay($0) })) {
                            if info.selectedDisplay == 0 { Text("Create or choose a screen").tag(UInt32(0)) }
                            ForEach(info.displays) { Text($0.name).tag($0.id) }
                        }
                        Button(info.displays.contains(where: { $0.virtual }) ? "Use Screener Screen" : "Create Screener Screen") { model.createScreen() }
                        if let desktop = info.desktop {
                            Picker("Resolution", selection: Binding(get: { desktop.currentMode }, set: { model.setScaling($0) })) {
                                ForEach(desktop.modes) { Text($0.label).tag($0.id) }
                            }
                            LabeledContent("Workspace", value: "\(desktop.logicalWidth) × \(desktop.logicalHeight)")
                        }
                        Text("The virtual screen stays available while Server is open, even after you stop viewing.").font(.caption).foregroundStyle(.secondary)
                    }.disabled(model.applyingServerCommand || info.update?.busy == true)
                    ServerPreferencesView(model: model)
                    Section("Video") {
                        Picker("Frame rate", selection: $model.fps) { Text("30 fps").tag(30); Text("60 fps").tag(60) }
                        Picker("Quality", selection: $model.bitrate) { Text("25 Mbps").tag(25); Text("45 Mbps").tag(45); Text("75 Mbps").tag(75); Text("100 Mbps").tag(100) }
                        Picker("Video detail", selection: $model.maximumVideoHeight) {
                            Text("Full · up to 4K").tag(2160); Text("Balanced · 1440p").tag(1440); Text("Fast · 1080p").tag(1080)
                        }
                    }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("Disconnect") { model.disconnect() }
                Spacer()
                Button(model.serverStatus?.selectedDisplay == 0 ? "Create & Start Screen" : "Start Screen") { model.startScreen() }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(model.applyingServerCommand || model.serverStatus?.screenRecording != true || model.serverStatus?.update?.busy == true)
            }.padding(20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ServerPreferencesView: View {
    @ObservedObject var model: ClientModel
    var body: some View {
        if let info = model.serverStatus {
            Section("Mini") {
                Toggle("Open Server at Login", isOn: Binding(get: { info.openAtLogin || info.loginApprovalRequired }, set: {
                    model.sendServerCommand(ServerCommand(.setPreferences, openAtLogin: $0))
                }))
                if info.loginApprovalRequired {
                    Text("Approve Screener Server in Login Items on the mini to finish enabling this.").font(.caption).foregroundStyle(.orange)
                    Button("Open Login Items on Mini") { model.sendServerCommand(ServerCommand(.loginSettings)) }
                }
                Toggle("Allow clipboard text sharing", isOn: Binding(get: { info.clipboardEnabled }, set: {
                    model.sendServerCommand(ServerCommand(.setPreferences, clipboardEnabled: $0))
                }))
                permission("Screen Recording", granted: info.screenRecording, command: .screenRecordingSettings)
                permission("Accessibility · keyboard and mouse", granted: info.accessibility, command: .accessibilitySettings)
                if !info.screenRecording || !info.accessibility {
                    Text("Approve these macOS permissions on the mini once, using its screen or macOS Screen Sharing. Reopen Server if macOS requests it. Server must run in a logged-in desktop session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(model.applyingServerCommand)
            if let update = info.update {
                Section("Server Updates") {
                    LabeledContent("Installed", value: info.version ?? "Unknown")
                    Text(update.message).font(.callout).foregroundStyle(update.phase == .failed ? .orange : .secondary).textSelection(.enabled)
                    if let progress = update.progress, update.busy { ProgressView(value: progress) }
                    if let result = model.serverUpdateResult { Text(result).font(.callout).foregroundStyle(.secondary) }
                    Button("Update & Restart Server") { model.updateServer() }.disabled(model.applyingServerCommand || update.busy)
                    Text("Install the latest signed update on the mini. Viewing pauses for the restart; this Client reconnects automatically. Administrator approval may still be needed on the mini.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func permission(_ title: String, granted: Bool, command: ServerCommand.Action) -> some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(granted ? .teal : .secondary)
            Spacer()
            if !granted { Button("Open on Mini") { model.sendServerCommand(ServerCommand(command)) } }
        }
    }
}
