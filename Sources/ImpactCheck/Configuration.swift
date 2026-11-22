import Foundation
import ImpactPhysics

private func complete(_ configuration: SceneConfiguration) throws -> SceneRun {
    var run = try SceneRun(configuration)
    while run.step() {}
    require(run.finished && run.simulation.failure == nil, run.simulation.failure ?? "Scene did not finish")
    return run
}

func configurationCheck() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("paired.impact.json")
    for preset in Preset.allCases {
        let standard = SceneConfiguration.standard(preset)
        try standard.save(to: url)
        let restored = try SceneConfiguration.open(url)
        require(restored == standard, "A factory preset changed after reopening")
    }

    let standard = SceneConfiguration.standard(.puckStrip)
    var edited = standard
    edited.first.width = 0.146
    edited.second?.width = 0.043
    edited.second?.height = 0.407
    edited.first.material = Material(young: 0.8e6, density: 1200, poisson: 0.10)
    edited.second?.material = Material(young: 1.4e6, density: 900, poisson: 0.15)
    edited.targetX = 0.012
    edited.gap = 0.011
    edited.centerY = -0.043
    edited.puckOffsetY = 0.059
    edited.targetVelocityX = -0.033
    edited.velocityY = 0.02
    edited.speed = 0.48
    try edited.save(to: url)
    let reopened = try SceneConfiguration.open(url)
    require(reopened == edited, "Edited dimensions, materials or initial conditions changed in the file")
    let baseline = try complete(standard)
    let before = try complete(edited)
    let after = try complete(reopened)
    let minimumClearance = after.simulation.body.boundaryClearance(to: after.simulation.secondBody!)
    require(minimumClearance > 0 && after.simulation.diagnostics.contact == 0,
            "The edited bodies failed to separate")
    require(before.samples == after.samples && before.simulation.dt == after.simulation.dt,
            "A saved and reopened scene must reproduce the same trace and timestep")
    require(before.simulation.dt != baseline.simulation.dt, "Comparison needs runs with different physical timesteps")
    let matched = after.trace.matching(baseline.trace)
    require(matched.count == min(baseline.samples.count, after.samples.count) && matched.count > 100,
            "The comparison lost the overlapping time range")
    for (i, sample) in matched.enumerated() {
        require(sample.time == Double(i) * SceneRun.sampleInterval
                && sample.time == after.samples[i].time && sample.time == baseline.samples[i].time,
                "A comparison paired different simulated times")
    }
    require(matched.contains { abs($0.reference.y - $0.current.y) > 0.01 },
            "The edited scene failed to produce a distinct target trace")
    print(String(format: "Scene round trip: %d exactly reproduced samples; %d matched-time comparisons at %.2f ms; edited clearance %.2f mm",
                 after.samples.count, matched.count, 1000 * SceneRun.sampleInterval, 1000 * minimumClearance))

    edited.gap = -1
    try JSONEncoder().encode(edited).write(to: url)
    require((try? SceneConfiguration.open(url)) == nil, "An initially overlapping file was accepted")
    var misaligned = SceneConfiguration.standard(.twoBars)
    misaligned.second?.height = 0.095
    try JSONEncoder().encode(misaligned).write(to: url)
    require((try? SceneConfiguration.open(url)) == nil, "A two-bar file bypassed the shared height")
    try Data("{\"formatVersion\":99}".utf8).write(to: url)
    require((try? SceneConfiguration.open(url)) == nil, "An unsupported file version was accepted")

    try mixedBarContactCheck()
}

private func mixedBarContactCheck() throws {
    var configuration = SceneConfiguration.standard(.twoBars)
    configuration.first.width = 0.45
    configuration.first.height = SceneConfiguration.sizeRange(0.10).lowerBound
    configuration.first.material = Material(young: 4e6, density: 500)
    configuration.second?.width = 0.55
    configuration.second?.height = configuration.first.height
    configuration.second?.material = Material(young: 0.5e6, density: 2500, poisson: 0.35)
    configuration.gap = configuration.gapRange.upperBound
    configuration.targetX = configuration.targetXRange.lowerBound
    configuration.centerY = -0.12
    configuration.targetVelocityX = -0.15
    configuration.velocityY = -0.10
    configuration.speed = 1
    var run = try SceneRun(configuration)
    var maxEnergy = 0.0
    var firstContact: Double?
    while run.step() {
        let d = run.simulation.diagnostics
        maxEnergy = max(maxEnergy, abs(d.relativeEnergyError))
        if firstContact == nil && d.contact > 0 { firstContact = run.simulation.time }
    }
    let final = run.simulation
    require(run.finished && final.failure == nil, final.failure ?? "Mixed bars did not finish")
    let firstImpact = configuration.gap / configuration.speed
    require(firstContact.map { abs($0 - firstImpact) < 1.01 * final.dt } ?? false, "Mixed bars missed first contact")
    require(final.diagnostics.contact == 0 && final.body.boundaryClearance(to: final.secondBody!) > 0,
            "Mixed bars failed to separate")
    require(final.peakRelativePenetration < 0.1 && maxEnergy < 0.01,
            "Mixed bars exceeded the overlap or energy gate")
    print(String(format: "Mixed bars: peak overlap %.3f%% of local edge; peak energy imbalance %.4f%%",
                 100 * final.peakRelativePenetration, 100 * maxEnergy))
}

