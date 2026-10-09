import XCTest
import Network
@testable import ScreenerCore

final class TransportTests: XCTestCase {
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
