import Foundation
import AVFAudio
import CoreMedia

/// Fixed wire format: 48 kHz, stereo, interleaved little-endian Float32 PCM.
public enum AudioPCM {
    public static let sampleRate: Double = 48_000
    public static let maximumFrames = 6_000
    public static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!

    public static func encode(_ sample: CMSampleBuffer) throws -> Data {
        let frames = CMSampleBufferGetNumSamples(sample)
        guard sample.isValid, frames > 0, frames <= maximumFrames,
            let description = CMSampleBufferGetFormatDescription(sample), CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio else {
            throw ScreenerError.message("Invalid captured audio buffer.")
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            throw ScreenerError.message("Unsupported captured audio format.")
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        guard status == noErr else { throw ScreenerError.message("Could not copy captured audio (\(status)).") }
        return try encode(buffer)
    }

    public static func encode(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let frames = Int(buffer.frameLength), format = buffer.format
        guard frames > 0, frames <= maximumFrames, format.sampleRate == sampleRate,
            format.channelCount == 2, format.commonFormat == .pcmFormatFloat32, let channels = buffer.floatChannelData else {
            throw ScreenerError.message("System audio must be 48 kHz stereo Float32.")
        }
        var words = [UInt32](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            for channel in 0..<2 {
                let value = format.isInterleaved ? channels[0][frame * 2 + channel] : channels[channel][frame]
                guard value.isFinite else { throw ScreenerError.message("Invalid audio sample.") }
                words[frame * 2 + channel] = value.bitPattern.littleEndian
            }
        }
        return words.withUnsafeBytes { Data($0) }
    }

    public static func decode(_ bytes: Data) throws -> AVAudioPCMBuffer {
        guard !bytes.isEmpty, bytes.count % 8 == 0, bytes.count <= maximumFrames * 8,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bytes.count / 8)),
            let channels = buffer.floatChannelData else { throw ScreenerError.message("Invalid audio packet.") }
        buffer.frameLength = buffer.frameCapacity
        try bytes.withUnsafeBytes { raw in
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<2 {
                    let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: (frame * 2 + channel) * 4, as: UInt32.self))
                    let value = Float(bitPattern: bits)
                    guard value.isFinite else { throw ScreenerError.message("Invalid audio sample.") }
                    channels[channel][frame] = min(1, max(-1, value))
                }
            }
        }
        return buffer
    }
}

/// Audio work stays off the UI/video queues. At most 125 ms is scheduled for playback.
public final class AudioPlayback: @unchecked Sendable {
    public var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "Screener.audio.playback", qos: .userInteractive)
    private let budget = DecodeBudget(limit: 8)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var enabled = true
    private var closed = false
    private var failed = false
    private var pendingFrames = 0
    private var generation = 0
    private var configurationObserver: NSObjectProtocol?
    public init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AudioPCM.format)
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.reset(); self.engine.stop() }
        }
    }
    public func setVolume(_ volume: Float) { queue.async { self.player.volume = min(1, max(0, volume)) } }
    public func setEnabled(_ enabled: Bool) {
        queue.async {
            self.enabled = enabled
            if !enabled { self.reset() }
        }
    }
    public func enqueue(_ bytes: Data) {
        guard budget.reserve() else { return }
        queue.async { [self] in
            defer { self.budget.release() }
            guard !self.closed, self.enabled, !self.failed else { return }
            do {
                let buffer = try AudioPCM.decode(bytes)
                let count = Int(buffer.frameLength)
                if self.pendingFrames + count > 6_000 { self.reset() }
                if !self.engine.isRunning { try self.engine.start() }
                let generation = self.generation
                self.pendingFrames += count
                self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    guard let self else { return }
                    self.queue.async {
                        if self.generation == generation { self.pendingFrames = max(0, self.pendingFrames - count) }
                    }
                }
                if !self.player.isPlaying { self.player.play() }
            } catch {
                self.failed = true; self.reset(); self.engine.stop()
                self.onError?("Audio playback failed: \(error.localizedDescription). Reconnect to try again.")
            }
        }
    }
    private func reset() { generation += 1; player.stop(); pendingFrames = 0 }
    public func stop() { queue.async { self.closed = true; self.reset(); self.engine.stop() } }
    deinit { if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) } }
}
