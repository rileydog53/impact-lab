import Foundation
import ImpactPhysics

// Regression for the fracture step-acceptance bug (decision record 27.1, milestone 27.7; plan step 1).
// A 40 × 40 mm elastic block released from rest 40 mm above a fixed bench, with default fracture on,
// stopped at first contact: the energy guard compared the residual with 2% of the starting energy,
// which is zero for a body released from rest under gravity, so the test was really |residual| ≤ 1e-9 J/m.
// The guard now measures the residual against the starting energy plus the gravitational work released
// so far (EnergyAcceptance). NUMERICAL VERIFICATION of the acceptance rule only, not physical validation.

private func dropScene(fracture: Bool) -> AssemblyScene {
    var scene = AssemblyScene()
    var bench = AssemblyPart("Bench", center: Point(0, -0.015), size: Point(0.30, 0.03))
    bench.support = .fixed
    bench.material = Material(young: 1e7, density: 2500, poisson: 0.2)
    // Bottom face 40 mm above the bench top.
    var block = AssemblyPart("Dropped block", center: Point(0, 0.06), size: Point(0.04, 0.04))
    block.material = Material(young: 2e6, density: 1100, poisson: 0.3)
    if fracture { block.fracture = MaterialFractureSettings() }
    scene.parts = [bench, block]
    scene.gravity = AssemblyScene.standardGravity
    scene.duration = 0.16
    return scene
}

private struct DropRun {
    var simulation: AssemblySimulation
    var residuals: [Double] = []
    var firstInsertionStep: Int?
    var completed: Bool { simulation.failure == nil && simulation.time >= simulation.scene.duration }

    init(_ simulation: AssemblySimulation) { self.simulation = simulation }

    mutating func run() {
        while simulation.time < simulation.scene.duration {
            guard simulation.step() else { return }
            residuals.append(simulation.energies.total - simulation.initialEnergy)
            if firstInsertionStep == nil, (simulation.fractureReading(1)?.insertedEdges ?? 0) > 0 {
                firstInsertionStep = residuals.count
            }
        }
    }
}

func fractureGuardCheck() throws {
    print("Fracture energy guard (numerical verification of the step-acceptance rule, not physical validation)")
    let g = AssemblyScene.standardGravity

    // 1. The rule itself, on the numbers recorded by the independent review (decision record 27.1).
    do {
        let residual = -0.000324293, release = 0.690388
        let old = EnergyAcceptance.legacyAccepts(residual: residual, initialEnergy: 0)
        let new = EnergyAcceptance.accepts(residual: residual, initialEnergy: 0, gravitationalRelease: release)
        print(String(format: "  Recorded first-contact step: residual %.6e J/m, m·g·h %.6f J/m (%.4f%%); old rule %@, new rule %@",
                     residual, release, 100 * abs(residual) / release, old ? "accepts" : "rejects", new ? "accepts" : "rejects"))
        require(!old, "the old rule should reproduce the recorded rejection")
        require(new, "a 0.047% residual of m·g·h must be accepted")
        let bad = 0.03 * release
        require(!EnergyAcceptance.accepts(residual: bad, initialEnergy: 0, gravitationalRelease: release)
                && !EnergyAcceptance.accepts(residual: -bad, initialEnergy: 0, gravitationalRelease: release),
                "negative control: a 3% residual must still be rejected")
        // Without gravity the new rule must be the old rule exactly.
        for initial in [0.0, 1e-12, 0.37, 12.5, 4.2e3] {
            for factor in [0.0, 0.0199999, 0.02, 0.0200001, 0.5, 1.0] {
                for sign in [-1.0, 1.0] {
                    let r = sign * factor * initial
                    require(EnergyAcceptance.accepts(residual: r, initialEnergy: initial, gravitationalRelease: 0)
                            == EnergyAcceptance.legacyAccepts(residual: r, initialEnergy: initial),
                            "without gravity the new rule must match the old one")
                }
            }
        }
        print("  Negative control (3% of m·g·h) rejected; with no gravity the rule equals the old one")
    }

    // 2. The 40 mm drop with default fracture on must now run to the end.
    let fractureScene = dropScene(fracture: true)
    let issues = fractureScene.issues()
    require(issues.isEmpty, issues.joined(separator: "; "))
    var fractured = DropRun(try AssemblySimulation(fractureScene))
    require(fractured.simulation.initialIssue == nil, fractured.simulation.initialIssue ?? "")
    let mass = fractured.simulation.body(1).totalMass
    let mgh = mass * g * 0.04
    fractured.run()
    let peak = fractured.residuals.map(abs).max() ?? 0
    let reading = fractured.simulation.fractureReading(1)
    print(String(format: "  Drop, fracture on: dt %.6f µs, reached %.4f ms of %.0f ms, peak |residual| %.3e J/m = %.4f%% of m·g·h (%.6f J/m)",
                 fractured.simulation.dt * 1e6, fractured.simulation.time * 1e3, fractureScene.duration * 1e3,
                 peak, 100 * peak / mgh, mgh))
    print("    cracks inserted: \(reading?.insertedEdges ?? 0), failed: \(reading?.failedEdges ?? 0)"
          + (fractured.simulation.failure.map { ", stopped: \($0)" } ?? ""))
    require(fractured.completed, "the 40 mm drop with fracture on must run to the end; stopped: \(fractured.simulation.failure ?? "?")")

    // 3. Matched uncracked control: fracture off, same timestep, same 2× interbody penalty.
    //    Reported, not judged: the review found the identical residual at first contact.
    var control = DropRun(try AssemblySimulation(dropScene(fracture: false), refinement: fractureScene.resolution.rawValue,
                                                 stepLimit: fractured.simulation.dt, interbodyStiffnessScale: 2))
    control.run()
    let matched = control.simulation.dt == fractured.simulation.dt
    let common = min(fractured.firstInsertionStep ?? fractured.residuals.count, control.residuals.count)
    var difference = 0.0
    for i in 0..<common { difference = max(difference, abs(fractured.residuals[i] - control.residuals[i])) }
    print(String(format: "  Control, fracture off: dt %@, reached %.4f ms; residuals differ by at most %.3e J/m over %d steps before any crack",
                 matched ? "matched" : "NOT matched", control.simulation.time * 1e3, difference, common))
    require(control.completed, "the fracture-off control must run to the end")

    // 4. Negative control: a deliberately bad run must still be stopped, and by the energy guard.
    //    The step bound is conservative for this mesh (3× and 4× still run cleanly), so use ten times it.
    var unstable = DropRun(try AssemblySimulation(fractureScene, refinement: fractureScene.resolution.rawValue,
                                                  stepLimit: .infinity, stepScale: 10))
    unstable.run()
    print(String(format: "  Unstable run (10× step): stopped at %.4f ms: %@", unstable.simulation.time * 1e3,
                 unstable.simulation.failure ?? "not stopped"))
    require(!unstable.completed && unstable.simulation.rejectedEnergy != nil,
            "a run at ten times the stable step must be rejected by the energy guard")
    print("PASS: fracture energy guard")
}
