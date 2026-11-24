import Foundation
import ImpactPhysics

// Contact reporting gate (approved 24 November 2026). Checks the reporting
// layer only: pulse detection, stated averaging windows, absolute and relative
// overlap. The contact formulation is unchanged. The low-speed metal rebound
// is kept as an unresolved numerical sensitivity and a regression benchmark:
// its convergence criterion is reported as it stands, never relaxed.

func contactReportingCheck() throws {
    syntheticPulseChecks()
    try metalReboundBenchmark()
    try fractureTimestepCheck()
    print("Contact reporting gate finished.")
}

private func syntheticPulseChecks() {
    let dt = 1e-6
    // A steady 100 N/m load for 1 ms is one pulse of 0.1 N·s/m, and every
    // window shorter than the pulse averages to 100 N/m.
    var steady = ContactPulseTracker(ContactPulseSettings(mergeGap: 5e-6, windows: [1e-5, 1e-4]))
    for n in 1...1000 { steady.record(time: Double(n) * dt, dt: dt, load: 100) }
    for n in 1001...1200 { steady.record(time: Double(n) * dt, dt: dt, load: 0) }
    let a = steady.report
    require(a.pulses.count == 1 && abs(a.pulses[0].impulse - 0.1) < 1e-9 && abs(a.totalImpulse - 0.1) < 1e-9,
            "Steady pulse impulse is wrong")
    require(a.windowPeaks.allSatisfy { abs($0 - 100) < 1e-6 } && abs(a.pulses[0].meanForce - 100) < 0.2,
            "Steady pulse averages are wrong")

    // Chatter: on for one step, off for one step, inside 50 µs. With a 5 µs
    // merge gap that is one pulse made of 25 solver episodes, not 25 pulses.
    // A second burst 100 µs later is a second pulse. A 0.5% touch is minor.
    var chatter = ContactPulseTracker(ContactPulseSettings(mergeGap: 5e-6, windows: [1e-5]))
    var n = 0
    func feed(_ load: Double) { n += 1; chatter.record(time: Double(n) * dt, dt: dt, load: load) }
    for k in 0..<50 { feed(k % 2 == 0 ? 1000 : 0) }
    for _ in 0..<100 { feed(0) }
    for _ in 0..<20 { feed(1000) }
    for _ in 0..<100 { feed(0) }
    feed(50)
    for _ in 0..<20 { feed(0) }
    let b = chatter.report
    require(b.pulses.count == 2 && b.pulses[0].episodes == 25 && b.rawEpisodes == 27 && b.minorCount == 1,
            "Chatter was not merged into pulses")
    require(abs(b.pulses.map(\.impulse).reduce(0, +) + b.minorImpulse - b.totalImpulse) < 1e-12,
            "Pulse impulses do not add up to the total")
    print("Pulse detection: steady pulse exact; 25 chatter episodes merged into one pulse; minor touch separated")
}

private func metalScene(speed: Double, fracture: Bool) -> AssemblyScene {
    var scene = AssemblyScene.bendingFractureExample()
    // Same E, density and Poisson ratio as the reference profiles. Provenance is
    // dropped only because the scene validator rejects fracture settings on
    // provenance-tagged materials (needed for the timestep check below).
    var al = MaterialProfile.aluminum6061.material; al.provenance = nil
    var steel = MaterialProfile.structuralSteel.material; steel.provenance = nil
    scene.parts[0].material = al
    for i in 1...4 { scene.parts[i].material = steel }
    let top = scene.parts[0].size.y / 2
    scene.parts[1].center.y = top + scene.parts[1].size.y / 2 + 1e-4
    for i in 2...3 { scene.parts[i].center.y = -top - scene.parts[i].size.y / 2 - 1e-4 }
    scene.parts[1].velocity.y = -speed
    if !fracture { scene.parts[0].fracture = nil }
    return scene
}

private struct MetalRun {
    let penalty: Double
    let report: ContactPulseReport
    let rebound, strikerImpulse, depth, relative, dt: Double
}

