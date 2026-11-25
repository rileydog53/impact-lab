import Foundation
import ImpactPhysics
import simd

// Layered target plan, step 5: spall against the 1D elastic wave picture (uniaxial strain, equal impedance).
//
// NUMERICAL VERIFICATION against a hand calculation, not physical validation. The plates are elastic on purpose
// (steel at 50 m/s would yield in reality: the Hugoniot elastic limit of the A36-like profile is about 0.44 GPa),
// and the cohesive strength is a test value set from the prediction, not a measured spall strength.
//
// Prediction (Meyers 1994, Antoun et al. 2003; worked in docs/layered-steps-4-6-design.md): impact at v drives
// σ = ρcv/2 into both plates. Each wave reflects from its free back face as a release wave.
//  - Equal plates (T = δ): the two release waves meet at the impact face at 2δ/c. A contact face cannot carry
//    tension, so the plates separate there: no crack, striker left at rest, target leaving at v.
//  - Target twice as thick (T = 2δ): the release waves meet δ from the target's back face (its middle) at 3δ/c,
//    where the stress becomes a tension of ρcv/2.
// The 1D picture holds only where no wave from the plates' top and bottom edges has arrived yet: at time t after
// contact that is |y| < H/2 − c·t (c is the fastest wave speed). Outside that zone the plate is genuinely 2D.
//
// Criteria, as first fixed before any run (2026-11-24), all with bulk viscosity on:
//  1. Equal plates, both plates able to crack at 0.5 ρcv/2: no crack anywhere up to 4δ/c; the contact opens within
//     5% of 2δ/c; afterwards the centre band of the striker moves at under 5% of v and that of the target within 5% of v.
//  2. T = 2δ, target crack strength 0.5 ρcv/2: no crack before 0.9 · 3δ/c; the first crack opens within 5% of 3δ/c,
//     within two element widths of the target's mid-plane.
//  3. Negative control, T = 2δ, crack strength 1.3 ρcv/2: no crack up to 5δ/c.
// First run (plates 8δ tall): 3 of these failed, every one because of cracks and contact 25 mm in from the top and
// bottom edges, inside the 2D edge zone, which the 1D picture does not describe (see docs/SPALL_CHECK.md). That run is
// kept below, reported against the original wording and not gated.
//
// Amended gate (written after the first run; accepted by Joseph in the project thread on 2026-11-25): the same tolerances, judged
// only inside the 1D zone, on plates 16δ tall so that zone is wide (|y| < 135 mm at 3δ/c). "Contact opens" is
// measured on the centre band of the impact face, as the last instant its faces still touch. A face exactly two
// cells from the plane counts as within two cells. Edge-zone cracks are reported, never hidden.
// Reported, not gated: cases 2 and 3 with bulk viscosity off.

private struct Face { let x, y, time: Double }

private func crackFaces(_ sim: AssemblySimulation, _ part: Int, at time: Double) -> [Face] {
    let mesh = sim.body(part).mesh
    return sim.crackFaces(part).map { face in
        let m = (mesh.reference[face.first.a] + mesh.reference[face.first.b]) / 2
        return Face(x: m.x, y: m.y, time: time)
    }
}

private struct SpallCase {
    var firstAnywhere: Face?
    var firstInZone: Face?
    var zoneFaces: [Face] = []
    var energyError = 0.0
    var reading: MaterialFractureReading?
}

/// Runs one plate impact and records, for the parts that can crack, the first crack anywhere and the first crack
/// inside the 1D zone (|y| < H/2 − c·t at the moment the face is first seen).
private func spallRun(_ scene: AssemblyScene, setup: PlateImpact, parts: [Int], until: Double,
                      observe: (AssemblySimulation, Double) -> Void = { _, _ in }) throws -> SpallCase {
    var result = SpallCase()
    var seen = Array(repeating: 0, count: parts.count)
    var sim = try AssemblySimulation(scene)
    require(sim.initialIssue == nil, sim.initialIssue ?? "")
    let initial = sim.initialEnergy
    var contact: Double?
    var steps = 0
    while contact == nil || sim.time - contact! < until {
        require(sim.step(), sim.failure ?? "spall step rejected at t = \(sim.time)")
        steps += 1
        require(steps < 200_000, "spall run exceeded 200,000 steps")
        result.energyError = max(result.energyError, abs(sim.energies.total - initial) / initial)
        if contact == nil, let first = sim.firstContactTimes[SIMD2(0, 1)] { contact = first }
        guard let contact else { continue }
        let t = sim.time - contact
        observe(sim, t)
        for (k, part) in parts.enumerated() {
            let count = sim.fractureReading(part)?.insertedEdges ?? 0
            guard count > seen[k] else { continue }
            seen[k] = count
            let zone = setup.height / 2 - setup.waveSpeed * t
            for face in crackFaces(sim, part, at: t) {
                if result.firstAnywhere == nil { result.firstAnywhere = face }
                if abs(face.y) < zone && !result.zoneFaces.contains(where: { $0.x == face.x && $0.y == face.y }) {
                    if result.firstInZone == nil { result.firstInZone = face }
                    result.zoneFaces.append(face)
                }
            }
        }
    }
    result.reading = sim.fractureReading(parts.last!)
    return result
}

