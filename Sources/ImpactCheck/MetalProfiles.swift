import Foundation
import ImpactPhysics
import simd

func metalProfilesCheck() throws {
    require(Set(MaterialProfile.references.map(\.id)).count == 4, "Metal library IDs are not unique")
    for profile in MaterialProfile.references {
        require(profile.isValid && profile.material.waveSpeed > 3000, "Invalid real-scale profile")
    }

    let copper = MaterialProfile.copperC110
    let table = copper.hardening
    let material = copper.material
    let g = material.young / (2 * (1 + material.poisson))
    let k = material.young / (3 * (1 - 2 * material.poisson))
    let modulus = k + 4 * g / 3
    let initial = table.points[0].stress
    let onset = initial / (2 * g)
    let model = J2Model(material: material, table: table)
    func point(_ strain: Double, _ history: J2History = .init()) -> J2Response {
        model.update(x: Point(exp(strain), 0), y: Point(0, 1), from: history)!
    }
    func tau(_ response: J2Response, _ strain: Double) -> Double { response.piolaX.x * exp(strain) }
    let early = point(0.9 * onset)
    require(early.history.equivalentStrain == 0 && abs(tau(early, 0.9 * onset) / (0.9 * onset * modulus) - 1) < 1e-10,
            "Plane-strain elastic slope or yield onset disagrees")
    require(point(1.001 * onset).history.equivalentStrain > 0, "Yield onset not detected")

    let alpha = 0.010
    let flow = (90 + (130 - 90) * (alpha - 0.005) / (0.02 - 0.005)) * 1e6
    let strain = (flow + 3 * g * alpha) / (2 * g)
    let high = point(strain)
    let hardeningWork = 0.5 * 0.005 * (90e6 - initial) + 0.5 * 0.005 * (90e6 + flow - 2 * initial)
    require(abs(high.history.equivalentStrain - alpha) < 1e-12 && abs(high.equivalentStress / flow - 1) < 1e-10,
            "Return across hardening knots disagrees with analytic solution")
    require(abs(high.hardeningEnergy - hardeningWork) < 1e-5 && abs(high.dissipation - initial * alpha) < 1e-5,
            "Plastic work partition disagrees with the piecewise integral")
    let tail = point((225e6 + 3 * g * 0.14) / (2 * g))
    require(abs(tail.equivalentStress - 225e6) < 1e-3 && abs(tail.history.equivalentStrain - 0.14) < 1e-12,
            "Constant extrapolation failed")
    var invalid = table
    invalid.points[2].stress = invalid.points[0].stress
    require(!invalid.isValid, "Softening table accepted")
    invalid = table
    invalid.points[1].strain = 0
    require(!invalid.isValid, "Repeated strain accepted")
    invalid = table
    invalid.points[0].stress = .infinity
    require(!invalid.isValid, "Nonfinite stress accepted")

    let angle = 0.71
    let u = Point(cos(angle), sin(angle))
    let v = Point(-u.y, u.x)
    let rotated = model.update(x: exp(strain) * u, y: v, from: high.history)!
    require(simd_length(rotated.piolaX - high.piolaX.x * u) < 0.01
            && simd_length(rotated.piolaY - high.piolaY.y * v) < 0.01,
            "Superposed rotation changed the tabulated response")
    require(abs(rotated.cauchyZZ / high.cauchyZZ - 1) < 1e-10, "Out-of-plane stress changed under rotation")
    require(abs(high.cauchyZZ * exp(strain) - (k * strain - 2 * g * strain / 3 + g * alpha)) < 0.01,
            "Plane-strain Cauchy stress disagrees with tau/J")

    let mild = 1.5 * onset
    let loaded = point(mild)
    let residualStrain = 2 * g * loaded.history.equivalentStrain / modulus
    let unloaded = point(residualStrain, loaded.history)
    let reloaded = point(mild, unloaded.history)
    let beyond = point(1.1 * mild, reloaded.history)
    require(residualStrain > 0 && abs(unloaded.piolaX.x) < 0.01
            && abs(tau(loaded, mild) / (modulus * (mild - residualStrain)) - 1) < 1e-10,
            "Unloading slope or permanent set disagrees")
    require(abs(reloaded.history.equivalentStrain - loaded.history.equivalentStrain) < 1e-12
            && abs(reloaded.dissipation - loaded.dissipation) < 1e-5 && beyond.dissipation > reloaded.dissipation,
            "Reloading failed to recover the yield surface")

    var work = 0.0
    var previous = point(0)
    var previousTau = 0.0
    for i in 1...4000 {
        let e = Double(i) * strain / 4000
        let response = point(e, previous.history)
        let currentTau = tau(response, e)
        work += 0.5 * (currentTau + previousTau) * strain / 4000
        require(response.dissipation >= previous.dissipation, "Tabulated plastic dissipation decreased")
        previous = response
        previousTau = currentTau
    }
    let workError = abs(work / (previous.elasticEnergy + previous.hardeningEnergy + previous.dissipation) - 1)
    require(workError < 1e-6 && abs(previous.history.equivalentStrain - alpha) < 1e-10,
            "Integrated Piola work disagrees with the energy sum or step subdivision changed the endpoint")
    print(String(format: "Tabulated J2: yield %.4f%%, residual %.4f%%, Kirchhoff flow %.3f MPa, work residual %.2e",
                 100 * onset, 100 * residualStrain, flow / 1e6, workError))

    let base = AssemblyScene.metalImpactExample()
    var comparison = base
    MaterialProfile.aluminum6061.apply(to: &comparison.parts[0])
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temp) }
    try base.save(to: temp)
    let reopened = try AssemblyScene.open(temp)
    require(reopened == base, "Scene round trip lost metal provenance or inputs")

    var shortRun = try AssemblyRun(base)
    var longSetup = comparison
    longSetup.duration *= 2
    var longRun = try AssemblyRun(longSetup)
    while !shortRun.finished { require(shortRun.step(), "Short assembly trace rejected") }
    while !longRun.finished { require(longRun.step(), "Long assembly trace rejected") }
    let matches = SceneTrace.matching(shortRun.samples, longRun.samples)
    require(matches.count >= 80 && matches.allSatisfy { $0.time == $0.referenceSample.time && $0.time == $0.currentSample.time },
            "Assembly comparison did not align different sampling grids")
    require(matches.last!.referenceSample.plasticDissipation > matches.last!.currentSample.plasticDissipation,
            "Resampled comparison lost the material contrast")

    func measure(_ title: String, _ setup: AssemblyScene, mesh: Int, limit: Double = .infinity) throws
        -> (loss: Double, dt: Double) {
        var run = try AssemblySimulation(setup, refinement: mesh, stepLimit: limit)
        let initialMomentum = run.momentum
        let angular = run.angularMomentum
        var loss = 0.0
        var energyError = 0.0
        while run.step() {
            let energy = run.energies
            require(energy.plastic >= loss - 1e-8, "Assembly plastic dissipation decreased")
            loss = energy.plastic
            energyError = max(energyError, abs(energy.total / run.initialEnergy - 1))
        }
        require(run.failure == nil && run.time >= setup.duration && !run.firstContactTimes.isEmpty,
                run.failure ?? "\(title) did not complete a contact event")
        let momentumError = simd_length(run.momentum - initialMomentum) / simd_length(initialMomentum)
        require(momentumError < 1e-10 && abs(run.angularMomentum - angular) < 1e-9, "\(title) lost momentum")
        require(energyError < 0.01, "\(title) exceeded 1% energy imbalance")
        print(String(format: "%@: dt %.3f µs, plastic %.4f J/m, peak energy error %.3f%%, momentum error %.2e",
                     title, run.dt * 1e6, loss, energyError * 100, momentumError))
        return (loss, run.dt)
    }
    let coarse = try measure("Copper, baseline", base, mesh: 1)
    let aluminum = try measure("6061-T6, same striker and velocity", comparison, mesh: 1)
    let fineDT = try AssemblySimulation(base, refinement: 2, stepLimit: .infinity).dt
    let step = min(coarse.dt / 2, fineDT)
    let time = try measure("Copper, smaller step", base, mesh: 1, limit: step)
    let mesh = try measure("Copper, doubled mesh at same step", base, mesh: 2, limit: step)
    require(coarse.loss > aluminum.loss + 1, "Material substitution did not meaningfully change dissipation")
    let timeChange = abs(time.loss / coarse.loss - 1)
    let meshChange = abs(mesh.loss / time.loss - 1)
    print(String(format: "Copper plastic work sensitivity: timestep %.2f%%, mesh %.2f%%", 100 * timeChange, 100 * meshChange))
    require(timeChange < 0.05 && meshChange < 0.05, "Tabulated impact failed the plastic-work sensitivity gates")
}
