import Foundation
import ImpactPhysics
import simd

private struct OffAxisResult {
    let events: LayeredImpactEvents
    let angleAtReceiver, spinBeforeReceiver, receiverSpeed, fracture, plastic: Double
    let backingTravel, receiverStrain: Double
    let detachedClearance: Double?
    let preReceiverSpeed: Double
    let trace: SceneTrace
}

private func offAxisRun(_ label: String, scene: SceneConfiguration, simulation: Simulation) -> OffAxisResult {
    let initial = simulation.diagnostics
    let momentumScale = scene.first.width * scene.first.height! * scene.first.material.density * scene.speed
    let angularScale = momentumScale * scene.second!.height!
    var run = SceneRun(scene, simulation: simulation)
    var momentumError = 0.0, angularError = 0.0, energyError = 0.0, interfaceWork = 0.0
    var angleAtReceiver = 0.0, angleAtFailure = 0.0, spinBeforeReceiver = 0.0
    var previous = simulation.seamLinkReadings
    var preReceiverSpeed = 0.0
    var receiverSpeed = 0.0, receiverStrain = 0.0, backingTravel = 0.0
    var centerAtFailure = Point.zero
    var minClearance: Double?
    var latestFracture = 0.0
    var sampledFailedFlight = false
    let start = ProcessInfo.processInfo.systemUptime
    while run.step() {
        let s = run.simulation
        let d = s.diagnostics
        momentumError = max(momentumError, simd_length(d.momentum - initial.momentum) / momentumScale)
        angularError = max(angularError, abs(d.angularMomentum - initial.angularMomentum) / angularScale)
        energyError = max(energyError, abs(d.relativeEnergyError))
        let seam = s.seamReadings!
        require(seam.dissipated >= latestFracture - 1e-12, "\(label) healed cohesive links")
        latestFracture = seam.dissipated
        let links = s.seamLinkReadings
        for (a, b) in zip(previous, links) {
            interfaceWork += 0.5 * (a.force + b.force) * (b.opening - a.opening)
        }
        previous = links
        let events = s.impactEvents!
        if events.failure != nil && s.time - events.failure! < s.dt * 0.5 {
            angleAtFailure = s.thirdBody!.orientation
            centerAtFailure = s.thirdBody!.centerOfMass
        }
        if events.receiver != nil && s.time - events.receiver! < s.dt * 0.5 {
            angleAtReceiver = s.thirdBody!.orientation
            if events.failure != nil {
                spinBeforeReceiver = abs((angleAtReceiver - angleAtFailure).remainder(dividingBy: 2 * .pi))
                backingTravel = simd_distance(centerAtFailure, s.thirdBody!.centerOfMass)
            }
        }
        if let failure = events.failure, !sampledFailedFlight, events.receiver == nil, s.time > failure + 0.009 {
            sampledFailedFlight = true
            minClearance = s.secondBody!.boundaryClearance(to: s.thirdBody!)
        }
        if events.failure != nil {
            require(seam.force == 0 && seam.separatedFraction > 1 - 1e-12, "\(label) recovered tensile capacity")
        }
        let options = scene.offAxis!
        let receiverVelocity = s.receiverBody!.centerVelocity - Point(options.receiverVelocityX, options.receiverVelocityY)
        let velocityChange = simd_length(receiverVelocity)
        if events.receiver == nil { preReceiverSpeed = max(preReceiverSpeed, velocityChange) }
        receiverSpeed = max(receiverSpeed, velocityChange)
        receiverStrain = max(receiverStrain, s.receiverStrain!.reduce(0) { max($0, abs($1)) })
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let s = run.simulation
    let events = s.impactEvents!
    let times = [events.strike, events.failure, events.receiver].map {
        $0.map { String(format: "%.3f", 1000 * $0) } ?? "—"
    }.joined(separator: "/")
    let seam = s.seamReadings!
    let workPerArea = interfaceWork / scene.second!.height!
    print(String(format: "%@: dt %.3f µs, strike/failure/receiver %@ ms, backing angle %.2f°, Δ angle after failure %.2f°, receiver Δv %.4f m/s, momentum %.2e, angular %.2e, energy %.3f%%, overlap %.2f%%, G %.5f (work %.5f, Gc %.5f) J/m², plastic %.5f J/m",
                 label, 1e6 * s.dt, times, angleAtReceiver * 180 / .pi, spinBeforeReceiver * 180 / .pi,
                 receiverSpeed, momentumError, angularError, 100 * energyError, 100 * s.peakRelativePenetration,
                 seam.dissipatedPerArea, workPerArea, seam.criticalEnergy, s.plasticDissipation))
    print(String(format: "  backing travel after failure %.2f mm, sampled detached clearance %@, receiver peak |axial strain| %.3f%%, runtime %.2f s",
                 backingTravel * 1000, minClearance.map { String(format: "%.2f mm", 1000 * $0) } ?? "—", 100 * receiverStrain, elapsed))
    require(run.finished && s.failure == nil, s.failure ?? "\(label) did not finish")
    require(momentumError < 1e-11 && angularError < 1e-11 && energyError < 0.005 && s.peakRelativePenetration < 0.08,
            "\(label) exceeded conservation or overlap tolerance")
    if events.failure != nil {
        require(abs(seam.dissipatedPerArea / seam.criticalEnergy - 1) < 1e-12,
                "\(label) mismatch between total fracture dissipation and Gc")
        require(abs(workPerArea / seam.criticalEnergy - 1) < 0.01,
                "\(label) mismatch between integrated cohesive work and Gc")
    }
    return OffAxisResult(events: events, angleAtReceiver: angleAtReceiver, spinBeforeReceiver: spinBeforeReceiver,
                         receiverSpeed: receiverSpeed, fracture: seam.dissipatedPerArea, plastic: s.plasticDissipation,
                         backingTravel: backingTravel, receiverStrain: receiverStrain, detachedClearance: minClearance,
                         preReceiverSpeed: preReceiverSpeed, trace: run.trace)
}

func offAxisImpactCheck() throws {
    let scene = SceneConfiguration.standard(.offAxisImpact)
    let base = try scene.makeSimulation()
    let finer = try scene.refinedOffAxisImpact(refinement: 2, stepScale: 1)
    let common = min(finer.dt, 0.5 * base.dt)
    let reference = offAxisRun("Off-axis impact", scene: scene, simulation: base)
    let half = offAxisRun("Smaller step", scene: scene, simulation: try scene.refinedOffAxisImpact(
        refinement: 1, stepScale: common / base.dt))
    let spatial = offAxisRun("Finer mesh at common step", scene: scene, simulation: try scene.refinedOffAxisImpact(
        refinement: 2, stepScale: common / finer.dt))
    for result in [reference, half, spatial] {
        guard let strike = result.events.strike, let failure = result.events.failure, let receiver = result.events.receiver else {
            require(false, "Expected strike, bond failure and receiver collision")
            return
        }
        require(strike < failure && failure < receiver && scene.duration - receiver > 0.06,
                "The expected sequence and aftermath were not resolved")
        require(result.spinBeforeReceiver > 0.25 && result.backingTravel > 0.012 && (result.detachedClearance ?? 0) > 0.0005
                && result.preReceiverSpeed < 1e-9 && result.receiverSpeed > 0.4 && result.receiverStrain > 0.003 && result.plastic > 0.5,
                "The sequence did not produce detached translation, rotation, plasticity or receiver deformation")
    }

    func sensitivity(_ a: OffAxisResult, _ b: OffAxisResult, label: String, tolerance: Double) {
        let readings = [(a.events.strike!, b.events.strike!), (a.events.failure!, b.events.failure!),
                        (a.events.receiver!, b.events.receiver!), (a.angleAtReceiver, b.angleAtReceiver),
                        (a.backingTravel, b.backingTravel), (a.receiverSpeed, b.receiverSpeed), (a.plastic, b.plastic)]
        let maximum = readings.map { abs($0 - $1) / abs($0) }.max()!
        print(String(format: "%@ max change in primary measurements %.2f%%", label, 100 * maximum))
        require(maximum < tolerance, "\(label) sensitivity exceeded tolerance")
    }
    sensitivity(reference, half, label: "Timestep", tolerance: 0.01)
    // Only change spatial resolution here. Use the common timestep.
    sensitivity(half, spatial, label: "Mesh", tolerance: 0.06)

    var mirrored = scene
    mirrored.offAxis?.strikerOffset *= -1
    mirrored.offAxis?.strikerAngle *= -1
    mirrored.offAxis?.receiverOffset *= -1
    mirrored.offAxis?.receiverAngle *= -1
    let reflection = offAxisRun("Mirrored geometry", scene: mirrored, simulation: try mirrored.makeSimulation())
    require(reflection.angleAtReceiver * reference.angleAtReceiver < 0
            && abs(reflection.angleAtReceiver + reference.angleAtReceiver) < 0.035
            && abs((reflection.events.receiver ?? 0) - reference.events.receiver!) < 0.001,
            "Reflecting the off-axis setup should reverse the rotation with similar contact timing")

    var miss = scene
    miss.offAxis?.receiverOffset = OffAxisSettings.receiverOffsetRange.upperBound
    miss.offAxis?.receiverVelocityY = 0.28
    let missed = offAxisRun("Receiver shifted clear", scene: miss, simulation: try miss.makeSimulation())
    require(missed.events.failure != nil && missed.events.receiver == nil && missed.receiverSpeed < 1e-9,
            "The out-of-path receiver still received an impulse")

    var intact = scene
    intact.seam?.response = .intact
    let bonded = offAxisRun("Intact control", scene: intact, simulation: try intact.makeSimulation())
    require(bonded.events.failure == nil && bonded.fracture == 0 && bonded.trace.samples != reference.trace.samples,
            "The intact bond control failed or produced an identical trace")
}
