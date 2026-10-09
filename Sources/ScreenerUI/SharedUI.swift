import SwiftUI
import Sparkle
import ScreenerCore

@MainActor public final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private var remoteUpdater: SPUUpdater?
    private var remoteDriver: RemoteUpdateDriver?
    public var onRemoteUpdateChanged: (() -> Void)?
    public var beforeRemoteInstall: (() async -> Void)?
    public init(remoteManaged: Bool = false) {
        super.init()
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            if remoteManaged {
                let driver = RemoteUpdateDriver()
                driver.onChanged = { [weak self] in self?.onRemoteUpdateChanged?() }
                driver.beforeInstall = { [weak self] in await self?.beforeRemoteInstall?() }
                let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
                remoteDriver = driver
                do { try updater.start(); remoteUpdater = updater }
                catch { driver.report(.failed, error.localizedDescription) }
            } else { controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) }
        }
    }
    public var available: Bool { controller != nil || remoteUpdater != nil }
    public var remoteStatus: RemoteUpdateStatus? { remoteDriver?.status }
    public func check() { if let remoteUpdater { remoteUpdater.checkForUpdates() } else { controller?.checkForUpdates(nil) } }
    public func updateRemotely() throws {
        guard let updater = remoteUpdater, let driver = remoteDriver else { throw ScreenerError.message("Remote updating is unavailable in this Server build.") }
        guard !driver.status.busy, updater.canCheckForUpdates else { throw ScreenerError.message("Server is already checking or updating. Finish its current update first.") }
        let app = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: app.path), FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            throw ScreenerError.message("Install Screener Server in a writable Applications folder on the mini before updating remotely. macOS may require local administrator approval.")
        }
        driver.begin(); updater.checkForUpdates()
    }
    public func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        remoteDriver?.finishCycle()
    }
}
public struct ScreenerMark: View {
    public init() {}
    public var body: some View {
        Image(systemName: "display.2").font(.system(size: 32, weight: .medium))
            .foregroundStyle(.white).frame(width: 68, height: 68)
            .background(LinearGradient(colors: [.teal, Color(red: 0.06, green: 0.3, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
    }
}
public struct StatusPill: View {
    let text: String
    let active: Bool
    public init(_ text: String, active: Bool) { self.text = text; self.active = active }
    public var body: some View {
        HStack(spacing: 6) { Circle().fill(active ? Color.teal : Color.secondary).frame(width: 7, height: 7); Text(text).font(.caption.weight(.medium)) }
            .padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: Capsule())
    }
}
public struct UpdateCommands: Commands {
    @ObservedObject var updater: UpdateController
    public init(updater: UpdateController) { self.updater = updater }
    public var body: some Commands {
        CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.check() }.disabled(!updater.available) }
    }
}
