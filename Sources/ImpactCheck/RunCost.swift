import Foundation
import ImpactPhysics

/// Reports the timestep diagnosis and the pre-run cost estimate for the
/// shipped scenes and for the slow steel-on-steel fracture case of Google Doc
/// section 21.4, then measures the real speed over a short stretch of each.
/// Reporting only; no solver setting is changed.
func runCostCheck() throws {
    var scenes: [(String, AssemblyScene)] = [
        ("builtin/metalImpactExample", .metalImpactExample()),
        ("builtin/enclosureExample", .enclosureExample()),
        ("builtin/bendingFractureExample", .bendingFractureExample()),
    ]
    var slow = AssemblyScene.metalImpactExample()
    MaterialProfile.structuralSteel.apply(to: &slow.parts[0])
    slow.parts[0].name = "Steel target"
    slow.parts[0].fracture = MaterialProfile.structuralSteel.defaultFracture
    slow.meshResolution = .extraFine
    slow.duration = 0.05
    scenes.append(("doc-21.4 steel on steel, fracture, 3 mm, 50 ms", slow))
    for directory in ["docs/scene-examples", "docs/showcase", "docs/lab-examples"] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        for file in files.filter({ $0.hasSuffix(".json") && $0 != "invalid-example.json" }).sorted() {
            scenes.append((directory + "/" + file, try AssemblyScene.open(URL(fileURLWithPath: directory + "/" + file))))
        }
    }
    var ratios: [Double] = []
    for (name, scene) in scenes {
        var simulation = try AssemblySimulation(scene)
        let diagnosis = simulation.timestep
        let estimate = RunCostEstimate(simulation)
        simulation.configureParallelFEM(true)
        let start = ProcessInfo.processInfo.systemUptime
        var steps = 0
        while ProcessInfo.processInfo.systemUptime - start < 2.0 && simulation.step() { steps += 1 }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let projected = elapsed / Double(max(1, steps)) * estimate.steps
        let ratio = projected / max(1e-9, estimate.seconds)
        ratios.append(ratio)
        print("\(name)")
        print("  \(diagnosis.explanation)")
        print(String(format: "  estimate %.0f steps × %d element-weight → %@ ; measured %d steps in %.2f s → projected %@ (measured/estimate %.2f)",
                     estimate.steps, estimate.elementWeight, RunCostEstimate.duration(estimate.seconds), steps, elapsed,
                     RunCostEstimate.duration(projected), ratio))
        print("  \(estimate.laneNote)")
    }
    print(String(format: "Measured/estimate ratio over %d scenes: min %.2f, max %.2f (default rate %.0e element-weight updates per second)",
                 ratios.count, ratios.min()!, ratios.max()!, RunCostEstimate.defaultRate))
}
