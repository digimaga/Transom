// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [.library(name: "WindowBarCore", targets: ["WindowBarCore"])]
var targets: [Target] = [
    .target(name: "WindowBarCore"),
    .testTarget(name: "WindowBarCoreTests", dependencies: ["WindowBarCore"])
]
#if os(macOS)
products += [
    .executable(name: "WindowBar", targets: ["WindowBarApp"]),
    .executable(name: "WindowBarLab", targets: ["WindowBarLab"])
]
targets += [
    .target(name: "WindowBarBridge", publicHeadersPath: "include", linkerSettings: [
        .linkedFramework("ApplicationServices"), .linkedFramework("CoreGraphics")
    ]),
    .executableTarget(name: "WindowBarApp", dependencies: ["WindowBarCore", "WindowBarBridge"],
        linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]),
    .executableTarget(name: "WindowBarLab", linkerSettings: [.linkedFramework("AppKit")])
]
#endif

let package = Package(
    name: "WindowBar",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    // Swift 6 toolchain; language mode 5 avoids pretending an AXUIElement is Sendable.
    // AX objects are confined to one serial queue per application. See docs/ARCHITECTURE.md.
    swiftLanguageModes: [.v5]
)
