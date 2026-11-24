// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImpactLab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ImpactPhysics"),
        .executableTarget(name: "ImpactLab", dependencies: ["ImpactPhysics"]),
        .executableTarget(name: "ImpactCheck", dependencies: ["ImpactPhysics"]),
        // Measurement harness for tests/regression (reads the solver only through its public API).
        .executableTarget(name: "ImpactRegression", dependencies: ["ImpactPhysics"]),
    ]
)
