import Foundation
import ImpactPhysics
import simd

// Checks for the workshop improvements: mesh-following body minimums, fracture status tags, the advisory
// bending note, the documented limits and the spring length readout. NUMERICAL VERIFICATION of the
// implementation only. Physics is untouched: the legacy replay and every earlier gate still apply separately.

private func tryBuild(_ scene: AssemblyScene) -> (simulation: AssemblySimulation?, message: String?) {
    do { return (try AssemblySimulation(scene), nil) } catch { return (nil, error.localizedDescription) }
}

private func runSteps(_ scene: AssemblyScene, count: Int) -> Bool {
    guard var simulation = tryBuild(scene).simulation else { return false }
    for _ in 0..<count where simulation.time < scene.duration {
        guard simulation.step(), simulation.energies.total.isFinite else { return false }
    }
    return true
}

func workshopImprovementsCheck() throws {
    print("Workshop improvements (numerical verification of the editor rules, not physical validation)")
    func scene(size: Double, mesh: AssemblyScene.Resolution?, refinement: AssemblyScene.Resolution? = nil) -> AssemblyScene {
        var s = AssemblyScene()
        var a = AssemblyPart("Small", center: Point(0, 0), size: Point(size, size))
        a.refinement = refinement
        var b = AssemblyPart("Striker", center: Point(0.05, 0), size: Point(0.03, 0.03))
        b.velocity = Point(-5, 0)
        s.parts = [a, b]
        s.meshResolution = mesh
        s.duration = 0.002
        return s
    }

    // Policy approved by Joseph 2026-11-24 (Google Doc section 28, decision 2): the 25–300 mm range and the
    // 8-body cap became advice. These checks used to require rejection; they now require that the same scenes
    // are accepted, run with finite energy, and carry an advisory note that names the cause. Only input bounds
    // (0.5 mm to 10 m, 64 bodies) and the enclosure's own 12.5 mm geometry rule still refuse.

    // 1. The advisory threshold follows the mesh and never exceeds the old fixed 25 mm.
    for r in AssemblyScene.Resolution.allCases {
        let minimum = AssemblyPart.minimumSize(resolution: r)
        require(abs(minimum - 0.025 / Double(r.rawValue)) < 1e-15 && minimum <= 0.025, "advisory threshold for \(r)")
    }
    require(AssemblyPart.minimumSize(resolution: .standard) == 0.025, "standard advisory threshold stays 25 mm")
    func smallNote(_ s: AssemblyScene) -> String? { s.advisories(for: s.parts[0]).first { $0.contains("smaller than three elements") } }
    require(tryBuild(scene(size: 0.025, mesh: nil)).simulation != nil && smallNote(scene(size: 0.025, mesh: nil)) == nil,
            "25 mm body on the standard mesh: accepted, no size note")
    let small = scene(size: 0.024, mesh: nil)
    require(small.issues().isEmpty && runSteps(small, count: 4000), "24 mm body on the standard mesh is accepted and runs")
    require(smallNote(small) != nil, "24 mm body carries an advisory note")
    print("  standard mesh: 24 mm accepted with advice: \"\(smallNote(small) ?? "")\"")

    // 2. A finer mesh gives smaller bodies full resolution; below it they still run, with the note.
    for (size, mesh) in [(0.0125, AssemblyScene.Resolution.fine), (0.007, .x4)] {
        let s = scene(size: size, mesh: mesh)
        require(s.issues().isEmpty && smallNote(s) == nil, "\(size) on \(mesh): accepted without note: \(s.issues())")
        require(runSteps(s, count: 4000), "\(size * 1000) mm body on \(mesh.label) runs with finite energy")
        print("  \(String(format: "%.1f", size * 1000)) mm body on \(mesh.label): accepted and runs")
    }
    for (size, mesh) in [(0.012, AssemblyScene.Resolution.fine), (0.003, .standard), (0.0005, .standard)] {
        let s = scene(size: size, mesh: mesh)
        require(s.issues().isEmpty && smallNote(s) != nil && runSteps(s, count: 2000),
                "\(size * 1000) mm on \(mesh.label): accepted, advised, runs")
    }
    let belowInput = scene(size: 0.0004, mesh: nil)
    require(tryBuild(belowInput).simulation == nil && !belowInput.issues().isEmpty, "below the 0.5 mm input bound: refused and explained")
    print("  12 mm (fine), 3 mm and 0.5 mm (standard) accepted with advice and run; 0.4 mm refused as an input bound")

    // 3. A per-body mesh override removes the note; coarsening brings it back but does not block.
    require(smallNote(scene(size: 0.007, mesh: nil, refinement: .x4)) == nil, "body with its own ×4 mesh: no note at 7 mm")
    var coarsened = scene(size: 0.007, mesh: .x4)
    coarsened.meshResolution = nil
    require(tryBuild(coarsened).simulation != nil && smallNote(coarsened) != nil, "coarsening to the standard mesh: accepted with note")

    // 3b. Regression for the crash found in --scene-documents: an enclosure smaller than a 5 mm wall allows
    // used to build an invalid wall range (`0.005...0.4×side`) and trap. It must be rejected cleanly instead.
    for mesh in AssemblyScene.Resolution.allCases {
        for side in [0.004, 0.0083, 0.0124, 0.0126] {
            var s = AssemblyScene()
            var box = AssemblyPart("Box", shape: .enclosure, size: Point(side, side))
            box.wall = 0.005
            s.parts = [box, AssemblyPart("Other", center: Point(0.1, 0), size: Point(0.03, 0.03))]
            s.meshResolution = mesh
            let rejected = tryBuild(s).simulation == nil
            require(rejected == (side < AssemblyPart.minimumEnclosureSide), "enclosure \(side) on \(mesh) handled")
            require(rejected == !s.issues().isEmpty, "enclosure \(side) on \(mesh) explained exactly when rejected")
        }
    }
    print("  enclosures below 12.5 mm (5 mm wall at most 40% of the side) are rejected cleanly on every mesh (regression: wall-range trap)")

    // 4. Large bodies and more than 8 bodies are accepted with advice; the remaining bounds are documented.
    var big = scene(size: 0.31, mesh: nil)
    big.parts[1].center = Point(0.3, 0)
    require(tryBuild(big).simulation != nil && big.advisories(for: big.parts[0]).contains { $0.contains("300 mm") },
            "310 mm accepted with an advisory note")
    big.parts[0].size = Point(10.5, 0.1)
    require(tryBuild(big).simulation == nil && !big.issues().isEmpty, "above the 10 m input bound: refused and explained")
    var many = AssemblyScene()
    for i in 0..<9 { many.parts.append(AssemblyPart("B\(i)", center: Point(Double(i) * 0.05, 0), size: Point(0.03, 0.03))) }
    require(tryBuild(many).simulation != nil && !many.sceneAdvisories.isEmpty, "9 bodies accepted with an advisory note")
    require(AssemblyScene.maximumParts == 64 && AssemblyScene.advisoryParts == 8, "64-body input bound, advice above 8")
    var tooMany = AssemblyScene()
    for i in 0..<65 { tooMany.parts.append(AssemblyPart("B\(i)", center: Point(Double(i % 13) * 0.05, Double(i / 13) * 0.05), size: Point(0.03, 0.03))) }
    require(tryBuild(tooMany).simulation == nil && !tooMany.issues().isEmpty, "65 bodies refused and explained")
    let kinds = Set(AssemblyScene.limits.map(\.kind))
    require(kinds == [.numerical, .implementation], "limits are classified: \(kinds)")
    for limit in AssemblyScene.limits { require(!limit.cause.isEmpty, "\(limit.name) has a cause") }
    print("  310 mm and 9 bodies accepted with advice; 10 m, 64 bodies and 12 connections documented: \(AssemblyScene.limits.map(\.name).joined(separator: ", "))")

    // 5. Fracture status tags and reasons.
    var block = AssemblyPart("Block", size: Point(0.06, 0.05))
    require(block.fractureStatus == .off && block.fractureStatus.tag == "fracture off", "plain block: off")
    block.fracture = MaterialFractureSettings()
    require(block.fractureStatus == .on && block.fractureStatus.tag == "fracture on", "fracture enabled: on")
    var round = AssemblyPart("Round", shape: .round, size: Point(0.05, 0.05))
    // Bonded-layer blocks can crack and delaminate since the layered target plan, step 3
    // (approved by Joseph 2026-11-24), so they report off/on like a plain block.
    var bonded = AssemblyPart("Bonded", size: Point(0.06, 0.05))
    bonded.bondedLayer = AssemblyPart.BondedLayer()
    require(bonded.fractureStatus == .off, "bonded block without fracture: off")
    bonded.fracture = MaterialFractureSettings()
    require(bonded.fractureStatus == .on, "bonded block with fracture: on")
    var clamped = AssemblyPart("Clamped", size: Point(0.1, 0.03))
    clamped.support = .clampLeft
    var fixed = AssemblyPart("Fixed", size: Point(0.2, 0.03))
    fixed.support = .fixed
    for part in [round, clamped, fixed] {
        guard case let .unavailable(reason) = part.fractureStatus else { require(false, "\(part.name) should be n/a"); continue }
        require(part.fractureStatus.tag == "fracture n/a" && reason.count > 40, "\(part.name) explains why: \(reason)")
        print("  \(part.name): \(part.fractureStatus.tag) — \(reason)")
    }
    round.fracture = nil

    // 6. The bending note is advisory, depends on geometry and loading, and never blocks.
    var beam = AssemblyScene()
    var cantilever = AssemblyPart("Cantilever", size: Point(0.15, 0.025))
    cantilever.support = .clampLeft
    beam.parts = [cantilever]
    beam.duration = 0.001
    require(beam.bendingAdvisory(for: beam.parts[0]) != nil, "slender clamped beam at the standard mesh gets the note")
    require(tryBuild(beam).simulation != nil && beam.issues().isEmpty, "the note does not block the scene")
    beam.meshResolution = .x4
    require(beam.bendingAdvisory(for: beam.parts[0]) == nil, "≥8 elements across: no note")
    var stubby = AssemblyScene()
    stubby.parts = [AssemblyPart("Stubby", size: Point(0.06, 0.05)), AssemblyPart("Other", center: Point(0.1, 0), size: Point(0.06, 0.05))]
    require(stubby.bendingAdvisory(for: stubby.parts[0]) == nil, "a stubby block is not a bending case")
    var alone = AssemblyScene()
    alone.parts = [AssemblyPart("Lone bar", size: Point(0.15, 0.025))]
    require(alone.bendingAdvisory(for: alone.parts[0]) == nil, "a lone unloaded bar gets no note")
    alone.gravity = AssemblyScene.standardGravity
    require(alone.bendingAdvisory(for: alone.parts[0]) != nil, "gravity makes it a bending case")
    print("  bending advisory: clamped 150×25 mm beam at the standard mesh → note; at ×4 → none; stubby or unloaded → none; never blocks")

    // 7. Spring lengths: rest = start − preload, with and without preload.
    for preload in [0.0, 0.004, -0.003] {
        var s = AssemblyScene()
        let a = AssemblyPart("Left", center: Point(-0.06, 0), size: Point(0.06, 0.05))
        let b = AssemblyPart("Right", center: Point(0.06, 0), size: Point(0.06, 0.05))
        s.parts = [a, b]
        var link = AssemblyConnection(first: a.id, second: b.id)
        link.firstAnchor = Point(1, 0)
        link.secondAnchor = Point(-1, 0)
        link.preload = preload == 0 ? nil : preload
        s.connections = [link]
        let simulation = try AssemblySimulation(s)
        guard let lengths = simulation.linkLengths(0) else { require(false, "lengths available"); return }
        require(abs(lengths.start - 0.06) < 1e-9, "start length is the anchor distance: \(lengths.start)")
        require(abs((lengths.start - lengths.rest) - preload) < 1e-12, "start − rest = preload (\(preload))")
        print(String(format: "  spring preload %+.1f mm: start %.1f mm, rest %.1f mm", preload * 1000, lengths.start * 1000, lengths.rest * 1000))
    }
    require(AssemblySimulationBlank.linkLengthsOutOfRange(), "unknown connection index has no lengths")
    print("Workshop improvement checks passed.")
}

private enum AssemblySimulationBlank {
    static func linkLengthsOutOfRange() -> Bool {
        var s = AssemblyScene()
        s.parts = [AssemblyPart("A", size: Point(0.05, 0.05))]
        return (try? AssemblySimulation(s))?.linkLengths(3) == nil
    }
}
