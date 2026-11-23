import Foundation
import ImpactPhysics
import simd

/// FEM versus the MPM prototype on one shared problem: a plane-strain copper
/// block (40 × 25 mm) striking a frictionless rigid wall. FEM represents the
/// wall by symmetry — two mirror-image blocks colliding head-on with
/// frictionless contact — so both methods solve the same boundary-value problem
/// with the same Hencky–J2 constitutive routine.
nonisolated(unsafe) private var blockSize = Point(0.040, 0.025)
private let gapToWall = 0.00025

private struct Outcome {
    let label: String
    var plastic = 0.0, stored = 0.0, kinetic = 0.0, initial = 0.0, drift = 0.0
    var rebound = 0.0, length = 0.0, faceHeight = 0.0, peakPlastic = 0.0
    var contactStart = Double.nan, contactEnd = Double.nan
    var steps = 0, seconds = 0.0, units = 0
    var failure: String?
}

private func material(elastic: Bool) -> (Material, HardeningTable) {
    let profile = MaterialProfile.copperC110
    // An unreachable yield keeps both methods on the identical Hencky law.
    let table = elastic ? HardeningTable(points: [.init(strain: 0, stress: 2e10), .init(strain: 1, stress: 2e10)]) : profile.hardening
    return (profile.material, table)
}

func copperWallFEMScene(speed: Double, resolution: AssemblyScene.Resolution, duration: Double,
                        elastic: Bool, size: Point) -> AssemblyScene {
    let (copper, table) = material(elastic: elastic)
    var scene = AssemblyScene()
    for side in [-1.0, 1.0] {
        var part = AssemblyPart(side < 0 ? "Left" : "Right",
                                center: Point(side * (size.x / 2 + gapToWall), 0), size: size)
        part.material = copper
        part.plasticity.response = .elastoplastic
        part.plasticity.table = table
        part.velocity = Point(-side * speed, 0)
        scene.parts.append(part)
    }
    scene.duration = duration
    scene.meshResolution = resolution
    return scene
}

private func runFEM(speed: Double, resolution: AssemblyScene.Resolution, duration: Double, elastic: Bool) -> Outcome {
    var outcome = Outcome(label: "FEM \(resolution.label)")
    let scene = copperWallFEMScene(speed: speed, resolution: resolution, duration: duration,
                                  elastic: elastic, size: blockSize)
    let started = ProcessInfo.processInfo.systemUptime
    do {
        var run = try AssemblyRun(scene)
        run.measureWork(parallelFEM: true)
        var replay = AssemblyReplay(run)
        while run.step(recording: &replay) { outcome.steps += 1 }
        replay.finish(run)
        outcome.failure = run.simulation.failure
        let frames = replay.frames
        let first = frames[0], last = frames.last!
        outcome.units = first.bodies[0].body.mesh.elements.count
        outcome.initial = first.energies.total / 2
        outcome.drift = frames.map { abs($0.energies.total - first.energies.total) / first.energies.total }.max()!
        let e = last.energies
        outcome.plastic = e.plastic / 2
        outcome.stored = (e.elastic + e.hardening + e.contact) / 2
        outcome.kinetic = e.kinetic / 2
        let body = last.bodies[0].body
        var w = Array(repeating: 0.0, count: body.mesh.reference.count)
        for t in body.mesh.elements {
            let r = body.mesh.reference
            let area = abs((r[t.b] - r[t.a]).x * (r[t.c] - r[t.a]).y - (r[t.b] - r[t.a]).y * (r[t.c] - r[t.a]).x) / 2
            for n in [t.a, t.b, t.c] { w[n] += area / 3 }
        }
        let total = w.reduce(0, +)
        outcome.rebound = zip(body.velocity, w).reduce(0.0) { $0 + $1.0.x * $1.1 } / total
        let xs = body.position.map(\.x), ys = body.position.map(\.y)
        outcome.length = xs.max()! - xs.min()!
        // Height of the impact face: nodes within 2 mm of the leading edge.
        let front = xs.max()!
        let face = zip(xs, ys).filter { $0.0 > front - 0.002 }.map(\.1)
        outcome.faceHeight = face.max()! - face.min()!
        outcome.peakPlastic = last.bodies[0].plasticStrain.max() ?? 0
        let active = frames.filter { frame in frame.contacts.contains { $0.force > 0 } }.map(\.time)
        outcome.contactStart = active.first ?? .nan
        outcome.contactEnd = active.last ?? .nan
    } catch { outcome.failure = error.localizedDescription + " " + scene.issues().joined(separator: " ") }
    outcome.seconds = ProcessInfo.processInfo.systemUptime - started
    return outcome
}

