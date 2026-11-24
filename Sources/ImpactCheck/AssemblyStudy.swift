import Foundation
import ImpactPhysics
import simd

func assemblyStudyCheck() async throws {
    let scene = AssemblyScene.bondedWaveExample()
    var matched = scene
    matched.parts[1].bondedLayer?.material = scene.parts[1].material
    let loaded = try await AssemblyStudy.run(scene, variation: .current)
    let control = try await AssemblyStudy.run(matched, variation: .current)
    let result = loaded.cases[0], baseline = control.cases[0]
    require(result.failure == nil && baseline.failure == nil, "Bonded wave and matched control complete")

    func average(_ run: AssemblyStudyCase, gauge: Int, between range: ClosedRange<Double>) -> Double {
        let velocities = run.samples.filter { range.contains($0.time) }.map { $0.gauges[gauge].velocity.x }
        require(!velocities.isEmpty, "Wave window contains solver samples")
        return velocities.reduce(0, +) / Double(velocities.count)
    }
    let incident = average(baseline, gauge: 0, between: 0.008...0.009)
    let reflected = average(result, gauge: 0, between: 0.012...0.013)
        - average(baseline, gauge: 0, between: 0.012...0.013)
    let transmitted = average(result, gauge: 1, between: 0.012...0.013)
    let soft = scene.parts[1].material, hard = scene.parts[1].bondedLayer!.material
    let z1 = soft.density * soft.waveSpeed, z2 = hard.density * hard.waveSpeed
    let reflection = (z1 - z2) / (z1 + z2), transmission = 2 * z1 / (z1 + z2)
    let maxResidual = result.samples.map { abs($0.residual) }.max()! / result.samples[0].energy.total
    print(String(format: "Bonded wave: incident %.5f m/s, reflection %+.4f (analytic %+.4f), transmission %.4f (analytic %.4f), sampled energy error %.4f%%",
                 incident, reflected / incident, reflection, transmitted / incident, transmission, maxResidual * 100))
    require(abs(reflected / incident - reflection) < 0.065, "Velocity reflection agrees with small-amplitude impedance")
    require(abs(transmitted / incident - transmission) < 0.065, "Velocity transmission agrees with small-amplitude impedance")
    require(maxResidual < 0.005, "Bonded wave sampled energy error under 0.5%")
    let compressive = result.samples.first { (0.008...0.009).contains($0.time) }!.gauges[0]
    require(compressive.strain < 0 && compressive.pressure > 0 && compressive.equivalentStress > 0,
            "Gauge records compression with the correct pressure and strain signs")

    var direct = try AssemblySimulation(scene)
    let starting = direct.body(0).centerVelocity.x
    var load = 0.0, integrated = 0.0, peak = 0.0
    while direct.step() {
        let next = direct.normalLoad(0, 1)
        integrated += 0.5 * direct.dt * (load + next)
        peak = max(peak, next)
        load = next
    }
    let remaining = direct.body(0).centerVelocity.x
    let momentumLoss = (starting - remaining) * soft.density * scene.parts[0].size.x * scene.parts[0].size.y
    let impulse = result.contacts[0].impulse
    print(String(format: "Bonded normal impulse: %.7f N·s/m, striker momentum loss %.7f N·s/m", impulse, momentumLoss))
    require(abs(impulse - integrated) < 1e-12 && peak == result.contacts[0].peak,
            "Study captures the step-level force peak and trapezoidal scalar impulse")
    require(direct.failure == nil && momentumLoss > 0 && abs(impulse / momentumLoss - 1) < 0.03,
            "The mostly axial contact gives a scalar impulse within 3% of the axial momentum loss")

    let options = AssemblyStudyVariation.mesh(body: scene.parts[1].id, levels: [.fine, .extraFine, .x4])
    let serial = try await AssemblyStudy.run(scene, variation: options, parallel: false)
    let parallel = try await AssemblyStudy.run(scene, variation: options)
    require(Set(parallel.cases.map(\.dt)).count == 1, "Refinement study holds the timestep fixed")
    for (a, b) in zip(serial.cases, parallel.cases) {
        require(a.failure == nil && b.failure == nil && a.triangles == b.triangles && a.steps == b.steps
                && a.contacts[0].impulse == b.contacts[0].impulse
                && a.samples.count == b.samples.count
                && zip(a.samples, b.samples).allSatisfy { left, right in
                    left.time == right.time && left.residual == right.residual
                        && left.gauges.map(\.velocity) == right.gauges.map(\.velocity)
                }, "Parallel cases reproduce serial accepted samples")
        let packet = average(b, gauge: 1, between: 0.012...0.013)
        print(String(format: "  %@: %d triangles, common %.3f µs, transmitted %.5f m/s, scalar impulse %.6f N·s/m",
                     b.label, b.triangles, b.dt * 1e6, packet, b.contacts[0].impulse))
    }
    let speedup = serial.wallTime / parallel.wallTime
    print(String(format: "Bonded mesh study: serial %.3f s, parallel %.3f s (%.2f×)",
                 serial.wallTime, parallel.wallTime, speedup))

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let sceneURL = folder.appendingPathComponent("bonded.json")
    try scene.save(to: sceneURL)
    let restored = try AssemblyScene.open(sceneURL)
    require(restored == scene, "Scene round trip preserves material layer, gauges and resolution")
    let csv = folder.appendingPathComponent("measurements.csv")
    try parallel.exportCSV(to: csv)
    let rows = try String(contentsOf: csv, encoding: .utf8).split(whereSeparator: \.isNewline)
    let lineCount = parallel.cases.reduce(1) { $0 + $1.samples.count }
    require(rows.count == lineCount && rows[0].contains("pressure_Pa") && rows[0].contains("scalar_impulse_Ns_per_m"),
            "CSV includes one row per accepted sample and SI headings")
    let pulseCSV = folder.appendingPathComponent("pulses.csv")
    try parallel.exportPulseCSV(to: pulseCSV)
    let pulseRows = try String(contentsOf: pulseCSV, encoding: .utf8).split(whereSeparator: \.isNewline)
    let pulseCount = parallel.cases.reduce(0) { $0 + $1.contacts.reduce(0) { $0 + ($1.pulses?.pulses.count ?? 0) } }
    require(pulseRows.count == pulseCount + 1 && pulseCount > 0 && pulseRows[0].contains("merge_gap_s")
                && pulseRows[0].contains("averaging_windows_s") && rows[0].contains("peak_penetration_depth_m"),
            "Pulse CSV states merge gap and windows, one row per pulse")
    for item in parallel.cases {
        for contact in item.contacts { if let r = contact.pulses {
            require(abs(r.pulses.map(\.impulse).reduce(0, +) + r.minorImpulse - r.totalImpulse) <= 1e-9 * max(1, r.totalImpulse)
                        && abs(r.totalImpulse - contact.impulse) <= 1e-6 * max(1e-12, contact.impulse),
                    "Pulse impulses add up to the pair impulse")
        } }
    }
    var small = AssemblyScene()
    var block = AssemblyPart("Free elastic block")
    block.velocity = Point(0.05, 0)
    small.parts = [block]
    small.duration = 0.02
    let temporal = try await AssemblyStudy.run(small, variation: .timestep)
    let timestep = temporal.cases[0].dt
    require(temporal.cases.map(\.dt) == [timestep, timestep / 2, timestep / 4]
            && Set(temporal.cases.map(\.triangles)).count == 1 && temporal.cases.allSatisfy { $0.failure == nil },
            "Timestep study halves the step with geometry held fixed")
    try notchGeometryCheck()
    try await instrumentedNotchCheck()
    try selectiveRefinementCheck()
    print("Assembly study checks passed")
}