private func metalReboundBenchmark() throws {
    // Steel striker on an aluminium beam at 1.45 m/s, mesh ×3, fracture off,
    // insertion off, penalty ×1, ×2 and ×4, 0.8 ms.
    let scene = metalScene(speed: 1.45, fracture: false)
    let penalties = [1.0, 2, 4]
    let probe = try AssemblySimulation(scene, refinement: 3, stepLimit: .infinity, notchDepth: 0.005,
                                       interbodyStiffnessScale: 1, insertionEnabled: false)
    // One transit time for all three runs, so every run uses the same windows.
    let transit = probe.elementTransitTime(bodies: [0, 1])
    let settings = ContactPulseSettings.guideline(transit: transit)
    let runs: [MetalRun] = try penalties.map { penalty in
        var run = try AssemblySimulation(scene, refinement: 3, stepLimit: .infinity, notchDepth: 0.005,
                                         interbodyStiffnessScale: penalty, insertionEnabled: false)
        let v0 = run.body(1).centerVelocity.y, mass = run.body(1).totalMass
        var tracker = ContactPulseTracker(settings)
        while run.time < 0.0008 && run.step() {
            tracker.record(time: run.time, dt: run.dt, load: run.normalLoad(0, 1))
        }
        require(run.failure == nil, "Metal run failed: \(run.failure ?? "")")
        let v = run.body(1).centerVelocity.y
        return MetalRun(penalty: penalty, report: tracker.report, rebound: v, strikerImpulse: mass * (v - v0),
                        depth: run.peakPenetrationDepth, relative: run.peakRelativePenetration, dt: run.dt)
    }
    func spread(_ values: [Double]) -> Double { 100 * (values.max()! / values.min()! - 1) }
    let windows = settings.windows.map { String(format: "%.3g µs", $0 * 1e6) }.joined(separator: ", ")
    print(String(format: "Metal contact (1.45 m/s, ×3): transit time %.3g µs, merge gap %.3g µs, windows %@",
                 transit * 1e6, settings.mergeGap * 1e6, windows))
    for r in runs {
        let pulses = r.report.pulses.map { String(format: "%.0f µs %.3f N·s/m", $0.start * 1e6, $0.impulse) }
        print(String(format: "  penalty ×%.0f dt %.4g ns: %d pulses from %d solver episodes (+%d minor) [%@]; rebound %.5f m/s; overlap %.3f µm (%.4f%% of edge); raw step peak %.3g N/m (diagnostic)",
                     r.penalty, r.dt * 1e9, r.report.pulses.count, r.report.rawEpisodes, r.report.minorCount,
                     pulses.joined(separator: ", "), r.rebound, r.depth * 1e6, 100 * r.relative, r.report.rawPeak))
    }
    // Instrumentation: the tracked impulse is the striker's momentum change.
    for r in runs {
        require(abs(r.report.totalImpulse - r.strikerImpulse) <= 1e-6 * abs(r.strikerImpulse),
                "Tracked impulse does not match the striker momentum change")
    }
    // Robust quantities, verified across penalty (23 November 2026 study).
    let first = runs.map { $0.report.pulses[0].impulse }
    let early = runs.map { r in r.report.pulses.filter { $0.start < 2.5e-4 }.count }
    let windowed = runs.map { $0.report.pulses[0].windowPeaks[1] }
    print(String(format: "  first-pulse impulse spread %.2f%% (limit 2%%); pulses before 250 µs %@; first-pulse %@ average spread %.2f%% (limit 5%%)",
                 spread(first), early.map(String.init).joined(separator: "/"),
                 String(format: "%.3g µs", settings.windows[1] * 1e6), spread(windowed)))
    require(spread(first) <= 2, "First-pulse impulse depends on penalty")
    require(Set(early).count == 1, "Early pulse count depends on penalty")
    require(spread(windowed) <= 5, "Averaged first-pulse force depends on penalty")
    require(runs.allSatisfy { $0.depth > 0 && $0.depth < 1e-6 && $0.relative > 0 },
            "Overlap diagnostics are missing or unexpectedly large")

    // Unresolved numerical sensitivity, kept as found. Criterion unchanged:
    // final rebound speed within 5% across penalty ×1 to ×4.
    let rebounds = runs.map(\.rebound)
    let reboundSpread = spread(rebounds)
    if reboundSpread <= 5 {
        print(String(format: "  REVIEW: low-speed metal rebound now agrees within %.2f%%. Something changed; investigate before celebrating.", reboundSpread))
    } else {
        print(String(format: "  OPEN (known numerical sensitivity): low-speed metal rebound spread %.0f%% across penalty, criterion ≤ 5%% not met. Late re-contacts after about 290 µs differ.", reboundSpread))
    }
    // Regression: these exact values on this commit. A change means the
    // solver changed, which must be explained, not re-baselined silently.
    let reference = metalReboundReference
    for (r, expected) in zip(runs, reference) {
        require(abs(r.rebound - expected) <= 1e-5,
                String(format: "Low-speed metal rebound changed at penalty ×%.0f: %.6f m/s, reference %.6f m/s", r.penalty, r.rebound, expected))
    }
    print("  Regression: rebound values match the recorded reference")
}

/// Recorded on 24 November 2026 (base 724e32b; identical on material-separation 47ccaad), rounded to 1e-5 m/s.
private let metalReboundReference: [Double] = [0.13675, 0.05888, 0.08029]

private func fractureTimestepCheck() throws {
    // Verifies the claim that fracture settings, whose cohesive strength is a
    // fraction of E, shrink the metal timestep.
    func dt(_ fraction: Double?) throws -> Double {
        var scene = metalScene(speed: 1.45, fracture: fraction != nil)
        if let fraction { scene.parts[0].fracture?.strengthFraction = fraction }
        let run = try AssemblySimulation(scene, refinement: 3, stepLimit: .infinity, notchDepth: 0.005,
                                         insertionEnabled: false)
        return run.dt
    }
    let none = try dt(nil)
    let fractions = [0.03, 0.015, 0.0075, 0.005]
    let steps = try fractions.map(dt)
    let young = MaterialProfile.aluminum6061.material.young
    print(String(format: "Fracture strength and timestep (Al beam, ×3): no fracture dt %.4g ns", none * 1e9))
    for (f, s) in zip(fractions, steps) {
        print(String(format: "  strengthFraction %.4f (cohesive strength %.0f MPa): dt %.4g ns, %.1f× smaller",
                     f, f * young / 1e6, s * 1e9, none / s))
    }
    require(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 }, "Timestep should grow as cohesive strength falls")
}