private func runMPM(speed: Double, spacing: Double, duration: Double, elastic: Bool) -> Outcome {
    var outcome = Outcome(label: String(format: "MPM dx %.2g mm", spacing * 1e3))
    let (copper, table) = material(elastic: elastic)
    let length = blockSize.x
    var mpm = MPMSimulation(spacing: spacing, domainMin: Point(-length - 0.03, -0.16), domainMax: Point(0.004, 0.16), wallX: 0)
    // MPM starts in contact (standard for kernel-based walls, which act on
    // material up to 1.5 cells away). Its clock is offset by FEM's free flight
    // to the symmetry plane, so both report time from the same physical event.
    mpm.addBlock(center: Point(-length / 2, 0), size: blockSize, velocity: Point(speed, 0), material: copper, table: table)
    outcome.units = mpm.particles.count
    outcome.initial = mpm.ledger().total
    let shift = -gapToWall / speed
    let duration = duration + shift
    let started = ProcessInfo.processInfo.systemUptime
    var dt = mpm.stableStep
    var lastImpulse = 0.0
    var increments: [(Double, Double)] = []
    while mpm.time < duration {
        if mpm.steps % 20 == 0 { dt = mpm.stableStep }
        guard mpm.step(min(dt, duration - mpm.time)) else { break }
        increments.append((mpm.time, (mpm.wallImpulse - lastImpulse) / max(dt, 1e-30)))
        lastImpulse = mpm.wallImpulse
        if mpm.steps % 200 == 0 {
            outcome.drift = max(outcome.drift, abs(mpm.ledger().total - outcome.initial) / outcome.initial)
        }
    }
    // Contact window: wall force above 2% of its peak (the B-spline kernel lets
    // the wall act on material up to 1.5 cells away, so onset is early).
    let peakForce = increments.map(\.1).max() ?? 0
    let active = increments.filter { $0.1 > 0.02 * peakForce }.map(\.0)
    outcome.contactStart = (active.first ?? .nan) - shift
    outcome.contactEnd = (active.last ?? .nan) - shift
    outcome.failure = mpm.failure
    outcome.steps = mpm.steps
    outcome.seconds = ProcessInfo.processInfo.systemUptime - started
    let ledger = mpm.ledger()
    outcome.drift = max(outcome.drift, abs(ledger.total - outcome.initial) / outcome.initial)
    outcome.plastic = ledger.plastic
    outcome.stored = ledger.elastic + ledger.hardening
    outcome.kinetic = ledger.kinetic
    outcome.rebound = mpm.centerVelocity(body: 0).x
    let extent = mpm.extent(body: 0)
    outcome.length = extent.max.x - extent.min.x
    let front = extent.max.x
    let face = mpm.particles.filter { $0.position.x > front - 0.002 }.map(\.position.y)
    outcome.faceHeight = (face.max() ?? 0) - (face.min() ?? 0) + spacing / 2
    outcome.peakPlastic = mpm.peakPlasticStrain(body: 0)
    return outcome
}

private func report(_ title: String, _ rows: [Outcome]) {
    print("\n" + title)
    print("method            units   steps    wall s  drift%   plastic  stored  kinetic J/m | rebound m/s | length mm  face mm | peak εp | contact window µs (duration)")
    for r in rows {
        if let failure = r.failure, r.steps == 0 { print("\(r.label.padding(toLength: 17, withPad: " ", startingAt: 0)) FAILED: \(failure)"); continue }
        print(String(format: "%@ %6d %7d %8.1f %7.3f %9.1f %7.1f %8.1f | %11.2f | %9.2f %8.2f | %6.1f%% | %5.1f–%5.1f (%5.1f)%@",
                     r.label.padding(toLength: 17, withPad: " ", startingAt: 0) as NSString, r.units, r.steps, r.seconds, 100 * r.drift,
                     r.plastic, r.stored, r.kinetic, r.rebound, r.length * 1e3, r.faceHeight * 1e3, 100 * r.peakPlastic,
                     r.contactStart * 1e6, r.contactEnd * 1e6, (r.contactEnd - r.contactStart) * 1e6, r.failure.map { "  FAILED: " + $0 } ?? ""))
    }
}

/// Usage: --mpm-compare elastic|plastic SPEED DURATION_US [fem levels e.g. 2,4,7] [mpm spacings mm e.g. 2,1,0.5]
func mpmComparison(_ args: [String]) throws {
    if args.first == "fem-limits" {
        require(args.count == 1, "Usage: ImpactCheck --mpm-compare fem-limits")
        try femLimitStudy()
        return
    }
    let elastic = args.first == "elastic"
    let speed = Double(args.count > 1 ? args[1] : "50")!
    let duration = Double(args.count > 2 ? args[2] : "300")! / 1e6
    let levels = (args.count > 3 ? args[3] : "2,4,7").split(separator: ",").compactMap { Int($0) }.compactMap(AssemblyScene.Resolution.init(rawValue:))
    let spacings = (args.count > 4 ? args[4] : "2,1,0.5").split(separator: ",").compactMap { Double($0) }.map { $0 * 1e-3 }
    if args.count > 5 {
        let mm = args[5].split(separator: "x").compactMap { Double($0) }
        if mm.count == 2 { blockSize = Point(mm[0], mm[1]) / 1000 }
    }
    var rows: [Outcome] = []
    if speed <= AssemblyPart.velocityRange.upperBound {
        for level in levels { rows.append(runFEM(speed: speed, resolution: level, duration: duration, elastic: elastic)) }
    } else {
        rows.append(Outcome(label: "FEM", failure: "not run: the FEM workshop accepts at most 150 m/s"))
    }
    for spacing in spacings { rows.append(runMPM(speed: speed, spacing: spacing, duration: duration, elastic: elastic)) }
    let (copper, _) = material(elastic: elastic)
    let bar = (copper.young / (copper.density * (1 - copper.poisson * copper.poisson))).squareRoot()
    report(String(format: "%@ copper block %.0f × %.0f mm at %.0f m/s onto a frictionless rigid wall, %.0f µs (per block, J/m). 1-D elastic estimate: contact %.1f µs (2L/c, plane-strain bar speed %.0f m/s)",
                  elastic ? "Elastic" : "Elastoplastic (C11000 profile)", blockSize.x * 1e3, blockSize.y * 1e3, speed, duration * 1e6, 2 * blockSize.x / bar * 1e6, bar), rows)
}
