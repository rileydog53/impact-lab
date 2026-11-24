import Foundation
import ImpactPhysics
import simd

// Verification gate for the bounded capabilities added on the integration branch:
// gravity, fixed supports (rigid fixtures), clamped edges and spring preload.
// Each case compares the unmodified explicit solver against a closed-form result
// or an energy balance. NUMERICAL VERIFICATION of the implementation only; it is
// not physical validation of any material.

private func runScene(_ scene: AssemblyScene, every: Int = 1,
                      _ observe: (AssemblySimulation) -> Void) throws -> AssemblySimulation {
    let issues = scene.issues()
    require(issues.isEmpty, issues.joined(separator: "; "))
    var simulation = try AssemblySimulation(scene)
    require(simulation.initialIssue == nil, simulation.initialIssue ?? "")
    observe(simulation)
    var count = 0
    while simulation.time < scene.duration {
        require(simulation.step(), simulation.failure ?? "step rejected")
        count += 1
        if count % every == 0 { observe(simulation) }
    }
    return simulation
}

private func centerY(_ body: Body) -> Double { body.centerOfMass.y }

/// Time average from t = 0 to the last local minimum of a 1 − cos response,
/// which is a whole number of periods for a body released from rest under a constant load.
private func meanToLastTrough(_ series: [(t: Double, v: Double)]) -> (mean: Double, end: Double, extremes: (Double, Double)) {
    var last = series.count - 1
    for i in stride(from: series.count - 2, to: 1, by: -1) where series[i].v <= series[i - 1].v && series[i].v < series[i + 1].v {
        last = i
        break
    }
    var integral = 0.0
    for i in 1...last { integral += 0.5 * (series[i].v + series[i - 1].v) * (series[i].t - series[i - 1].t) }
    let values = series.prefix(last + 1).map(\.v)
    return (integral / series[last].t, series[last].t, (values.min()!, values.max()!))
}

