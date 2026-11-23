import Foundation
import ImpactPhysics
import simd

/// Runs scene files exactly as the app does and reports what happened to each
/// body. Read-only post-processing of the recorded replay; no solver changes.
func showcaseReport(_ paths: [String]) throws {
    for path in paths {
        let url = URL(fileURLWithPath: path)
        let scene = try AssemblyScene.open(url)
        var run = try AssemblyRun(scene)
        require(run.simulation.initialIssue == nil, "\(url.lastPathComponent): \(run.simulation.initialIssue ?? "")")
        run.measureWork(parallelFEM: true)
        let started = ProcessInfo.processInfo.systemUptime
        var replay = AssemblyReplay(run)
        var steps = 0
        while run.step(recording: &replay) { steps += 1 }
        replay.finish(run)
        require(run.finished && run.simulation.failure == nil, "\(url.lastPathComponent) ran to completion: \(run.simulation.failure ?? "")")
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let first = replay.frames.first!, last = replay.frames.last!
        let initial = first.energies.total
        let drift = replay.frames.map { abs($0.energies.total - initial) / initial }.max()!
        print("\n=== \(url.lastPathComponent): \(scene.parts.count) bodies, \(String(format: "%.3f", scene.duration * 1e3)) ms, "
              + "\(steps) steps (mean step \(String(format: "%.4f", scene.duration / Double(steps) * 1e6)) µs) in \(String(format: "%.1f", elapsed)) s, "
              + "\(replay.frames.count) frames, energy drift \(String(format: "%.3f", 100 * drift))%")
        let e = last.energies
        print(String(format: "Energy J/m  start %.1f → end: kinetic %.1f, elastic %.1f, hardening %.1f, plastic %.1f, fracture %.3f, contact %.2f, links %.2f",
                     initial, e.kinetic, e.elastic, e.hardening, e.plastic, e.fracture, e.contact, e.connection))

        // Nodal weights from element areas (lumped, uniform density per body).
        func weights(_ body: Body) -> [Double] {
            var w = Array(repeating: 0.0, count: body.mesh.reference.count)
            for t in body.mesh.elements {
                let r = body.mesh.reference
                let area = abs((r[t.b] - r[t.a]).x * (r[t.c] - r[t.a]).y - (r[t.b] - r[t.a]).y * (r[t.c] - r[t.a]).x) / 2
                for n in [t.a, t.b, t.c] { w[n] += area / 3 }
            }
            let total = w.reduce(0, +)
            return w.map { $0 / total }
        }
        func centroid(_ p: [Point], _ w: [Double]) -> Point { zip(p, w).reduce(Point.zero) { $0 + $1.0 * $1.1 } }
        for (i, part) in scene.parts.enumerated() {
            let b0 = first.bodies[i].body, b1 = last.bodies[i].body
            let w = weights(b0)
            let c0 = centroid(b0.position, w), c1 = centroid(b1.position, w)
            let v0 = centroid(b0.velocity, w), v1 = centroid(b1.velocity, w)
            var dot = 0.0, cross = 0.0
            for n in w.indices {
                let p = b0.position[n] - c0, q = b1.position[n] - c1
                dot += w[n] * (p.x * q.x + p.y * q.y)
                cross += w[n] * (p.x * q.y - p.y * q.x)
            }
            let rotation = atan2(cross, dot) * 180 / .pi
            let peakVM = replay.frames.map { $0.bodies[i].stress.map(\.equivalent).max() ?? 0 }.max() ?? 0
            let plastic = last.bodies[i].plasticStrain.max() ?? 0
            let mass = b0.totalMass
            var line = String(format: "  %-16@ m %5.2f kg/m | v %6.1f,%6.1f → %6.1f,%6.1f m/s | moved %5.1f mm | rotated %6.1f° | peak VM %6.3g MPa | final peak plastic %5.2f%%",
                              part.name as NSString, mass, v0.x, v0.y, v1.x, v1.y, simd_length(c1 - c0) * 1e3, rotation, peakVM / 1e6, plastic * 100)
            if part.fracture != nil {
                let pieces = last.bodies[i].pieces
                let major = pieces.filter { $0.mass >= 0.02 * mass }.sorted { $0.mass > $1.mass }
                line += " | pieces \(pieces.count), \(major.count) over 2% of mass" + (pieces.count > 1 ? " (" + major.map { String(format: "%.0f%%@%.1f,%.1f m/s", 100 * $0.mass / mass, $0.velocity.x, $0.velocity.y) }.joined(separator: "; ") + ")" : "")
                if let reading = last.bodies[i].fracture { line += String(format: " | crack faces %d", last.bodies[i].cracks.count); _ = reading }
            }
            print(line)
        }
        // Contact sequence: first frame each pair carries force.
        var seen: [SIMD2<Int>: Double] = [:]
        var peak: [SIMD2<Int>: Double] = [:]
        for frame in replay.frames {
            for c in frame.contacts where c.force > 0 {
                if seen[c.pair] == nil { seen[c.pair] = frame.time }
                peak[c.pair] = max(peak[c.pair] ?? 0, c.force)
            }
        }
        let order = seen.sorted { $0.value < $1.value }
        print("Contact sequence (sampled frames): " + order.map {
            String(format: "%@↔%@ %.3f ms (peak %.0f kN/m)", scene.parts[$0.key.x].name, scene.parts[$0.key.y].name, $0.value * 1e3, (peak[$0.key] ?? 0) / 1e3)
        }.joined(separator: "; "))
        print("Events: " + replay.events.map { String(format: "%@ %.3f ms", $0.label, $0.time * 1e3) }.joined(separator: "; "))
    }
}
