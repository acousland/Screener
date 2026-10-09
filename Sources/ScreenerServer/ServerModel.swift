import AppKit
import SwiftUI
import Network
import ScreenCaptureKit
import ServiceManagement
import ScreenerCore

@MainActor final class ServerModel: ObservableObject {
    @Published var running = false
    @Published var starting = false
    @Published var streaming = false
    @Published var status = "Ready to set up"
    @Published var error: String?
    @Published var displays: [HostDisplay] = []
    @Published var selectedDisplay: CGDirectDisplayID = 0
    @Published var desktop: DesktopInfo?
    @Published var clientName: String?
    @Published var keyVisible = false
    @Published var secretCode = ""
    @Published var screenPermission = CGPreflightScreenCaptureAccess()
    @Published var controlPermission = AXIsProcessTrusted()
    @Published var loginItem = SMAppService.mainApp.status == .enabled
    @Published var clipboardEnabled = UserDefaults.standard.bool(forKey: "allowClipboard")
    var hostAddress: String { (Host.current().localizedName ?? ProcessInfo.processInfo.hostName) }
    var networkAddress: String { ProcessInfo.processInfo.hostName }
    private let displayManager = Displays()
    private let input = InputInjector()
    private var secret: PairingSecret?
    private var listener: NWListener?
    private var candidates: [ObjectIdentifier: PeerConnection] = [:]
    private var viewer: PeerConnection?
    private var hello: ClientHello?
    private var capture: DesktopCapture?
    private var generation = 0
    private var poll: Timer?
    private let networkQueue = DispatchQueue(label: "Screener.listener", qos: .userInteractive)
    init() {
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        refresh()
        if UserDefaults.standard.bool(forKey: "startServerOnLaunch") { Task { await start() } }
    }
    func refresh() {
        screenPermission = CGPreflightScreenCaptureAccess(); controlPermission = AXIsProcessTrusted()
        loginItem = SMAppService.mainApp.status == .enabled
        displays = displayManager.list()
        guard selectedDisplay != 0 else { return }
        do {
            let info = try displayManager.info(selectedDisplay)
            if desktop?.currentMode != info.currentMode || desktop?.streamWidth != info.streamWidth || desktop?.streamHeight != info.streamHeight {
                desktop = info
                if selectedDisplay == displayManager.virtualID { displayManager.saveScaling(info) }
                sendDesktop()
                if viewer != nil { Task { await restartCapture() } }
            }
        } catch { if viewer != nil { stopSession(error.localizedDescription) } }
    }
    func createVirtual() {
        do {
            let id = try displayManager.ensureVirtual()
            selectedDisplay = id; displayManager.restoreScaling(on: id); refresh(); error = nil
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard self.selectedDisplay == id else { return }
                self.displayManager.restoreScaling(on: id); self.refresh()
            }
        } catch { self.error = error.localizedDescription }
    }
    func chooseDisplay(_ id: CGDirectDisplayID) {
        selectedDisplay = id; desktop = nil; refresh()
    }
    func setScaling(_ id: Int32) {
        do { try displayManager.setMode(id, on: selectedDisplay); refresh() }
        catch { self.error = error.localizedDescription; sendFailure(error.localizedDescription) }
    }
    func requestScreenPermission() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        refresh()
    }
    func requestControlPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        refresh()
    }
    func setLoginItem(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginItem = enabled }
        catch { self.error = "Could not change Open at Login: \(error.localizedDescription)" }
    }
    func start() async {
        guard listener == nil else { return }
        error = nil
        if selectedDisplay == 0 { createVirtual() }
        guard selectedDisplay != 0 else { return }
        do {
            let key = try SecretStore.read(account: "server") ?? PairingSecret()
            try SecretStore.save(key, account: "server"); secret = key; secretCode = key.code
            let listener = try NWListener(using: SecureParameters.make(secret: key), on: NWEndpoint.Port(rawValue: SecureParameters.port)!)
            listener.service = NWListener.Service(name: hostAddress, type: SecureParameters.serviceType)
            listener.stateUpdateHandler = { [weak self, weak listener] state in Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready: self.running = true; self.starting = false; self.status = "Waiting for your MacBook"; UserDefaults.standard.set(true, forKey: "startServerOnLaunch")
                case .waiting(let error): self.status = "Waiting for network access"; self.error = "Network access is unavailable: \(error.localizedDescription). Check Local Network permission for Screener Server in System Settings."
                case .failed(let error): self.error = "Server could not listen: \(error.localizedDescription)"; self.stop()
                default: break
                }
            } }
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            self.listener = listener; starting = true; status = "Starting server…"; listener.start(queue: networkQueue)
        } catch { self.error = error.localizedDescription; starting = false; status = "Server stopped" }
    }
    func stop() {
        listener?.cancel(); listener = nil; running = false; starting = false
        UserDefaults.standard.set(false, forKey: "startServerOnLaunch")
        stopSession(nil)
        for connection in candidates.values { connection.close() }; candidates.removeAll()
        status = "Server stopped"
    }
    func disconnectViewer() { stopSession("Disconnected by the mini.") }
    private func accept(_ connection: NWConnection) {
        guard candidates.count < 8 else { connection.cancel(); return }
        let peer = PeerConnection(connection); let id = ObjectIdentifier(peer)
        candidates[id] = peer
        peer.onMessage = { [weak self, weak peer] message in Task { @MainActor in
            guard let self, let peer else { return }; self.receive(message, from: peer)
        } }
        peer.onClose = { [weak self, weak peer] reason in Task { @MainActor in
            guard let self, let peer else { return }; self.candidates.removeValue(forKey: ObjectIdentifier(peer))
            if self.viewer === peer { self.stopSession(reason) }
        } }
        peer.start()
        // TLS-authenticated clients must also send the protocol greeting promptly.
        Task { try? await Task.sleep(for: .seconds(10)); if self.candidates[id] === peer && self.viewer !== peer { peer.close() } }
    }
    private func receive(_ message: WireMessage, from peer: PeerConnection) {
        do {
            if message.kind == .hello {
                guard viewer == nil else { try peer.send(WireMessage(.failure, value: "This mini already has a connected viewer.")); peer.close(); return }
                let hello = try message.decode(ClientHello.self)
                guard hello.valid else { throw ScreenerError.message("The client version or streaming settings are unsupported.") }
                guard screenPermission else { throw ScreenerError.message("Grant Screener Server Screen Recording permission on the mini, then reconnect.") }
                self.hello = hello; viewer = peer; clientName = hello.name; status = "Connected to \(hello.name)"
                sendDesktop(); Task { await restartCapture() }; return
            }
            guard viewer === peer else { peer.close(); return }
            switch message.kind {
            case .input: input.apply(try message.decode(InputEvent.self), displayID: selectedDisplay)
            case .configure: setScaling(try message.decode(ConfigureDisplay.self).modeID)
            case .clipboard:
                guard clipboardEnabled else { sendFailure("Enable clipboard sharing in Screener Server first."); return }
                guard message.payload.count <= 256 * 1024 else { return }
                let text = try message.decode(String.self); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            case .clipboardRequest:
                guard clipboardEnabled else { sendFailure("Enable clipboard sharing in Screener Server first."); return }
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                guard text.utf8.count <= 128 * 1024 else { sendFailure("Clipboard text exceeds 128 KB."); return }
                try peer.send(WireMessage(.clipboard, value: text))
            case .ping: peer.send(WireMessage(.pong, payload: message.payload))
            default: break
            }
        } catch { try? peer.send(WireMessage(.failure, value: error.localizedDescription)); if viewer !== peer { peer.close() } }
    }
    private func sendDesktop() { if let desktop, let viewer { try? viewer.send(WireMessage(.desktop, value: desktop)) } }
    private func sendFailure(_ text: String) { if let viewer { try? viewer.send(WireMessage(.failure, value: text)) } }
    private func restartCapture() async {
        generation += 1; let current = generation
        let previous = capture; capture = nil; streaming = false
        await previous?.stop()
        guard current == generation, let peer = viewer, let hello, let desktop else { return }
        let capture = DesktopCapture(); self.capture = capture
        capture.onError = { [weak self] text in Task { @MainActor in
            guard let self, self.generation == current else { return }; self.error = text; self.stopSession(text)
        } }
        do {
            try await capture.start(displayID: selectedDisplay, width: desktop.streamWidth, height: desktop.streamHeight,
                fps: hello.framesPerSecond, bitrate: hello.megabitsPerSecond, canSend: { [weak peer] in peer?.readyForVideo == true },
                onFormat: { [weak peer] format in try? peer?.send(WireMessage(.format, value: format)) },
                onFrame: { [weak peer] frame in peer?.sendVideo(frame) == true })
            guard current == generation, viewer === peer else { await capture.stop(); return }
            streaming = true; status = "Sharing \(desktop.name)"
        } catch { if current == generation { self.error = error.localizedDescription; stopSession(error.localizedDescription) } }
    }
    private func stopSession(_ reason: String?) {
        generation += 1; input.releaseAll()
        let old = viewer; viewer = nil; hello = nil; clientName = nil; streaming = false
        if let old { candidates.removeValue(forKey: ObjectIdentifier(old)); old.close() }
        let capture = capture; self.capture = nil; Task { await capture?.stop() }
        status = running ? "Waiting for your MacBook" : "Server stopped"
        if let reason { error = reason }
    }
    func rotateKey() {
        guard viewer == nil else { error = "Disconnect the viewer before changing the connection key."; return }
        do {
            let key = try PairingSecret(); try SecretStore.save(key, account: "server"); secretCode = key.code; secret = key
            let wasRunning = running; stop(); if wasRunning { Task { await start() } }
        } catch { self.error = error.localizedDescription }
    }
}
