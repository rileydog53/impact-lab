import Foundation
import ImpactPhysics
import simd

private func materialPointCheck() {
    let material = Material(poisson: 0.25)
    let yield = 18_000.0, hardening = 320_000.0
    let model = J2Model(material: material, yieldStress: yield, hardening: hardening)
    let g = material.young / (2 * (1 + material.poisson))
    let lambda = material.young * material.poisson / ((1 + material.poisson) * (1 - 2 * material.poisson))
    let modulus = lambda + 2 * g
    let onset = yield / (2 * g)
    let peak = 1.6 * onset
    func response(_ strain: Double, from history: J2History) -> J2Response {
        model.update(x: Point(exp(strain), 0), y: Point(0, 1), from: history)!
    }
    func axialKirchhoff(_ result: J2Response, _ strain: Double) -> Double {
        result.piolaX.x * exp(strain)
    }

    let below = response(onset - 1e-6, from: J2History())
    let above = response(onset + 1e-6, from: below.history)
    require(below.history.equivalentStrain == 0 && above.history.equivalentStrain > 0,
            "J2 yielded outside the analytic onset bracket")
    require(abs(below.equivalentStress - 2 * g * (onset - 1e-6)) < 1e-7, "Elastic trial stress disagrees")
    let high = response(peak, from: above.history)
    let expectedAlpha = (2 * g * peak - yield) / (3 * g + hardening)
    let expectedAxial = modulus * peak - 2 * g * expectedAlpha
    let expectedZZ = (lambda * peak + g * expectedAlpha) / exp(peak)
    require(abs(high.history.equivalentStrain - expectedAlpha) < 1e-12, "Linear isotropic hardening disagrees")
    require(abs(high.equivalentStress - (yield + hardening * expectedAlpha)) < 1e-7,
            "Returned stress is off the hardened yield surface")
    require(abs(axialKirchhoff(high, peak) - expectedAxial) < 1e-7, "Plastic axial stress disagrees")
    require(abs(high.cauchyZZ - expectedZZ) < 1e-7, "Plane-strain out-of-plane stress disagrees")

    let angle = 0.61
    let axis = Point(cos(angle), sin(angle))
    let perpendicular = Point(-axis.y, axis.x)
    let rotated = model.update(x: exp(peak) * axis, y: perpendicular, from: high.history)!
    require(simd_length(rotated.piolaX - high.piolaX.x * axis) < 1e-7
            && simd_length(rotated.piolaY - high.piolaY.y * perpendicular) < 1e-7
            && abs(rotated.history.equivalentStrain - high.history.equivalentStrain) < 1e-12,
            "Superposed rigid rotation changed the material response")

    let unloadStrain = peak - 0.01
    let unloaded = response(unloadStrain, from: high.history)
    let slope = (axialKirchhoff(high, peak) - axialKirchhoff(unloaded, unloadStrain)) / (peak - unloadStrain)
    let residualStrain = 2 * g * expectedAlpha / modulus
    let residual = response(residualStrain, from: unloaded.history)
    require(abs(slope / modulus - 1) < 1e-10,
            "Unloading slope does not match the plane-strain elastic modulus")
    require(abs(residual.piolaX.x) < 1e-7 && abs(residual.history.equivalentStrain - expectedAlpha) < 1e-12,
            "Zero axial stress does not occur at the analytic residual strain")
    require(below.dissipation == 0 && high.dissipation > above.dissipation
            && abs(residual.dissipation - yield * expectedAlpha) < 1e-8,
            "Plastic dissipation is not nonnegative and monotone")
    print(String(format: "J2 material point: yield at %.3f%% log strain, unloading slope %.3f MPa, residual %.4f%%, dissipation %.3f J/m³, peak σzz %.3f kPa",
                 100 * onset, slope / 1e6, 100 * residualStrain, residual.dissipation, high.cauchyZZ / 1000))
}

private struct CouponResult {
    let extensionMM: Double
    let run: SceneRun
}

