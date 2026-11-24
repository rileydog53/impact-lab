import Foundation
import ImpactPhysics
import simd

// Layered target plan, steps 2 and 3: material and plasticity per element inside one body,
// and bonded layers that can yield, crack and delaminate (one cohesive law per layer and
// one per bond, Camacho and Ortiz 1996 extrinsic insertion with a linear-softening law).
//
// NUMERICAL VERIFICATION of the implementation only. None of these cases is physical
// validation of a real material or laminate; every material here is illustrative or uses
// elastic constants from the built-in reference profiles.
//
//   ImpactCheck --layered-bodies            all cases (about two minutes on an M4 Air)
//   ImpactCheck --layered-bodies quick      skip the Card 7 reflection sweep

private func runToEnd(_ simulation: inout AssemblySimulation, _ observe: (AssemblySimulation) -> Void = { _ in }) {
    require(simulation.initialIssue == nil, simulation.initialIssue ?? "")
    while simulation.time < simulation.scene.duration {
        require(simulation.step(), simulation.failure ?? "step rejected at t = \(simulation.time)")
        observe(simulation)
    }
}

private func elementLayers(_ part: AssemblyPart, _ simulation: AssemblySimulation, _ index: Int) -> [Int] {
    // Recover each element's layer from its reference centroid (layers are bands across the width).
    let body = simulation.body(index)
    return body.mesh.elements.indices.map { i in
        let c = body.mesh.elements[i]
        let x = (body.mesh.reference[c.a].x + body.mesh.reference[c.b].x + body.mesh.reference[c.c].x) / 3
        let fraction = x / part.size.x + 0.5
        let cuts = [part.bondedLayer!.interfaceFraction] + (part.bondedLayer!.third.map { [$0.interfaceFraction] } ?? [])
        return cuts.filter { fraction > $0 }.count
    }
}

