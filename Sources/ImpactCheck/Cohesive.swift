import Foundation
import ImpactPhysics

private func cohesivePointCheck() {
    let law = CohesiveLaw(strength: 21_600, finalOpening: 0.008)
    let peak = law.evaluate(opening: law.onset, previousMaximum: 0, canSeparate: true)
    let part = law.evaluate(opening: (law.onset + law.finalOpening) / 2,
                            previousMaximum: peak.maximumOpening, canSeparate: true)
    let unload = law.evaluate(opening: part.maximumOpening / 2,
                              previousMaximum: part.maximumOpening, canSeparate: true)
    let failed = law.evaluate(opening: law.finalOpening, previousMaximum: part.maximumOpening, canSeparate: true)
    let closed = law.evaluate(opening: -law.onset / 2, previousMaximum: failed.maximumOpening, canSeparate: true)
    let reopened = law.evaluate(opening: law.onset, previousMaximum: closed.maximumOpening, canSeparate: true)
    require(peak.traction == law.strength && peak.dissipated == 0, "Cohesive initiation does not match the law")
    require(abs(part.traction / law.strength - 0.5) < 1e-12
            && abs(part.dissipated / law.fractureEnergy - 0.5) < 1e-12,
            "The softening branch is incorrect")
    require(unload.dissipated == part.dissipated && abs(unload.traction / part.traction - 0.5) < 1e-12,
            "Unloading did not follow the degraded secant")
    require(failed.traction == 0 && failed.dissipated == law.fractureEnergy,
            "A fully separated seam did not consume Gc")
    require(closed.traction == -law.contactStiffness * law.onset / 2
            && closed.contactEnergy > 0 && reopened.traction == 0 && reopened.dissipated == failed.dissipated,
            "Reclosure or reopening healed the seam or lost compression")
}

private struct SeamResult {
    let openingWork, dissipation: Double
    let curve: [Double]
    let trace: SceneTrace
}

private func testSeam(_ label: String, scene: SceneConfiguration, simulation: Simulation) -> SeamResult {
    var run = SceneRun(scene, simulation: simulation)
    let separating = scene.seam!.response == .separating
    let criticalOpening = scene.seam!.criticalOpening
    let height = scene.first.height!
    let strength = scene.seam!.strengthFraction * min(scene.first.material.young, scene.second!.material.young)
    let openingEnd = simulation.seamFirstOpeningTime!
    let curveOpenings = (1...20).map { criticalOpening * Double($0) / 20 }
    var curve: [Double] = []
    var previous = simulation.seamReadings!
    var previousLinks = simulation.seamLinkReadings
    var openingWork = 0.0
    var maximumError = 0.0
    var compressiveForce = 0.0
    var compressionAfterSeparation = false
    var opened = false
    var steps = 0
    let start = ProcessInfo.processInfo.systemUptime
    while run.step() {
        steps += 1
        let d = run.simulation.diagnostics
        let seam = run.simulation.seamReadings!
        require(seam.dissipated >= previous.dissipated - 1e-12, "The interface lost fracture history")
        if run.simulation.time <= openingEnd {
            let links = run.simulation.seamLinkReadings
            for (old, new) in zip(previousLinks, links) {
                openingWork += 0.5 * (old.force + new.force) * (new.opening - old.opening) / height
            }
            previousLinks = links
            while curve.count < curveOpenings.count, seam.opening >= curveOpenings[curve.count] {
                let u = (curveOpenings[curve.count] - previous.opening) / (seam.opening - previous.opening)
                curve.append((previous.force + u * (seam.force - previous.force)) / (height * strength))
            }
            opened = opened || seam.separatedFraction > 1 - 1e-12
        } else if seam.force < 0, d.contact > 0 {
            compressionAfterSeparation = compressionAfterSeparation || opened
            compressiveForce = min(compressiveForce, seam.force)
        }
        maximumError = max(maximumError, abs(d.relativeEnergyError))
        previous = seam
    }
    let final = run.simulation.seamReadings!
    let targetEnergy = final.criticalEnergy
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print(String(format: "%@: opening work %.5f, dissipation %.5f, Gc %.5f J/m², closure force %.2f N/m, final gap %.3f mm, work error %.5f%%, %.1f µs/step",
                 label, openingWork, final.dissipatedPerArea, targetEnergy, compressiveForce, 1000 * final.opening,
                 100 * maximumError, elapsed * 1e6 / Double(steps)))
    require(run.finished && run.simulation.failure == nil, run.simulation.failure ?? "\(label) did not finish")
    require(maximumError < 0.01, "\(label) lost work balance")
    require(compressiveForce < -0.01 && run.simulation.peakRelativePenetration < 0.2,
            "\(label) did not reclose with bounded compression")
    if separating {
        require(opened && compressionAfterSeparation, "\(label) did not completely separate and reclose")
        require(final.opening > 0 && abs(final.force) < 1e-8 && run.simulation.diagnostics.contact == 0,
                "\(label) transferred tension after reopening")
        require(abs(final.dissipatedPerArea / targetEnergy - 1) < 1e-10
                && abs(openingWork / targetEnergy - 1) < 0.01,
                "\(label) disagrees with Gc")
        require(curve.count == curveOpenings.count, "\(label) did not trace the full opening curve")
        for (opening, traction) in zip(curveOpenings, curve) {
            let x = opening / criticalOpening
            let predicted = x <= 0.25 ? x / 0.25 : (1 - x) / 0.75
            require(abs(traction - predicted) < 0.02, "\(label) differs from the force–opening envelope")
        }
    } else {
        require(!opened && final.dissipated == 0 && final.force > 0.01,
                "The intact control lost tensile capacity")
    }
    return SeamResult(openingWork: openingWork, dissipation: final.dissipatedPerArea,
                      curve: curve, trace: run.trace)
}

func cohesiveCheck() throws {
    cohesivePointCheck()
    let scene = SceneConfiguration.standard(.layeredSeam)
    var intact = scene
    intact.seam?.response = .intact
    let nominal = try scene.makeSimulation()
    let control = testSeam("Intact seam", scene: intact, simulation: try intact.makeSimulation())
    let reference = testSeam("Separating seam", scene: scene, simulation: nominal)
    let fine = try scene.refinedSeam(rows: 16, stepScale: 1)
    let dt = min(nominal.dt / 2, fine.dt)
    let timeRefined = testSeam("Separating seam, smaller step", scene: scene,
                              simulation: try scene.refinedSeam(rows: 8, stepScale: dt / nominal.dt))
    let meshRefined = testSeam("Separating seam, finer interface at same step", scene: scene,
                              simulation: try scene.refinedSeam(rows: 16, stepScale: dt / fine.dt))
    for (axis, a, b) in [("Timestep", reference, timeRefined), ("Interface mesh", timeRefined, meshRefined)] {
        let curveDelta = zip(a.curve, b.curve).map { abs($0 - $1) }.max()!
        let workDelta = abs(a.openingWork / b.openingWork - 1)
        let dissipatedDelta = abs(a.dissipation / b.dissipation - 1)
        print(String(format: "%@ refinement: max curve change %.4f%% of peak, opening work change %.4f%%, dissipation change %.4f%%",
                     axis, 100 * curveDelta, 100 * workDelta, 100 * dissipatedDelta))
        require(curveDelta < 0.02 && workDelta < 0.01 && dissipatedDelta < 0.01,
                "\(axis) fracture refinement did not converge")
    }
    let compared = reference.trace.matching(control.trace)
    require(compared.count > 100 && compared.last!.reference.y == 0 && compared.last!.current.y > 0,
            "Matched-time comparison did not show the fracture-energy difference")
}
