import XCTest
import AVFAudio
import CoreMedia
@testable import ScreenerCore

final class AudioTests: XCTestCase {
    func testPCMChannelOrderAndCaptureBufferRoundTrip() throws {
        for interleaved in [false, true] {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
            buffer.frameLength = 480
            for frame in 0..<480 {
                if interleaved { buffer.floatChannelData![0][frame * 2] = 0.25; buffer.floatChannelData![0][frame * 2 + 1] = -0.5 }
                else { buffer.floatChannelData![0][frame] = 0.25; buffer.floatChannelData![1][frame] = -0.5 }
            }
            let sample = try makeSample(buffer)
            let bytes = try AudioPCM.encode(sample)
            XCTAssertEqual(bytes.count, 480 * 8)
            XCTAssertEqual(Array(bytes.prefix(8)), [0, 0, 128, 62, 0, 0, 0, 191])
            let decoded = try AudioPCM.decode(bytes)
            XCTAssertEqual(decoded.frameLength, 480); XCTAssertEqual(decoded.format.sampleRate, 48_000)
            for frame in 0..<480 {
                XCTAssertEqual(decoded.floatChannelData![0][frame], 0.25)
                XCTAssertEqual(decoded.floatChannelData![1][frame], -0.5)
            }
        }
    }
    func testRejectsMalformedPCMAndUnsupportedCaptureFormats() throws {
        for bytes in [Data(), Data([1]), Data(repeating: 0, count: 7), Data(repeating: 0, count: (AudioPCM.maximumFrames + 1) * 8),
            Data([0, 0, 128, 127, 0, 0, 0, 0]), Data([0, 0, 192, 127, 0, 0, 0, 0])] {
            XCTAssertThrowsError(try AudioPCM.decode(bytes))
        }
        for (rate, channels) in [(44_100.0, AVAudioChannelCount(2)), (48_000.0, AVAudioChannelCount(1))] {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!; buffer.frameLength = 480
            XCTAssertThrowsError(try AudioPCM.encode(buffer))
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: AudioPCM.format, frameCapacity: 1)!; buffer.frameLength = 1
        buffer.floatChannelData![0][0] = .nan; buffer.floatChannelData![1][0] = 0
        XCTAssertThrowsError(try AudioPCM.encode(buffer))
    }
    func testAudioMessagesStayWithinFramingLimits() throws {
        let audio = Data(repeating: 0, count: AudioPCM.maximumFrames * 8)
        var parser = MessageParser()
        let messages = try parser.append(WireMessage(.audio, payload: audio).framed() + WireMessage(.ping).framed())
        XCTAssertEqual(messages.map(\.kind), [.audio, .ping]); XCTAssertEqual(messages[0].payload, audio)
        var badParser = MessageParser()
        XCTAssertThrowsError(try badParser.append(WireMessage(.audio, payload: Data(repeating: 0, count: 65_536)).framed()))
    }
    private func makeSample(_ buffer: AVAudioPCMBuffer) throws -> CMSampleBuffer {
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: buffer.format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: description, sampleCount: Int(buffer.frameLength), sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample), noErr)
        let result = try XCTUnwrap(sample)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList), noErr)
        XCTAssertEqual(CMSampleBufferSetDataReady(result), noErr)
        return result
    }
}
