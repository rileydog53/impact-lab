import Foundation
import ImpactPhysics

/// Timing benchmark for performance work. Runs a fixed number of steps of a few
/// representative scenes and prints wall time plus a bit-exact fingerprint of the
/// final state (positions, velocities and energies), so an optimization can be
/// checked to leave every number unchanged. Reporting only.
func runPerfBench(steps limit: Int) throws {
    var fracture = AssemblyScene.bendingFractureExample()
    var noFracture = fracture
    noFracture.parts[0].fracture = nil
    var outline = try AssemblyScene.open(URL(fileURLWithPath: "docs/geometry/outline-bracket.json"))
    let cases: [(String, AssemblyScene)] = [
        ("bend, fracture on", fracture),
        ("bend, fracture off", noFracture),
        ("outline bracket", outline),
    ]
    for (name, scene) in cases {
        var simulation = try AssemblySimulation(scene)
        simulation.configureParallelFEM(true)
        let start = ProcessInfo.processInfo.systemUptime
        var steps = 0
        while steps < limit && simulation.step() { steps += 1 }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: Double) { hash = (hash ^ value.bitPattern) &* 0x100000001b3 }
        for i in 0..<simulation.bodyCount {
            let body = simulation.body(i)
            for p in body.position { mix(p.x); mix(p.y) }
            for v in body.velocity { mix(v.x); mix(v.y) }
        }
        let e = simulation.energies
        for value in [e.kinetic, e.elastic, e.contact, e.fracture, e.cohesive, e.plastic] { mix(value) }
        print(String(format: "%@: %d steps in %.3f s (%.1f µs/step) fingerprint %016llx%@", name, steps, elapsed,
                     elapsed / Double(max(1, steps)) * 1e6, hash, simulation.failure.map { " FAILED " + $0 } ?? ""))
    }
}
