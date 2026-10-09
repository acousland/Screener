import Foundation
import CoreGraphics

public enum ScreenerError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public enum MessageKind: UInt8, Sendable {
    case hello = 1, desktop, configure, format, video, input, clipboard, clipboardRequest, failure, ping, pong
}
public struct WireMessage: Sendable {
    public let kind: MessageKind
    public let payload: Data
    public init(_ kind: MessageKind, payload: Data = Data()) { self.kind = kind; self.payload = payload }
    public init<T: Encodable>(_ kind: MessageKind, value: T) throws {
        self.init(kind, payload: try JSONEncoder().encode(value))
    }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: payload) }
    public func framed() -> Data {
        let length = UInt32(payload.count + 1)
        var result = Data([UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255), kind.rawValue])
        result.append(payload)
        return result
    }
}

/// A stream may split or coalesce messages at arbitrary byte boundaries.
public struct MessageParser {
    public static let maximumPayload = 16 * 1024 * 1024
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [WireMessage] {
        buffer.append(data)
        var messages: [WireMessage] = []
        while buffer.count >= 4 {
            let prefix = Array(buffer.prefix(4))
            let length = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= Self.maximumPayload else { throw ScreenerError.message("Invalid network message length.") }
            guard buffer.count >= 4 + Int(length) else { break }
            let start = buffer.startIndex
            guard let kind = MessageKind(rawValue: buffer[start + 4]) else { throw ScreenerError.message("Unknown network message.") }
            let limit = kind == .video ? Self.maximumPayload : [.desktop, .format, .clipboard].contains(kind) ? 256 * 1024 : 4096
            guard Int(length) <= limit else { throw ScreenerError.message("Network message exceeds the limit for its type.") }
            messages.append(WireMessage(kind, payload: Data(buffer[(start + 5)..<(start + 4 + Int(length))])))
            buffer = Data(buffer.dropFirst(4 + Int(length)))
        }
        guard buffer.count <= Self.maximumPayload + 4 else { throw ScreenerError.message("Network buffer limit exceeded.") }
        return messages
    }
}

public struct ClientHello: Codable {
    public let protocolVersion: Int
    public let name: String
    public let framesPerSecond: Int
    public let megabitsPerSecond: Int
    public init(name: String, fps: Int = 60, bitrate: Int = 45) {
        protocolVersion = 1; self.name = String(name.prefix(100)); framesPerSecond = fps; megabitsPerSecond = bitrate
    }
    public var valid: Bool { protocolVersion == 1 && name.count <= 100 && [30, 60].contains(framesPerSecond) && (10...100).contains(megabitsPerSecond) }
}
public struct DisplayModeInfo: Codable, Identifiable, Hashable {
    public let id: Int32
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public var hiDPI: Bool { pixelWidth > width }
    public var aspectRatioLabel: String? {
        guard width > 0, height > 0 else { return nil }
        var divisor = width, remainder = height
        while remainder != 0 { (divisor, remainder) = (remainder, divisor % remainder) }
        switch (width / divisor, height / divisor) {
        case (8, 5): return "16:10"
        case (16, 9): return "16:9"
        default: return nil
        }
    }
    public var label: String {
        "\(width) × \(height)\(aspectRatioLabel.map { " · \($0)" } ?? "")\(hiDPI ? " · HiDPI" : "")"
    }
    public init(id: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int) {
        self.id = id; self.width = width; self.height = height; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }
}
public struct DesktopInfo: Codable {
    public let name: String
    public let streamWidth: Int
    public let streamHeight: Int
    public let logicalWidth: Int
    public let logicalHeight: Int
    public let currentMode: Int32
    public let modes: [DisplayModeInfo]
    public let framesPerSecond: Int?
    public let megabitsPerSecond: Int?
    public init(name: String, streamWidth: Int, streamHeight: Int, logicalWidth: Int, logicalHeight: Int, currentMode: Int32, modes: [DisplayModeInfo], framesPerSecond: Int? = nil, megabitsPerSecond: Int? = nil) {
        self.name = name; self.streamWidth = streamWidth; self.streamHeight = streamHeight
        self.logicalWidth = logicalWidth; self.logicalHeight = logicalHeight; self.currentMode = currentMode; self.modes = modes
        self.framesPerSecond = framesPerSecond; self.megabitsPerSecond = megabitsPerSecond
    }
}
public struct ConfigureDisplay: Codable {
    public let modeID: Int32
    public let framesPerSecond: Int?
    public let megabitsPerSecond: Int?
    public init(modeID: Int32, fps: Int? = nil, bitrate: Int? = nil) {
        self.modeID = modeID; framesPerSecond = fps; megabitsPerSecond = bitrate
    }
    public var valid: Bool {
        (framesPerSecond.map { [30, 60].contains($0) } ?? true)
        && (megabitsPerSecond.map { (10...100).contains($0) } ?? true)
    }
}
public struct VideoFormat: Codable {
    public let parameterSets: [Data]
    public init(parameterSets: [Data]) { self.parameterSets = parameterSets }
}
public struct InputEvent: Codable {
    public enum Action: String, Codable { case move, down, up, scroll, keyDown, keyUp, flags }
    public let action: Action
    public var x: Double = 0
    public var y: Double = 0
    public var button: Int = 0
    public var keyCode: UInt16 = 0
    public var modifiers: UInt64 = 0
    public var deltaX: Double = 0
    public var deltaY: Double = 0
    public init(_ action: Action, x: Double = 0, y: Double = 0, button: Int = 0, keyCode: UInt16 = 0, modifiers: UInt64 = 0, deltaX: Double = 0, deltaY: Double = 0) {
        self.action = action; self.x = x; self.y = y; self.button = button; self.keyCode = keyCode
        self.modifiers = modifiers; self.deltaX = deltaX; self.deltaY = deltaY
    }
    public var valid: Bool {
        x.isFinite && y.isFinite && deltaX.isFinite && deltaY.isFinite && (0...1).contains(x) && (0...1).contains(y) && (0...2).contains(button)
        && abs(deltaX) <= 10000 && abs(deltaY) <= 10000 && keyCode <= 127
    }
}
public enum VideoPacket {
    public static func encode(_ data: Data, timestamp: UInt64, keyframe: Bool) -> Data {
        var result = Data([keyframe ? 1 : 0])
        for shift in stride(from: 56, through: 0, by: -8) { result.append(UInt8((timestamp >> UInt64(shift)) & 255)) }
        result.append(data); return result
    }
    public static func decode(_ data: Data) throws -> (bytes: Data, timestamp: UInt64, keyframe: Bool) {
        guard data.count > 9, data.first == 0 || data.first == 1 else { throw ScreenerError.message("Invalid video packet.") }
        let timestamp = data.dropFirst().prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return (Data(data.dropFirst(9)), timestamp, data.first == 1)
    }
}
public enum ScreenGeometry {
    public static func streamSize(width: Int, height: Int) -> (Int, Int) {
        let scale = min(3840.0 / Double(max(1, width)), 2160.0 / Double(max(1, height)), 1)
        // Avoid losing two pixels when floating-point scaling lands just below an exact even size.
        return (max(2, Int(Double(width) * scale / 2 + 1e-9) * 2), max(2, Int(Double(height) * scale / 2 + 1e-9) * 2))
    }
    public static func fit(content: CGSize, in bounds: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    public static func normalized(_ point: CGPoint, in rect: CGRect) -> CGPoint? {
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
}
