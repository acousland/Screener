import XCTest
import Network
@testable import ScreenerCore

final class TransportTests: XCTestCase {
    func testAuthenticatedSetupStartStopAndUpdateShareOneConnection() throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" { throw XCTSkip("Local networking is unavailable.") }
        let secret = try PairingSecret()
        let listener = try NWListener(using: SecureParameters.make(secret: secret), on: .any)
        let listening = expectation(description: "Management listener")
        let completed = expectation(description: "Setup and update remain connected")
        var server: PeerConnection?
        var session = ServerSessionState()
        var screen: DesktopInfo?
        let queue = DispatchQueue(label: "Screener.test.setup")
        listener.stateUpdateHandler = { if case .ready = $0 { listening.fulfill() } }
        listener.newConnectionHandler = { connection in
            let peer = PeerConnection(connection); server = peer
            peer.onMessage = { message in
                do {
                    var completedRequest: UUID?
                    var update: RemoteUpdateStatus?
                    if message.kind == .hello {
                        try session.greet(message.decode(ClientHello.self))
                        XCTAssertFalse(session.viewing); XCTAssertFalse(session.allows(.input))
                    } else {
                        XCTAssertTrue(session.allows(message.kind))
                        let command = try message.decode(ServerCommand.self)
                        XCTAssertTrue(command.valid); completedRequest = command.requestID
                        switch command.action {
                        case .createVirtualScreen:
                            screen = DesktopInfo(name: "Virtual", streamWidth: 3840, streamHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, currentMode: 7, modes: [])
                            XCTAssertFalse(session.viewing)
                        case .startSession: try session.startViewing(); XCTAssertTrue(session.allows(.input))
                        case .stopSession: session.stopViewing(); XCTAssertFalse(session.allows(.input))
                        case .updateServer: update = RemoteUpdateStatus(.checking, message: "Checking signed feed")
                        default: XCTFail("Unexpected setup command")
                        }
                    }
                    let status = ServerStatus(name: "Mini", displays: screen == nil ? [] : [ManagedDisplay(id: 42, name: "Virtual", virtual: true)],
                        selectedDisplay: screen == nil ? 0 : 42, desktop: screen, screenRecording: true, accessibility: true,
                        openAtLogin: true, loginApprovalRequired: false, clipboardEnabled: false, sessionActive: session.viewing,
                        update: update, completedRequest: completedRequest)
                    peer.send(try WireMessage(.serverStatus, value: status))
                } catch { XCTFail(error.localizedDescription) }
            }
            peer.start()
        }
        listener.start(queue: queue); defer { listener.cancel(); server?.close() }
        wait(for: [listening], timeout: 5)
        let client = PeerConnection(endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port)), secret: secret)
        let commands = [ServerCommand(.createVirtualScreen), ServerCommand(.startSession, streamSettings: ClientHello(name: "MacBook")), ServerCommand(.stopSession), ServerCommand(.updateServer)]
        var response = 0
        client.onReady = { client.send(try! WireMessage(.hello, value: ClientHello(name: "MacBook", manageServer: true))) }
        client.onMessage = { message in
            XCTAssertEqual(message.kind, .serverStatus)
            guard let status = try? message.decode(ServerStatus.self) else { XCTFail("Missing setup status"); return }
            XCTAssertTrue(status.valid)
            XCTAssertEqual(status.sessionActive, response == 2)
            if response > 0 { XCTAssertEqual(status.completedRequest, commands[response - 1].requestID) }
            if response < commands.count { client.send(try! WireMessage(.serverCommand, value: commands[response])) }
            else { XCTAssertEqual(status.update?.phase, .checking); completed.fulfill() }
            response += 1
        }
        client.onClose = { _ in if response <= commands.count { XCTFail("Setup connection closed unexpectedly") } }
        client.start(); defer { client.close() }
        wait(for: [completed], timeout: 8)
    }
    func testSystemAudioAndVideoShareAuthenticatedConnection() throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" { throw XCTSkip("Local networking is unavailable.") }
        let secret = try PairingSecret()
        let listener = try NWListener(using: SecureParameters.make(secret: secret), on: .any)
        let listening = expectation(description: "Audio/video listener")
        let received = expectation(description: "Both media messages")
        received.expectedFulfillmentCount = 2
        let pcm = Data(repeating: 0, count: 480 * 8)
        let video = VideoPacket.encode(Data([0,0,0,1,1]), timestamp: 1, keyframe: true)
        var server: PeerConnection?
        listener.stateUpdateHandler = { if case .ready = $0 { listening.fulfill() } }
        listener.newConnectionHandler = { connection in
            let peer = PeerConnection(connection); server = peer
            peer.onMessage = { [weak peer] message in
                guard message.kind == .hello, let peer else { return }
                XCTAssertEqual(try? message.decode(ClientHello.self).audioEnabled, true)
                XCTAssertTrue(peer.sendAudio(pcm)); XCTAssertTrue(peer.sendVideo(video))
            }
            peer.start()
        }
        listener.start(queue: DispatchQueue(label: "Screener.test.media"))
        defer { listener.cancel(); server?.close() }
        wait(for: [listening], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let client = PeerConnection(endpoint: .hostPort(host: "127.0.0.1", port: port), secret: secret)
        client.onReady = { client.send(try! WireMessage(.hello, value: ClientHello(name: "Test Mac", audioEnabled: true))) }
        client.onMessage = { message in
            if message.kind == .audio { XCTAssertEqual(message.payload, pcm); received.fulfill() }
            if message.kind == .video { XCTAssertEqual(message.payload, video); received.fulfill() }
        }
        client.start(); defer { client.close() }
        wait(for: [received], timeout: 5)
    }
    func testSessionRejectionArrivesBeforeDisconnect() throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" { throw XCTSkip("This session blocks local networking; run this test in an unrestricted developer session.") }
        let secret = try PairingSecret()
        let listener = try NWListener(using: SecureParameters.make(secret: secret), on: .any)
        let listening = expectation(description: "TLS listener")
        let closed = expectation(description: "Rejected session closed")
        let reason = "Grant Screener Server Screen Recording permission on the mini, then reconnect."
        var server: PeerConnection?
        listener.stateUpdateHandler = { if case .ready = $0 { listening.fulfill() } }
        listener.newConnectionHandler = { connection in
            let peer = PeerConnection(connection); server = peer
            peer.onMessage = { [weak peer] message in
                guard message.kind == .hello, let peer else { return }
                peer.close(with: reason)
                server = nil // The server releases rejected sessions immediately.
            }
            peer.start()
        }
        listener.start(queue: DispatchQueue(label: "Screener.test.rejection"))
        defer { listener.cancel(); server?.close() }
        wait(for: [listening], timeout: 5)
        guard let port = listener.port else { XCTFail("Listener has no port"); return }
        let client = PeerConnection(endpoint: .hostPort(host: "127.0.0.1", port: port), secret: secret)
        var receivedReason: String?
        client.onReady = { client.send(try! WireMessage(.hello, value: ClientHello(name: "Test Mac"))) }
        client.onMessage = { message in
            if message.kind == .failure { receivedReason = try? message.decode(String.self) }
        }
        client.onClose = { closeReason in
            XCTAssertEqual(receivedReason, reason)
            XCTAssertEqual(closeReason, reason)
            closed.fulfill()
        }
        client.start(); defer { client.close() }
        wait(for: [closed], timeout: 5)
    }
    func testEncryptedAuthenticatedLoopback() throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" { throw XCTSkip("This session blocks local networking; run this test in an unrestricted developer session.") }
        let secret = try PairingSecret()
        let listener = try NWListener(using: SecureParameters.make(secret: secret), on: .any)
        let listening = expectation(description: "TLS listener")
        let message = expectation(description: "Authenticated message")
        let queue = DispatchQueue(label: "Screener.test.listener")
        var server: PeerConnection?
        listener.stateUpdateHandler = { state in
            if case .ready = state { listening.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            let peer = PeerConnection(connection); server = peer
            peer.onMessage = { packet in
                if packet.kind == .ping, packet.payload == Data("encrypted".utf8) { peer.send(WireMessage(.pong, payload: packet.payload)) }
            }
            peer.start()
        }
        listener.start(queue: queue)
        defer { listener.cancel(); server?.close() }
        wait(for: [listening], timeout: 5)
        guard let port = listener.port else { XCTFail("Listener has no port"); return }
        let client = PeerConnection(endpoint: .hostPort(host: "127.0.0.1", port: port), secret: secret)
        client.onReady = { client.send(WireMessage(.ping, payload: Data("encrypted".utf8))) }
        client.onMessage = { packet in if packet.kind == .pong, packet.payload == Data("encrypted".utf8) { message.fulfill() } }
        client.start(); defer { client.close() }
        wait(for: [message], timeout: 10)
    }
    func testWrongKeyCannotAuthenticate() throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" { throw XCTSkip("This session blocks local networking; run this test in an unrestricted developer session.") }
        let listener = try NWListener(using: SecureParameters.make(secret: PairingSecret()), on: .any)
        let listening = expectation(description: "Listening")
        let closed = expectation(description: "Wrong key rejected")
        let queue = DispatchQueue(label: "Screener.test.wrong-key")
        var server: PeerConnection?
        listener.stateUpdateHandler = { state in if case .ready = state { listening.fulfill() } }
        listener.newConnectionHandler = { connection in let peer = PeerConnection(connection); server = peer; peer.start() }
        listener.start(queue: queue); defer { listener.cancel(); server?.close() }
        wait(for: [listening], timeout: 5)
        guard let port = listener.port else { XCTFail("Listener has no port"); return }
        let client = PeerConnection(endpoint: .hostPort(host: "127.0.0.1", port: port), secret: try PairingSecret())
        client.onReady = { XCTFail("A client with the wrong key authenticated") }
        client.onClose = { _ in closed.fulfill() }
        client.start(); defer { client.close() }; wait(for: [closed], timeout: 15)
    }
}
