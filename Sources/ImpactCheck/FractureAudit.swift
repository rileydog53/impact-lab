import Foundation
import ImpactPhysics
import simd

// Independent audit probe: where and when cohesive faces are inserted in the
// compliant-pad notched bend.
func fractureMapProbe(_ orientation: String, refinement: Int, dt: Double, duration: Double, strikerX: Double? = nil, quiet: Bool = false, production: Bool = false) throws {
    var scene = AssemblyScene.bendingFractureExample()
    let mesh = MaterialFractureSettings.MeshPattern.allCases.first { $0.rawValue.lowercased() == orientation }!
    scene.parts[0].fracture?.meshPattern = mesh
    scene.duration = duration
    if let strikerX { scene.parts[1].center.x = strikerX }
    let pad: StrikerPad? = production ? nil : StrikerPad(thickness: 0.004, modulus: 250_000, samples: 64)
    if let pad { scene.parts[1].center.y += pad.thickness }
    var s = try AssemblySimulation(scene, refinement: refinement, stepLimit: dt, notchDepth: production ? 0 : 0.005, strikerPad: pad)
    let strength = scene.parts[0].material.young * scene.parts[0].fracture!.strengthFraction
    var seen = 0
    var printed = 0
    var crossing: Double?
    while s.step() {
        if crossing == nil {
            let q = s.body(0).mesh.reference
            if s.crackFaces(0).contains(where: { $0.damage == 1 && abs((q[$0.first.a] + q[$0.first.b]).x / 2) < 0.004 && (q[$0.first.a] + q[$0.first.b]).y / 2 > 0.0025 }) { crossing = s.time }
        }
        let faces = s.crackFaces(0)
        if faces.count > seen {
            let p = s.body(0).mesh.reference
            for f in faces[seen...] where printed < (quiet ? 0 : 40) {
                let m = (p[f.first.a] + p[f.first.b]) / 2
                let d = p[f.first.b] - p[f.first.a]
                print(String(format: "t=%.3f ms  mid (%.1f, %.1f) mm  dir (%.2f, %.2f)  seed n/s %.2f %.2f", s.time * 1000, m.x * 1000, m.y * 1000,
                             d.x / simd_length(d), d.y / simd_length(d), f.seed.x / strength, f.seed.y / strength))
                printed += 1
            }
            seen = faces.count
        }
    }
    let p = s.body(0).mesh.reference
    var bins: [String: (n: Int, w: Double)] = [:]
    let g = scene.parts[0].fracture!.energy
    for f in s.crackFaces(0) where f.damage > 0 {
        let m = (p[f.first.a] + p[f.first.b]) / 2
        let key = String(format: "x%+04.0f y%+03.0f", (m.x * 1000 / 10).rounded(.down) * 10, (m.y * 1000 / 7).rounded(.down) * 7)
        let w = g * simd_distance(p[f.first.a], p[f.first.b]) * f.damage
        bins[key, default: (0, 0)].n += 1
        bins[key, default: (0, 0)].w += w
    }
    // Notch-connected advance: highest y among fully failed faces whose
    // midpoints lie within 4 mm of the notch axis.
    let ligament = s.crackFaces(0).filter { $0.damage == 1 }.map { (p[$0.first.a] + p[$0.first.b]) / 2 }.filter { abs($0.x) < 0.004 }.map(\.y).max() ?? -1
    print(String(format: "Highest spent face within 4 mm of axis: y = %.1f mm", ligament * 1000))
    var near = 0.0, far = 0.0
    for f in s.crackFaces(0) where f.damage > 0 {
        let m = (p[f.first.a] + p[f.first.b]) / 2
        let w = g * simd_distance(p[f.first.a], p[f.first.b]) * f.damage
        if abs(m.x) < 0.006 { near += w } else { far += w }
    }
    var kinds: [String: Double] = [:]
    for f in s.crackFaces(0) where f.damage > 0 {
        let a = p[f.first.a], b = p[f.first.b], m = (a + b) / 2
        guard abs(m.x) < 0.006 else { continue }
        let d = simd_normalize(b - a)
        let kind = abs(d.y) > 0.95 ? "vertical" : abs(d.x) > 0.95 ? "horizontal" : "inclined"
        kinds[kind + (f.damage == 1 ? " spent" : " partial"), default: 0] += g * simd_distance(a, b) * f.damage
    }
    print(kinds.keys.sorted().map { String(format: "%@ %.4f", $0, kinds[$0]!) }.joined(separator: ", "))
    print(String(format: "Work within 6 mm of notch axis %.5f J/m, elsewhere %.5f J/m", near, far))
    for key in bins.keys.sorted() where !quiet { print(String(format: "%@  faces %3d  work %.4f J/m", key, bins[key]!.n, bins[key]!.w)) }
    print(String(format: "Notch crack past y = 2.5 mm at %.3f ms", (crossing ?? .nan) * 1000))
    print(String(format: "Total work %.5f J/m, faces %d, stopped %@", s.fractureReading(0)!.dissipation, s.crackFaces(0).count, s.failure ?? "no"))
}