func supportsGravityCheck() throws {
    let g = AssemblyScene.standardGravity
    print("Supports, gravity and preload verification (numerical verification, not physical validation)")

    // 1. Free fall: constant force, so velocity Verlet is exact up to round-off.
    do {
        var scene = AssemblyScene()
        var block = AssemblyPart("Falling block", size: Point(0.05, 0.05))
        block.material = Material(young: 2e6, density: 1200, poisson: 0.2)
        scene.parts = [block]
        scene.gravity = g
        scene.duration = 0.15
        var y0 = 0.0, worstEnergy = 0.0
        let final = try runScene(scene, every: 50) { sim in
            if sim.time == 0 { y0 = centerY(sim.body(0)) }
            let e = sim.energies
            worstEnergy = max(worstEnergy, abs(e.total - sim.initialEnergy))
        }
        let t = final.time
        let expected = y0 - 0.5 * g * t * t
        let drop = y0 - centerY(final.body(0))
        let error = abs(centerY(final.body(0)) - expected) / (0.5 * g * t * t)
        let mass = final.body(0).totalMass
        let energyScale = mass * g * drop
        print(String(format: "  Free fall: drop %.4f mm at t = %.4f s, analytic %.4f mm, error %.2e; energy drift %.2e of m·g·h",
                     drop * 1000, t, 0.5 * g * t * t * 1000, error, worstEnergy / energyScale))
        require(error < 1e-6, "free fall departs from y0 - g t^2 / 2")
        require(worstEnergy / energyScale < 1e-3, "free-fall energy balance")
    }

    // 2. A block resting on a rigid bench: mean support reaction equals the weight, no drift.
    do {
        var scene = AssemblyScene()
        var bench = AssemblyPart("Bench", center: Point(0, -0.05), size: Point(0.40, 0.04))
        bench.support = .fixed
        bench.material = Material(young: 2e7, density: 2000, poisson: 0.2)
        var block = AssemblyPart("Resting block", center: Point(0.01, -0.03 + 0.025 + 1e-5), size: Point(0.06, 0.05))
        block.material = Material(young: 3e6, density: 1100, poisson: 0.25)
        scene.parts = [bench, block]
        scene.gravity = g
        scene.duration = 0.25
        var series: [(t: Double, v: Double)] = []
        var worstEnergy = 0.0, minY = Double.infinity, maxX = 0.0
        var x0 = 0.0
        let final = try runScene(scene, every: 20) { sim in
            series.append((sim.time, sim.supportReaction(0).y))
            let body = sim.body(1)
            if sim.time == 0 { x0 = body.centerOfMass.x }
            minY = min(minY, body.position.map(\.y).min()!)
            maxX = max(maxX, abs(body.centerOfMass.x - x0))
            worstEnergy = max(worstEnergy, abs(sim.energies.total - sim.initialEnergy))
        }
        let weight = final.body(1).totalMass * g
        let late = series.filter { $0.t > 0.1 }
        let mean = late.map(\.v).reduce(0, +) / Double(late.count)
                print(String(format: "  Block on fixed bench: weight %.3f N/m, mean support reaction (t > 0.1 s) %.3f N/m, ratio %.4f",
                     weight, mean, mean / weight))
        print(String(format: "    lowest block node %.4f mm below bench top, lateral drift %.2e mm, energy drift %.2e J/m",
                     (-0.03 - minY) * 1000, maxX * 1000, worstEnergy))
        require(abs(mean / weight - 1) < 0.01, "bench reaction differs from the weight by more than 1%")
        require(-0.03 - minY < 0.1e-3, "block sinks more than 0.1 mm into the bench")
        require(maxX < 1e-5, "block drifts sideways by more than 0.01 mm on a frictionless bench")
        require(worstEnergy < 1e-3 * weight * 0.05, "bench energy balance")
    }

    // 3. Clamped cantilever under its own weight: mean tip deflection against
    //    Timoshenko beam theory, w L^4 / (8 E I) + w L^2 / (2 κ G A).
    do {
        let L = 0.15, h = 0.025, E = 1e7, rho = 1000.0
        var scene = AssemblyScene()
        var beam = AssemblyPart("Cantilever", size: Point(L, h))
        beam.material = Material(young: E, density: rho, poisson: 0)
        beam.support = .clampLeft
        beam.refinement = .x4
        scene.parts = [beam]
        scene.gravity = g
        scene.duration = 0.30
        var tipNodes: [Int] = []
        var series: [(t: Double, v: Double)] = []
        var worstEnergy = 0.0, peakEnergy = 0.0
        var reactions: [Double] = []
        let final = try runScene(scene, every: 10) { sim in
            let body = sim.body(0)
            if tipNodes.isEmpty {
                let right = body.mesh.reference.map(\.x).max()!
                tipNodes = body.mesh.reference.indices.filter { abs(body.mesh.reference[$0].x - right) < 1e-9 }
            }
            let tip = tipNodes.reduce(0) { $0 + body.position[$1].y - body.mesh.reference[$1].y } / Double(tipNodes.count)
            series.append((sim.time, -tip))
            reactions.append(sim.supportReaction(0).y)
            let e = sim.energies
            worstEnergy = max(worstEnergy, abs(e.total - sim.initialEnergy))
            peakEnergy = max(peakEnergy, abs(e.gravitational))
        }
        let w = rho * g * h, I = h * h * h / 12, G = E / 2, kappa = 5.0 / 6
        let bending = w * pow(L, 4) / (8 * E * I), shear = w * L * L / (2 * kappa * G * h)
        let analytic = bending + shear
        let (mean, end, extremes) = meanToLastTrough(series)
        let weight = final.body(0).totalMass * g
        let meanReaction = reactions.reduce(0, +) / Double(reactions.count)
        print(String(format: "  Clamped cantilever L %.0f mm, h %.0f mm, E %.0e Pa, 12 rows: mean tip sag %.4f mm (0 to %.3f s), Timoshenko %.4f mm (bending %.4f + shear %.4f), error %+.2f%%",
                     L * 1000, h * 1000, E, mean * 1000, end, analytic * 1000, bending * 1000, shear * 1000, (mean / analytic - 1) * 100))
        print(String(format: "    tip swings %.4f to %.4f mm (about 2× the static value, as expected for a load applied suddenly); mean clamp reaction %.3f N/m vs weight %.3f N/m; energy drift %.2e of peak potential",
                     extremes.0 * 1000, extremes.1 * 1000, meanReaction, weight, worstEnergy / peakEnergy))
        require(abs(mean / analytic - 1) < 0.05, "cantilever sag differs from beam theory by more than 5%")
        require(worstEnergy / peakEnergy < 0.01, "cantilever energy balance")
    }

    // 4. Simply supported bar resting on two fixed rollers, with overhangs a:
    //    midspan deflection relative to the supports w L^2 (5 L^2 - 24 a^2) / (384 E I).
    do {
        let total = 0.30, span = 0.26, h = 0.025, E = 1e7, rho = 1000.0
        let a = (total - span) / 2
        var scene = AssemblyScene()
        var bar = AssemblyPart("Bar", size: Point(total, h))
        bar.material = Material(young: E, density: rho, poisson: 0)
        bar.refinement = .x4
        let rollerDiameter = 0.025
        var left = AssemblyPart("Left roller", shape: .round, center: Point(-span / 2, -h / 2 - rollerDiameter / 2 - 1e-5),
                                size: Point(rollerDiameter, rollerDiameter))
        left.support = .fixed
        left.material = Material(young: 5e7, density: 2000, poisson: 0.2)
        var right = left
        right.id = UUID()
        right.name = "Right roller"
        right.center.x = span / 2
        scene.parts = [bar, left, right]
        scene.gravity = g
        scene.duration = 0.30
        var series: [(t: Double, v: Double)] = []
        var mid: [Int] = [], ends: [Int] = []
        var reactions: [Double] = []
        let final = try runScene(scene, every: 10) { sim in
            let body = sim.body(0)
            if mid.isEmpty {
                let ref = body.mesh.reference
                let midX = ref.map { abs($0.x) }.min()!
                mid = ref.indices.filter { abs(abs(ref[$0].x) - midX) < 1e-9 && ref[$0].y < -h / 2 + 1e-9 }
                let near = ref.map { abs(abs($0.x) - span / 2) }.min()!
                ends = ref.indices.filter { abs(abs(abs(ref[$0].x) - span / 2) - near) < 1e-9 && ref[$0].y < -h / 2 + 1e-9 }
            }
            func lift(_ nodes: [Int]) -> Double {
                nodes.reduce(0) { $0 + body.position[$1].y - body.mesh.reference[$1].y } / Double(nodes.count)
            }
            series.append((sim.time, lift(ends) - lift(mid)))
            reactions.append(sim.supportReaction(1).y + sim.supportReaction(2).y)
        }
        let w = rho * g * h, I = h * h * h / 12
        let analytic = w * span * span * (5 * span * span - 24 * a * a) / (384 * E * I)
        let (mean, end, _) = meanToLastTrough(series)
        let weight = final.body(0).totalMass * g
        let meanReaction = reactions.reduce(0, +) / Double(reactions.count)
        print(String(format: "  Bar on two fixed rollers, span %.0f mm, overhang %.0f mm: mean midspan sag %.4f mm (0 to %.3f s), beam theory %.4f mm, error %+.2f%%; mean roller reaction %.3f vs weight %.3f N/m",
                     span * 1000, a * 1000, mean * 1000, end, analytic * 1000, (mean / analytic - 1) * 100, meanReaction, weight))
        // Contact rollers spread the reaction over a small patch and the bar may chatter
        // on them, so this case is a bounded demonstration with a looser band than the clamp.
        require(abs(mean / analytic - 1) < 0.10, "roller-supported sag differs from beam theory by more than 10%")
        require(abs(meanReaction / weight - 1) < 0.03, "roller reactions differ from the weight by more than 3%")
    }

    // 5. Spring preload: two blocks joined by a stretched spring oscillate with
    //    ω² = k (1/m1 + 1/m2), starting from the stated preload, with energy conserved.
    do {
        var scene = AssemblyScene()
        var left = AssemblyPart("Left mass", center: Point(-0.06, 0), size: Point(0.04, 0.04))
        left.material = Material(young: 5e7, density: 2000, poisson: 0.2)
        var right = AssemblyPart("Right mass", center: Point(0.06, 0), size: Point(0.04, 0.04))
        right.material = Material(young: 5e7, density: 1000, poisson: 0.2)
        var spring = AssemblyConnection(first: left.id, second: right.id, firstAnchor: Point(1, 0), secondAnchor: Point(-1, 0))
        spring.stiffness = 20_000
        spring.preload = 0.004
        scene.parts = [left, right]
        scene.connections = [spring]
        scene.duration = 0.12
        var series: [(t: Double, v: Double)] = []
        var worstEnergy = 0.0, initialStored = 0.0, worstMomentum = 0.0
        let final = try runScene(scene, every: 5) { sim in
            if sim.time == 0 { initialStored = sim.energies.connection }
            series.append((sim.time, sim.linkReadings[0].extensionLength))
            worstEnergy = max(worstEnergy, abs(sim.energies.total - sim.initialEnergy))
            worstMomentum = max(worstMomentum, simd_length(sim.momentum))
        }
        let m1 = final.body(0).totalMass, m2 = final.body(1).totalMass
        let omega = (spring.stiffness * (1 / m1 + 1 / m2)).squareRoot()
        // Period from successive upward zero crossings of the extension.
        var crossings: [Double] = []
        for i in 1..<series.count where series[i - 1].v < 0 && series[i].v >= 0 {
            let f = -series[i - 1].v / (series[i].v - series[i - 1].v)
            crossings.append(series[i - 1].t + f * (series[i].t - series[i - 1].t))
        }
        require(crossings.count >= 2, "preloaded spring did not oscillate")
        let period = (crossings.last! - crossings.first!) / Double(crossings.count - 1)
        let expected = 2 * Double.pi / omega
        let stored = 0.5 * spring.stiffness * 0.004 * 0.004
        let amplitude = series.map { abs($0.v) }.max()!
        print(String(format: "  Preloaded spring, 4 mm stretch: initial stored %.5f J/m (½ k e² = %.5f), period %.3f ms vs two-mass %.3f ms (%+.2f%%), max extension %.4f mm, energy drift %.2e of stored, peak |momentum| %.1e",
                     initialStored, stored, period * 1000, expected * 1000, (period / expected - 1) * 100, amplitude * 1000,
                     worstEnergy / stored, worstMomentum))
        require(abs(initialStored / stored - 1) < 1e-12, "initial spring energy")
        require(abs(period / expected - 1) < 0.02, "preloaded spring period")
        require(amplitude < 0.004 * 1.02, "extension grew beyond the preload")
        require(worstEnergy / stored < 0.01, "preload energy balance")
        require(worstMomentum < 1e-9, "momentum not conserved")
    }
    print("Supports, gravity and preload checks passed.")
}

