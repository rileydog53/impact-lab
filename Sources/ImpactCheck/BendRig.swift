import Foundation
import ImpactPhysics
import simd

// Displacement-driven bend on the virtual test machine, and the crack-load benchmark (layered target plan, step 8
// part 2; milestone "trustworthy ordinary experiments", bend row).
//
// A beam is clamped on its left edge, and a grip holds its right edge and moves it straight down: a fixed-guided beam.
// Both ends keep their slope, so the bending moment is P L / 2 at both ends (opposite signs) and zero at midspan.
// Theory, plane strain (a wide plate: E' = E / (1 − ν²)), Timoshenko beam with shear coefficient κ = 5/6:
//     δ = P L³ / (12 E' I) + P L / (κ G A),   I = h³/12,  A = h  (per metre of depth).
// The test machine prescribes δ, so the check gates the grip's REACTION FORCE at that deflection against theory, not
// the deflection itself (review of PR 16, 2026-11-25). The force-driven sags stay as separate regressions in
// `--supports-gravity` (cantilever 1.2180 mm, rollers 1.0885 mm).
// Crack load: the end moment P L / 2 gives a surface stress 3 P L / h², which reaches the crack strength σ at
// P = σ h² / (3 L).
//
// NUMERICAL VERIFICATION, not physical validation. The clamp and grip corners are stress singularities in plane strain
// [recall: Williams 1952], so a strength-based crack test starts cracks earlier on finer meshes.
// Criteria fixed before the first run (2026-11-25):
//  1. Elastic beam (fracture off): the slope of grip force against grip displacement, fitted over the points after the
//     ramp, is within 3% of the Timoshenko stiffness on the x4 mesh (12 elements through the depth). x6 reported.
//  2. Cracking beam (fracture on, 4.5 MPa, 100 J/m²): the first crack is within 10% of the span from either end, on
//     that end's tension face (top at the clamp, bottom at the grip); every step is accepted.
//  3. The grip force at the first crack is within 20% of σ h² / (3 L) on x4; x6 is reported with the change from x4.
// AMENDED after the first run (2026-11-25), which failed criterion 1: x4 came out +3.41% stiff. The probe mode
// (`--bend-rig probe`) split that up. About +0.66% is membrane tension: the grip also holds the beam's end at its
// length, so a 1.9 mm deflection stretches the beam (axial grip force 1.47 kN/m). That nonlinear effect is outside the
// linear theory and vanishes at small deflection (15 N/m at a tenth of it). The rest is the mesh: linear triangles are
// too stiff in bending, +2.75% at x4, +1.93% x5, +1.44% x6, +1.18% x7, converging toward theory. Criterion 1 now
// compares the LINEAR response (a tenth of the deflection) with linear theory, still within 3% on x4, and adds a
// requirement that x6 is closer to theory than x4. The full-deflection stiffness is still reported. The 3% is unchanged.
// Loading: about 15 periods of the beam's first fixed-guided bending mode (about 4.9 ms) up to the crack load.

private let span = 0.16, depth = 0.02
private let young = 1e9, poisson = 0.2, density = 1000.0, strength = 4.5e6