// Quantitative fracture-convergence control: compliant-pad bend with the
// striker centred over a 5 mm notch, so the notch is the critical site on every
// mesh. Metrics are taken at the through-crack event, when the network of
// fully spent faces connected to the notch tip first reaches the top surface.
// Post-separation fragment motion and secondary cracking are excluded.
struct CenteredOutcome {
    var through: Double?
    var networkWork = 0.0
    var verticalSpent = 0.0
    var totalWork = 0.0
    var energyError = 0.0
    var error: String?
}

func centeredFixture(_ pattern: MaterialFractureSettings.MeshPattern, refinement: Int, dt: Double) throws -> CenteredOutcome {
    var scene = AssemblyScene.bendingFractureExample()
    scene.parts[0].fracture?.meshPattern = pattern
    scene.parts[1].center.x = 0
    scene.duration = 0.030
    let pad = StrikerPad(thickness: 0.004, modulus: 250_000, samples: 64)
    scene.parts[1].center.y += pad.thickness
    var s = try AssemblySimulation(scene, refinement: refinement, stepLimit: dt, notchDepth: 0.005, strikerPad: pad)
    let half = 0.5 * scene.parts[0].size.y, tip = Point(0, -half + 0.005)
    let g = scene.parts[0].fracture!.energy
    var outcome = CenteredOutcome()
    var failed = 0
    while s.step() {
        outcome.energyError = max(outcome.energyError, abs(s.energies.total / s.initialEnergy - 1))
        let reading = s.fractureReading(0)!
        guard reading.failedEdges != failed else { continue }
        failed = reading.failedEdges
        let p = s.body(0).mesh.reference
        var links: [Point: [Point]] = [:]
        var spent: [(Point, Point)] = []
        for f in s.crackFaces(0) where f.damage == 1 {
            let a = p[f.first.a], b = p[f.first.b]
            links[a, default: []].append(b)
            links[b, default: []].append(a)
            spent.append((a, b))
        }
        guard links[tip] != nil else { continue }
        var reached: Set<Point> = [tip], queue = [tip], i = 0
        while i < queue.count {
            for target in links[queue[i]]! where reached.insert(target).inserted { queue.append(target) }
            i += 1
        }
        var work = 0.0, vertical = 0.0
        for (a, b) in spent where reached.contains(a) {
            let w = g * simd_distance(a, b)
            work += w
            if abs(simd_normalize(b - a).y) > 0.95 { vertical += w }
        }
        if queue.contains(where: { abs($0.y - half) < 1e-10 }) {
            outcome.through = s.time
            outcome.networkWork = work
            outcome.verticalSpent = vertical
            outcome.totalWork = reading.dissipation
            break
        }
    }
    if outcome.through == nil { outcome.error = s.failure ?? "no through crack by 30 ms" }
    return outcome
}

