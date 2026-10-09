import Foundation
import Network
import Security

public struct PairingSecret: Equatable {
    public let bytes: Data
    public var code: String { bytes.map { String(format: "%02x", $0) }.joined() }
    public init(code: String) throws {
        let text = code.filter { !$0.isWhitespace && $0 != "-" }
        guard text.count == 64, text.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw ScreenerError.message("Paste the 64-character connection key from Screener Server.")
        }
        var data = Data(); var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<end], radix: 16) else { throw ScreenerError.message("Invalid connection key.") }
            data.append(byte); index = end
        }
        bytes = data
    }
    public init() throws {
        var data = Data(count: 32)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else { throw ScreenerError.message("Could not create a secure connection key.") }
        bytes = data
    }
}
public enum SecretStore {
    private static let service = "au.com.acousland.Screener.connection"
    public static func read(account: String) throws -> PairingSecret? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service,
            kSecAttrAccount as String:account, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let code = String(data: data, encoding: .utf8) else {
            throw ScreenerError.message("The connection key could not be read from Keychain (\(status)).")
        }
        return try PairingSecret(code: code)
    }
    public static func save(_ secret: PairingSecret, account: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:account]
        let attributes: [String: Any] = [kSecValueData as String:Data(secret.code.utf8), kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item.merge(attributes) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw ScreenerError.message("Could not save the connection key in Keychain (\(added)).") }
        } else if status != errSecSuccess { throw ScreenerError.message("Could not update the connection key in Keychain (\(status)).") }
    }
}

public enum SecureParameters {
    public static let serviceType = "_screener._tcp"
    public static let port: UInt16 = 49555
    public static func make(secret: PairingSecret) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = secret.bytes.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("Screener-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, key as __DispatchData, identity as __DispatchData)
        // A random 256-bit key authenticates both endpoints. Never accept an unverified certificate.
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0x00A8)!)
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true; tcp.connectionTimeout = 10
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }
}

public final class PeerConnection: @unchecked Sendable {
    public var onReady: (() -> Void)?
    public var onMessage: ((WireMessage) -> Void)?
    public var onClose: ((String?) -> Void)?
    public let endpoint: NWEndpoint
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "Screener.peer", qos: .userInteractive)
    private var parser = MessageParser()
    private var closed = false
    private var closing = false
    private var closingReason: String?
    private var remoteFailure: String?
    private var timeout: DispatchWorkItem?
    private let lock = NSLock()
    private var videoBusy = false
    private var pendingSends = 0
    public var readyForVideo: Bool { lock.lock(); defer { lock.unlock() }; return !videoBusy }
    public init(_ connection: NWConnection) { self.connection = connection; endpoint = connection.endpoint }
    public convenience init(endpoint: NWEndpoint, secret: PairingSecret) {
        self.init(NWConnection(to: endpoint, using: SecureParameters.make(secret: secret)))
    }
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.timeout?.cancel(); self.onReady?(); self.receive()
            case .failed(let error): self.finish("Connection failed: \(error.localizedDescription). Check the address and connection key.")
            case .cancelled: self.finish(nil)
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.finish("Connection timed out. Check the server, connection key and network permissions.") }
        self.timeout = timeout; queue.asyncAfter(deadline: .now() + 12, execute: timeout)
        connection.start(queue: queue)
    }
    public func close() { queue.async { self.finish(nil) } }
    // Send the rejection and a TLS/TCP end-of-stream before cancelling the connection.
    // Keep the peer alive briefly even when the caller releases a rejected session.
    public func close(with reason: String) {
        queue.async {
            guard !self.closed, !self.closing else { return }
            self.closing = true; self.closingReason = reason; self.timeout?.cancel()
            do {
                let message = try WireMessage(.failure, value: String(reason.prefix(1000)))
                self.connection.send(content: message.framed(), contentContext: .finalMessage, isComplete: true,
                    completion: .contentProcessed { [self] error in
                        if error != nil { self.finish(reason) }
                    })
                self.queue.asyncAfter(deadline: .now() + 2) { self.finish(reason) }
            } catch { self.finish(reason) }
        }
    }
    private func finish(_ reason: String?) {
        guard !closed else { return }; closed = true; timeout?.cancel()
        connection.stateUpdateHandler = nil; connection.cancel(); onClose?(reason)
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            do { if let data { for message in try self.parser.append(data) {
                self.remoteFailure = message.kind == .failure ? try? message.decode(String.self) : nil
                if !self.closing { self.onMessage?(message) }
            } } }
            catch { self.finish(error.localizedDescription); return }
            if let error { self.finish(error.localizedDescription) }
            else if complete { self.finish(self.closingReason ?? self.remoteFailure ?? "The other Mac disconnected.") }
            else { self.receive() }
        }
    }
    public func send(_ message: WireMessage) {
        lock.lock(); pendingSends += 1; let pending = pendingSends; lock.unlock()
        guard pending <= 256, message.payload.count < MessageParser.maximumPayload else {
            queue.async { self.finish("The connection cannot keep up with outgoing messages.") }; return
        }
        queue.async {
            guard !self.closed, !self.closing else { self.sent(); return }
            self.connection.send(content: message.framed(), completion: .contentProcessed { error in
                self.sent(); if let error { self.finish(error.localizedDescription) }
            })
        }
    }
    private func sent() { lock.lock(); pendingSends -= 1; lock.unlock() }
    @discardableResult public func sendVideo(_ payload: Data) -> Bool {
        lock.lock()
        guard !videoBusy else { lock.unlock(); return false }
        videoBusy = true; lock.unlock()
        queue.async {
            guard !self.closed, !self.closing else { self.clearVideo(); return }
            self.connection.send(content: WireMessage(.video, payload: payload).framed(), completion: .contentProcessed { error in
                self.clearVideo(); if let error { self.finish(error.localizedDescription) }
            })
        }
        return true
    }
    private func clearVideo() { lock.lock(); videoBusy = false; lock.unlock() }
}
