import AppKit
import SwiftUI
import Network
import ScreenerCore

struct DiscoveredServer: Identifiable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
}
struct PairedServer: Codable, Identifiable {
    var id: String { host }
    let host: String
    let name: String
}
@MainActor final class ClientModel: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
    @Published var connectionKey = ""
    @Published var servers: [DiscoveredServer] = []
    @Published var selectedServer = ""
    @Published private(set) var pairedServers: [PairedServer] = []
    @Published private(set) var linked = false
    @Published private(set) var serverStatus: ServerStatus?
    @Published private(set) var applyingServerCommand = false
    @Published private(set) var serverUpdateResult: String?
    @Published var connected = false
    @Published var connecting = false
    @Published var desktop: DesktopInfo?
    @Published var image: CVPixelBuffer?
    @Published var status = "Choose your Mac mini"
    @Published var error: String?
    @Published var fps = 60
    @Published var bitrate = 45
    @Published var maximumVideoHeight = 2160
    @Published private(set) var audioEnabled = UserDefaults.standard.object(forKey: "audioEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(audioEnabled, forKey: "audioEnabled") }
    }
    @Published var audioVolume: Double = 1 { didSet { audioPlayer?.setVolume(Float(audioVolume)) } }
    @Published private(set) var muteHostAudio = UserDefaults.standard.object(forKey: "muteHostAudio") as? Bool ?? true {
        didSet { UserDefaults.standard.set(muteHostAudio, forKey: "muteHostAudio") }
    }
    let keyboardCapture = KeyboardCaptureController()
    @Published private(set) var applyingStreamSettings = false
    @Published var captureShortcuts = true
    @Published private(set) var gameMouse = false
    @Published var mouseSensitivity = 1.0
    @Published var reconnectAutomatically = true
    @Published var receivedFrames = 0
    @Published private(set) var cursorEmbedded = true
    @Published private(set) var responsiveCursor = UserDefaults.standard.object(forKey: "responsiveCursor") as? Bool ?? true {
        didSet { UserDefaults.standard.set(responsiveCursor, forKey: "responsiveCursor") }
    }
    @Published var transparentMode = UserDefaults.standard.object(forKey: "transparentMode") as? Bool ?? true {
        didSet { UserDefaults.standard.set(transparentMode, forKey: "transparentMode") }
    }
    private var browser: NWBrowser?
    private var peer: PeerConnection?
    private var decoder: VideoDecoder?
    private var audioPlayer: AudioPlayback?
    private var audioPlaybackFailed = false
    private var reconnectTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var savedEndpoint: NWEndpoint?
    private var savedSecret: PairingSecret?
    private var userDisconnected = false
    private var serverFailure: String?
    private var desiredSession = false
    private var pendingCommand: UUID?
    private var commandTimeout: Task<Void, Never>?
    private var greetingTimeout: Task<Void, Never>?
    private var updatingServerBuild: String?
    private var updateConnectionLost = false
    private var selectedDisplayWasVirtual = true
    private var preferredDisplayName: String?
    private let browseQueue = DispatchQueue(label: "Screener.discovery")
    private let decodeQueue = DispatchQueue(label: "Screener.decode", qos: .userInteractive)
    private let frames = LatestValueSlot<(PixelFrame, ObjectIdentifier)>()
    init() {
        if let data = UserDefaults.standard.data(forKey: "pairedServers"), let saved = try? JSONDecoder().decode([PairedServer].self, from: data) {
            pairedServers = Array(saved.filter { !$0.host.isEmpty && $0.host.count <= 255 && $0.name.count <= 100 }.prefix(32))
        }
        if !host.isEmpty, let key = try? SecretStore.read(account: "client:\(host)") { connectionKey = key.code }
        let browser = NWBrowser(for: .bonjour(type: SecureParameters.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in Task { @MainActor in
            guard let self else { return }
            self.servers = results.compactMap { result in
                guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                return DiscoveredServer(id: "\(name).\(type).\(domain)", name: name, endpoint: result.endpoint)
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if self.selectedServer.isEmpty, !self.linked, !self.connecting, !self.host.isEmpty {
                let name = self.pairedServers.first(where: { $0.host == self.host })?.name ?? self.host
                self.selectedServer = self.servers.first(where: { $0.name == name })?.id ?? ""
            }
        } }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { Task { @MainActor in self?.error = "Discovery unavailable: \(error.localizedDescription). You can enter the mini's address manually." } }
        }
        self.browser = browser; browser.start(queue: browseQueue)
    }
    func selectServer(_ id: String) {
        selectedServer = id
        guard let server = servers.first(where: { $0.id == id }) else { return }
        host = server.name
        connectionKey = (try? SecretStore.read(account: "client:\(host)"))?.code ?? ""
    }
    func selectPairedServer(_ saved: PairedServer) {
        host = saved.host
        selectedServer = servers.first(where: { $0.name == saved.name })?.id ?? ""
        connectionKey = (try? SecretStore.read(account: "client:\(host)"))?.code ?? ""
    }
    func pastePairingInvitation() {
        do {
            let invitation = try PairingInvitation(text: NSPasteboard.general.string(forType: .string) ?? "")
            host = invitation.host; connectionKey = invitation.secret.code
            selectedServer = servers.first(where: { $0.name == invitation.name })?.id ?? ""
            error = nil; status = "Ready to pair with \(invitation.name)"
        } catch { self.error = error.localizedDescription }
    }
    func connect(autoStart: Bool = true) {
        guard !linked, !connected, !connecting else { return }
        error = nil; userDisconnected = false; retryAttempt = 0; reconnectTask?.cancel()
        desiredSession = autoStart; updatingServerBuild = nil; updateConnectionLost = false; serverUpdateResult = nil
        do {
            let secret = try PairingSecret(code: connectionKey)
            let endpoint: NWEndpoint
            if let server = servers.first(where: { $0.id == selectedServer }) { endpoint = server.endpoint }
            else {
                let address = try ServerAddress(host)
                endpoint = .hostPort(host: NWEndpoint.Host(address.host), port: NWEndpoint.Port(rawValue: address.port)!)
            }
            savedEndpoint = endpoint; savedSecret = secret
            begin(endpoint: endpoint, secret: secret)
        } catch { self.error = error.localizedDescription }
    }
    private func begin(endpoint: NWEndpoint, secret: PairingSecret) {
        connecting = true; connected = false; linked = false; serverStatus = nil
        status = "Connecting securely…"; desktop = nil; image = nil; serverFailure = nil; applyingStreamSettings = false
        clearPendingCommand()
        let peer = PeerConnection(endpoint: endpoint, secret: secret); self.peer = peer
        let decoder = VideoDecoder(); self.decoder = decoder
        audioPlaybackFailed = false
        let audio = AudioPlayback(); self.audioPlayer = audio
        audio.setEnabled(audioEnabled); audio.setVolume(Float(audioVolume))
        audio.onError = { [weak self, weak peer] text in Task { @MainActor in
            guard let self, let peer, self.peer === peer else { return }
            self.audioPlaybackFailed = true; self.setAudioEnabled(false); self.error = text
        } }
        let peerID = ObjectIdentifier(peer)
        let budget = DecodeBudget()
        decoder.onImage = { [weak self, weak decoder] image in
            self?.deliver(PixelFrame(image, cursorEmbedded: decoder?.cursorEmbedded ?? true), peerID: peerID)
        }
        peer.onReady = { [weak self, weak peer] in DispatchQueue.main.async {
            guard let self, let peer, self.peer === peer else { return }
            self.status = "Connecting to Server setup…"
            try? peer.send(WireMessage(.hello, value: self.streamHello()))
            self.greetingTimeout?.cancel()
            self.greetingTimeout = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, self.peer === peer, !self.linked, !self.connected else { return }
                self.disconnect(); self.error = "Server did not respond. Check that it is running on the mini and update both apps."
            }
        } }
        peer.onMessage = { [weak self, weak peer, weak decoder, weak audio] message in
            guard let self, let peer, let decoder else { return }
            if message.kind == .audio { audio?.enqueue(message.payload) }
            else if message.kind == .format || message.kind == .video {
                guard budget.reserve() else {
                    Task { @MainActor in
                        if self.peer === peer { self.disconnect(); self.error = "Video decoding cannot keep up. Choose 30 fps or a lower quality setting and reconnect." }
                    }; return
                }
                self.decodeQueue.async {
                    defer { budget.release() }
                    do {
                        if message.kind == .format { try decoder.configure(message.decode(VideoFormat.self)) }
                        else { try decoder.decode(message.payload) }
                    } catch { Task { @MainActor in if self.peer === peer { self.error = error.localizedDescription; self.disconnect() } } }
                }
            } else { DispatchQueue.main.async { guard self.peer === peer else { return }; self.receive(message, secret: secret) } }
        }
        peer.onClose = { [weak self, weak peer] reason in DispatchQueue.main.async {
            guard let self, let peer, self.peer === peer else { return }
            if self.updatingServerBuild != nil { self.updateConnectionLost = true }
            self.peer = nil; self.connected = false; self.connecting = false; self.linked = false; self.serverStatus = nil
            self.image = nil; self.desktop = nil; self.applyingStreamSettings = false; self.gameMouse = false
            self.clearPendingCommand(); self.greetingTimeout?.cancel()
            let decoder = self.decoder; self.decoder = nil; self.decodeQueue.async { decoder?.invalidate() }
            self.audioPlayer?.stop(); self.audioPlayer = nil
            self.status = "Disconnected"; if let reason, self.updatingServerBuild == nil { self.error = reason }
            let rejected = reason != nil && reason == self.serverFailure
            if !rejected && !self.userDisconnected && (self.reconnectAutomatically || self.updatingServerBuild != nil) { self.scheduleReconnect() }
        } }
        peer.start()
    }
    // Keep the newest frame while the main thread is busy drawing or handling input.
    nonisolated private func deliver(_ frame: PixelFrame, peerID: ObjectIdentifier) {
        guard frames.offer((frame, peerID)) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let (latest, source) = self.frames.take() else { return }
            if self.connected, self.desiredSession, let peer = self.peer, ObjectIdentifier(peer) == source {
                self.cursorEmbedded = latest.cursorEmbedded
                self.image = latest.buffer; self.receivedFrames += 1; self.retryAttempt = 0
            }
        }
    }
    private func receive(_ message: WireMessage, secret: PairingSecret) {
        do {
            switch message.kind {
            case .serverStatus:
                let info = try message.decode(ServerStatus.self)
                guard info.valid else { throw ScreenerError.message("Invalid server setup status.") }
                let first = !linked
                linked = true; connecting = false; serverStatus = info; greetingTimeout?.cancel()
                if info.completedRequest == pendingCommand, pendingCommand != nil { clearPendingCommand() }
                if first {
                    retryAttempt = 0
                    rememberPairing(secret, name: info.name)
                    if updateConnectionLost, let expectedBuild = updatingServerBuild {
                        serverUpdateResult = info.build == expectedBuild ? "Server updated to \(info.version ?? "the new version")." : "Server reopened, but its version does not match the requested update. Try updating again."
                        if info.build != expectedBuild { error = serverUpdateResult }
                        updatingServerBuild = nil; updateConnectionLost = false
                    }
                    status = "Paired with \(info.name)"
                    if desiredSession {
                        if info.update?.busy == true {
                            resumeAfterScreenCreation = true; status = "Waiting for the Server update to finish…"
                        } else if !selectedDisplayWasVirtual, let preferredDisplayName, let display = info.displays.first(where: { $0.name == preferredDisplayName }), display.id != info.selectedDisplay {
                            resumeAfterScreenCreation = true; sendServerCommand(ServerCommand(.selectDisplay, displayID: display.id))
                        } else if selectedDisplayWasVirtual, info.displays.contains(where: { $0.virtual }) == false, info.selectedDisplay != 0 {
                            // A relaunched server needs a new virtual screen rather than silently sharing a physical one.
                            resumeAfterScreenCreation = true; sendServerCommand(ServerCommand(.createVirtualScreen))
                        } else { startScreen() }
                    }
                }
                if let update = info.update, update.phase == .restarting { updatingServerBuild = update.targetBuild }
                if !info.sessionActive {
                    if connected {
                        connected = false; desktop = nil; image = nil; gameMouse = false; audioPlayer?.setEnabled(false)
                        let decoder = decoder; decodeQueue.async { decoder?.invalidate() }
                    }
                    if !first, !applyingServerCommand, desiredSession, info.update?.busy != true, pendingCommand == nil {
                        // Resume only after the requested display setup has been acknowledged.
                        if resumeAfterScreenCreation { resumeAfterScreenCreation = false; startScreen() }
                    }
                    if !connected, !desiredSession { status = "Ready to start a Screener screen" }
                }
            case .desktop:
                // Older servers ignore manageServer and start streaming immediately.
                if serverStatus == nil { desiredSession = true }
                guard desiredSession else { return }
                let info = try message.decode(DesktopInfo.self)
                guard info.streamWidth > 0, info.streamWidth <= 3840, info.streamHeight > 0, info.streamHeight <= 2160,
                    info.logicalWidth > 0, info.logicalHeight > 0, info.modes.count <= 200 else { throw ScreenerError.message("Invalid desktop configuration.") }
                guard ConfigureDisplay(modeID: info.currentMode, fps: info.framesPerSecond, bitrate: info.megabitsPerSecond, maximumVideoHeight: info.maximumVideoHeight).valid else {
                    throw ScreenerError.message("Invalid desktop streaming settings.")
                }
                desktop = info; connected = true; connecting = false; greetingTimeout?.cancel()
                audioPlayer?.setEnabled(audioEnabled)
                if let value = info.framesPerSecond { fps = value }
                if let value = info.megabitsPerSecond { bitrate = value }
                if let embedded = info.cursorEmbedded { responsiveCursor = !embedded }
                if let height = info.maximumVideoHeight { maximumVideoHeight = height }
                if let enabled = info.audioEnabled {
                    if audioPlaybackFailed {
                        audioEnabled = false; audioPlayer?.setEnabled(false)
                        if enabled { peer?.send(try WireMessage(.configure, value: ConfigureDisplay(modeID: info.currentMode, audioEnabled: false))) }
                    } else { audioEnabled = enabled; audioPlayer?.setEnabled(enabled) }
                }
                if let mute = info.muteHostAudio { muteHostAudio = mute }
                applyingStreamSettings = false
                status = "\(info.streamWidth) × \(info.streamHeight) · \(info.framesPerSecond ?? fps) fps target"
                if serverStatus == nil { rememberPairing(secret, name: host) }
            case .serverError:
                clearPendingCommand()
                resumeAfterScreenCreation = false
                error = String(try message.decode(String.self).prefix(2000))
                if !connected { desiredSession = false; status = "Server setup needs attention" }
            case .failure:
                applyingStreamSettings = false
                let text = String(try message.decode(String.self).prefix(2000)); error = text; serverFailure = text
                if !connected && !linked { userDisconnected = true; disconnect(); error = text }
            case .clipboard:
                guard message.payload.count <= 256 * 1024 else { return }
                let text = try message.decode(String.self); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            default: break
            }
        } catch { self.error = error.localizedDescription; disconnect() }
    }
    func disconnect() {
        userDisconnected = true; reconnectTask?.cancel(); reconnectTask = nil
        desiredSession = false; updatingServerBuild = nil; updateConnectionLost = false; resumeAfterScreenCreation = false
        clearPendingCommand(); greetingTimeout?.cancel()
        let peer = peer; self.peer = nil; peer?.close()
        let decoder = decoder; self.decoder = nil; decodeQueue.async { decoder?.invalidate() }
        audioPlayer?.stop(); audioPlayer = nil
        connected = false; connecting = false; linked = false; serverStatus = nil; image = nil; desktop = nil; status = "Disconnected"; applyingStreamSettings = false; gameMouse = false
    }
    private func scheduleReconnect() {
        guard let endpoint = savedEndpoint, let secret = savedSecret, retryAttempt < (updatingServerBuild != nil ? 24 : 5) else {
            if updatingServerBuild != nil { error = "Server has not returned after its update. Check it on the mini, then reconnect."; updatingServerBuild = nil }
            return
        }
        retryAttempt += 1
        let delay = min(15, retryAttempt * 3); status = updatingServerBuild == nil ? "Reconnecting in \(delay)s…" : "Server is updating · Reconnecting in \(delay)s…"
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, !self.userDisconnected else { return }
            self.begin(endpoint: endpoint, secret: secret)
        }
    }
    func sendInput(_ input: InputEvent) { if connected, input.valid { try? peer?.send(WireMessage(.input, value: input)) } }
    func setScaling(_ mode: Int32) {
        if linked, !connected { sendServerCommand(ServerCommand(.setResolution, modeID: mode)); return }
        if desktop?.modes.contains(where: { $0.id == mode }) == true { try? peer?.send(WireMessage(.configure, value: ConfigureDisplay(modeID: mode))) }
    }
    private var resumeAfterScreenCreation = false
    private func streamHello() -> ClientHello {
        ClientHello(name: Host.current().localizedName ?? "MacBook", fps: fps, bitrate: bitrate, responsiveCursor: responsiveCursor,
            maximumVideoHeight: maximumVideoHeight, audioEnabled: audioEnabled, muteHostAudio: muteHostAudio, manageServer: true)
    }
    private func rememberPairing(_ secret: PairingSecret, name: String) {
        do {
            try SecretStore.save(secret, account: "client:\(host)")
            UserDefaults.standard.set(host, forKey: "lastHost")
            pairedServers.removeAll { $0.host == host }
            pairedServers.insert(PairedServer(host: host, name: String(name.prefix(100))), at: 0)
            pairedServers = Array(pairedServers.prefix(32))
            UserDefaults.standard.set(try JSONEncoder().encode(pairedServers), forKey: "pairedServers")
        } catch { self.error = "Connected. Pairing could not be saved: \(error.localizedDescription)" }
    }
    private func clearPendingCommand() {
        pendingCommand = nil; applyingServerCommand = false; commandTimeout?.cancel(); commandTimeout = nil
    }
    func sendServerCommand(_ command: ServerCommand) {
        guard linked, !applyingServerCommand, command.valid, let peer else { return }
        do {
            pendingCommand = command.requestID; applyingServerCommand = true; error = nil
            try peer.send(WireMessage(.serverCommand, value: command))
            commandTimeout = Task {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, self.pendingCommand == command.requestID else { return }
                self.clearPendingCommand(); self.error = "Server has not finished this request. Check its status and try again."
            }
        } catch { clearPendingCommand(); self.error = error.localizedDescription }
    }
    func createScreen() { selectedDisplayWasVirtual = true; sendServerCommand(ServerCommand(.createVirtualScreen)) }
    func selectDisplay(_ id: UInt32) {
        selectedDisplayWasVirtual = serverStatus?.displays.first(where: { $0.id == id })?.virtual ?? false
        preferredDisplayName = serverStatus?.displays.first(where: { $0.id == id })?.name
        sendServerCommand(ServerCommand(.selectDisplay, displayID: id))
    }
    func startScreen() {
        guard linked, !connected, !applyingServerCommand, serverStatus?.update?.busy != true else { return }
        resumeAfterScreenCreation = false
        desiredSession = true; status = "Starting Screener screen…"
        selectedDisplayWasVirtual = serverStatus?.selectedDisplay == 0 || serverStatus?.displays.first(where: { $0.id == serverStatus?.selectedDisplay })?.virtual == true
        preferredDisplayName = serverStatus?.displays.first(where: { $0.id == serverStatus?.selectedDisplay })?.name
        sendServerCommand(ServerCommand(.startSession, streamSettings: streamHello()))
    }
    func stopScreen() {
        guard linked, !applyingServerCommand else { return }
        desiredSession = false; connected = false; desktop = nil; image = nil; gameMouse = false; audioPlayer?.setEnabled(false)
        sendServerCommand(ServerCommand(.stopSession))
    }
    func updateServer() { serverUpdateResult = nil; sendServerCommand(ServerCommand(.updateServer)) }
    var supportsLiveStreamSettings: Bool { desktop?.framesPerSecond != nil && desktop?.megabitsPerSecond != nil }
    var supportsResponsiveCursor: Bool { desktop?.cursorEmbedded != nil }
    var supportsVideoDetail: Bool { desktop?.maximumVideoHeight != nil }
    var supportsAudio: Bool { desktop?.audioEnabled != nil }
    var supportsHostMute: Bool { desktop?.muteHostAudio != nil }
    var supportsGameMouse: Bool { desktop?.relativeMouseSupported == true }
    func setGameMouse(_ enabled: Bool) {
        guard !enabled || (connected && supportsGameMouse) else { return }
        gameMouse = enabled
    }
    func setMuteHostAudio(_ enabled: Bool) {
        guard !connected || supportsHostMute else { return }
        muteHostAudio = enabled
        guard connected, let desktop, let peer else { return }
        do {
            try peer.send(WireMessage(.configure, value: ConfigureDisplay(modeID: desktop.currentMode, muteHostAudio: enabled)))
            applyingStreamSettings = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func setAudioEnabled(_ enabled: Bool) {
        guard !connected || supportsAudio else { return }
        audioEnabled = enabled; audioPlayer?.setEnabled(enabled)
        guard connected, let desktop, let peer else { return }
        do {
            try peer.send(WireMessage(.configure, value: ConfigureDisplay(modeID: desktop.currentMode, audioEnabled: enabled)))
            applyingStreamSettings = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func setResponsiveCursor(_ enabled: Bool) {
        guard !connected || supportsResponsiveCursor else { return }
        responsiveCursor = enabled
        guard connected, let desktop, let peer else { return }
        do {
            try peer.send(WireMessage(.configure, value: ConfigureDisplay(modeID: desktop.currentMode, responsiveCursor: enabled)))
            applyingStreamSettings = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    var streamSettingsChanged: Bool { supportsLiveStreamSettings && (desktop?.framesPerSecond != fps || desktop?.megabitsPerSecond != bitrate || (supportsVideoDetail && desktop?.maximumVideoHeight != maximumVideoHeight)) }
    func applyStreamSettings() {
        guard connected, supportsLiveStreamSettings, streamSettingsChanged, !applyingStreamSettings, let desktop, let peer else { return }
        do {
            try peer.send(WireMessage(.configure, value: ConfigureDisplay(modeID: desktop.currentMode, fps: fps, bitrate: bitrate, maximumVideoHeight: supportsVideoDetail ? maximumVideoHeight : nil)))
            applyingStreamSettings = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func sendClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), text.utf8.count <= 128 * 1024 else { error = "Copy some text first (up to 128 KB)."; return }
        try? peer?.send(WireMessage(.clipboard, value: text))
    }
    func receiveClipboard() { peer?.send(WireMessage(.clipboardRequest)) }
}
