import Foundation
import ImpactPhysics

private struct ImpactResult {
    let failureTime, reclosureTime, finalOpening, peakOpening, plastic: Double
    let trace: SceneTrace
}

private func runLayeredImpact(_ label: String, _ scene: SceneConfiguration,
                              simulation: Simulation) -> ImpactResult {
    var run = SceneRun(scene, simulation: simulation)
    let initial = simulation.diagnostics
    let height = scene.second!.height!
    var previousLinks = simulation.seamLinkReadings
    var previousDissipation = 0.0
    var interfaceWork = 0.0
    var energyError = 0.0, momentumError = 0.0, peakOpening = 0.0
    var failedCompression = 0.0, greatestFailedTension = 0.0
    var detachedSpeed: Double?, returnSpeed: Double?
    var steps = 0
    let start = ProcessInfo.processInfo.systemUptime
    while run.step() {
        steps += 1
        let s = run.simulation
        let d = s.diagnostics
        let seam = s.seamReadings!
        energyError = max(energyError, abs(d.relativeEnergyError))
        momentumError = max(momentumError, abs(d.momentum.x - initial.momentum.x + s.wallImpulse)
                            / abs(initial.momentum.x))
        require(seam.dissipated >= previousDissipation - 1e-12, "\(label) healed the interface")
        previousDissipation = seam.dissipated
        peakOpening = max(peakOpening, seam.opening)
        let links = s.seamLinkReadings
        for (old, new) in zip(previousLinks, links) {
            interfaceWork += 0.5 * (old.force + new.force) * (new.opening - old.opening) / height
            if s.impactEvents?.failure != nil && new.opening >= 0 {
                greatestFailedTension = max(greatestFailedTension, new.force)
            }
        }
        previousLinks = links
        if s.impactEvents?.failure != nil {
            failedCompression = min(failedCompression, seam.force)
            let backingSpeed = s.thirdBody!.centerVelocity.x
            if detachedSpeed == nil { detachedSpeed = backingSpeed }
            if s.impactEvents?.backstop != nil && backingSpeed < 0 && returnSpeed == nil {
                returnSpeed = backingSpeed
            }
        }
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let s = run.simulation
    let d = s.diagnostics
    let seam = s.seamReadings!
    let events = s.impactEvents!
    let timing = [events.strike, events.failure, events.backstop, events.reclosure].map { time in
        time.map { String(format: "%.3f ms", 1000 * $0) } ?? "—"
    }.joined(separator: " / ")
    print(String(format: "%@: dt %.3f µs, strike/failure/stop/reclosure %@, end/peak opening %.3f/%.3f mm, interface work %.5f, G %.5f J/m², plastic %.4f J/m, peak energy error %.3f%%, momentum residual %.2e, peak relative overlap %.2f%%, %.1f µs/step",
                 label, 1e6 * s.dt, timing, 1000 * seam.opening, 1000 * peakOpening, interfaceWork,
                 seam.dissipatedPerArea, d.plasticDissipation, 100 * energyError, momentumError,
                 100 * s.peakRelativePenetration, 1e6 * elapsed / Double(steps)))

    require(run.finished && s.failure == nil, s.failure ?? "\(label) did not finish")
    require(abs((events.strike ?? -1) - scene.gap / scene.speed) <= 1.001 * s.dt,
            "\(label) missed first contact")
    require(momentumError < 1e-11 && energyError < 0.005 && s.peakRelativePenetration < 0.08,
            "\(label) failed momentum, energy, or overlap tolerance")
    require(d.plasticDissipation > 0 && s.plasticStrain.contains(where: { $0 > 0 })
            && s.secondPlasticStrain.contains(where: { $0 > 0 }), "\(label) did not yield in both active regions")
    if scene.seam?.response == .separating {
        require(events.failure != nil && (detachedSpeed ?? 0) > 0 && seam.opening > scene.seam!.criticalOpening
                && abs(seam.force) < 1e-9 && greatestFailedTension < 1e-9,
                "\(label) lost detached motion or recovered tensile capacity")
        require(abs(seam.dissipatedPerArea / seam.criticalEnergy - 1) < 1e-12
                && abs(interfaceWork / seam.criticalEnergy - 1) < 0.02,
                "\(label) did not balance integrated interface work with Gc")
        if scene.backstopGap != nil {
            let failure = events.failure ?? .infinity
            let stop = events.backstop ?? .infinity
            let reclosure = events.reclosure ?? -.infinity
            require(failure < stop && stop < reclosure
                    && failedCompression < -0.01 && (returnSpeed ?? 0) < 0 && s.wallImpulse > 0,
                    "\(label) did not resolve backing rebound and failed-face recontact")
        } else {
            require(s.wallImpulse == 0 && events.backstop == nil && events.reclosure == nil,
                    "\(label) produced unexpected contact for the reference free specimen")
        }
    } else {
        require(events.failure == nil && events.reclosure == nil && seam.dissipated == 0 && peakOpening > 0,
                "\(label) damaged the intact control or never loaded it in tension")
    }
    return ImpactResult(failureTime: events.failure ?? 0, reclosureTime: events.reclosure ?? 0,
                        finalOpening: seam.opening, peakOpening: peakOpening, plastic: d.plasticDissipation,
                        trace: run.trace)
}

func layeredImpactCheck() throws {
    let scene = SceneConfiguration.standard(.layeredImpact)
    let coarse = try scene.makeSimulation()
    let fine = try scene.refinedLayeredImpact(refinement: 2, stepScale: 1)
    let commonStep = min(0.5 * coarse.dt, fine.dt)
    let reference = runLayeredImpact("Layered impact", scene, simulation: coarse)
    let half = runLayeredImpact("Smaller step", scene, simulation: try scene.refinedLayeredImpact(
        refinement: 1, stepScale: commonStep / coarse.dt))
    let spatial = runLayeredImpact("Finer mesh at common step", scene, simulation: try scene.refinedLayeredImpact(
        refinement: 2, stepScale: commonStep / fine.dt))
    for (axis, first, second) in [("Timestep", reference, half), ("Mesh", half, spatial)] {
        let failure = abs(second.failureTime / first.failureTime - 1)
        let closure = abs(second.reclosureTime / first.reclosureTime - 1)
        let opening = abs(second.peakOpening / first.peakOpening - 1)
        let final = abs(second.finalOpening / first.finalOpening - 1)
        let plastic = abs(second.plastic / first.plastic - 1)
        print(String(format: "%@ sensitivity: failure %.2f%%, reclosure %.2f%%, peak/final opening %.2f/%.2f%%, plastic work %.2f%%",
                     axis, 100 * failure, 100 * closure, 100 * opening, 100 * final, 100 * plastic))
        require(max(failure, closure, opening, final) < 0.05 && plastic < 0.15,
                "\(axis) sensitivity exceeded the integrated reference tolerances")
    }
    var free = scene
    free.backstopGap = nil
    _ = runLayeredImpact("Free specimen", free, simulation: try free.makeSimulation())
    var intact = scene
    intact.seam?.response = .intact
    let control = runLayeredImpact("Intact bond", intact, simulation: try intact.makeSimulation())
    let comparison = reference.trace.matching(control.trace)
    require(comparison.count > 100 && comparison.last!.reference.y == 0 && comparison.last!.current.y > 0
            && comparison.last!.referenceSample.plasticDissipation > comparison.last!.currentSample.plasticDissipation,
            "Layered impact comparison did not show the fracture and plastic dissipation differences")
}

func layeredImpactEnvelopeCheck() throws {
    for (label, material, strength, opening, stopGap, drift) in [
        ("Soft dense", Material(young: 0.5e6, density: 2500, poisson: 0.35),
         0.001, 0.003, 0.006, 0.15),
        ("Stiff light", Material(young: 4e6, density: 500, poisson: 0.35),
         0.016, 0.0002, 0.022, -0.15)
    ] {
        var scene = SceneConfiguration.standard(.layeredImpact)
        scene.first.material = material
        scene.second?.material = material
        scene.third?.material = material
        scene.seam?.strengthFraction = strength
        scene.seam?.criticalOpening = opening
        scene.backstopGap = stopGap
        scene.targetVelocityX = drift
        scene.speed = scene.speedRange.upperBound
        var run = try SceneRun(scene)
        var energy = 0.0
        while run.step() { energy = max(energy, abs(run.simulation.diagnostics.relativeEnergyError)) }
        let s = run.simulation
        print(String(format: "%@ layered impact: peak energy error %.3f%%, peak relative overlap %.2f%%",
                     label, 100 * energy, 100 * s.peakRelativePenetration))
        require(run.finished && s.failure == nil, s.failure ?? "\(label) layered impact did not finish")
        require(s.impactEvents?.strike != nil && s.peakRelativePenetration < 0.15 && energy < 0.01,
                "\(label) layered impact lost contact or energy accuracy")
    }
}
