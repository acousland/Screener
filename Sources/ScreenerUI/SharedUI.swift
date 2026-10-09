import SwiftUI
import Sparkle
import ScreenerCore

@MainActor public final class UpdateController: ObservableObject {
    private var controller: SPUStandardUpdaterController?
    public init() {
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
    }
    public var available: Bool { controller != nil }
    public func check() { controller?.checkForUpdates(nil) }
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
