import Foundation
import VideoToolbox
import ScreenCaptureKit
import CoreMedia

public final class VideoEncoder {
    public var onFormat: ((VideoFormat) -> Void)?
    public var onFrame: ((Data) -> Bool)?
    public var onError: ((String) -> Void)?
    private var session: VTCompressionSession?
    private let lock = NSLock()
    private var inFlight = false
    private var needsKeyframe = true
    private var frameNumber: Int64 = 0
    private let fps: Int32
    public init(width: Int, height: Int, fps: Int, megabits: Int) throws {
        self.fps = Int32(fps)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:true] as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: { ref, _, status, _, sample in
                guard let ref else { return }
                let encoder = Unmanaged<VideoEncoder>.fromOpaque(ref).takeUnretainedValue()
                defer { encoder.lock.lock(); encoder.inFlight = false; encoder.lock.unlock() }
                guard status == noErr, let sample else { encoder.onError?("Video encoding failed (\(status))."); return }
                encoder.output(sample)
            }, refcon: ref, compressionSessionOut: &session)
        guard status == noErr, let session else { throw ScreenerError.message("The hardware video encoder could not start (\(status)).") }
        let properties: [CFString: Any] = [kVTCompressionPropertyKey_RealTime:true,
            kVTCompressionPropertyKey_AllowFrameReordering:false,
            kVTCompressionPropertyKey_ProfileLevel:kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_AverageBitRate:megabits * 1_000_000,
            kVTCompressionPropertyKey_ExpectedFrameRate:fps,
            kVTCompressionPropertyKey_MaxKeyFrameInterval:fps * 2,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration:2]
        let configured = VTSessionSetProperties(session, propertyDictionary: properties as CFDictionary)
        guard configured == noErr else { throw ScreenerError.message("Could not configure the video encoder (\(configured)).") }
        let prepared = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepared == noErr else { throw ScreenerError.message("Could not prepare the video encoder (\(prepared)).") }
    }
    deinit { if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(session) } }
    public func encode(_ image: CVPixelBuffer) {
        lock.lock(); guard !inFlight else { lock.unlock(); return }; inFlight = true
        let force = needsKeyframe; needsKeyframe = false; lock.unlock()
        guard let session else { return }
        frameNumber += 1
        let pts = CMTime(value: frameNumber, timescale: fps)
        let options: CFDictionary? = force ? [kVTEncodeFrameOptionKey_ForceKeyFrame:true] as CFDictionary : nil
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: image, presentationTimeStamp: pts, duration: CMTime(value: 1, timescale: fps), frameProperties: options, sourceFrameRefcon: nil, infoFlagsOut: nil)
        if status != noErr { lock.lock(); inFlight = false; needsKeyframe = true; lock.unlock(); onError?("Video frame encoding failed (\(status)).") }
    }
    private func output(_ sample: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sample), let format = CMSampleBufferGetFormatDescription(sample) else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let keyframe = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) != true
        if keyframe {
            var sets: [Data] = []
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?; var length = 0; var count = 0
                let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &length, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
                guard status == noErr, let pointer else { return }; sets.append(Data(bytes: pointer, count: length))
            }
            onFormat?(VideoFormat(parameterSets: sets))
        }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0, length < MessageParser.maximumPayload - 9 else { return }
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        guard status == noErr else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let timestamp = UInt64(max(0, CMTimeGetSeconds(pts)) * 1_000_000_000)
        if onFrame?(VideoPacket.encode(data, timestamp: timestamp, keyframe: keyframe)) != true {
            lock.lock(); needsKeyframe = true; lock.unlock()
        }
    }
}

public final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    public var onError: ((String) -> Void)?
    private var stream: SCStream?
    private var encoder: VideoEncoder?
    private var canSend: () -> Bool = { false }
    private let queue = DispatchQueue(label: "Screener.capture", qos: .userInteractive)
    public func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, bitrate: Int,
        canSend: @escaping () -> Bool, onFormat: @escaping (VideoFormat) -> Void, onFrame: @escaping (Data) -> Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ScreenerError.message("The selected display is no longer available.") }
        let encoder = try VideoEncoder(width: width, height: height, fps: fps, megabits: bitrate)
        encoder.onFormat = onFormat; encoder.onFrame = onFrame; encoder.onError = { [weak self] in self?.onError?($0) }
        self.encoder = encoder; self.canSend = canSend
        let configuration = SCStreamConfiguration()
        configuration.width = width; configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        configuration.queueDepth = 3; configuration.showsCursor = true; configuration.capturesAudio = false
        configuration.scalesToFit = true
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }
    public func stop() async {
        if let stream { try? await stream.stopCapture() }
        queue.sync { encoder = nil }
        stream = nil
    }
    public func stream(_ stream: SCStream, didStopWithError error: Error) { onError?(error.localizedDescription) }
    public func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid, canSend(),
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
            let image = CMSampleBufferGetImageBuffer(sample) else { return }
        encoder?.encode(image)
    }
}

