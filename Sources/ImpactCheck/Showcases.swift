import Foundation
import ImpactPhysics

/// `ImpactCheck --showcases [full] [NAME…]`: every ready-made showcase builds through the scene-document validator and
/// starts a run. Without `full` each one takes 200 steps (a smoke check for CI). With `full` each runs to its end and
/// the report gives wall time, step, first crack, crack length, plastic work and energy error, so the presets can be
/// tuned to do something visible. Reading results only; nothing here changes the solver.
func showcaseCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    let args = CommandLine.arguments
    let full = args.contains("full")
    let chosen = ShowcasePreset.allCases.filter { preset in
        let names = args.drop { $0 != "--showcases" }.dropFirst().filter { $0 != "full" }
        return names.isEmpty || names.contains { preset.rawValue.lowercased().contains($0.lowercased()) }
    }
    print("Ready-made showcases (\(full ? "full runs" : "200-step smoke")). Numerical behaviour only, not validation.")
    for preset in chosen {
        let scene = try preset.scene()
        var sim = try AssemblySimulation(scene)
        require(sim.initialIssue == nil, "\(preset.rawValue): \(sim.initialIssue ?? "")")
        require(scene.parts.allSatisfy { abs($0.velocity.x) <= 150 && abs($0.velocity.y) <= 150 }, "\(preset.rawValue): speed above 150 m/s")
        let began = Date()
        var steps = 0, worst = 0.0, firstCrack: Double?
        while sim.time < scene.duration - 1e-15, full || steps < 200 {
            require(sim.step(), "\(preset.rawValue): \(sim.failure ?? "step rejected") at \(sim.time) s")
            steps += 1
            if sim.initialEnergy > 0 { worst = max(worst, abs(sim.energies.total - sim.initialEnergy) / sim.initialEnergy) }
            if firstCrack == nil, (0..<sim.bodyCount).contains(where: { (sim.fractureReading($0)?.insertedEdges ?? 0) > 0 }) {
                firstCrack = sim.time
            }
        }
        let crack = (0..<sim.bodyCount).compactMap { sim.fractureReading($0) }
        let length = crack.map(\.crackLength).reduce(0, +)
        print(String(format: "  %@: %d steps, step %.3g s, %.1f s wall, first crack %@, crack length %.1f mm, plastic work %.3g J/m, energy error %.2f%%",
                     preset.rawValue, steps, sim.dt, Date().timeIntervalSince(began),
                     firstCrack.map { String(format: "%.1f µs", $0 * 1e6) } ?? "none", length * 1000,
                     sim.plasticWorkIntegral, worst * 100))
    }
    print("PASS: every showcase builds and runs.")
}
