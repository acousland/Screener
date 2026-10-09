import Foundation
import Sparkle
import ScreenerCore

/// Sparkle still validates the signed feed and archive and performs installation itself.
/// Only an explicitly authenticated Client command selects automatic replies for this cycle.
@MainActor final class RemoteUpdateDriver: NSObject, SPUUserDriver {
    private let standard = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
    private(set) var status = RemoteUpdateStatus(.idle, message: "Update Server from this MacBook.")
    private var remote = false
    private var expected: UInt64 = 0
    private var received: UInt64 = 0
    private var version: String?
    private var build: String?
    var onChanged: (() -> Void)?
    var beforeInstall: (() async -> Void)?
    func begin() {
        remote = true; version = nil; build = nil; expected = 0; received = 0
        report(.checking, "Checking for a signed Server update…")
    }
    func report(_ phase: RemoteUpdateStatus.Phase, _ message: String, progress: Double? = nil) {
        let next = RemoteUpdateStatus(phase, message: message, progress: progress, targetVersion: version, targetBuild: build)
        if next != status { status = next; onChanged?() }
    }
    func finishCycle() {
        if remote && status.busy && status.phase != .restarting { report(.failed, "The Server update ended before installation completed. Try again.") }
        remote = false
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        if remote { reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)) }
        else { standard.show(request, reply: reply) }
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        if remote { report(.checking, "Checking for a signed Server update…") }
        else { standard.showUserInitiatedUpdateCheck(cancellation: cancellation) }
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if !remote && !state.userInitiated {
            version = appcastItem.displayVersionString; build = appcastItem.versionString
            report(.available, "Server \(version ?? "update") is available. Update from this MacBook or the Server's menu.")
            reply(.dismiss); return
        }
        guard remote else { standard.showUpdateFound(with: appcastItem, state: state, reply: reply); return }
        version = appcastItem.displayVersionString; build = appcastItem.versionString
        guard !appcastItem.isInformationOnlyUpdate else {
            report(.failed, "This release requires manual installation on the mini."); reply(.dismiss); return
        }
        report(.downloading, "Downloading Server \(version ?? "update")…"); reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if !remote { standard.showUpdateReleaseNotes(with: downloadData) }
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        if !remote { standard.showUpdateReleaseNotesFailedToDownloadWithError(error) }
    }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if remote {
            let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value ?? -1
            let latest = reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue
            report(latest ? .upToDate : .failed, error.localizedDescription); acknowledgement()
        }
        else { standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement) }
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if remote { report(.failed, error.localizedDescription); acknowledgement() }
        else { standard.showUpdaterError(error, acknowledgement: acknowledgement) }
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        if remote { report(.downloading, "Downloading Server \(version ?? "update")…") }
        else { standard.showDownloadInitiated(cancellation: cancellation) }
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        if remote { expected = expectedContentLength }
        else { standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength) }
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        if remote {
            received = received > UInt64.max - length ? UInt64.max : received + length
            let progress = expected > 0 ? min(1, Double(received) / Double(expected)) : nil
            // Send whole-percent progress so downloads cannot overwhelm the control channel.
            if progress.map({ Int($0 * 100) }) != status.progress.map({ Int($0 * 100) }) {
                report(.downloading, "Downloading Server \(version ?? "update")…", progress: progress)
            }
        } else { standard.showDownloadDidReceiveData(ofLength: length) }
    }
    func showDownloadDidStartExtractingUpdate() {
        if remote { report(.extracting, "Verifying and preparing Server \(version ?? "update")…") }
        else { standard.showDownloadDidStartExtractingUpdate() }
    }
    func showExtractionReceivedProgress(_ progress: Double) {
        if remote {
            let bounded = progress.isFinite ? min(1, max(0, progress)) : 0
            if Int(bounded * 100) != status.progress.map({ Int($0 * 100) }) { report(.extracting, "Preparing the signed Server update…", progress: bounded) }
        } else { standard.showExtractionReceivedProgress(progress) }
    }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard remote else { standard.showReady(toInstallAndRelaunch: reply); return }
        report(.restarting, "Installing Server \(version ?? "update") and restarting. The Client will reconnect…")
        Task { await beforeInstall?(); reply(.install) }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if remote { report(.restarting, "Server is restarting to finish the update…") }
        else { standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication) }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        if remote { acknowledgement() }
        else { standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement) }
    }
    func dismissUpdateInstallation() { if !remote { standard.dismissUpdateInstallation() } }
    func showUpdateInFocus() { if !remote { standard.showUpdateInFocus() } }
}