func bondedBarCheck() throws {
    let standard = SceneConfiguration.standard(.bondedBar)
    for (label, first, second) in [
        ("higher impedance", Material(), Material(young: 4e6)),
        ("lower impedance", Material(young: 4e6), Material()),
        ("identical materials", Material(), Material()),
        ("different materials, equal impedance", Material(young: 2e6), Material(young: 4e6, density: 500))
    ] {
        var configuration = standard
        configuration.first.material = first
        configuration.second?.material = second
        var run = try SceneRun(configuration)
        let body = run.simulation.body
        let interface = body.mesh.interfaceNodes
        require(interface.count == 5 && Set(interface).count == 5 && run.simulation.secondBody == nil,
                "The bond must be a shared column of nodes in one body")
        require(interface.allSatisfy { node in
            let adjoining = body.mesh.elements.filter { [$0.a, $0.b, $0.c].contains(node) }
            let neighbors = adjoining.flatMap { [$0.a, $0.b, $0.c] }
            return neighbors.contains { body.mesh.reference[$0].x < 0 }
                && neighbors.contains { body.mesh.reference[$0].x > 0 }
        }, "An interface node is not shared by both materials")
        let probeX = body.probePosition!.x
        let pulseX = -0.54 * configuration.first.width
        let incidentTime = (probeX - pulseX) / first.waveSpeed
        let reflectedTime = (-probeX - pulseX) / first.waveSpeed
        let window = 0.105 * configuration.first.width / first.waveSpeed
        // Read close to the bond to limit dispersive broadening of the transmitted peak.
        let rightProbeX = 0.10 * configuration.second!.width
        let reference = body.mesh.reference
        let rightColumns = Set(reference.lazy.map(\.x).filter { $0 > 0 })
        let nearX = rightColumns.filter { $0 < rightProbeX }.max()!
        let farX = rightColumns.filter { $0 >= rightProbeX }.min()!
        let nearNodes = reference.indices.filter { reference[$0].x == nearX }
        let farNodes = reference.indices.filter { reference[$0].x == farX }
        let transmittedTime = -pulseX / first.waveSpeed + (nearX + farX) / (2 * second.waveSpeed)
        let firstModulus = first.density * first.waveSpeed * first.waveSpeed
        let secondModulus = second.density * second.waveSpeed * second.waveSpeed
        let start = ProcessInfo.processInfo.systemUptime
        var energyDrift = 0.0
        var transmittedStress = 0.0
        var steps = 0
        while run.step() {
            steps += 1
            energyDrift = max(energyDrift, abs(run.simulation.diagnostics.relativeEnergyError))
            if abs(run.simulation.time - transmittedTime) <= window {
                let position = run.simulation.body.position
                // Cross-section average of the axial strain in the small-amplitude limit.
                let stretchSum = zip(nearNodes, farNodes).reduce(0.0) { sum, nodes in
                    sum + (position[nodes.1].x - position[nodes.0].x) / (farX - nearX)
                }
                let stress = secondModulus * (stretchSum / Double(nearNodes.count) - 1)
                transmittedStress = min(transmittedStress, stress)
            }
        }
        require(run.finished && run.simulation.failure == nil, "The bonded run did not finish")
        require(run.simulation.wallImpulse == 0 && run.simulation.diagnostics.contact == 0, "A free bonded bar contacted a wall")
        let incident = run.samples.filter { abs($0.time - incidentTime) <= window }.map(\.values.x).min() ?? 0
        let reflected = run.samples.filter { abs($0.time - reflectedTime) <= window }.map(\.values.x)
            .max { abs($0) < abs($1) } ?? 0
        require(incident < -1e-3, "The incident compressive pulse did not reach the probe")
        let measured = reflected / incident
        let z1 = first.density * first.waveSpeed
        let z2 = second.density * second.waveSpeed
        let expected = (z2 - z1) / (z1 + z2)
        let transmitted = transmittedStress / (firstModulus * incident / 100)
        let expectedTransmission = 2 * z2 / (z1 + z2)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print(String(format: "Bonded bar %@: reflection %+.4f (predicted %+.4f), transmission %.4f (predicted %.4f), peak energy imbalance %.4f%%, %.1f µs/step",
                     label, measured, expected, transmitted, expectedTransmission, 100 * energyDrift, elapsed * 1e6 / Double(steps)))
        require(abs(measured - expected) < (abs(expected) < 1e-10 ? 0.01 : 0.03),
                "Reflected strain disagrees with the impedance prediction")
        require(abs(transmitted - expectedTransmission) < 0.03,
                "Transmitted stress disagrees with the impedance prediction")
        require(energyDrift < 0.01, "Bonded bar exceeded 1% peak energy imbalance")
    }
}
