import Foundation
import Network

public struct ServerAddress: Equatable {
    public let host: String
    public let port: UInt16
    public init(_ text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func failure() -> ScreenerError { .message("Enter the mini's IP address or .local hostname, optionally followed by a port.") }
        guard !text.isEmpty, text.utf8.count <= 255 else { throw failure() }
        let host: String, suffix: String
        if text.first == "[" {
            guard let closing = text.firstIndex(of: "]") else { throw failure() }
            host = String(text[text.index(after: text.startIndex)..<closing])
            guard IPv6Address(host) != nil else { throw failure() }
            suffix = String(text[text.index(after: closing)...])
        } else if IPv6Address(text) != nil { host = text; suffix = "" }
        else {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { throw failure() }
            host = String(parts[0]); suffix = parts.count == 2 ? ":\(parts[1])" : ""
            guard !host.isEmpty, host.unicodeScalars.allSatisfy({
                ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || ".-_".unicodeScalars.contains($0)
            }), host.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.alphanumerics.contains($0) }) else { throw failure() }
        }
        if suffix.isEmpty { port = SecureParameters.port }
        else {
            guard suffix.first == ":", let value = UInt16(suffix.dropFirst()), value > 0 else { throw failure() }
            port = value
        }
        self.host = host
    }
}

/// Invitations are deliberately pasted into the app, never opened through a browser or URL handler.
/// Possession of the full random key authorizes this Mac to view and manage the server.
public struct PairingInvitation {
    public let host: String
    public let name: String
    public let secret: PairingSecret
    public init(host: String, name: String, secret: PairingSecret) throws {
        guard Self.validHost(host), !name.isEmpty, name.count <= 100 else { throw ScreenerError.message("Invalid pairing invitation.") }
        self.host = host; self.name = name; self.secret = secret
    }
    public var text: String {
        var components = URLComponents()
        components.scheme = "screener"; components.host = "pair"
        components.queryItems = [URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "name", value: name), URLQueryItem(name: "key", value: secret.code)]
        return components.string!
    }
    public init(text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 2048, let components = URLComponents(string: text),
            components.scheme == "screener", components.host == "pair", components.path.isEmpty,
            components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
            let items = components.queryItems, items.count == 4,
            Set(items.map(\.name)) == Set(["v", "host", "name", "key"]),
            items.first(where: { $0.name == "v" })?.value == "1",
            let host = items.first(where: { $0.name == "host" })?.value,
            let name = items.first(where: { $0.name == "name" })?.value,
            let code = items.first(where: { $0.name == "key" })?.value else {
            throw ScreenerError.message("Copy a pairing invitation from Screener Server on the mini.")
        }
        try self.init(host: host, name: name, secret: PairingSecret(code: code))
    }
    public static func validHost(_ host: String) -> Bool {
        host == host.trimmingCharacters(in: .whitespacesAndNewlines) && (try? ServerAddress(host)) != nil
    }
}

public struct ManagedDisplay: Codable, Identifiable, Equatable {
    public let id: UInt32
    public let name: String
    public let virtual: Bool
    public init(id: UInt32, name: String, virtual: Bool) { self.id = id; self.name = name; self.virtual = virtual }
}

public struct ServerStatus: Codable {
    public let name: String
    public let displays: [ManagedDisplay]
    public let selectedDisplay: UInt32
    public let desktop: DesktopInfo?
    public let screenRecording: Bool
    public let accessibility: Bool
    public let openAtLogin: Bool
    public let loginApprovalRequired: Bool
    public let clipboardEnabled: Bool
    public let sessionActive: Bool
    public let version: String?
    public let build: String?
    public let update: RemoteUpdateStatus?
    public let completedRequest: UUID?
    public init(name: String, displays: [ManagedDisplay], selectedDisplay: UInt32, desktop: DesktopInfo?, screenRecording: Bool,
        accessibility: Bool, openAtLogin: Bool, loginApprovalRequired: Bool, clipboardEnabled: Bool, sessionActive: Bool,
        version: String? = nil, build: String? = nil, update: RemoteUpdateStatus? = nil, completedRequest: UUID? = nil) {
        self.name = name; self.displays = displays; self.selectedDisplay = selectedDisplay; self.desktop = desktop
        self.screenRecording = screenRecording; self.accessibility = accessibility; self.openAtLogin = openAtLogin
        self.loginApprovalRequired = loginApprovalRequired; self.clipboardEnabled = clipboardEnabled; self.sessionActive = sessionActive
        self.version = version; self.build = build; self.update = update
        self.completedRequest = completedRequest
    }
    public var valid: Bool {
        guard !name.isEmpty, name.count <= 100, displays.count <= 32, Set(displays.map(\.id)).count == displays.count,
            displays.allSatisfy({ $0.id > 0 && !$0.name.isEmpty && $0.name.count <= 200 }),
            selectedDisplay == 0 || displays.contains(where: { $0.id == selectedDisplay }),
            !sessionActive || (selectedDisplay != 0 && desktop != nil), update?.valid != false,
            (version?.count ?? 0) <= 100, (build?.count ?? 0) <= 100 else { return false }
        guard let desktop else { return true }
        return selectedDisplay != 0 && desktop.streamWidth > 0 && desktop.streamWidth <= 3840 && desktop.streamHeight > 0
            && desktop.streamHeight <= 2160 && desktop.logicalWidth > 0 && desktop.logicalHeight > 0 && desktop.modes.count <= 200
    }
}

