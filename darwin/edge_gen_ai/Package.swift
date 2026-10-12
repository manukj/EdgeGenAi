// swift-tools-version: 5.9
import PackageDescription

let flutterPackage = "FlutterFramework"

let package = Package(
    name: "edge_gen_ai",
    platforms: [.iOS("13.0"), .macOS("12.0")],
    products: [.library(name: "edge-gen-ai", targets: ["edge_gen_ai"])],
    dependencies: [.package(name: flutterPackage, path: "../\(flutterPackage)")],
    targets: [
        .target(
            name: "edge_gen_ai",
            dependencies: [.product(name: flutterPackage, package: flutterPackage)],
            resources: [.process("PrivacyInfo.xcprivacy")]
        )
    ]
)