/// Loads every lab example through the scene-file reader, runs it to the end and
/// prints the quantity its description promises, so the descriptions stay true.
func labExamplesCheck() throws {
    let directory = "docs/lab-examples"
    let g = AssemblyScene.standardGravity
    for file in try FileManager.default.contentsOfDirectory(atPath: directory).filter({ $0.hasSuffix(".json") }).sorted() {
        let scene = try AssemblyScene.open(URL(fileURLWithPath: directory + "/" + file))
        let embedded = LabExample.allCases.first { $0.fileName == file }
        require(try embedded?.scene().parts.map(\.name) == scene.parts.map(\.name)
                && (try String(contentsOfFile: directory + "/" + file, encoding: .utf8)).trimmingCharacters(in: .newlines) == embedded?.json,
                "\(file) differs from the copy built into the app (Sources/ImpactPhysics/LabExamples.swift)")
        let saved = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("roundtrip-" + file)
        try scene.save(to: saved)
        require(try AssemblyScene.open(saved) == scene, "\(file): saved scene does not reopen identically")
        try? FileManager.default.removeItem(at: saved)
        var simulation = try AssemblySimulation(scene)
        require(simulation.initialIssue == nil, "\(file): \(simulation.initialIssue ?? "")")
        let estimate = RunCostEstimate(simulation)
        let start = ProcessInfo.processInfo.systemUptime
        var reactions: [Double] = []
        var drift = 0.0
        var peakSpeed = 0.0
        let free = scene.parts.indices.filter { scene.parts[$0].support == nil }
        let initialY = free.map { simulation.body($0).centerOfMass.y }
        var steps = 0
        while simulation.step() {
            steps += 1
            if steps % 20 == 0 {
                let supported = scene.parts.indices.filter { scene.parts[$0].support != nil }
                reactions.append(supported.reduce(0) { $0 + simulation.supportReaction($1).y })
                drift = max(drift, abs(simulation.energies.total - simulation.initialEnergy))
                if file == "hanging-springs.json" {
                    peakSpeed = max(peakSpeed, simd_length(simulation.body(2).centerVelocity))
                }
            }
        }
        require(simulation.failure == nil && simulation.time >= scene.duration, "\(file): \(simulation.failure ?? "ended early")")
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let moving = scene.parts.indices.filter { scene.parts[$0].support?.isFixture != true }
        let weight = moving.reduce(0) { $0 + simulation.body($1).totalMass } * (scene.gravity ?? 0)
        let late = reactions.suffix(reactions.count / 2)
        let mean = late.reduce(0, +) / Double(max(1, late.count))
        var line = String(format: "  %@: %d steps in %.1f s (estimated %@); mean support reaction, second half %.3f N/m vs weight of non-fixed bodies %.3f N/m; energy drift %.2e J/m",
                          file, steps, elapsed, RunCostEstimate.duration(estimate.seconds), mean, weight, drift)
        if file == "hanging-springs.json" {
            let dropUnloaded = initialY[0] - simulation.body(1).centerOfMass.y
            line += String(format: "; preloaded block peak speed %.2e m/s, unloaded block moved %.2f mm (equilibrium stretch %.2f mm)",
                           peakSpeed, dropUnloaded * 1000, simulation.body(1).totalMass * g / 2000 * 1000)
            require(peakSpeed < 1e-3, "preloaded hanging block should start in equilibrium")
        }
        print(line)
    }
    print("Lab examples load, run to completion and report.")
}
