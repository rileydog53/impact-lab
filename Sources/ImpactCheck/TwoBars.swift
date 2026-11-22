import Foundation
import ImpactPhysics
import simd

private func collision(label: String, simulation initial: Simulation, expectedSpeed: Double,
                       checkExchange: Bool = true) {
    var simulation = initial
    let initialDiagnostics = simulation.diagnostics
    let initialMomentum = simd_length(initialDiagnostics.momentum)
    let barLength = 0.5
    let firstImpact = simulation.gap / expectedSpeed
    let end = 2 * firstImpact + 4 * barLength / simulation.body.material.waveSpeed
    var firstContact: Double?
    var lastContact = 0.0
    var peakContact = 0.0
    var energyError = 0.0
    var linearError = 0.0
    var angularError = 0.0
    var steps = 0
    let start = ProcessInfo.processInfo.systemUptime
    while simulation.time < end {
        let accepted = simulation.step()
        require(accepted, "\(label) at \(simulation.time * 1000) ms: \(simulation.failure ?? "step rejected")")
        steps += 1
        let d = simulation.diagnostics
        if d.contact > 0 {
            if firstContact == nil { firstContact = simulation.time }
            lastContact = simulation.time
            peakContact = max(peakContact, d.contact)
        }
        energyError = max(energyError, abs(d.relativeEnergyError))
        linearError = max(linearError, simd_length(d.momentum - initialDiagnostics.momentum))
        angularError = max(angularError, abs(d.angularMomentum - initialDiagnostics.angularMomentum))
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    guard let right = simulation.secondBody else {
        require(false, "Two-bar preset is missing its second body")
        return
    }
    let leftSpeed = simulation.body.centerVelocity
    let rightSpeed = right.centerVelocity
    let clearance = right.position.map(\.x).min()! - simulation.body.position.map(\.x).max()!
    let exchangeError = max(simd_length(leftSpeed), simd_length(rightSpeed - Point(expectedSpeed, 0))) / expectedSpeed
    print(String(format: "%@: final vx %+.6f / %+.6f m/s (exchange error %.3f%%), gap %.2f mm, peak overlap %.3f mm",
                 label, leftSpeed.x, rightSpeed.x, 100 * exchangeError, 1000 * clearance, 1000 * simulation.peakPenetration))
    print(String(format: "  peak energy imbalance %.3f%%, peak penalty %.3f%% of initial KE, |Δp| %.2e N·s/m, |ΔL| %.2e N·m·s/m, dt %.2f µs, %.1f µs/step",
                 100 * energyError, 100 * peakContact / initialDiagnostics.kinetic, linearError, angularError,
                 simulation.dt * 1e6, elapsed * 1e6 / Double(steps)))
    require(firstContact.map { abs($0 - firstImpact) <= 1.01 * simulation.dt } ?? false,
            "First impact was missed or detected early")
    require(peakContact > 0 && simulation.diagnostics.contact == 0 && clearance > 0.005
            && lastContact < simulation.time && rightSpeed.x > leftSpeed.x,
            "Bars must make compressive contact and then separate")
    require(!checkExchange || exchangeError < 0.02, "Small-amplitude velocity exchange error above 2%")
    require(linearError / initialMomentum < 1e-11, "Two-bar linear momentum drift")
    require(angularError / (initialMomentum * barLength) < 1e-11, "Two-bar angular momentum drift")
    require(energyError < 0.01, "Two-bar peak energy imbalance above 1%")
    require(simulation.peakPenetration < 0.2 * 0.025, "Overlap above 20% of a reference contact edge")
    require(simulation.wallImpulse == 0 && simulation.wallAngularImpulse == 0, "Wall reacted in free collision")
}

func twoBarCheck() {
    collision(label: "Small-amplitude bars", simulation: .alignedBars(speed: 0.1), expectedSpeed: 0.1)
    collision(label: "Small-amplitude bars, half timestep",
              simulation: .alignedBars(speed: 0.1, stepScale: 0.5), expectedSpeed: 0.1)
    collision(label: "Two-bar preset", simulation: Preset.twoBars.makeSimulation(), expectedSpeed: 0.4)
    let softDense = Material(young: 0.5e6, density: 2500, poisson: 0.35)
    collision(label: "Soft dense bars at maximum speed",
              simulation: Preset.twoBars.makeSimulation(material: softDense, speed: 1),
              expectedSpeed: 1, checkExchange: false)
    let stiffLight = Material(young: 4e6, density: 500, poisson: 0.35)
    collision(label: "Stiff light bars at minimum speed",
              simulation: Preset.twoBars.makeSimulation(material: stiffLight, speed: 0.1),
              expectedSpeed: 0.1, checkExchange: false)
}