private func notchGeometryCheck() throws {
    var scene = AssemblyScene.bendingFractureExample()
    var notch = AssemblyPart.Notch()
    notch.centerFraction = 0.17
    notch.depthFraction = 0.37
    scene.parts[0].notch = notch
    scene.parts[0].fracture?.meshPattern = .staggered
    scene.gauges = [AssemblyGauge(body: scene.parts[0].id, name: "Ligament", location: Point(0.02771, 0.0023))]
    let expected = Point(scene.parts[0].size.x * notch.centerFraction, scene.parts[0].size.y * (notch.depthFraction - 0.5))
    for level in AssemblyScene.Resolution.allCases {
        scene.parts[0].refinement = level
        let simulation = try AssemblySimulation(scene)
        let body = simulation.body(0)
        require(body.mesh.boundary.contains { simd_distance(body.mesh.reference[$0.a], expected) < 1e-12 },
                "The authored notch tip is a boundary node at ×\(level.rawValue)")
        let area = body.mesh.elements.reduce(0.0) { sum, element in
            let u = body.mesh.reference[element.b] - body.mesh.reference[element.a]
            let v = body.mesh.reference[element.c] - body.mesh.reference[element.a]
            return sum + 0.5 * (u.x * v.y - u.y * v.x)
        }
        require(abs(area - scene.parts[0].size.x * scene.parts[0].size.y
                    * (1 - notch.widthFraction * notch.depthFraction / 2)) < 1e-12,
                "The notch maintains the analytical section area at ×\(level.rawValue)")
        require(simd_distance(simulation.gaugePosition(0), scene.gauges![0].location) < 1e-12,
                "The reference gauge retains its material location at ×\(level.rawValue)")
    }
}