func layeredBodiesCheck(quick: Bool) throws {
    print("Layered bodies (plan steps 2 and 3). Numerical verification, not physical validation.")

    // 1. The per-element plasticity path reproduces the single-model path bit for bit
    //    when every element carries the same model.
    do {
        let scene = AssemblyScene.metalImpactExample()
        var uniform = try AssemblySimulation(scene, refinement: 1, stepLimit: .infinity)
        var perElement = try AssemblySimulation(scene, refinement: 1, stepLimit: .infinity, perElementPlasticity: true)
        runToEnd(&uniform)
        runToEnd(&perElement)
        var identical = uniform.time == perElement.time && uniform.energies.plastic == perElement.energies.plastic
        for i in 0..<uniform.bodyCount {
            identical = identical && uniform.body(i).position == perElement.body(i).position
                && uniform.body(i).velocity == perElement.body(i).velocity
                && uniform.plasticStrain(i) == perElement.plasticStrain(i)
        }
        require(identical, "Per-element J2 path differs from the uniform path")
        print("  1. Per-element J2 with one shared model is bit-identical to the uniform path (metal impact example, \(String(format: "%.1f", uniform.energies.plastic)) J/m plastic work)")
    }

    // 2. Two-region block: a plastic copper layer on the struck side, bonded to an elastic steel layer.
    do {
        var scene = AssemblyScene.metalImpactExample()
        scene.meshResolution = .x4
        var target = scene.parts[0]
        target.name = "Copper on steel"
        var layer = AssemblyPart.BondedLayer()
        layer.interfaceFraction = 0.5
        var steel = AssemblyPart("steel")
        MaterialProfile.structuralSteel.apply(to: &steel, elasticOnly: true)
        layer.material = steel.material
        target.bondedLayer = layer
        scene.parts[0] = target
        require(scene.issues().isEmpty, scene.issues().joined(separator: "; "))
        var simulation = try AssemblySimulation(scene)
        let initial = simulation.initialEnergy
        var worst = 0.0
        runToEnd(&simulation) { worst = max(worst, abs($0.energies.total - initial) / initial) }
        let layers = elementLayers(target, simulation, 0)
        let plastic = simulation.plasticStrain(0)
        let copperPeak = zip(layers, plastic).filter { $0.0 == 0 }.map(\.1).max() ?? 0
        let steelPeak = zip(layers, plastic).filter { $0.0 == 1 }.map(\.1).max() ?? 0
        let energy = simulation.energies
        print(String(format: "  2. Copper (J2) on steel (elastic), 24 m/s, x4 mesh: max energy error %.4f%% (criterion < 0.5%%), plastic work %.1f J/m of %.1f J/m, peak plastic strain copper %.4f, steel %.1g",
                     100 * worst, energy.plastic, initial, copperPeak, steelPeak))
        require(worst < 0.005, "Two-region block energy error \(worst) is not below 0.5%")
        require(copperPeak > 0.001 && energy.plastic > 0, "The copper layer yields")
        require(steelPeak == 0, "The elastic steel layer carries no plastic strain")
    }

    // 3. Two-layer bar pulled apart: it separates along the bond, and the dissipated
    //    fracture energy equals the bond toughness times the bond length.
    do {
        var scene = AssemblyScene()
        var bar = AssemblyPart("Two-layer bar", size: Point(0.20, 0.03))
        bar.material = Material(young: 1e6, density: 1000, poisson: 0)
        bar.refinement = .x4
        var bulk = MaterialFractureSettings()
        bulk.strengthFraction = 0.08 // 80 kPa: never reached (peak stress about 47 kPa).
        bulk.energy = 20
        var bond = MaterialFractureSettings()
        bond.strengthFraction = 0.02 // 20 kPa: reached at the bond, which sits where the stretch peaks.
        bond.energy = 2.0
        bar.fracture = bulk
        var layer = AssemblyPart.BondedLayer()
        layer.material = bar.material
        layer.fracture = bulk
        layer.bond = bond
        bar.bondedLayer = layer
        scene.parts = [bar]
        scene.duration = 0.008
        require(scene.issues().isEmpty, scene.issues().joined(separator: "; "))
        let rate = 15.0 // 1/s; ends move apart at 1.5 m/s each.
        var simulation = try AssemblySimulation(scene, refinement: 1, stepLimit: .infinity) { _, p in Point(rate * p.x, 0) }
        let initial = simulation.initialEnergy
        var worst = 0.0, separated: Double?
        runToEnd(&simulation) { sim in
            worst = max(worst, abs(sim.energies.total - initial) / initial)
            if separated == nil, (sim.fractureReading(0)?.pieces ?? 1) > 1 { separated = sim.time }
        }
        let reading = simulation.fractureReading(0)!
        let expected = bond.energy * bar.size.y
        let ratio = simulation.energies.fracture / expected
        print(String(format: "  3. Bar pulled apart at %.0f/s: %d pieces at %@, bond crack %.2f mm of %.2f mm, %d failed faces (%d on the bond), fracture energy %.5f J/m vs G·h %.5f J/m (ratio %.4f, criterion 0.98–1.02), max energy error %.3f%%",
                     rate, reading.pieces, separated.map { String(format: "%.2f ms", $0 * 1000) } ?? "never",
                     reading.bondCrackLength * 1000, bar.size.y * 1000, reading.failedEdges, reading.failedBondEdges,
                     simulation.energies.fracture, expected, ratio, 100 * worst))
        require(reading.pieces == 2, "The bar separates into two pieces")
        require(abs(reading.bondCrackLength - bar.size.y) < 1e-9, "The whole bond fails")
        require(reading.failedEdges == reading.failedBondEdges, "No crack runs through either layer")
        require(abs(ratio - 1) <= 0.02, "Fracture energy matches bond toughness × bond length")
    }

    // 4. Plastic and cracking layers in one body: a laminated panel struck by a falling weight.
    //    A yielding facing layer, a brittle core layer and a weaker bond (illustrative soft materials).
    do {
        var scene = AssemblyScene()
        var panel = AssemblyPart("Laminated panel", size: Point(0.03, 0.16))
        panel.angle = 90 // Layers stack vertically: the facing is on top.
        panel.refinement = .fine
        panel.material = Material(young: 1.0e6, density: 950, poisson: 0.12)  // brittle core (bottom)
        var core = MaterialFractureSettings()
        core.strengthFraction = 0.03
        core.energy = 4
        panel.fracture = core
        var layer = AssemblyPart.BondedLayer()
        layer.interfaceFraction = 0.6
        layer.material = Material(young: 2.0e6, density: 1200, poisson: 0.2)     // ductile facing (top)
        layer.plasticity = ImpactPlasticity(response: .elastoplastic)
        var bond = MaterialFractureSettings()
        bond.strengthFraction = 0.012
        bond.energy = 1.5
        layer.bond = bond
        panel.bondedLayer = layer
        var weight = AssemblyPart("Falling weight", center: Point(0, 0.0355), size: Point(0.025, 0.04))
        weight.material = Material(young: 3.0e6, density: 2200, poisson: 0.15)
        weight.velocity.y = -2.0
        var left = AssemblyPart("Left support", center: Point(-0.062, -0.0705), size: Point(0.03, 0.11))
        left.material = Material(young: 3.5e6, density: 2500, poisson: 0.1)
        var right = left
        right.id = UUID()
        right.name = "Right support"
        right.center.x = 0.062
        scene.parts = [panel, weight, left, right]
        scene.monitor = panel.id
        scene.duration = 0.06
        require(scene.issues().isEmpty, scene.issues().joined(separator: "; "))
        var simulation = try AssemblySimulation(scene)
        runToEnd(&simulation)
        let reading = simulation.fractureReading(0)!
        let layers = elementLayers(panel, simulation, 0)
        let plastic = simulation.plasticStrain(0)
        let facingPeak = zip(layers, plastic).filter { $0.0 == 1 }.map(\.1).max() ?? 0
        let corePeak = zip(layers, plastic).filter { $0.0 == 0 }.map(\.1).max() ?? 0
        let energy = simulation.energies
        let error = abs(energy.total - simulation.initialEnergy) / simulation.initialEnergy
        print(String(format: "  4. Laminated panel, 2 m/s: ran to %.0f ms, energy error %.3f%%, plastic work %.4f J/m (facing peak %.4f, core %.1g), %d failed faces (%d on the bond, %.1f mm delaminated), %d pieces, fracture energy %.4f J/m",
                     simulation.time * 1000, 100 * error, energy.plastic, facingPeak, corePeak, reading.failedEdges,
                     reading.failedBondEdges, reading.bondCrackLength * 1000, reading.pieces, energy.fracture))
        require(corePeak == 0, "The elastic core layer carries no plastic strain")
        require(error < 0.02, "Energy balance within the 2% fracture gate")
    }

    // 5. Scene files: per-layer plasticity, cracks and bonds read, save and reopen; older files
    //    gain no new keys when saved again.
    do {
        let text = """
        { "duration": 0.001, "parts": [ { "name": "Panel", "size": [0.1, 0.03],
            "material": { "young": 1e6, "density": 1000 },
            "fracture": { "strengthFraction": 0.03, "energy": 5 },
            "bondedLayer": { "interfaceFraction": 0.5, "material": { "young": 2e6, "density": 1200 },
              "plasticity": { "response": "elastoplastic", "yieldFraction": 0.02 },
              "fracture": { "strength": 50000, "energy": 8 }, "bond": { "strength": 20000, "energy": 2 },
              "third": { "interfaceFraction": 0.8, "material": { "profile": "copper-c11000-annealed", "elasticOnly": false },
                         "bond": { "strength": 1e6, "energy": 100 } } } } ] }
        """
        let scene = try AssemblyScene.document(Data(text.utf8))
        let layer = scene.parts[0].bondedLayer!
        require(layer.plasticity?.response == .elastoplastic && layer.plasticity?.yieldFraction == 0.02, "Layer plasticity reads")
        require(layer.fracture?.strength == 50000 && layer.bond?.energy == 2, "Layer crack and bond settings read")
        require(layer.third?.plasticity?.table != nil, "A metal profile with elasticOnly false brings its hardening table")
        require(layer.third?.fracture == nil && layer.third?.bond?.strength == 1e6, "Third layer settings read")
        let data = try JSONEncoder().encode(scene)
        require(try JSONDecoder().decode(AssemblyScene.self, from: data) == scene, "Layered scene saves and reopens")
        let legacy = try AssemblyScene.open(URL(fileURLWithPath: "docs/scene-examples/layered-panel.json"))
        let saved = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(legacy)) as! [String: Any]
        let savedLayer = ((saved["parts"] as! [[String: Any]])[0]["bondedLayer"] as! [String: Any])
        require(Set(savedLayer.keys) == ["interfaceFraction", "material", "third"]
                && Set((savedLayer["third"] as! [String: Any]).keys) == ["interfaceFraction", "material"],
                "A saved legacy layered scene gains no new layer keys")
        require(legacy.parts[0].bondedLayer?.plasticity == nil && legacy.parts[0].bondedLayer?.third?.plasticity == nil,
                "Profiles named in legacy layers stay elastic")
        var noFracture = scene
        noFracture.parts[0].fracture = nil
        require(noFracture.issues().contains { $0.contains("need fracture switched on") }, "Layer crack settings without body fracture are explained")
        print("  5. Scene files: layer plasticity, cracks and bonds read and reopen; legacy layered file unchanged")
    }

    // 6. Card 7 bonded-layer reflection, run as the Assembly tab's scenario does, with the permanent
    //    bond and with breakable layers (fracture on, strong bond). Criterion: within 0.008 of 1D impedance.
    if !quick {
        func run(_ scene: AssemblyScene) throws -> LabScenario.Case {
            var solver = try AssemblyRun(scene)
            require(solver.simulation.initialIssue == nil, solver.simulation.initialIssue ?? "")
            solver.measureWork(parallelFEM: true)
            var replay = AssemblyReplay(solver)
            while solver.step(recording: &replay) {}
            replay.finish(solver)
            require(solver.finished && solver.simulation.failure == nil, solver.simulation.failure ?? "Scenario case ended early")
            return LabScenario.Case(scene: scene, replay: replay)
        }
        let scenario = LabScenario.bondedLayers
        for shared in scenario.sharedOptions.indices {
            var settings = scenario.defaultSettings
            settings.shared = shared
            let started = ProcessInfo.processInfo.systemUptime
            let control = try run(scenario.scene(settings, case: 0))
            var worst = 0.0
            var cells: [String] = []
            for option in scenario.secondOptions.indices {
                settings.second = option
                let variant = try run(scenario.scene(settings, case: 1))
                let bond = LabScenario.measureBond(control: control, variant: variant)!
                let error = max(abs(bond.reflection - bond.predictedReflection), abs(bond.transmission - bond.predictedTransmission))
                worst = max(worst, error)
                cells.append(String(format: "%@ R %+.4f (1D %+.4f) T %.4f (1D %.4f)",
                                    scenario.secondOptions[option], bond.reflection, bond.predictedReflection,
                                    bond.transmission, bond.predictedTransmission))
                if shared == 1 {
                    let reading = variant.replay.frames.last!.bodies[1].fracture
                    require((reading?.insertedEdges ?? 0) == 0, "The strong breakable bond does not crack under the small pulse")
                }
            }
            print(String(format: "  6. Card 7 bonded layers, %@: worst |error| %.4f (criterion < 0.008), %.0f s",
                         scenario.sharedOptions[shared], worst, ProcessInfo.processInfo.systemUptime - started))
            for cell in cells { print("       " + cell) }
            require(worst < 0.008, "Bonded-layer reflection and transmission within 0.008 of 1D impedance (\(scenario.sharedOptions[shared]))")
        }
    }
    print("Layered bodies: all checks passed")
}
