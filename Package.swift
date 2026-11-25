// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImpactLab",
    platforms: [.macOS(.v14)],
    targets: [
        // Clipper2 (Angus Johnson, BSL-1.0) behind a small C interface, for the editor's Cut and Join.
        .target(name: "CClipper2", exclude: ["README.md", "vendor/LICENSE"],
                cxxSettings: [.headerSearchPath("vendor/include")]),
        // Solver-independent geometry: polygon outlines, quality triangle mesher, mesh metrics, advisory notes,
        // polygon booleans (through CClipper2).
        .target(name: "ImpactGeometry", dependencies: ["CClipper2"]),
        .target(name: "ImpactPhysics", dependencies: ["ImpactGeometry"]),
        .executableTarget(name: "ImpactLab", dependencies: ["ImpactPhysics", "ImpactGeometry"]),
        .executableTarget(name: "ImpactCheck", dependencies: ["ImpactPhysics", "ImpactGeometry"]),
        // Measurement harness for tests/regression (reads the solver only through its public API).
        .executableTarget(name: "ImpactRegression", dependencies: ["ImpactPhysics"]),
        .executableTarget(name: "MeshCheck", dependencies: ["ImpactGeometry", "ImpactPhysics"]),
    ],
    cxxLanguageStandard: .cxx17
)