func fractureConvergenceCheck(_ arguments: [String]) throws -> Bool {
    // Worker mode: one case per process so the six cases run in parallel.
    if arguments.count == 3, let pattern = MaterialFractureSettings.MeshPattern.allCases.first(where: { $0.rawValue.lowercased() == arguments[0] }),
       let refinement = Int(arguments[1]), let dt = Double(arguments[2]) {
        let o = try centeredFixture(pattern, refinement: refinement, dt: dt * 1e-6)
        print(String(format: "%.9f %.9f %.9f %.9f %.9f %@", o.through ?? -1, o.networkWork, o.verticalSpent, o.totalWork, o.energyError,
                     (o.error ?? "ok").replacingOccurrences(of: " ", with: "_")))
        return o.error == nil
    }
    let cases = [("aligned", 6, 0.225), ("aligned", 7, 0.225), ("aligned", 6, 0.1125),
                 ("staggered", 6, 0.225), ("staggered", 7, 0.225), ("staggered", 6, 0.1125)]
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    var pipes: [Pipe] = []
    var processes: [Process] = []
    for (pattern, refinement, dt) in cases {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--fracture-convergence", pattern, String(refinement), String(dt)]
        process.standardOutput = pipe
        try process.run()
        processes.append(process)
        pipes.append(pipe)
    }
    var results: [[String]] = []
    for (process, pipe) in zip(processes, pipes) {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        results.append(String(decoding: data, as: UTF8.self).split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
    }
    let ligament = 0.021 * 7.0
    print("Centred notched bend (compliant pad), metrics at the through-crack event. Convergence demonstrated on this fixture only, not general mesh independence.")
    var pass = true
    for (i, (pattern, refinement, dt)) in cases.enumerated() {
        let r = results[i]
        guard r.count == 6, r[5] == "ok" else {
            print("\(pattern) ×\(refinement) dt \(dt) µs: FAIL, \(r.last ?? "no output")")
            pass = false
            continue
        }
        print(String(format: "%@ ×%d dt %.4f µs: through %.3f ms, notch network %.5f J/m (vertical %.5f), total %.5f J/m, energy %.4f%%",
                     pattern, refinement, dt, 1000 * Double(r[0])!, Double(r[1])!, Double(r[2])!, Double(r[3])!, 100 * Double(r[4])!))
        pass = pass && Double(r[4])! < 0.005
    }
    guard pass else { return false }
    func change(_ a: Int, _ b: Int, _ k: Int) -> Double { 100 * abs(Double(results[b][k])! / Double(results[a][k])! - 1) }
    // Gated: notch-crack fracture energy at the through-crack event, using the
    // study's 2% tolerance. Reported only: the through-crack time, which is
    // not converged (the final ligament under the striker is in compression).
    for (name, base) in [("aligned", 0), ("staggered", 3)] {
        let refinement = (time: change(base, base + 1, 0), work: change(base, base + 1, 1))
        let step = (time: change(base, base + 2, 0), work: change(base, base + 2, 1))
        let ok = max(refinement.work, step.work) < 2
        print(String(format: "%@: notch-crack energy ×6→×7 %.2f%%, half step %.2f%% — %@. Through-crack time ×6→×7 %.2f%%, half step %.2f%% — NOT CONVERGED, not gated.",
                     name, refinement.work, step.work, ok ? "PASS" : "FAIL", refinement.time, step.time))
        pass = pass && ok
    }
    print(String(format: "Reported, not gated: aligned ×7 notch crack %.5f J/m vs straight-crack Gc·L %.5f J/m; staggered/aligned ×7 energy %+.2f%% (edge-path zigzag floor +11.8%%)",
                 Double(results[1][1])!, ligament, 100 * (Double(results[4][1])! / Double(results[1][1])! - 1)))
    return pass
}
