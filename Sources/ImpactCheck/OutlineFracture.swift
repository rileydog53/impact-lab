import Foundation
import ImpactPhysics
import simd

// Fracture on drawn (outline) bodies: the milestone's "one checked case" before the editor allows it
// (docs/GENERAL_GEOMETRY.md said fracture stays off on outline bodies until crack paths on generated meshes are verified).
// Outline bodies are meshed by the quality Delaunay mesher, so cracks have to run along unstructured element edges.
//
// NUMERICAL VERIFICATION, not physical validation. Criteria fixed before the first run (2026-11-25):
//  A. Crack load on a generated mesh. The fixed-guided bend rig of `--bend-rig`, but the beam is an outline rectangle
//     (160 × 20 mm, mesh size 20/8 mm, the 8 elements through the depth the bending advisory asks for). First crack at an end on that end's tension face, grip force
//     at first crack within 20% of σ h² / (3 L) = 3750 N/m, every step accepted (the same criteria as the block on x4).
//  B. No crack, no change. An outline plate with a hole struck by a ball, fracture on but strength too high to crack,
//     against fracture off at the same time step and contact stiffness: identical node positions at the end.
//  C. Cracking impact. The same plate with a breakable strength: cracks open, the run reaches its end with energy error
//     under 2% (the fracture guard's limit), and every crack face joins two nodes that started at the same place
//     (cracks open only along element edges, never through an element).
// Changed before any result of A existed (2026-11-25): A first used mesh size 20/12 mm and loading over 70 ms; the
// generated mesh at that size needs a step of about 0.011 µs, and the run was stopped by its 45-minute limit at 37.5 ms,
// before any crack. A now uses 20/8 mm and loads over 40 ms (about 8 periods of the beam's first mode after a 10 ms ramp).

private let span = 0.16, depth = 0.02, strength = 4.5e6

