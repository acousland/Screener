import Foundation
import CoreVideo

/// Decoder output is retained and treated as immutable while it crosses queues.
public final class PixelFrame: @unchecked Sendable {
    public let buffer: CVPixelBuffer
    public let cursorEmbedded: Bool
    public init(_ buffer: CVPixelBuffer, cursorEmbedded: Bool = true) { self.buffer = buffer; self.cursorEmbedded = cursorEmbedded }
}
/// Replaces stale output while one delivery is waiting on another queue.
public final class LatestValueSlot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    public init() {}
    /// Returns true only when the caller needs to schedule a delivery.
    public func offer(_ newValue: Value) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let schedule = value == nil
        value = newValue
        return schedule
    }
    public func take() -> Value? {
        lock.lock(); defer { lock.unlock() }
        let latest = value; value = nil; return latest
    }
}
/// Bounds the number of compressed frames awaiting hardware decode.
public final class DecodeBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    private let limit: Int
    public init(limit: Int = 8) { self.limit = limit }
    public func reserve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard pending < limit else { return false }; pending += 1; return true
    }
    public func release() { lock.lock(); pending = max(0, pending - 1); lock.unlock() }
}
