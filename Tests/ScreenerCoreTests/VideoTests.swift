import XCTest
import VideoToolbox
@testable import ScreenerCore

final class VideoTests: XCTestCase {
    func testHardware4KEncodeDecode() throws {
        try hardwareRoundTrip(width: 3840, height: 2160)
    }
    func testHardware16By10EncodeDecode() throws {
        try hardwareRoundTrip(width: 3456, height: 2160)
    }
    func testCursorModeChangesWithUnchangedH264ParameterSets() throws {
        try hardwareRoundTrip(width: 1280, height: 800, changeCursor: true)
    }
    func testHardwareColorPatchesAndRec709Metadata() throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" || ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("A physical media engine is required.")
        }
        let decoded = expectation(description: "Color patches survive H.264")
        let decoder = VideoDecoder(), queue = DispatchQueue(label: "Screener.test.colors")
        let colors: [[UInt8]] = [[0,0,0], [128,128,128], [255,255,255], [0,0,255], [0,255,0], [255,0,0]] // BGR
        decoder.onImage = { image in
            XCTAssertEqual(CVBufferCopyAttachment(image, kCVImageBufferColorPrimariesKey, nil) as? String, kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
            XCTAssertEqual(CVBufferCopyAttachment(image, kCVImageBufferTransferFunctionKey, nil) as? String, kCVImageBufferTransferFunction_ITU_R_709_2 as String)
            CVPixelBufferLockBaseAddress(image, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
            let base = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
            for patch in 0..<colors.count {
                let offset = 32 * CVPixelBufferGetBytesPerRow(image) + (patch * 64 + 32) * 4
                for channel in 0..<3 { XCTAssertEqual(Double(base[offset + channel]), Double(colors[patch][channel]), accuracy: 8, "Patch \(patch), channel \(channel)") }
            }
            decoded.fulfill()
        }
        let encoder = try VideoEncoder(width: 384, height: 64, fps: 60, megabits: 45)
        encoder.onError = { XCTFail($0) }
        encoder.onFormat = { info in queue.async { do { try decoder.configure(info) } catch { XCTFail(error.localizedDescription) } } }
        encoder.onFrame = { packet in queue.async { do { try decoder.decode(packet) } catch { XCTFail(error.localizedDescription) } }; return true }
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 384, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary, &image), kCVReturnSuccess)
        let source = try XCTUnwrap(image)
        CVBufferSetAttachment(source, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(source, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(source, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVPixelBufferLockBaseAddress(source, [])
        let base = CVPixelBufferGetBaseAddress(source)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<64 { for x in 0..<384 {
            let offset = y * CVPixelBufferGetBytesPerRow(source) + x * 4
            for channel in 0..<3 { base[offset + channel] = colors[x / 64][channel] }; base[offset + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(source, [])
        encoder.encode(source)
        wait(for: [decoded], timeout: 10)
        queue.sync { decoder.invalidate() }
        withExtendedLifetime(encoder) {}
    }
    private func hardwareRoundTrip(width: Int, height: Int, changeCursor: Bool = false) throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" { throw XCTSkip("This session cannot access VideoToolbox hardware encoders.") }
        if ProcessInfo.processInfo.environment["CI"] == "true" { throw XCTSkip("Hosted CI runners do not provide a physical Apple silicon media engine.") }
        let decoded = expectation(description: "\(width) × \(height) hardware decode")
        let decoder = VideoDecoder()
        let queue = DispatchQueue(label: "Screener.test.video")
        var capturedFormat: VideoFormat?
        var capturedPacket: Data?
        decoder.onImage = { image in
            XCTAssertEqual(CVPixelBufferGetWidth(image), width); XCTAssertEqual(CVPixelBufferGetHeight(image), height)
            XCTAssertTrue(decoder.cursorEmbedded) // Missing metadata from older servers means embedded.
            decoded.fulfill()
        }
        let encoder = try VideoEncoder(width: width, height: height, fps: 60, megabits: 45)
        encoder.onError = { text in XCTFail(text) }
        encoder.onFormat = { format in queue.async { capturedFormat = format; do { try decoder.configure(format) } catch { XCTFail(error.localizedDescription) } } }
        encoder.onFrame = { bytes in queue.async { capturedPacket = bytes; do { try decoder.decode(bytes) } catch { XCTFail(error.localizedDescription) } }; return true }
        var image: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary, &image)
        XCTAssertEqual(result, kCVReturnSuccess)
        guard let image else { XCTFail("Could not create a test frame"); return }
        CVPixelBufferLockBaseAddress(image, [])
        if let base = CVPixelBufferGetBaseAddress(image) { memset(base, 128, CVPixelBufferGetBytesPerRow(image) * height) }
        CVPixelBufferUnlockBaseAddress(image, [])
        encoder.encode(image)
        wait(for: [decoded], timeout: 10)
        if changeCursor {
            let changed = expectation(description: "Frame after cursor mode change")
            try queue.sync {
                guard let format = capturedFormat, let packet = capturedPacket else { throw ScreenerError.message("Test frame was not encoded.") }
                try decoder.configure(VideoFormat(parameterSets: format.parameterSets, cursorEmbedded: false))
                decoder.onImage = { frame in
                    XCTAssertEqual(CVPixelBufferGetWidth(frame), width); XCTAssertEqual(CVPixelBufferGetHeight(frame), height)
                    XCTAssertFalse(decoder.cursorEmbedded)
                    changed.fulfill()
                }
                try decoder.decode(packet)
            }
            wait(for: [changed], timeout: 10)
        }
        queue.sync { decoder.invalidate() }
        withExtendedLifetime(encoder) {}
    }
    func testRejectsInvalidVideoConfiguration() {
        let decoder = VideoDecoder()
        for sets in [[], [Data()], [Data([1]), Data()], [Data(repeating: 1, count: 65537), Data([1])]] {
            XCTAssertThrowsError(try decoder.configure(VideoFormat(parameterSets: sets)))
        }
    }
}