private func coupon(_ title: String, run initial: SceneRun) -> CouponResult {
    var run = initial
    var count = 0
    var error = 0.0
    var previousDissipation = 0.0
    let clock = ProcessInfo.processInfo.systemUptime
    while run.step() {
        count += 1
        let d = run.simulation.diagnostics
        error = max(error, abs(d.relativeEnergyError))
        require(d.plasticDissipation >= previousDissipation - 1e-10, "\(title) lost plastic dissipation")
        previousDissipation = d.plasticDissipation
    }
    let final = run.simulation
    let elapsed = ProcessInfo.processInfo.systemUptime - clock
    require(run.finished && final.failure == nil, final.failure ?? "\(title) did not finish")
    require(final.appliedTraction == 0 && final.time > final.loadReleaseTime!,
            "\(title) did not reach zero external load")
    let residual = 1000 * (run.residualLength! - run.configuration.first.width)
    let period = run.configuration.first.width / run.configuration.first.material.waveSpeed
    let tail = run.samples.reversed().prefix { $0.time >= run.horizon - 6 * period }
    let span = tail.map(\.values.x).max()! - tail.map(\.values.x).min()!
    print(String(format: "%@: residual %+.4f mm (tail span %.4f mm), mean accumulated plastic strain %.3f%%, dissipation %.3f J/m, peak work balance error %.4f%%, %.1f µs/step",
                 title, residual, span, 100 * final.meanPlasticStrain, previousDissipation, 100 * error, elapsed * 1e6 / Double(count)))
    require(error < 0.01, "\(title) exceeded 1% work-balance error")
    require(span < max(0.15, 0.08 * abs(residual)), "\(title) final length varied too much after unloading")
    require(simd_length(final.diagnostics.momentum) < 1e-9, "\(title) had a net applied force")
    return CouponResult(extensionMM: residual, run: run)
}

func plasticityCheck() throws {
    materialPointCheck()
    let plastic = SceneConfiguration.standard(.tensionCoupon)
    var elastic = plastic
    elastic.tension?.response = .elastic
    let elasticResult = coupon("Elastic coupon", run: try SceneRun(elastic))
    let nominal = coupon("Elastoplastic coupon", run: try SceneRun(plastic))
    let refined = try plastic.refinedTension(columns: 64, rows: 12, stepScale: 1)
    let commonStep = min(nominal.run.simulation.dt / 2, refined.dt)
    let smallerStep = try plastic.refinedTension(columns: 32, rows: 6, stepScale: commonStep / nominal.run.simulation.dt)
    let fine = try plastic.refinedTension(columns: 64, rows: 12, stepScale: commonStep / refined.dt)
    let timeResult = coupon("Elastoplastic coupon, smaller timestep", run: SceneRun(plastic, simulation: smallerStep))
    let meshResult = coupon("Elastoplastic coupon, finer mesh at same step", run: SceneRun(plastic, simulation: fine))
    let timeChange = abs(timeResult.extensionMM / nominal.extensionMM - 1)
    let meshChange = abs(meshResult.extensionMM / timeResult.extensionMM - 1)
    require(abs(elasticResult.extensionMM) < 0.05 && elasticResult.run.simulation.meanPlasticStrain == 0,
            "Elastic coupon failed to recover its initial length")
    require(nominal.extensionMM > 1 && timeResult.extensionMM > 1 && meshResult.extensionMM > 1,
            "A repeatable permanent set did not survive unloading")
    require(timeChange < 0.05 && meshChange < 0.05, "Permanent set failed the 5% refinement gate")
    require(nominal.run.simulation.plasticStrain.contains { $0 > 0 } && nominal.run.simulation.diagnostics.plasticDissipation > 0,
            "The coupon did not retain per-element plastic history")
    let matches = nominal.run.trace.matching(elasticResult.run.trace)
    require(matches.count == nominal.run.samples.count
            && (matches.last?.reference.y ?? .infinity) == 0
            && (matches.last?.current.y ?? 0) > 0,
            "The two loading models did not compare on the shared time grid")
    print(String(format: "Residual extension changed %.3f%% with timestep refinement and %.3f%% with mesh refinement",
                 100 * timeChange, 100 * meshChange))
}