// Configuration/decoding/invalidation are confined to the client's decode queue.
public final class VideoDecoder: @unchecked Sendable {
    public var onImage: ((CVPixelBuffer) -> Void)?
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var parameterSets: [Data] = []
    private var hasKeyframe = false
    public init() {}
    public func configure(_ info: VideoFormat) throws {
        guard info.parameterSets.count == 2, info.parameterSets.allSatisfy({ !$0.isEmpty && $0.count <= 65536 }) else { throw ScreenerError.message("Invalid H.264 configuration.") }
        if parameterSets == info.parameterSets, session != nil { return }
        invalidate()
        var description: CMVideoFormatDescription?
        let status = info.parameterSets[0].withUnsafeBytes { sps in
            info.parameterSets[1].withUnsafeBytes { pps in
                let pointers = [sps.baseAddress!.assumingMemoryBound(to: UInt8.self), pps.baseAddress!.assumingMemoryBound(to: UInt8.self)]
                let sizes = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in sizes.withUnsafeBufferPointer { sizeBuffer in
                    CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2,
                        parameterSetPointers: pointerBuffer.baseAddress!, parameterSetSizes: sizeBuffer.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                } }
            }
        }
        guard status == noErr, let description else { throw ScreenerError.message("The video format is unsupported (\(status)).") }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        guard dimensions.width > 0, dimensions.height > 0, dimensions.width <= 3840, dimensions.height <= 2160 else { throw ScreenerError.message("Video exceeds the 4K limit.") }
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { ref, _, status, _, image, _, _ in
            guard status == noErr, let image, let ref else { return }
            Unmanaged<VideoDecoder>.fromOpaque(ref).takeUnretainedValue().onImage?(image)
        }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        let created = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: description,
            decoderSpecification: [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder:true] as CFDictionary,
            imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey:kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey:[:] ] as CFDictionary, outputCallback: &callback, decompressionSessionOut: &session)
        guard created == noErr else { throw ScreenerError.message("The hardware decoder could not start (\(created)).") }
        format = description; parameterSets = info.parameterSets
    }
    public func decode(_ packet: Data) throws {
        guard let session, let format else { return }
        let frame = try VideoPacket.decode(packet)
        if frame.keyframe { hasKeyframe = true }
        guard hasKeyframe else { return }
        // Validate AVCC lengths before passing peer-provided data to VideoToolbox.
        var offset = 0
        while offset < frame.bytes.count {
            guard frame.bytes.count - offset >= 4 else { throw ScreenerError.message("Truncated video frame.") }
            let length = frame.bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, Int(length) <= frame.bytes.count - offset - 4 else { throw ScreenerError.message("Invalid video NAL length.") }
            offset += 4 + Int(length)
        }
        var block: CMBlockBuffer?
        let allocated = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: frame.bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: frame.bytes.count, flags: 0, blockBufferOut: &block)
        guard allocated == noErr, let block else { throw ScreenerError.message("Could not allocate a video frame.") }
        let copied = frame.bytes.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: frame.bytes.count) }
        guard copied == noErr else { throw ScreenerError.message("Could not copy the video frame.") }
        var sample: CMSampleBuffer?
        var size = frame.bytes.count
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: Int64(clamping: frame.timestamp), timescale: 1_000_000_000), decodeTimeStamp: .invalid)
        let made = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard made == noErr, let sample else { throw ScreenerError.message("Could not create a video sample.") }
        let decoded = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [._EnableAsynchronousDecompression, ._EnableTemporalProcessing], frameRefcon: nil, infoFlagsOut: nil)
        guard decoded == noErr else { hasKeyframe = false; throw ScreenerError.message("Video decoding failed (\(decoded)).") }
    }
    public func invalidate() {
        if let session { VTDecompressionSessionWaitForAsynchronousFrames(session); VTDecompressionSessionInvalidate(session) }
        session = nil; format = nil; parameterSets = []; hasKeyframe = false
    }
    deinit { invalidate() }
}
