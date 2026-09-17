// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [.library(name: "TransomCore", targets: ["TransomCore"])]
var targets: [Target] = [
    .target(name: "TransomCore"),
    .testTarget(name: "TransomCoreTests", dependencies: ["TransomCore"])
]
#if os(macOS)
products += [
    .executable(name: "Transom", targets: ["TransomApp"]),
    .executable(name: "TransomLab", targets: ["TransomLab"])
]
targets += [
    .target(name: "TransomBridge", publicHeadersPath: "include", linkerSettings: [
        .linkedFramework("ApplicationServices"), .linkedFramework("CoreGraphics")
    ]),
    .executableTarget(name: "TransomApp", dependencies: ["TransomCore", "TransomBridge"],
        linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]),
    .executableTarget(name: "TransomLab", linkerSettings: [.linkedFramework("AppKit")])
]
#endif

let package = Package(
    name: "Transom",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    // Swift 6 toolchain; language mode 5 avoids pretending an AXUIElement is Sendable.
    // AX objects are confined to one serial queue per application. See docs/ARCHITECTURE.md.
    swiftLanguageModes: [.v5]
)
