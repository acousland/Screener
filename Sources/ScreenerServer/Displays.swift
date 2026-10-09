import AppKit
import ScreenerCore
import VirtualDisplayBridge

struct HostDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let virtual: Bool
}
@MainActor final class Displays {
    private var virtualMonitor: SCRVirtualMonitor?
    var virtualID: CGDirectDisplayID? { virtualMonitor?.displayID }
    func ensureVirtual() throws -> CGDirectDisplayID {
        if let virtualMonitor { return virtualMonitor.displayID }
        var failure: NSString?
        guard let monitor = SCRVirtualMonitor(failure: &failure) else { throw ScreenerError.message(failure as String? ?? "Virtual display creation failed.") }
        virtualMonitor = monitor
        return monitor.displayID
    }
    func list() -> [HostDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsActive($0) != 0 }.map { id in
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            return HostDisplay(id: id, name: id == virtualID ? "Screener 4K · Virtual" : screen?.localizedName ?? "Display \(id)", virtual: id == virtualID)
        }
    }
    func modes(_ id: CGDirectDisplayID) -> [DisplayModeInfo] {
        guard let all = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes:true] as CFDictionary) as? [CGDisplayMode] else { return [] }
        var seen = Set<String>()
        return all.filter { mode in
            let key = "\(mode.width)x\(mode.height):\(mode.pixelWidth)x\(mode.pixelHeight)"
            return mode.isUsableForDesktopGUI() && mode.width >= 1280 && mode.pixelWidth <= 7680 && mode.pixelHeight <= 4320 && seen.insert(key).inserted
        }.map { DisplayModeInfo(id: $0.ioDisplayModeID, width: $0.width, height: $0.height, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight) }
            .sorted { $0.width == $1.width ? $0.pixelWidth > $1.pixelWidth : $0.width < $1.width }
    }
    func setMode(_ modeID: Int32, on id: CGDirectDisplayID) throws {
        guard modes(id).contains(where: { $0.id == modeID }),
            let all = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes:true] as CFDictionary) as? [CGDisplayMode],
            let mode = all.first(where: { $0.ioDisplayModeID == modeID }) else { throw ScreenerError.message("That display scaling mode is no longer available.") }
        let result = CGDisplaySetDisplayMode(id, mode, nil)
        guard result == .success else { throw ScreenerError.message("macOS could not change the display scaling (\(result.rawValue)).") }
    }
    func info(_ id: CGDirectDisplayID) throws -> DesktopInfo {
        guard let mode = CGDisplayCopyDisplayMode(id) else { throw ScreenerError.message("The selected monitor is not available.") }
        let size = ScreenGeometry.streamSize(width: mode.pixelWidth, height: mode.pixelHeight)
        return DesktopInfo(name: list().first(where: { $0.id == id })?.name ?? "Mac desktop", streamWidth: size.0, streamHeight: size.1,
            logicalWidth: mode.width, logicalHeight: mode.height, currentMode: mode.ioDisplayModeID, modes: modes(id))
    }
    func restoreScaling(on id: CGDirectDisplayID) {
        let width = UserDefaults.standard.integer(forKey: "virtualLogicalWidth")
        let height = UserDefaults.standard.integer(forKey: "virtualLogicalHeight")
        let target = modes(id).first { $0.hiDPI && $0.width == (width == 0 ? 1920 : width) && $0.height == (height == 0 ? 1080 : height) }
        if let target { try? setMode(target.id, on: id) }
    }
    func saveScaling(_ info: DesktopInfo) {
        UserDefaults.standard.set(info.logicalWidth, forKey: "virtualLogicalWidth")
        UserDefaults.standard.set(info.logicalHeight, forKey: "virtualLogicalHeight")
    }
}
