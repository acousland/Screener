import XCTest
import VideoToolbox
@testable import ScreenerCore

final class VideoTests: XCTestCase {
    func testHardware4KEncodeDecode() throws {
        if ProcessInfo.processInfo.environment["SCREENER_RESTRICTED_TESTS"] == "1" { throw XCTSkip("This session cannot access VideoToolbox hardware encoders.") }
        if ProcessInfo.processInfo.environment["CI"] == "true" { throw XCTSkip("Hosted CI runners do not provide a physical Apple silicon media engine.") }
        let decoded = expectation(description: "4K hardware decode")
        let decoder = VideoDecoder()
        let queue = DispatchQueue(label: "Screener.test.video")
        decoder.onImage = { image in
            XCTAssertEqual(CVPixelBufferGetWidth(image), 3840); XCTAssertEqual(CVPixelBufferGetHeight(image), 2160)
            decoded.fulfill()
        }
        let encoder = try VideoEncoder(width: 3840, height: 2160, fps: 60, megabits: 45)
        encoder.onError = { text in XCTFail(text) }
        encoder.onFormat = { format in queue.async { do { try decoder.configure(format) } catch { XCTFail(error.localizedDescription) } } }
        encoder.onFrame = { bytes in queue.async { do { try decoder.decode(bytes) } catch { XCTFail(error.localizedDescription) } }; return true }
        var image: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 3840, 2160, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary, &image)
        XCTAssertEqual(result, kCVReturnSuccess)
        guard let image else { XCTFail("Could not create a 4K test frame"); return }
        CVPixelBufferLockBaseAddress(image, [])
        if let base = CVPixelBufferGetBaseAddress(image) { memset(base, 128, CVPixelBufferGetBytesPerRow(image) * 2160) }
        CVPixelBufferUnlockBaseAddress(image, [])
        encoder.encode(image)
        wait(for: [decoded], timeout: 10)
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
