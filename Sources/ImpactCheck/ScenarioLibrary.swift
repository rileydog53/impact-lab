import Foundation
import ImpactPhysics

/// Runs each scenario the way the app does and checks its calculated physics.
func scenarioLibraryCheck(only: String? = nil) throws {
    func run(_ scene: AssemblyScene) throws -> LabScenario.Case {
        var solver = try AssemblyRun(scene)
        require(solver.simulation.initialIssue == nil, solver.simulation.initialIssue ?? "")
        solver.measureWork(parallelFEM: true)
        var replay = AssemblyReplay(solver)
        while solver.step(recording: &replay) {}
        replay.finish(solver)
        require(solver.finished && solver.simulation.failure == nil, solver.simulation.failure ?? "Scenario case ended early")
        let initial = replay.frames[0].energies.total
        let drift = replay.frames.map { abs($0.energies.total - initial) / initial }.max()!
        require(drift < 0.02, "Scenario energy drift \(drift)")
        return LabScenario.Case(scene: scene, replay: replay)
    }

    func pair(_ scenario: LabScenario, _ settings: LabScenario.Settings) throws -> (LabScenario.Case, LabScenario.Case, LabScenario.Report) {
        let started = ProcessInfo.processInfo.systemUptime
        let a = try run(scenario.scene(settings, case: 0))
        let b = try run(scenario.scene(settings, case: 1))
        guard let report = scenario.report(a, b) else {
            require(false, "\(scenario.rawValue) produced no report")
            fatalError()
        }
        print("\n\(scenario.rawValue): A = \(scenario.caseLabel(settings, case: 0)), B = \(scenario.caseLabel(settings, case: 1)), speed \(settings.speed) m/s, \(String(format: "%.1f", ProcessInfo.processInfo.systemUptime - started)) s")
        for row in report.rows {
            print("  \(row.label): \(row.first) | \(row.second)" + (row.prediction.map { " | predicted \($0)" } ?? ""))
        }
        print("  → \(report.finding)")
        return (a, b, report)
    }

    for scenario in LabScenario.allCases where only == nil || scenario.rawValue.lowercased().hasPrefix(only!) {
        require(scenario.speedRange.contains(scenario.defaultSettings.speed), "Default speed is in range")
        for index in 0..<2 {
            let scene = scenario.scene(scenario.defaultSettings, case: index)
            let data = try JSONEncoder().encode(scene)
            require(try JSONDecoder().decode(AssemblyScene.self, from: data) == scene, "Scenario scene saves and reopens")
        }
        switch scenario {
        case .elasticContrast:
            let (a, b, _) = try pair(scenario, scenario.defaultSettings)
            let wa = LabScenario.measureWave(a)!, wb = LabScenario.measureWave(b)!
            for w in [wa, wb] {
                require(abs(w.speed / w.predictedSpeed - 1) < 0.08, "Wave speed within 8% of the plane-strain bar speed")
            }
            require(wb.speed < wa.speed, "Copper carries the wave more slowly than steel")
            require(wb.strikerVelocity > wa.strikerVelocity, "Lower-impedance copper leaves the striker moving faster")
            let faster = LabScenario.Settings(first: 0, second: 2, shared: 0, speed: 5)
            let (_, c, _) = try pair(scenario, faster)
            let wc = LabScenario.measureWave(c)!
            require(abs(wc.speed / wc.predictedSpeed - 1) < 0.08, "Aluminum wave speed within 8%")
        case .elasticVersusYielding:
            let (a, b, _) = try pair(scenario, scenario.defaultSettings)
            let ea = LabScenario.measureImpact(a)!, eb = LabScenario.measureImpact(b)!
            require(ea.plasticWork == 0 && ea.peakPlasticStrain == 0, "Elastic case has no plastic work")
            require(eb.plasticWork > 0 && eb.peakPlasticStrain > 0.001, "Yielding case leaves permanent strain")
            require(eb.restitution < ea.restitution, "Yielding lowers the separation speed")
        case .strainHardening:
            let (a, b, _) = try pair(scenario, scenario.defaultSettings)
            let copper = LabScenario.measureImpact(a)!, stainless = LabScenario.measureImpact(b)!
            require(copper.plasticWork > 0 && stainless.plasticWork > 0, "Both metals yield")
            require(stainless.peakStress > copper.peakStress, "Harder 304 stainless carries higher flow stress")
            require(copper.peakPlasticStrain > stainless.peakPlasticStrain, "Copper deforms more permanently")
        case .bondedLayers:
            for option in scenario.secondOptions.indices {
                var settings = scenario.defaultSettings
                settings.second = option
                let (a, b, _) = try pair(scenario, settings)
                let bond = LabScenario.measureBond(control: a, variant: b)!
                require(abs(bond.reflection - bond.predictedReflection) < 0.065, "Reflection agrees with 1D impedance")
                require(abs(bond.transmission - bond.predictedTransmission) < 0.065, "Transmission agrees with 1D impedance")
            }
        case .interfaceFailure:
            let (a, b, _) = try pair(scenario, scenario.defaultSettings)
            let fa = LabScenario.measureFracture(a)!, fb = LabScenario.measureFracture(b)!
            require(fa.firstFailure == nil && fa.fractureEnergy == 0, "Intact case cannot crack")
            require(fb.firstFailure != nil && fb.fractureEnergy > 0 && fb.crackLength > 0, "Cracking case opens a crack")
            var tough = scenario.defaultSettings
            tough.second = 2
            let (_, c, _) = try pair(scenario, tough)
            let fc = LabScenario.measureFracture(c)!
            require((fc.firstFailure ?? .infinity) >= fb.firstFailure!, "Higher fracture energy delays or prevents failure")
        }
    }
    print("\nScenario library checks passed")
}
