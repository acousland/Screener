import XCTest
import Sparkle
import ScreenerCore
@testable import ScreenerUI

final class RemoteUpdateTests: XCTestCase {
    @MainActor func testRemoteInstallWaitsForSessionShutdown() async {
        let driver = RemoteUpdateDriver()
        let shutdownStarted = expectation(description: "Session shutdown begins")
        let installed = expectation(description: "Installer authorized after shutdown")
        var shutdownFinished = false
        driver.beforeInstall = {
            shutdownStarted.fulfill()
            await Task.yield()
            shutdownFinished = true
        }
        driver.begin(); driver.showReady(toInstallAndRelaunch: { choice in
            XCTAssertTrue(shutdownFinished); XCTAssertEqual(choice, .install); installed.fulfill()
        })
        XCTAssertEqual(driver.status.phase, .restarting)
        await fulfillment(of: [shutdownStarted, installed], timeout: 3)
    }
    @MainActor func testRemoteDownloadAndExtractionReportBoundedProgress() {
        let driver = RemoteUpdateDriver(); driver.begin()
        driver.showDownloadInitiated(cancellation: { XCTFail("Unexpected cancellation") })
        driver.showDownloadDidReceiveExpectedContentLength(100)
        driver.showDownloadDidReceiveData(ofLength: 20)
        XCTAssertEqual(driver.status.phase, .downloading); XCTAssertEqual(driver.status.progress, 0.2)
        driver.showDownloadDidReceiveData(ofLength: UInt64.max)
        XCTAssertEqual(driver.status.progress, 1)
        driver.showDownloadDidReceiveData(ofLength: UInt64.max)
        XCTAssertTrue(driver.status.valid)
        driver.showDownloadDidStartExtractingUpdate(); XCTAssertEqual(driver.status.phase, .extracting)
        for progress in [-1, Double.nan, Double.infinity, 2] { driver.showExtractionReceivedProgress(progress); XCTAssertTrue(driver.status.valid) }
    }
    @MainActor func testNoUpdateDistinguishesCurrentVersionFromUnsupportedSystem() {
        let driver = RemoteUpdateDriver(); driver.begin()
        var acknowledgements = 0
        let latest = NSError(domain: "SUSparkleErrorDomain", code: 1001, userInfo: [SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.onLatestVersion.rawValue)])
        driver.showUpdateNotFoundWithError(latest, acknowledgement: { acknowledgements += 1 })
        XCTAssertEqual(driver.status.phase, .upToDate)
        driver.finishCycle(); driver.begin()
        let unsupported = NSError(domain: "SUSparkleErrorDomain", code: 1001, userInfo: [SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.systemIsTooOld.rawValue)])
        driver.showUpdateNotFoundWithError(unsupported, acknowledgement: { acknowledgements += 1 })
        XCTAssertEqual(driver.status.phase, .failed); XCTAssertEqual(acknowledgements, 2)
    }
    @MainActor func testRemoteErrorsAndInterruptedCyclesRemainRetryable() {
        let controller = UpdateController(remoteManaged: true)
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("updater:didFinishUpdateCycleForUpdateCheck:error:")))
        let driver = RemoteUpdateDriver(); driver.begin()
        var acknowledged = false
        driver.showUpdaterError(NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid archive signature"]), acknowledgement: { acknowledged = true })
        XCTAssertTrue(acknowledged); XCTAssertEqual(driver.status.phase, .failed); XCTAssertFalse(driver.status.busy)
        driver.finishCycle(); driver.begin(); XCTAssertEqual(driver.status.phase, .checking)
        driver.finishCycle(); XCTAssertEqual(driver.status.phase, .failed)
    }
}