func materialImpactCheck() throws {
    let plastic = SceneConfiguration.standard(.materialImpact)
    var elastic = plastic
    elastic.impactPlasticity?.response = .elastic

    func measure(_ label: String, _ initial: SceneRun) -> (residual: Double, run: SceneRun) {
        var run = initial
        var peakError = 0.0
        var dissipation = 0.0
        var steps = 0
        let start = ProcessInfo.processInfo.systemUptime
        let initialMomentum = run.simulation.diagnostics.momentum.x
        while run.step() {
            steps += 1
            let d = run.simulation.diagnostics
            peakError = max(peakError, abs(d.relativeEnergyError))
            require(d.plasticDissipation >= dissipation, "\(label) lost plastic dissipation")
            dissipation = d.plasticDissipation
        }
        let sim = run.simulation
        require(run.finished && sim.failure == nil, sim.failure ?? "\(label) did not finish")
        require(sim.wallImpulse > 0 && sim.diagnostics.contact == 0 && sim.body.centerVelocity.x < 0,
                "\(label) did not hit and rebound from the wall")
        require(abs(sim.diagnostics.momentum.x + sim.wallImpulse - initialMomentum) < 1e-9,
                "\(label) violated wall impulse balance")
        let residual = 1000 * ((run.residualLength ?? .nan) - run.configuration.first.width)
        let measurementWindow = 6 * run.configuration.first.width / run.configuration.first.material.waveSpeed
        let tail = run.samples.reversed().prefix { $0.time >= run.horizon - measurementWindow }
        let span = tail.map(\.values.x).max()! - tail.map(\.values.x).min()!
        let timePerStep = (ProcessInfo.processInfo.systemUptime - start) * 1e6 / Double(steps)
        print(String(format: "%@: residual length change %+.4f mm (tail span %.4f mm), mean / peak plastic strain %.3f%% / %.3f%%, dissipated %.4f J/m, peak imbalance %.4f%%, %.1f µs/step",
                     label, residual, span, 100 * sim.meanPlasticStrain, 100 * sim.peakPlasticStrain,
                     dissipation, 100 * peakError, timePerStep))
        require(residual.isFinite, "\(label) did not have a full unloaded measurement window")
        require(peakError < 0.01, "\(label) exceeded 1% peak energy imbalance")
        return (residual, run)
    }

    let baseline = measure("Elastic impact", try SceneRun(elastic))
    let nominal = measure("Elastoplastic impact", try SceneRun(plastic))
    let fine = try plastic.refinedImpact(columns: 96, rows: 16, stepScale: 1)
    let commonStep = min(nominal.run.simulation.dt / 2, fine.dt)
    let smallerStep = try plastic.refinedImpact(columns: 48, rows: 8, stepScale: commonStep / nominal.run.simulation.dt)
    let fineStep = try plastic.refinedImpact(columns: 96, rows: 16, stepScale: commonStep / fine.dt)
    let temporal = measure("Elastoplastic impact, smaller timestep", SceneRun(plastic, simulation: smallerStep))
    let spatial = measure("Elastoplastic impact, finer mesh at same step", SceneRun(plastic, simulation: fineStep))
    require(abs(baseline.residual) < 0.1 && baseline.run.simulation.peakPlasticStrain == 0,
            "Elastic impact did not recover")
    require(nominal.residual < -1 && nominal.run.simulation.meanPlasticStrain > 0
            && nominal.run.simulation.diagnostics.plasticDissipation > 0,
            "Elastoplastic impact did not retain a measurable set and plastic history")
    let timeChange = abs(temporal.residual / nominal.residual - 1)
    let meshChange = abs(spatial.residual / temporal.residual - 1)
    print(String(format: "Impact residual refinement: timestep %.3f%%, mesh %.3f%%", 100 * timeChange, 100 * meshChange))
    require(timeChange < 0.05 && meshChange < 0.05, "Impact residual failed 5% independent refinement gate")
    let matches = nominal.run.trace.matching(baseline.run.trace)
    require(matches.count == nominal.run.samples.count
            && matches.last?.reference.y == 0 && (matches.last?.current.y ?? 0) > 0,
            "Impact references did not compare on the shared time grid")
}
