import Foundation
import ImpactPhysics
import simd

// Layered target plan, step 8: fracture on a clamped body. A glass cantilever, clamped along its left edge, is struck
// near its free end; the bending tension at the clamp cracks it. When a crack splits a held node, both copies must stay
// held (Physics.swift, splitNodes).
//
// NUMERICAL VERIFICATION of the bookkeeping, not physical validation. Criteria fixed before the first run (2026-11-25):
//  1. The run reaches its end with energy error under 2% (the fracture guard's limit), and at least one crack opens.
//  2. At every step, every node whose reference position is on the clamped edge, including nodes made by a split,
//     is exactly at its reference position with zero velocity.
//  3. Control: the same scene with a crack strength too high to ever crack ends at exactly the same node positions
//     as the scene with fracture off (fracture on with no crack behaves like fracture off).
// Amended after the first run (2026-11-25): that run compared the two at different time steps (fracture on uses a
// smaller, conservative step and twice the contact stiffness, see FractureGuard.swift), so they differed by 41 µm.
// The control now matches the step and contact stiffness exactly as the fracture guard's control does, and uses a
// 5 m/s strike with a 200 MPa crack strength so it never cracks and runs in reasonable time. Still exact equality.
private func cantilever(strength: Double?, speed: Double = 20) throws -> AssemblyScene {
    let fracture = strength.map { #", "fracture": { "strength": \#($0), "energy": 7.4 }"# } ?? ""
    let text = #"""
    { "duration": 0.0003, "meshResolution": "fine",
      "parts": [
        { "name": "Glass cantilever", "size": [0.1, 0.012], "center": [0, 0], "support": "clampLeft",
          "material": { "young": 7.2e10, "density": 2500, "poisson": 0.23 }\#(fracture) },
        { "name": "Steel ball", "shape": "round", "size": [0.012, 0.012], "center": [0.035, 0.0125], "velocity": [0, -\#(speed)],
          "material": { "profile": "structural-steel-a36", "elasticOnly": true } } ] }
    """#
    return try AssemblyScene.document(Data(text.utf8))
}

func clampedFractureCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Fracture on a clamped body (plan step 8). Numerical verification, not physical validation.")
    func run(_ scene: AssemblyScene, watchClamp: Bool, matching: AssemblySimulation? = nil) throws -> (sim: AssemblySimulation, worst: Double, worstHeld: Double, held: (Int, Int)) {
        var sim = try matching.map { try AssemblySimulation(scene, refinement: scene.resolution.rawValue, stepLimit: $0.dt, interbodyStiffnessScale: 2) }
            ?? AssemblySimulation(scene)
        require(sim.initialIssue == nil, sim.initialIssue ?? "")
        let edge = -scene.parts[0].size.x / 2, tolerance = 1e-9 * scene.parts[0].size.x
        func heldNodes() -> [Int] { sim.body(0).mesh.reference.indices.filter { sim.body(0).mesh.reference[$0].x <= edge + tolerance } }
        let before = heldNodes().count
        let initial = sim.initialEnergy
        var worst = 0.0, worstHeld = 0.0
        while sim.time < scene.duration - 1e-15 {
            require(sim.step(), "\(scene.parts[0].name): \(sim.failure ?? "step rejected") at \(sim.time)")
            worst = max(worst, abs(sim.energies.total - initial) / initial)
            if watchClamp {
                let body = sim.body(0)
                for i in heldNodes() {
                    worstHeld = max(worstHeld, simd_length(body.position[i] - body.mesh.reference[i] - scene.parts[0].center),
                                    simd_length(body.velocity[i]))
                }
            }
        }
        print(String(format: "    (%@: %d steps, dt %.3g µs)", scene.parts[0].fracture == nil ? "fracture off" : "fracture on", Int((scene.duration / sim.dt).rounded()), 1e6 * sim.dt))
        return (sim, worst, worstHeld, (before, heldNodes().count))
    }
    let cracked = try run(cantilever(strength: 4.1e7), watchClamp: true)
    let reading = cracked.sim.fractureReading(0)!
    let atClamp = cracked.sim.crackFaces(0).filter { face in
        let mesh = cracked.sim.body(0).mesh
        return min(mesh.reference[face.first.a].x, mesh.reference[face.first.b].x) <= -0.05 + 1e-9
    }.count
    print(String(format: "  Cracking cantilever (41 MPa, 7.4 J/m²): %d crack faces (%d touching the clamped edge), %d failed, %d pieces; energy error %.4f%%; held nodes %d at the start, %d at the end; largest held-node movement or speed %.3g",
                 reading.insertedEdges, atClamp, reading.failedEdges, reading.pieces, 100 * cracked.worst,
                 cracked.held.0, cracked.held.1, cracked.worstHeld))
    require(reading.insertedEdges > 0, "The clamped cantilever did not crack")
    require(cracked.worst < 0.02, "Energy error above 2% on the clamped cracking cantilever")
    require(cracked.worstHeld == 0, "A held node moved after crack insertion")

    let strong = try run(cantilever(strength: 2e8, speed: 5), watchClamp: false)
    let off = try run(cantilever(strength: nil, speed: 5), watchClamp: false, matching: strong.sim)
    require(off.sim.dt == strong.sim.dt, "Control time steps differ")
    let a = off.sim.body(0).position, b = strong.sim.body(0).position
    require(a.count == b.count && strong.sim.fractureReading(0)!.insertedEdges == 0, "The control cracked or changed its mesh")
    let difference = zip(a, b).map { simd_length($0 - $1) }.max() ?? 0
    print(String(format: "  Control at 5 m/s, same time step and contact stiffness: fracture on but too strong to crack vs fracture off: largest node difference %.3g m", difference))
    require(difference == 0, "Fracture on without a crack does not match fracture off on a clamped body")
    print("Clamped fracture check passed.")
}

// Layered target plan, step 8 design (docs/step8-design.md, Part 1): a body resting on fixed supports can already
// crack, but no recorded run had shown it. The three-point-bend lab example is run with fracture on.
// Criteria fixed before the first run (2026-11-25): with crack strength 1e4 Pa (energy 1 J/m²) the bar cracks, and its
// first crack faces lie in the middle third of the 260 mm span. At the default strength (3% of E, 0.3 MPa) it does not
// crack, which confirms that strength, not a block, explains the earlier zero-crack runs.
func restingFractureCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Fracture on a body resting on fixed rollers (plan step 8). Numerical verification, not physical validation.")
    let base = try AssemblyScene.open(URL(fileURLWithPath: "docs/lab-examples/three-point-bend.json"))
    for strength in [1e4, nil] as [Double?] {
        var scene = base
        var settings = MaterialFractureSettings()
        if let strength { settings.strength = strength; settings.energy = 1 }
        scene.parts[0].fracture = settings
        var sim = try AssemblySimulation(scene)
        require(sim.initialIssue == nil, sim.initialIssue ?? "")
        var first: (time: Double, faces: [(x: Double, y: Double)])?
        while sim.time < scene.duration - 1e-15 {
            require(sim.step(), "three-point bend: \(sim.failure ?? "step rejected") at \(sim.time)")
            if first == nil, (sim.fractureReading(0)?.insertedEdges ?? 0) > 0 {
                let mesh = sim.body(0).mesh
                first = (sim.time, sim.crackFaces(0).map { face in
                    let m = (mesh.reference[face.first.a] + mesh.reference[face.first.b]) / 2
                    return (m.x, m.y)
                })
            }
        }
        let reading = sim.fractureReading(0)!
        let label = strength.map { String(format: "strength %.0e Pa", $0) } ?? "default strength (3% of E)"
        if let first {
            let xs = first.faces.map(\.x), ys = first.faces.map(\.y)
            print(String(format: "  %@: first crack at %.2f ms, x from %.1f to %.1f mm, y from %.1f to %.1f mm (bar is ±12.5 mm); at the end %d crack faces, %d failed, %d pieces; the run's own energy guard (which counts gravity) accepted every step",
                         label, 1e3 * first.time, 1e3 * xs.min()!, 1e3 * xs.max()!, 1e3 * ys.min()!, 1e3 * ys.max()!,
                         reading.insertedEdges, reading.failedEdges, reading.pieces))
            require(strength != nil, "The bar cracked at the default strength")
            require(xs.allSatisfy { abs($0) <= 0.26 / 6 + 1e-9 }, "First crack outside the middle third of the span")
        } else {
            print(String(format: "  %@: no crack in %.0f ms", label, 1e3 * scene.duration))
            require(strength == nil, "The bar did not crack at 1e4 Pa")
        }
    }
    print("Resting fracture check passed.")
}