public struct ServerCommand: Codable {
    public enum Action: String, Codable {
        case createVirtualScreen, selectDisplay, setResolution, startSession, stopSession, setPreferences, screenRecordingSettings, accessibilitySettings, loginSettings, updateServer
    }
    public let action: Action
    public let displayID: UInt32?
    public let modeID: Int32?
    public let openAtLogin: Bool?
    public let clipboardEnabled: Bool?
    public let streamSettings: ClientHello?
    public let requestID: UUID?
    public init(_ action: Action, displayID: UInt32? = nil, modeID: Int32? = nil, openAtLogin: Bool? = nil, clipboardEnabled: Bool? = nil, streamSettings: ClientHello? = nil, requestID: UUID = UUID()) {
        self.action = action; self.displayID = displayID; self.modeID = modeID
        self.openAtLogin = openAtLogin; self.clipboardEnabled = clipboardEnabled; self.streamSettings = streamSettings
        self.requestID = requestID
    }
    public var valid: Bool {
        switch action {
        case .selectDisplay: return displayID.map { $0 > 0 } == true && modeID == nil && openAtLogin == nil && clipboardEnabled == nil && streamSettings == nil
        case .setResolution: return modeID != nil && displayID == nil && openAtLogin == nil && clipboardEnabled == nil && streamSettings == nil
        case .setPreferences: return (openAtLogin != nil || clipboardEnabled != nil) && displayID == nil && modeID == nil && streamSettings == nil
        case .startSession: return streamSettings?.valid == true && displayID == nil && modeID == nil && openAtLogin == nil && clipboardEnabled == nil
        default: return displayID == nil && modeID == nil && openAtLogin == nil && clipboardEnabled == nil && streamSettings == nil
        }
    }
}

public struct RemoteUpdateStatus: Codable, Equatable {
    public enum Phase: String, Codable { case idle, available, checking, downloading, extracting, restarting, upToDate, failed }
    public let phase: Phase
    public let message: String
    public let progress: Double?
    public let targetVersion: String?
    public let targetBuild: String?
    public init(_ phase: Phase, message: String, progress: Double? = nil, targetVersion: String? = nil, targetBuild: String? = nil) {
        self.phase = phase; self.message = String(message.prefix(2000)); self.progress = progress
        self.targetVersion = targetVersion; self.targetBuild = targetBuild
    }
    public var busy: Bool { [.checking, .downloading, .extracting, .restarting].contains(phase) }
    public var valid: Bool {
        message.count <= 2000 && (targetVersion?.count ?? 0) <= 100 && (targetBuild?.count ?? 0) <= 100
            && (progress.map { $0.isFinite && (0...1).contains($0) } ?? true)
    }
}

/// The TLS handshake must authenticate before the protocol greeting reaches this policy.
/// Setup connections have no authority to inject input or configure a stream until viewing starts.
public struct ServerSessionState {
    public private(set) var greeted = false
    public private(set) var management = false
    public private(set) var viewing = false
    public init() { }
    public mutating func greet(_ hello: ClientHello) throws {
        guard !greeted, hello.valid else { throw ScreenerError.message("Invalid or repeated client greeting.") }
        greeted = true; management = hello.manageServer == true; viewing = !management
    }
    public mutating func startViewing() throws {
        guard greeted, management, !viewing else { throw ScreenerError.message("A screen session is already starting or active.") }
        viewing = true
    }
    public mutating func stopViewing() { viewing = false }
    public func allows(_ kind: MessageKind) -> Bool {
        guard greeted else { return false }
        switch kind {
        case .serverCommand: return management
        case .input, .configure, .clipboard, .clipboardRequest: return viewing
        case .ping: return true
        default: return false
        }
    }
}