private func instrumentedNotchCheck() async throws {
    var scene = AssemblyScene.bendingFractureExample()
    var notch = AssemblyPart.Notch()
    notch.depthFraction = 0.005 / scene.parts[0].size.y
    scene.parts[0].notch = notch
    scene.parts[0].refinement = .extraFine
    scene.parts[1].center.x = 0
    scene.duration = 0.030
    scene.gauges = [
        AssemblyGauge(body: scene.parts[0].id, name: "Left of notch", location: Point(-0.025, -0.002)),
        AssemblyGauge(body: scene.parts[0].id, name: "Right of notch", location: Point(0.025, -0.002))
    ]
    let study = try await AssemblyStudy.run(scene, variation: .current)
    let result = study.cases[0]
    let final = result.samples.last!
    let fracture = final.fractures[0]!
    let insertion = result.firstInsertions[0] ?? -1
    print(String(format: "Authored notch ×3: first insertion %.3f ms, %d faces inserted, %d pieces at %.2f ms, sampled residual %.4f%%",
                 insertion * 1000, fracture.insertedEdges, fracture.pieces, final.time * 1000,
                 100 * result.samples.map { abs($0.residual) }.max()! / result.samples[0].energy.total))
    require(result.failure == nil && insertion > 0 && fracture.dissipation > 0,
            "The authored notch runs to completion and records fracture events")
    require(result.samples[0].gauges[0].position == scene.gauges![0].location
            || simd_distance(result.samples[0].gauges[0].position, scene.gauges![0].location) < 1e-12,
            "Gauge starts at its saved material coordinate")
    require(result.samples.allSatisfy { sample in
        sample.gauges.allSatisfy { $0.position.x.isFinite && $0.pressure.isFinite }
    } && final.gauges[0].position != result.samples[0].gauges[0].position,
           "Material-point motion and stress remain measurable across fracture insertion")
}

private func selectiveRefinementCheck() throws {
    var uniform = AssemblyScene.bendingFractureExample()
    uniform.duration = 0.020
    uniform.meshResolution = .x5
    uniform.parts[0].fracture = nil
    var graded = uniform
    for i in graded.parts.indices.dropFirst() { graded.parts[i].refinement = .fine }
    let sharedStep = try min(AssemblySimulation(uniform).dt, AssemblySimulation(graded).dt)
    let reference = try AssemblySimulation(uniform, refinement: uniform.resolution.rawValue, stepLimit: sharedStep)
    let selective = try AssemblySimulation(graded, refinement: graded.resolution.rawValue, stepLimit: sharedStep)

    func run(_ initial: AssemblySimulation, label: String) -> (seconds: Double, triangles: Int, impulse: Double) {
        var sim = initial
        let elements = (0..<sim.bodyCount).reduce(0) { $0 + sim.body($1).mesh.elements.count }
        var load = 0.0, impulse = 0.0, peak = 0.0
        let start = ProcessInfo.processInfo.systemUptime
        while sim.step() {
            let next = sim.normalLoad(0, 1)
            impulse += 0.5 * sim.dt * (load + next)
            load = next
            peak = max(peak, load)
        }
        let seconds = ProcessInfo.processInfo.systemUptime - start
        let imbalance = abs(sim.energies.total / sim.initialEnergy - 1)
        require(sim.failure == nil && imbalance < 0.01 && impulse > 0, "Elastic bending benchmark completes within an energy tolerance")
        print(String(format: "%@: %d triangles, %.3f µs, %.3f s, %.6f N·s/m, peak %.3f N/m, residual %.4f%%",
                     label, elements, sim.dt * 1e6, seconds, impulse, peak, imbalance * 100))
        return (seconds, elements, impulse)
    }
    let all = run(reference, label: "Uniform ×5 bend")
    let mixed = run(selective, label: "Specimen ×5, other bodies ×2 bend")
    print(String(format: "Selective refinement: %.2f× speedup, %.2f%% fewer triangles, %+.3f%% striker impulse change",
                 all.seconds / mixed.seconds, 100 * (1 - Double(mixed.triangles) / Double(all.triangles)),
                 100 * (mixed.impulse / all.impulse - 1)))
    require(abs(mixed.impulse / all.impulse - 1) < 0.05, "Window-integrated striker impulse is within 5% of the uniform mesh")
}
