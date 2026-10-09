// swift-tools-version: 6.0
import PackageDescription
import Foundation

// An offline build can use the same official xcframework from a local Sparkle cache.
let offline = ProcessInfo.processInfo.environment["SCREENER_LOCAL_SPARKLE"] == "1"
let sparkleDependency: Target.Dependency = offline ? "Sparkle" : .product(name: "Sparkle", package: "Sparkle")
var targets: [Target] = [
    .target(name: "VirtualDisplayBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("Foundation")]),
    .target(name: "ScreenerCore", linkerSettings: [.linkedFramework("ScreenCaptureKit"), .linkedFramework("VideoToolbox")]),
    .target(name: "ScreenerUI", dependencies: ["ScreenerCore", sparkleDependency]),
    .executableTarget(name: "ScreenerServer", dependencies: ["ScreenerCore", "ScreenerUI", "VirtualDisplayBridge"], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .executableTarget(name: "ScreenerClient", dependencies: ["ScreenerCore", "ScreenerUI"], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .executableTarget(name: "ScreenerDiagnostics", dependencies: ["ScreenerCore", "VirtualDisplayBridge"]),
    .testTarget(name: "ScreenerCoreTests", dependencies: ["ScreenerCore"]),
]
if offline { targets.append(.binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework")) }
let package = Package(name: "Screener", platforms: [.macOS(.v15)],
    products: [.executable(name: "ScreenerServer", targets: ["ScreenerServer"]),
               .executable(name: "ScreenerClient", targets: ["ScreenerClient"]),
               .executable(name: "ScreenerDiagnostics", targets: ["ScreenerDiagnostics"])],
    dependencies: offline ? [] : [.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")],
    targets: targets, swiftLanguageModes: [.v5])
