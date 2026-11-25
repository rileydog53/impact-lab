import Foundation
import ImpactPhysics
import simd

// Layered target plan, step 8, test-only path: find where the mesh actually fails above the app's former 150 m/s cap.
// The scenes are saved with their striker at rest (so they pass the scene rules) and the striker is given its speed
// through the solver's test-only initial-velocity hook, so nothing here depends on the app's speed limit.
//
// NUMERICAL ROBUSTNESS ONLY. A run that "holds" kept its books balanced and its contact clean; that says nothing about
// whether the physics is right at that speed (no rate effects, no heating, no shock equation of state).
//
// Criteria fixed before the first run (2026-11-25). A run holds when it reaches its end without the solver rejecting a
// step, with energy error at most 0.5% (2% for the fracture scene, the fracture guard's own limit) and peak contact
// overlap at most 2% of an edge (the step-probe bounds in docs/PHASE_0_8.md). The supported cap is the highest tested
// speed at which every scene holds at that speed and at every lower one.
// First run (2026-11-25): no speed met that, because the laminated glass scene stops at 150 m/s (its bulk viscosity
// needs a shorter step than the run uses, a deliberate stop from step 4). The sweep is therefore a measurement, not a
// gate, and the app's cap is unchanged; see docs/SPEED_LIMIT.md.
struct SpeedCase {
    let name: String
    let scene: AssemblyScene
    let striker: Int
    let energyLimit: Double
    var gated = true
}

func speedLimitCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Speed limit sweep (plan step 8, test-only path). Numerical robustness only, not physical validation.")
    let speeds: [Double] = [150, 200, 300, 400, 500, 700, 1000]
    let plate = try AssemblyScene.open(URL(fileURLWithPath: "docs/scene-examples/metal-plate-impact.json"))
    var smoothed = plate
    smoothed.bulkViscosity = .standard
    let glass = try LayeredExample.laminated_glass_on_aluminium.scene()
    var unsmoothed = glass
    unsmoothed.bulkViscosity = nil
    let cases = [SpeedCase(name: "Metal plate impact (steel ball on aluminium, plastic)", scene: plate, striker: 1, energyLimit: 0.005),
                 SpeedCase(name: "Metal plate impact, bulk viscosity on", scene: smoothed, striker: 1, energyLimit: 0.005),
                 SpeedCase(name: "Laminated glass on aluminium (fracture and bonds)", scene: glass, striker: 1, energyLimit: 0.02),
                 SpeedCase(name: "Laminated glass on aluminium, bulk viscosity off (reported, not gated)", scene: unsmoothed, striker: 1, energyLimit: 0.02, gated: false)]
    var holds: [String: [Double: Bool]] = [:]
    for item in cases {
        let direction = simd_normalize(item.scene.parts[item.striker].velocity)
        let baseSpeed = simd_length(item.scene.parts[item.striker].velocity)
        print("  \(item.name), saved at \(Int(baseSpeed)) m/s over \(String(format: "%.3g", 1e3 * item.scene.duration)) ms")
        for speed in speeds {
            var scene = item.scene
            scene.parts[item.striker].velocity = .zero
            // The same striker travel as the saved scene, with a floor so slow waves still cross the target.
            scene.duration = max(0.00015, item.scene.duration * baseSpeed / speed)
            let velocity = speed * direction
            let start = ProcessInfo.processInfo.systemUptime
            var sim = try AssemblySimulation(scene, refinement: scene.resolution.rawValue, stepLimit: .infinity,
                                             initialVelocity: { part, _ in part == item.striker ? velocity : .zero })
            let initial = sim.initialEnergy
            var worst = 0.0, steps = 0, failure: String?
            while sim.time < scene.duration - 1e-15 {
                guard sim.step() else { failure = sim.failure ?? "step rejected"; break }
                steps += 1
                worst = max(worst, abs(sim.energies.total - initial) / initial)
                if steps > 2_000_000 { failure = "more than 2,000,000 steps"; break }
            }
            let held = failure == nil && worst <= item.energyLimit && sim.peakRelativePenetration <= 0.02
            holds[item.name, default: [:]][speed] = held
            let cracks = sim.fractureReading(0).map { ", \($0.insertedEdges) crack faces, \($0.pieces) pieces" } ?? ""
            print(String(format: "    %5.0f m/s: %@ — %d steps in %.1f s, energy error %.3f%%, peak overlap %.2f%% of an edge%@%@",
                         speed, held ? "holds" : "FAILS", steps, ProcessInfo.processInfo.systemUptime - start, 100 * worst,
                         100 * sim.peakRelativePenetration, cracks, failure.map { "; stopped at \(String(format: "%.4g", 1e6 * sim.time)) µs: \($0)" } ?? ""))
        }
    }
    let supported = speeds.prefix { speed in cases.filter(\.gated).allSatisfy { holds[$0.name]![speed]! } }.last
    print("  Highest tested speed at which every scene holds (and at every lower one): " + (supported.map { "\(Int($0)) m/s" } ?? "none"))
    // A measurement, not a gate: the cap stays where it is until this result is reviewed (docs/SPEED_LIMIT.md).
    print("Speed limit sweep finished (measurement only). The app's cap is \(Int(AssemblyPart.velocityRange.upperBound)) m/s.")
}
