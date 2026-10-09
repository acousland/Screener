import XCTest
import Network
@testable import ScreenerCore

final class ServerSetupTests: XCTestCase {
    func testInvitationPreservesFullSecretAddressAndEscapedName() throws {
        let secret = try PairingSecret()
        let invitation = try PairingInvitation(host: "mini.local:49555", name: "Aaron’s mini & desk #1", secret: secret)
        let parsed = try PairingInvitation(text: " \(invitation.text)\n")
        XCTAssertEqual(parsed.host, invitation.host); XCTAssertEqual(parsed.name, invitation.name); XCTAssertEqual(parsed.secret, secret)
        XCTAssertEqual(parsed.secret.bytes.count, 32)
    }
    func testInvitationsRejectAmbiguousUnsafeOrWeakInputs() throws {
        let invitation = try PairingInvitation(host: "mini.local", name: "Mini", secret: PairingSecret()).text
        for text in [invitation + "&key=1234", invitation + "&extra=value", invitation.replacingOccurrences(of: "v=1", with: "v=2"),
            invitation.replacingOccurrences(of: "screener://pair?", with: "https://pair?"),
            invitation.replacingOccurrences(of: "screener://pair?", with: "screener://pair/launch?"), invitation + "#fragment", String(repeating: "a", count: 2049)] {
            XCTAssertThrowsError(try PairingInvitation(text: text))
        }
        for host in ["", "mini.local/path", "user@mini.local", "https://mini.local", "mini.local\n", "mini.local:0", "mini.local:65536", "mini.local:bad"] {
            XCTAssertThrowsError(try PairingInvitation(host: host, name: "Mini", secret: PairingSecret()))
        }
        var parts = try XCTUnwrap(URLComponents(string: invitation))
        parts.queryItems = parts.queryItems?.map { $0.name == "key" ? URLQueryItem(name: "key", value: "123456") : $0 }
        XCTAssertThrowsError(try PairingInvitation(text: XCTUnwrap(parts.string)))
    }
    func testServerAddressesParseIPv4IPv6AndExplicitPorts() throws {
        for input in ["mini.local", "192.168.1.10", "::1", "[fe80::1]"] { XCTAssertEqual(try ServerAddress(input).port, 49555) }
        XCTAssertEqual(try ServerAddress(" [::1]:1234 \n").host, "::1")
        XCTAssertEqual(try ServerAddress("[::1]:1234").port, 1234)
        XCTAssertEqual(try ServerAddress("mini.local:65535").port, 65535)
        for input in ["[::1]bad", "[mini.local]:1234", "[::1]:", "mini.local:", "...", "a b", "a/b", "mini:0", "mini:99999"] { XCTAssertThrowsError(try ServerAddress(input)) }
    }
    func testManagedGreetingDoesNotAuthorizeInputUntilViewingStarts() throws {
        var session = ServerSessionState()
        for kind: MessageKind in [.serverCommand, .input, .configure, .clipboard, .ping] { XCTAssertFalse(session.allows(kind)) }
        XCTAssertThrowsError(try session.startViewing())
        XCTAssertThrowsError(try session.greet(ClientHello(name: "Mini", fps: 1000, manageServer: true)))
        XCTAssertFalse(session.greeted)
        try session.greet(ClientHello(name: "MacBook", manageServer: true))
        XCTAssertTrue(session.management); XCTAssertFalse(session.viewing); XCTAssertTrue(session.allows(.serverCommand))
        for kind: MessageKind in [.input, .configure, .clipboard, .clipboardRequest] { XCTAssertFalse(session.allows(kind)) }
        XCTAssertThrowsError(try session.greet(ClientHello(name: "Other Mac")))
        try session.startViewing(); XCTAssertTrue(session.allows(.input)); XCTAssertTrue(session.allows(.configure))
        XCTAssertThrowsError(try session.startViewing())
        session.stopViewing(); XCTAssertFalse(session.allows(.input)); XCTAssertFalse(session.allows(.clipboard)); XCTAssertTrue(session.allows(.serverCommand))
        try session.startViewing(); XCTAssertTrue(session.viewing)
    }
    func testLegacyGreetingStillStreamsWithoutManagementAuthority() throws {
        let hello = try WireMessage(.hello, payload: Data(#"{"protocolVersion":1,"name":"MacBook","framesPerSecond":60,"megabitsPerSecond":45}"#.utf8)).decode(ClientHello.self)
        XCTAssertNil(hello.manageServer)
        var session = ServerSessionState(); try session.greet(hello)
        XCTAssertTrue(session.viewing); XCTAssertFalse(session.management); XCTAssertFalse(session.allows(.serverCommand))
        let current = try WireMessage(.hello, value: ClientHello(name: "MacBook", manageServer: true)).decode(ClientHello.self)
        XCTAssertEqual(current.manageServer, true)
    }
    func testServerCommandsStrictlyValidateActionParametersAndCorrelation() throws {
        let commands = [ServerCommand(.createVirtualScreen), ServerCommand(.selectDisplay, displayID: 42), ServerCommand(.setResolution, modeID: 7),
            ServerCommand(.startSession, streamSettings: ClientHello(name: "MacBook")), ServerCommand(.stopSession),
            ServerCommand(.setPreferences, openAtLogin: true, clipboardEnabled: false), ServerCommand(.screenRecordingSettings), ServerCommand(.updateServer)]
        for command in commands {
            XCTAssertTrue(command.valid)
            let parsed = try WireMessage(.serverCommand, value: command).decode(ServerCommand.self)
            XCTAssertTrue(parsed.valid); XCTAssertEqual(parsed.requestID, command.requestID); XCTAssertEqual(parsed.action, command.action)
        }
        for command in [ServerCommand(.selectDisplay), ServerCommand(.selectDisplay, displayID: 0), ServerCommand(.setPreferences),
            ServerCommand(.setResolution), ServerCommand(.startSession), ServerCommand(.startSession, streamSettings: ClientHello(name: "MacBook", fps: 0)),
            ServerCommand(.updateServer, displayID: 42), ServerCommand(.stopSession, openAtLogin: true)] { XCTAssertFalse(command.valid) }
        XCTAssertThrowsError(try WireMessage(.serverCommand, payload: Data(#"{"action":"runShell"}"#.utf8)).decode(ServerCommand.self))
    }
    func testSetupStatusSupportsNoMonitorAndBoundsInventory() throws {
        func status(_ displays: [ManagedDisplay] = [], selected: UInt32 = 0, active: Bool = false) -> ServerStatus {
            ServerStatus(name: "Mini", displays: displays, selectedDisplay: selected, desktop: nil, screenRecording: false,
                accessibility: false, openAtLogin: false, loginApprovalRequired: false, clipboardEnabled: false, sessionActive: active)
        }
        XCTAssertTrue(status().valid)
        XCTAssertFalse(status(selected: 42).valid); XCTAssertFalse(status(active: true).valid)
        let display = ManagedDisplay(id: 42, name: "Virtual", virtual: true)
        XCTAssertTrue(status([display], selected: 42).valid); XCTAssertFalse(status([display, display], selected: 42).valid)
        XCTAssertFalse(status([ManagedDisplay(id: 0, name: "Bad", virtual: false)]).valid)
        XCTAssertFalse(status((1...33).map { ManagedDisplay(id: UInt32($0), name: "Monitor", virtual: false) }).valid)
    }
    func testSetupStatusFramingAllowsInventoryButCommandsRemainSmall() throws {
        let displays = (1...32).map { ManagedDisplay(id: UInt32($0), name: String(repeating: "x", count: 190), virtual: false) }
        let status = ServerStatus(name: "Mini", displays: displays, selectedDisplay: 0, desktop: nil, screenRecording: true,
            accessibility: true, openAtLogin: true, loginApprovalRequired: false, clipboardEnabled: false, sessionActive: false, completedRequest: UUID())
        let message = try WireMessage(.serverStatus, value: status)
        XCTAssertGreaterThan(message.payload.count, 4096)
        var parser = MessageParser(); var parsed: [WireMessage] = []
        for byte in message.framed() { parsed += try parser.append(Data([byte])) }
        let decoded = try XCTUnwrap(parsed.first).decode(ServerStatus.self)
        XCTAssertEqual(decoded.displays, displays); XCTAssertEqual(decoded.completedRequest, status.completedRequest); XCTAssertTrue(decoded.valid)
        var commandParser = MessageParser()
        XCTAssertThrowsError(try commandParser.append(WireMessage(.serverCommand, payload: Data(repeating: 0, count: 4096)).framed()))
    }
    func testUpdateProgressAndTargetVersionsAreBounded() {
        XCTAssertTrue(RemoteUpdateStatus(.restarting, message: "Restarting", progress: 1, targetVersion: "0.2.0", targetBuild: "1234").valid)
        for progress in [-1, 1.01, Double.nan, Double.infinity] { XCTAssertFalse(RemoteUpdateStatus(.downloading, message: "Download", progress: progress).valid) }
        XCTAssertFalse(RemoteUpdateStatus(.idle, message: "", targetBuild: String(repeating: "a", count: 101)).valid)
        XCTAssertFalse(RemoteUpdateStatus(.available, message: "Update available").busy)
        XCTAssertTrue(RemoteUpdateStatus(.checking, message: "Checking").busy)
    }
}
