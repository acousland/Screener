import AppKit
import VideoToolbox
import ScreenerCore
import VirtualDisplayBridge

// Intentionally does not request permissions or inject input.
@main struct Diagnostics {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        if args.contains("--virtual-display") {
            do {
                var failure: NSString?
                guard let monitor = SCRVirtualMonitor(failure: &failure) else { throw ScreenerError.message(failure as String? ?? "Virtual display creation failed.") }
                let modes = CGDisplayCopyAllDisplayModes(monitor.displayID, [kCGDisplayShowDuplicateLowResolutionModes:true] as CFDictionary) as? [CGDisplayMode] ?? []
                let details = modes.map { ["logicalWidth":$0.width, "logicalHeight":$0.height, "pixelWidth":$0.pixelWidth, "pixelHeight":$0.pixelHeight] }
                let object: [String: Any] = ["displayID":monitor.displayID, "modes":details]
                print(String(data: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
                guard modes.contains(where: { $0.width == 1920 && $0.pixelWidth == 3840 }), modes.contains(where: { $0.width == 2560 && $0.pixelWidth == 5120 }) else {
                    fputs("Required HiDPI modes are missing.\n", stderr); exit(1)
                }
                if args.contains("--hold") { try? await Task.sleep(for: .seconds(30)) }
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        } else {
            let object: [String: Any] = ["system":ProcessInfo.processInfo.operatingSystemVersionString,
                "screenRecording":CGPreflightScreenCaptureAccess(), "accessibility":AXIsProcessTrusted(),
                "virtualDisplayAPI":NSClassFromString("CGVirtualDisplay") != nil,
                "hardwareH264Decode":VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)]
            print(String(data: try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        }
    }
}