private func outlineBeam(speed: Double) throws -> AssemblyScene {
    let h = depth / 8
    let text = #"""
    { "duration": 0.08,
      "parts": [
        { "name": "Outline beam", "shape": "outline", "center": [0, 0], "support": "clampLeft",
          "outline": { "outer": [[-0.08, -0.01], [0.08, -0.01], [0.08, 0.01], [-0.08, 0.01]], "meshSize": \#(h) },
          "material": { "young": 1e9, "density": 1000, "poisson": 0.2 },
          "fracture": { "strength": \#(strength), "energy": 100 },
          "grip": { "edge": "right", "velocity": [0, -\#(speed)], "ramp": 0.01 } } ] }
    """#
    return try AssemblyScene.document(Data(text.utf8))
}

private func plateWithHole(strength: Double?, duration: Double = 0.0004) throws -> AssemblyScene {
    let fracture = strength.map { #", "fracture": { "strength": \#($0), "energy": 7.4 }"# } ?? ""
    let text = #"""
    { "duration": \#(duration),
      "parts": [
        { "name": "Plate with a hole", "shape": "outline", "center": [0, 0], "support": "clampBottom",
          "outline": { "outer": [[-0.05, -0.02], [0.05, -0.02], [0.05, 0.02], [-0.05, 0.02]],
                       "holes": [[[-0.008, -0.006], [0.008, -0.006], [0.008, 0.006], [-0.008, 0.006]]], "meshSize": 0.003 },
          "material": { "young": 7.2e10, "density": 2500, "poisson": 0.23 }\#(fracture) },
        { "name": "Steel ball", "shape": "round", "size": [0.012, 0.012], "center": [0, 0.0262], "velocity": [0, -20],
          "material": { "profile": "structural-steel-a36", "elasticOnly": true } } ] }
    """#
    return try AssemblyScene.document(Data(text.utf8))
}

func outlineFractureCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Fracture on outline (drawn) bodies, generated meshes. Numerical verification, not physical validation.")

    let bendOnly = CommandLine.arguments.contains("bend")
    // B first: it is quick and says whether the crack machinery leaves an uncracked generated mesh alone.
    func run(_ scene: AssemblyScene, matching: AssemblySimulation? = nil) throws -> (AssemblySimulation, Double) {
        var sim = try matching.map { try AssemblySimulation(scene, refinement: scene.resolution.rawValue, stepLimit: $0.dt, interbodyStiffnessScale: 2) }
            ?? AssemblySimulation(scene)
        require(sim.initialIssue == nil, sim.initialIssue ?? "")
        var worst = 0.0
        let began = Date()
        defer { print(String(format: "    (%@: %.0f s, step %.3g s)", scene.parts[0].fracture == nil ? "fracture off" : "fracture on", Date().timeIntervalSince(began), sim.dt)) }
        while sim.time < scene.duration - 1e-15 {
            require(sim.step(), "\(scene.parts[0].name): \(sim.failure ?? "step rejected") at \(sim.time)")
            worst = max(worst, abs(sim.energies.total - sim.initialEnergy) / sim.initialEnergy)
        }
        return (sim, worst)
    }
    // A crack strength this high forces a step of about 0.17 ns (2.3 million steps, about 7 minutes per run on the M4),
    // so `quick` runs B over the first 100 µs only: the ball touches the plate at about 10 µs, so contact is still included.
    let quick = CommandLine.arguments.contains("quick")
    let durationB = quick ? 0.0001 : 0.0004
    if !bendOnly {
    let strong = try run(plateWithHole(strength: 2e9, duration: durationB))
    let off = try run(plateWithHole(strength: nil, duration: durationB), matching: strong.0)
    require(strong.0.fractureReading(0)!.insertedEdges == 0, "B: the strong plate cracked")
    let a = strong.0.body(0).position, b = off.0.body(0).position
    require(a.count == b.count, "B: node counts differ")
    let difference = zip(a, b).map { simd_length($0 - $1) }.max() ?? 0
    print(String(format: "  B. Plate with a hole, %d elements, %.0f µs: fracture on but too strong to crack vs fracture off, same step and contact stiffness: largest node difference %.3g m",
                 strong.0.body(0).mesh.elements.count, 1e6 * durationB, difference))
    require(difference == 0, "B: fracture on without a crack does not match fracture off on a generated mesh")

    // C. Cracking impact.
    let cracked = try run(plateWithHole(strength: 4.1e7))
    let reading = cracked.0.fractureReading(0)!
    let mesh = cracked.0.body(0).mesh
    let faces = cracked.0.crackFaces(0)
    let paired = faces.allSatisfy { face in
        simd_length(mesh.reference[face.first.a] - mesh.reference[face.second.b]) < 1e-12
            || simd_length(mesh.reference[face.first.a] - mesh.reference[face.second.a]) < 1e-12
    }
    print(String(format: "  C. Same plate at 41 MPa: %d crack faces, %d failed, %d pieces; energy error %.4f%%; every face joins nodes that started together: %@",
                 faces.count, reading.failedEdges, cracked.0.materialPieces(0).count, 100 * cracked.1, paired ? "yes" : "no"))
    require(reading.insertedEdges > 0, "C: no crack")
    require(cracked.1 < 0.02, "C: energy error at or above 2%")
    require(paired, "C: a crack face does not join nodes from the same starting point")
    }

    // `quick` (for CI) stops here: case A takes about 13 minutes on the M4.
    if quick {
        print("Outline fracture check passed (quick: cases B and C).")
        return
    }

    // A. Crack load on the bend rig.
    let planeStrain = 1e9 / (1 - 0.04), shear = 1e9 / 2.4, inertia = depth * depth * depth / 12
    let compliance = span * span * span / (12 * planeStrain * inertia) + span / (5.0 / 6 * shear * depth)
    let crackLoad = strength * depth * depth / (3 * span)
    let scene = try outlineBeam(speed: crackLoad * compliance / 0.045)
    require(scene.issues().isEmpty, scene.issues().joined(separator: "; "))
    var sim = try AssemblySimulation(scene)
    require(sim.initialIssue == nil, sim.initialIssue ?? "")
    let started = Date()
    var first: (time: Double, load: Double, at: Point)?
    var steps = 0
    while sim.time < scene.duration - 1e-15 && first == nil {
        require(sim.step(), "A: \(sim.failure ?? "step rejected") at \(sim.time)")
        steps += 1
        if (sim.fractureReading(0)?.insertedEdges ?? 0) > 0 {
            let mesh = sim.body(0).mesh
            let at = sim.crackFaces(0).first.map { (mesh.reference[$0.first.a] + mesh.reference[$0.first.b]) / 2 } ?? .zero
            first = (sim.time, -sim.gripReaction(0).y, at)
        }
        if steps.isMultiple(of: 400_000) {
            print(String(format: "    (A: %.1f ms, grip force %.0f N/m, %.0f s)", 1000 * sim.time, -sim.gripReaction(0).y, Date().timeIntervalSince(started)))
        }
    }
    let crack = try unwrap(first, "A: no crack by \(scene.duration) s")
    let nearClamp = crack.at.x <= -span / 2 + 0.1 * span, nearGrip = crack.at.x >= span / 2 - 0.1 * span
    print(String(format: "  A. Outline bend rig, %d elements: first crack at %.1f ms, grip force %.0f N/m (%+.1f%% vs %.0f); at x %+.1f mm, y %+.1f mm (%@); %d steps, %.0f s",
                 sim.body(0).mesh.elements.count, 1000 * crack.time, crack.load, 100 * (crack.load / crackLoad - 1), crackLoad,
                 1000 * crack.at.x, 1000 * crack.at.y, nearClamp ? "clamp end" : nearGrip ? "grip end" : "not at an end",
                 steps, Date().timeIntervalSince(started)))
    require((nearClamp && crack.at.y > 0) || (nearGrip && crack.at.y < 0), "A: first crack is not at an end on its tension face")
    require(abs(crack.load / crackLoad - 1) <= 0.20, "A: first-crack load more than 20% from beam theory")
    print("Outline fracture check passed.")
}
