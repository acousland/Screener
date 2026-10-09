import Foundation
import CoreVideo

/// Decoder output is retained and treated as immutable while it crosses queues.
public final class PixelFrame: @unchecked Sendable {
    public let buffer: CVPixelBuffer
    public init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
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