private func bendScene(_ resolution: String, fracture: Bool, speed: Double, duration: Double) throws -> AssemblyScene {
    let crack = fracture ? #", "fracture": { "strength": \#(strength), "energy": 100 }"# : ""
    let text = #"""
    { "duration": \#(duration), "meshResolution": "\#(resolution)",
      "parts": [
        { "name": "Fixed-guided beam", "size": [\#(span), \#(depth)], "center": [0, 0], "support": "clampLeft",
          "material": { "young": \#(young), "density": \#(density), "poisson": \#(poisson) }\#(crack),
          "grip": { "edge": "right", "velocity": [0, -\#(speed)], "ramp": 0.01 } } ] }
    """#
    return try AssemblyScene.document(Data(text.utf8))
}

func bendRigCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Displacement-driven bend and crack load on the test machine (fixed-guided beam). Numerical verification, not physical validation.")
    let planeStrain = young / (1 - poisson * poisson)
    let shear = young / (2 * (1 + poisson))
    let inertia = depth * depth * depth / 12
    let compliance = span * span * span / (12 * planeStrain * inertia) + span / (5.0 / 6 * shear * depth)
    let stiffness = 1 / compliance
    let crackLoad = strength * depth * depth / (3 * span)
    let crackDeflection = crackLoad * compliance
    let speed = crackDeflection / 0.07
    print(String(format: "  Beam %.0f × %.0f mm, E' %.4g GPa: Timoshenko stiffness %.4g N/m per m (bending %.1f%%, shear %.1f%% of the compliance); crack load %.0f N/m at %.3f mm; grip %.4f m/s",
                 1000 * span, 1000 * depth, planeStrain / 1e9, stiffness,
                 100 * span * span * span / (12 * planeStrain * inertia) / compliance,
                 100 * span / (5.0 / 6 * shear * depth) / compliance, crackLoad, 1000 * crackDeflection, speed))

    // Diagnosis only (`--bend-rig probe`): stiffness against mesh and against deflection size.
    if CommandLine.arguments.contains("probe") {
        for resolution in ["x4", "x5", "x6", "x7"] {
            for scale in [1.0, 0.1] {
                let scene = try bendScene(resolution, fracture: false, speed: scale * speed, duration: 0.07)
                var sim = try AssemblySimulation(scene)
                var points: [(Double, Double)] = []
                while sim.time < scene.duration - 1e-15 {
                    require(sim.step(), "probe \(resolution): \(sim.failure ?? "step rejected")")
                    if sim.time > 0.02 { points.append((-sim.gripDisplacement(0).y, -sim.gripReaction(0).y)) }
                }
                let n = Double(points.count)
                let mx = points.reduce(0) { $0 + $1.0 } / n, my = points.reduce(0) { $0 + $1.1 } / n
                let slope = points.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / points.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
                print(String(format: "  probe %@, deflection x%.1f: stiffness %+.2f%% vs Timoshenko, axial grip force %.0f N/m",
                             resolution, scale, 100 * (slope / stiffness - 1), sim.gripReaction(0).x))
            }
        }
        return
    }

    // 1. Elastic stiffness from the force at the prescribed deflection.
    var slopes: [Double] = []
    for (resolution, scale) in [("x4", 0.1), ("x6", 0.1), ("x4", 1.0)] {
        let scene = try bendScene(resolution, fracture: false, speed: scale * speed, duration: 0.07)
        require(scene.issues().isEmpty, scene.issues().joined(separator: "; "))
        var sim = try AssemblySimulation(scene)
        require(sim.initialIssue == nil, sim.initialIssue ?? "")
        let started = Date()
        var points: [(Double, Double)] = []
        while sim.time < scene.duration - 1e-15 {
            require(sim.step(), "elastic \(resolution): \(sim.failure ?? "step rejected") at \(sim.time)")
            if sim.time > 0.02 { points.append((-sim.gripDisplacement(0).y, -sim.gripReaction(0).y)) }
        }
        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.0 } / n, my = points.reduce(0) { $0 + $1.1 } / n
        let slope = points.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / points.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
        let atEnd = points.last!.1 / points.last!.0
        slopes.append(slope)
        print(String(format: "  Elastic %@, %@ deflection: fitted stiffness %.4g N/m per m (%+.2f%% vs Timoshenko), force over deflection at the end %+.2f%%; clamp force %.0f vs grip force %.0f N/m at the end; %.0f s",
                     resolution, scale < 1 ? "a tenth of the crack" : "the full crack", slope, 100 * (slope / stiffness - 1), 100 * (atEnd / stiffness - 1),
                     sim.supportReaction(0).y, -sim.gripReaction(0).y, Date().timeIntervalSince(started)))
        if resolution == "x4" && scale < 1 {
            require(abs(slope / stiffness - 1) <= 0.03, "x4: linear bending stiffness more than 3% from Timoshenko beam theory")
        }
    }
    require(abs(slopes[1] / stiffness - 1) < abs(slopes[0] / stiffness - 1), "x6 is not closer to beam theory than x4")

    // 2 and 3. First crack. `quick` (used by CI) runs x4 only: the x6 cracking run takes about 20 minutes here.
    let quick = CommandLine.arguments.contains("quick")
    var loads: [Double] = []
    for resolution in quick ? ["x4"] : ["x4", "x6"] {
        let scene = try bendScene(resolution, fracture: true, speed: speed, duration: 0.14)
        var sim = try AssemblySimulation(scene)
        require(sim.initialIssue == nil, sim.initialIssue ?? "")
        let started = Date()
        var steps = 0
        var first: (time: Double, load: Double, deflection: Double, at: Point)?
        while sim.time < scene.duration - 1e-15 && first == nil {
            require(sim.step(), "cracking \(resolution): \(sim.failure ?? "step rejected") at \(sim.time)")
            steps += 1
            if (sim.fractureReading(0)?.insertedEdges ?? 0) > 0 {
                let mesh = sim.body(0).mesh
                let at = sim.crackFaces(0).first.map { (mesh.reference[$0.first.a] + mesh.reference[$0.first.b]) / 2 } ?? .zero
                first = (sim.time, -sim.gripReaction(0).y, -sim.gripDisplacement(0).y, at)
            }
            if steps.isMultiple(of: 100_000) {
                print(String(format: "    (%@: %.1f ms, grip force %.0f N/m, %.0f s)", resolution, 1000 * sim.time,
                             -sim.gripReaction(0).y, Date().timeIntervalSince(started)))
            }
        }
        let crack = try unwrap(first, "\(resolution): no crack by \(scene.duration) s")
        loads.append(crack.load)
        let nearClamp = crack.at.x <= -span / 2 + 0.1 * span, nearGrip = crack.at.x >= span / 2 - 0.1 * span
        print(String(format: "  Cracking %@: first crack at %.1f ms, grip force %.0f N/m (%+.1f%% vs %.0f), deflection %.3f mm; at x %+.1f mm, y %+.1f mm (%@); dt %.3g µs, %d steps, %.0f s",
                     resolution, 1000 * crack.time, crack.load, 100 * (crack.load / crackLoad - 1), crackLoad,
                     1000 * crack.deflection, 1000 * crack.at.x, 1000 * crack.at.y,
                     nearClamp ? "clamp end" : nearGrip ? "grip end" : "not at an end", 1e6 * sim.dt, steps,
                     Date().timeIntervalSince(started)))
        require((nearClamp && crack.at.y > 0) || (nearGrip && crack.at.y < 0),
                "\(resolution): first crack is not at an end on its tension face")
        if resolution == "x4" {
            require(abs(crack.load / crackLoad - 1) <= 0.20, "x4: first-crack load more than 20% from beam theory")
        }
    }
    if loads.count == 2 {
        print(String(format: "  x6 against x4: linear stiffness %+.2f%%, first-crack load %+.1f%%", 100 * (slopes[1] / slopes[0] - 1),
                     100 * (loads[1] / loads[0] - 1)))
    }
    print("Displacement-driven bend check passed.")
}