private func describe(_ face: Face?) -> String {
    guard let face else { return "none" }
    return String(format: "%.3f µs at x %+.2f mm, y %+.1f mm", 1e6 * face.time, 1000 * face.x, 1000 * face.y)
}

func spallCheck() throws {
    var failures: [String] = []
    func gate(_ ok: Bool, _ message: String) { if !ok { failures.append(message); print("     GATE FAILED: \(message)") } }
    print("Spall against the 1D elastic wave picture (plan step 5). Numerical verification, not physical validation.")
    var base = PlateImpact()
    base.viscosity = .standard
    let c = base.waveSpeed, delta = base.striker, sigma = base.elasticStress
    func fracture(_ multiple: Double) -> MaterialFractureSettings {
        var settings = MaterialFractureSettings()
        settings.strength = multiple * sigma
        settings.energy = 50
        return settings
    }
    print(String(format: "  Steel profile, elastic: c = %.0f m/s, ρcv/2 = %.3f GPa at %.0f m/s, δ = %.0f mm, mesh cell %.2f mm",
                 c, sigma / 1e9, base.speed, 1000 * delta, 1000 * base.cell))

    for (height, gated) in [(8 * delta, false), (16 * delta, true)] {
        print(String(format: "  %@ — plates %.0f mm tall (%.0fδ)%@", gated ? "Gate" : "First run, as first specified", 1000 * height,
                     height / delta, gated ? ", criteria judged inside the 1D zone |y| < H/2 − c·t" : ", original whole-plate wording, reported only"))
        var setup = base
        setup.height = height

        // 1. Equal plates: no spall, separation at the impact face.
        do {
            var equal = setup
            equal.target = delta
            equal.targetFracture = fracture(0.5)
            var scene = equal.scene
            scene.parts[0].fracture = fracture(0.5)
            let predicted = 2 * delta / c
            var anyContact: Double?, bandOpen: Double?
            var striker = 0.0, target = 0.0
            let result = try spallRun(scene, setup: equal, parts: [0, 1], until: 4 * delta / c) { sim, t in
                let a = sim.body(0), b = sim.body(1)
                // Centre band of the two contact faces (reference x = +δ/2 on the striker, −δ/2 on the target).
                func face(_ body: Body, _ x: Double) -> [Int] {
                    body.mesh.reference.indices.filter { abs(body.mesh.reference[$0].x - x) < 1e-9 && abs(body.mesh.reference[$0].y) < equal.height / 16 }
                }
                let gap = zip(face(a, delta / 2).sorted { a.mesh.reference[$0].y < a.mesh.reference[$1].y },
                              face(b, -delta / 2).sorted { b.mesh.reference[$0].y < b.mesh.reference[$1].y })
                    .map { b.position[$0.1].x - a.position[$0.0].x }.min()!
                // Penalty contact lets the faces part for an instant while still loaded, so the opening time is the
                // last moment the centre band was still touching (gap ≤ 0); after it the band stays open to the end.
                if gap <= 0 { bandOpen = t }
                if anyContact == nil, t > 0.5 * predicted, !sim.activeContacts.contains(SIMD2(0, 1)) { anyContact = t }
                func band(_ body: Body) -> Double {
                    let nodes = body.mesh.reference.indices.filter { abs(body.mesh.reference[$0].y) < equal.height / 16 }
                    return nodes.reduce(0) { $0 + body.velocity[$1].x } / Double(nodes.count)
                }
                striker = band(a)
                target = band(b)
            }
            let open = gated ? bandOpen.map { $0 < 4 * delta / c - 1e-12 ? $0 : nil } ?? nil : anyContact
            let opened = try unwrap(open, "the plates never separated")
            print(String(format: "    1. Equal plates: contact opened %.3f µs after first contact %@ (predicted 2δ/c = %.3f µs, %+.2f%%); whole face clear at %@; centre band velocity striker %.2f m/s, target %.2f m/s (impact %.0f m/s); first crack anywhere %@, inside the 1D zone %@",
                         1e6 * opened, gated ? "on the centre band" : "over the whole face", 1e6 * predicted, 100 * (opened / predicted - 1),
                         anyContact.map { String(format: "%.3f µs", 1e6 * $0) } ?? "never", striker, target, setup.speed,
                         describe(result.firstAnywhere), describe(result.firstInZone)))
            if gated {
                gate(result.firstInZone == nil, "Equal plates cracked inside the 1D zone; the 1D picture predicts no spall")
                gate(abs(opened / predicted - 1) <= 0.05, "Equal plates separated more than 5% away from 2δ/c")
                gate(abs(striker) <= 0.05 * setup.speed && abs(target / setup.speed - 1) <= 0.05, "Equal plates did not swap their momentum")
            } else {
                print("       as first specified: no crack anywhere \(result.firstAnywhere == nil ? "met" : "NOT met"); separation within 5% \(abs(opened / predicted - 1) <= 0.05 ? "met" : "NOT met"); momentum swap \(abs(striker) <= 0.05 * setup.speed && abs(target / setup.speed - 1) <= 0.05 ? "met" : "NOT met")")
            }
        }

        // 2 and 3. Target twice as thick.
        let cases: [(Double, Bool)] = gated ? [(0.5, true), (1.3, true), (0.5, false), (1.3, false)] : [(0.5, true), (1.3, true)]
        for (multiple, viscosity) in cases {
            var thick = setup
            thick.target = 2 * delta
            thick.targetFracture = fracture(multiple)
            if !viscosity { thick.viscosity = nil }
            let predicted = 3 * delta / c
            let until = multiple < 1 ? 1.3 * predicted : 5 * delta / c
            let result = try spallRun(thick.scene, setup: thick, parts: [1], until: until)
            let label = String(format: "strength %.1f ρcv/2, viscosity %@", multiple, viscosity ? "on" : "off")
            let judged = gated ? result.firstInZone : result.firstAnywhere
            // Faces in the 1D zone that opened within 5% of the first: the spall plane.
            let plane = result.zoneFaces.filter { $0.time <= (result.firstInZone?.time ?? 0) * 1.05 }
            let offset = plane.map { abs($0.x) }.max() ?? .infinity
            let reading = result.reading!
            print(String(format: "    %@. T = 2δ, %@: first crack anywhere %@; inside the 1D zone %@ (predicted 3δ/c = %.3f µs at x 0)%@; at the end %d inserted, %d failed, %d pieces, energy error %.4f%%",
                         multiple < 1 ? "2" : "3", label, describe(result.firstAnywhere), describe(result.firstInZone), 1e6 * predicted,
                         plane.isEmpty ? "" : String(format: "; %d zone faces within 5%% of it, all within %.2f mm (%.2f cells) of the mid-plane, y %+.0f to %+.0f mm",
                                                     plane.count, 1000 * offset, offset / thick.cell, 1000 * plane.map(\.y).min()!, 1000 * plane.map(\.y).max()!),
                         reading.insertedEdges, reading.failedEdges, reading.pieces, 100 * result.energyError))
            guard viscosity else { continue }
            if multiple > 1 {
                if gated { gate(judged == nil, "Negative control (1.3 ρcv/2) cracked inside the 1D zone") }
                else { print("       as first specified: no crack up to 5δ/c \(judged == nil ? "met" : "NOT met")") }
                continue
            }
            if gated {
                let first = try unwrap(judged, "no spall crack inside the 1D zone at 0.5 ρcv/2")
                gate(first.time >= 0.9 * predicted, "Spall crack opened before 0.9 · 3δ/c")
                gate(abs(first.time / predicted - 1) <= 0.05, "Spall crack time more than 5% from 3δ/c")
                // Inclusive: faces exactly two cells away (mesh lines at ±2 cells) count as within.
                gate(offset <= 2 * thick.cell * (1 + 1e-9), "Spall crack more than two element widths from the predicted plane")
            } else if let first = judged {
                print("       as first specified: time within 5% \(abs(first.time / predicted - 1) <= 0.05 ? "met" : "NOT met"); first crack within two cells of the plane \(abs(first.x) <= 2 * thick.cell ? "met" : "NOT met")")
            }
        }
    }
    require(failures.isEmpty, "\(failures.count) spall gate(s) failed: " + failures.joined(separator: "; "))
    print("Spall check passed.")
}
