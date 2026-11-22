import Foundation
import ImpactPhysics
import simd

private struct ImpactResult {
    let releaseSpeed: Double
    let contactTime: Double
}

private func impact(_ label: String, simulation initial: Simulation, speed: Double) -> ImpactResult {
    var simulation = initial
    let start = simulation.diagnostics
    let momentumScale = simd_length(start.momentum)
    let firstImpact = initial.gap / speed
    let timeScale = Material().waveSpeed / initial.body.material.waveSpeed
    let horizon = 2 * firstImpact + 0.11 * timeScale
    var firstContact: Double?
    var lastContact = 0.0
    var energyDrift = 0.0
    var linearDrift = 0.0
    var angularDrift = 0.0
    var puckStrain = 0.0
    var stripStrain = 0.0
    var steps = 0
    let clock = ProcessInfo.processInfo.systemUptime
    while simulation.time < horizon {
        let accepted = simulation.step()
        require(accepted, "\(label) at \(simulation.time * 1000) ms: \(simulation.failure ?? "step rejected")")
        steps += 1
        let d = simulation.diagnostics
        if d.contact > 0 {
            if firstContact == nil { firstContact = simulation.time }
            lastContact = simulation.time
            puckStrain = simulation.strain.reduce(puckStrain) { max($0, abs($1)) }
            stripStrain = simulation.secondStrain!.reduce(stripStrain) { max($0, abs($1)) }
        }
        energyDrift = max(energyDrift, abs(d.relativeEnergyError))
        linearDrift = max(linearDrift, simd_length(d.momentum - start.momentum))
        angularDrift = max(angularDrift, abs(d.angularMomentum - start.angularMomentum))
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - clock
    let puck = simulation.body
    let strip = simulation.secondBody!
    let clearance = puck.boundaryClearance(to: strip)
    let releaseSpeed = strip.centerVelocity.x - puck.centerVelocity.x
    let contactTime = lastContact - (firstContact ?? lastContact)
    print(String(format: "%@: gap %.2f mm, release Δvx %.5f m/s, contact span %.3f ms, overlap %.3f mm (%.2f%% of local edge)",
                 label, 1000 * clearance, releaseSpeed, 1000 * contactTime,
                 1000 * simulation.peakPenetration, 100 * simulation.peakRelativePenetration))
    print(String(format: "  energy imbalance %.3f%%, |Δp| %.2e N·s/m, |ΔL| %.2e N·m·s/m, peak strains %.2f%% / %.2f%%, strip angle %+.2f°, dt %.2f µs, %.1f µs/step",
                 100 * energyDrift, linearDrift, angularDrift, 100 * puckStrain, 100 * stripStrain,
                 strip.orientation * 180 / .pi, simulation.dt * 1e6, elapsed * 1e6 / Double(steps)))
    require(firstContact.map { abs($0 - firstImpact) <= 1.01 * simulation.dt } ?? false,
            "\(label) missed contact at the approaching puck tip")
    require(simulation.diagnostics.contact == 0 && clearance > 0.001
            && releaseSpeed > 0 && horizon - lastContact > 0.010 * timeScale,
            "\(label) did not separate with a positive clearance and opening speed")
    require(simulation.peakRelativePenetration > 0 && simulation.peakRelativePenetration < 0.1,
            "\(label) exceeded 10% overlap relative to a local contact edge")
    require(puckStrain > 1e-4 && stripStrain > 1e-4 && abs(strip.orientation) > 1e-3,
            "\(label) did not deform both bodies and rotate the free strip")
    require(energyDrift < 0.01, "\(label) exceeded 1% peak energy imbalance")
    require(linearDrift < 1e-11 * momentumScale, "\(label) linear momentum drift")
    require(angularDrift < 1e-11 * momentumScale * 0.42, "\(label) angular momentum drift")
    return ImpactResult(releaseSpeed: releaseSpeed, contactTime: contactTime)
}

func puckStripCheck() {
    let speed = 0.4
    let shipped = Preset.puckStrip.makeSimulation(speed: speed)
    let fine = Simulation.puckAndStrip(speed: speed, finerBoundary: true)
    let sharedStep = min(shipped.dt / 2, fine.dt)
    let halfStep = Simulation.puckAndStrip(speed: speed, stepScale: sharedStep / shipped.dt)
    let fineMesh = Simulation.puckAndStrip(speed: speed, stepScale: sharedStep / fine.dt, finerBoundary: true)
    let baseline = impact("Puck and strip", simulation: shipped, speed: speed)
    let timeRefined = impact("Puck and strip, smaller step", simulation: halfStep, speed: speed)
    let spaceRefined = impact("Puck and strip, finer mesh at same step", simulation: fineMesh, speed: speed)
    for (label, a, b) in [("Timestep", baseline, timeRefined), ("Boundary mesh", timeRefined, spaceRefined)] {
        let releaseChange = abs(a.releaseSpeed / b.releaseSpeed - 1)
        let contactChange = abs(a.contactTime / b.contactTime - 1)
        print(String(format: "  %@ refinement: release speed change %.2f%%, contact span change %.2f%%",
                     label, 100 * releaseChange, 100 * contactChange))
        require(releaseChange < 0.05, "\(label) refinement changed release speed by more than 5%")
        require(contactChange < 0.05, "\(label) refinement changed the contact span by more than 5%")
    }

    for young in [0.5e6, 4e6] {
        for density in [500.0, 2500.0] {
            for poisson in [0.0, 0.35] {
                for speed in [0.1, 1.0] {
                    let material = Material(young: young, density: density, poisson: poisson)
                    let label = String(format: "Puck and strip %.1f MPa, %.0f kg/m³, ν=%.2f, %.1f m/s",
                                       young / 1e6, density, poisson, speed)
                    _ = impact(label, simulation: .puckAndStrip(material: material, speed: speed), speed: speed)
                }
            }
        }
    }
}
