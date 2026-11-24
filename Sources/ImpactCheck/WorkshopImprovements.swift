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

    // 1. The minimum follows the mesh and never exceeds the old fixed 25 mm.
    for r in AssemblyScene.Resolution.allCases {
        let minimum = AssemblyPart.minimumSize(resolution: r)
        require(abs(minimum - 0.025 / Double(r.rawValue)) < 1e-15 && minimum <= 0.025, "minimum for \(r)")
    }
    require(AssemblyPart.minimumSize(resolution: .standard) == 0.025, "standard minimum stays 25 mm")
    require(tryBuild(scene(size: 0.025, mesh: nil)).simulation != nil, "25 mm body on the standard mesh")
    let tooSmall = tryBuild(scene(size: 0.024, mesh: nil))
    require(tooSmall.simulation == nil && (tooSmall.message ?? "").contains("smaller than 25 mm"),
            "24 mm body on the standard mesh is rejected with a specific message: \(tooSmall.message ?? "none")")
    print("  standard mesh: 25 mm accepted, 24 mm rejected: \"\(tooSmall.message ?? "")\"")

    // 2. A finer mesh accepts smaller bodies, and they calculate.
    for (size, mesh) in [(0.0125, AssemblyScene.Resolution.fine), (0.007, .x4)] {
        let s = scene(size: size, mesh: mesh)
        require(s.issues().isEmpty, "issues for \(size) on \(mesh): \(s.issues())")
        require(runSteps(s, count: 4000), "\(size * 1000) mm body on \(mesh.label) runs with finite energy")
        print("  \(String(format: "%.1f", size * 1000)) mm body on \(mesh.label): accepted and runs")
    }
    let belowFine = tryBuild(scene(size: 0.012, mesh: .fine))
    require(belowFine.simulation == nil, "12 mm is below the 12.5 mm minimum of the fine mesh")
    require(!scene(size: 0.012, mesh: .fine).issues().isEmpty, "the scene document check explains the same rule")
    print("  fine mesh: 12 mm rejected (\(scene(size: 0.012, mesh: .fine).issues().first ?? ""))")

    // 3. A per-body mesh override sets that body's minimum; coarsening cannot hide a too-small body.
    require(tryBuild(scene(size: 0.007, mesh: nil, refinement: .x4)).simulation != nil, "body with its own ×4 mesh accepts 7 mm")
    var coarsened = scene(size: 0.007, mesh: .x4)
    coarsened.meshResolution = nil
    let back = tryBuild(coarsened)
    require(back.simulation == nil && (back.message ?? "").contains("smaller than"), "coarsening to the standard mesh is refused with a cause")

    // 4. Arbitrary and implementation limits are unchanged and documented with their cause.
    var big = scene(size: 0.31, mesh: nil)
    require(tryBuild(big).simulation == nil, "300 mm maximum unchanged")
    big.parts[0].size = Point(0.30, 0.30)
    require(tryBuild(big).simulation != nil, "300 mm accepted")
    var many = AssemblyScene()
    for i in 0..<9 { many.parts.append(AssemblyPart("B\(i)", center: Point(Double(i) * 0.05, 0), size: Point(0.03, 0.03))) }
    require(tryBuild(many).simulation == nil && AssemblyScene.maximumParts == 8, "8-body cap unchanged")
    let kinds = Set(AssemblyScene.limits.map(\.kind))
    require(kinds == [.numerical, .workshop, .implementation], "limits are classified: \(kinds)")
    for limit in AssemblyScene.limits { require(!limit.cause.isEmpty, "\(limit.name) has a cause") }
    print("  limits unchanged (300 mm, 8 bodies, 12 connections) and documented: \(AssemblyScene.limits.map(\.name).joined(separator: ", "))")

    // 5. Fracture status tags and reasons.
    var block = AssemblyPart("Block", size: Point(0.06, 0.05))
    require(block.fractureStatus == .off && block.fractureStatus.tag == "fracture off", "plain block: off")
    block.fracture = MaterialFractureSettings()
    require(block.fractureStatus == .on && block.fractureStatus.tag == "fracture on", "fracture enabled: on")
    var round = AssemblyPart("Round", shape: .round, size: Point(0.05, 0.05))
    var bonded = AssemblyPart("Bonded", size: Point(0.06, 0.05))
    bonded.bondedLayer = AssemblyPart.BondedLayer()
    var clamped = AssemblyPart("Clamped", size: Point(0.1, 0.03))
    clamped.support = .clampLeft
    var fixed = AssemblyPart("Fixed", size: Point(0.2, 0.03))
    fixed.support = .fixed
    for part in [round, bonded, clamped, fixed] {
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
