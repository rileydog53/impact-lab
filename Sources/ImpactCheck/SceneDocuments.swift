import Foundation
import ImpactPhysics

/// Checks the JSON scene workflow: native files round-trip unchanged, hand-written
/// and generated scenes load with defaults and named references, every unsupported
/// setting is reported, and the examples run and re-export.
func sceneDocumentsCheck(examples directory: URL) throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("impact-scene-documents-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    // 1. Every built-in scene is read back exactly as the previous decoder read it.
    var builtIn: [(String, AssemblyScene)] = [
        ("Enclosure example", .enclosureExample()), ("Bending fracture example", .bendingFractureExample()),
        ("Metal impact example", .metalImpactExample()), ("Bonded wave example", .bondedWaveExample()),
    ]
    for preset in AssemblyExperimentPreset.allCases { builtIn.append((preset.rawValue, preset.scene())) }
    for scenario in LabScenario.allCases {
        for index in 0..<2 { builtIn.append(("\(scenario.rawValue) \(index)", scenario.scene(scenario.defaultSettings, case: index))) }
    }
    for (name, scene) in builtIn {
        let url = temp.appendingPathComponent("native.json")
        try scene.save(to: url)
        let data = try Data(contentsOf: url)
        let legacy = try JSONDecoder().decode(AssemblyScene.self, from: data)
        let reopened = try AssemblyScene.open(url)
        require(reopened == scene && reopened == legacy, "\(name) round-trips unchanged through the scene reader")
        require(scene.issues().isEmpty, "\(name) reports no issues: \(scene.issues())")
    }
    print("Native round trip: \(builtIn.count) built-in scenes identical to the previous decoder")

    // 2. The explanations appear exactly when the solver's own validation rejects a scene.
    var generator = SystemRandomNumberGenerator()
    var rejected = 0
    let bases = [AssemblyScene.enclosureExample(), .bendingFractureExample(), .metalImpactExample(),
                 AssemblyExperimentPreset.bondedComposite.scene(), AssemblyExperimentPreset.angledPanels.scene()]
    for trial in 0..<3000 {
        var scene = bases[trial % bases.count]
        scene.gauges = nil
        let i = Int.random(in: 0..<scene.parts.count, using: &generator)
        let wide = { (low: Double, high: Double) in Double.random(in: low...high, using: &generator) }
        switch Int.random(in: 0..<16, using: &generator) {
        case 0: scene.parts[i].size.x = wide(0.0, 0.4)
        case 1: scene.parts[i].size.y = wide(0.0, 0.4)
        case 2: scene.parts[i].center.x = wide(-1.3, 1.3)
        case 3: scene.parts[i].angle = wide(-400, 400)
        case 4: scene.parts[i].velocity.y = wide(-180, 180)
        case 5: scene.parts[i].material.young = pow(10, wide(4, 12))
        case 6: scene.parts[i].material.density = wide(10, 30_000)
        case 7: scene.parts[i].material.poisson = wide(-1, 0.6)
        case 8: scene.parts[i].plasticity.yieldFraction = wide(0, 0.05)
        case 9: scene.duration = wide(0, 0.3)
        case 10: scene.parts[i].wall = wide(0, 0.05)
        case 11: scene.parts[i].fracture = Bool.random(using: &generator) ? MaterialFractureSettings() : nil
            scene.parts[i].fracture?.energy = wide(0, 60)
        case 12: scene.parts[i].notch = AssemblyPart.Notch(); scene.parts[i].notch?.depthFraction = wide(0, 0.5)
        case 13: scene.parts[i].shape = AssemblyPart.Shape.allCases.randomElement(using: &generator)!
        case 14: scene.parts[i].name = Bool.random(using: &generator) ? "" : String(repeating: "x", count: Int(wide(1, 60)))
        default:
            if !scene.connections.isEmpty { scene.connections[0].span = wide(0, 2.2); scene.connections[0].stiffness = wide(0, 300_000) }
            else { scene.parts[i].plasticity.response = .elastoplastic; scene.parts[i].bondedLayer = AssemblyPart.BondedLayer() }
        }
        let solverRejects = (try? AssemblySimulation(scene)) == nil
        let explained = !scene.issues().isEmpty
        require(solverRejects == explained, "Trial \(trial): solver rejects \(solverRejects) but issues \(scene.issues())")
        if solverRejects { rejected += 1 }
    }
    print("Validation explanations: 3000 random edits, \(rejected) rejected, each with a specific message and none without")

    // 3. Hand-written forms and their specific errors.
    func load(_ json: String) throws -> AssemblyScene { try AssemblyScene.document(Data(json.utf8)) }
    func errors(_ json: String) -> [String] {
        do { _ = try load(json); return [] }
        catch let error as SceneDocumentError { return error.issues }
        catch { return [error.localizedDescription] }
    }
    let minimal = try load(#"{"parts": [{"name": "A", "size": [0.05, 0.05]}, {"name": "B", "size": [0.05, 0.05], "center": [0.06, 0], "velocity": [-2, 0]}]}"#)
    require(minimal.parts.count == 2 && minimal.duration == 0.12 && minimal.parts[0].material == Material()
            && minimal.parts[0].plasticity == AssemblyPart("x").plasticity && minimal.parts[1].velocity.x == -2,
            "Minimal scene takes workshop defaults")
    let profiled = try load(#"{"parts": [{"name": "P", "size": [0.05, 0.05], "material": "copper-c11000-annealed"}]}"#)
    var expected = AssemblyPart("P")
    MaterialProfile.copperC110.apply(to: &expected)
    require(profiled.parts[0].material == expected.material && profiled.parts[0].plasticity == expected.plasticity,
            "Profile name expands to the library profile and its hardening table")
    let linked = try load(#"{"parts": [{"name": "A", "id": "left", "size": [0.05, 0.05]}, {"name": "B", "size": [0.05, 0.05], "center": [0.06, 0]}], "connections": [{"first": "left", "second": "B"}], "monitor": "B", "meshResolution": "fine"}"#)
    require(linked.connections[0].first == linked.parts[0].id && linked.connections[0].second == linked.parts[1].id
            && linked.monitor == linked.parts[1].id && linked.resolution == .fine, "Names and readable ids resolve")
    let cases: [(String, String)] = [
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05], "fixed": true}]}"#, "fixed or clamped constraints are not supported"),
        (#"{"gravity": [0, -9.81], "parts": [{"name": "A", "size": [0.05, 0.05]}]}"#, "gravity are not supported"),
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05], "velocty": [1, 0]}]}"#, "did you mean \"velocity\""),
        (#"{"parts": [{"name": "A", "size": [0.01, 0.05]}]}"#, "parts[0] \"A\".size[0] (width) is 0.01 m; allowed 0.025 m to 0.3 m"),
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05], "material": "titanium"}]}"#, "unknown material profile \"titanium\""),
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05]}], "connections": [{"first": "A", "second": "Z"}]}"#, "no body named or with id \"Z\""),
        (#"{"parts": [{"name": "A", "size": "big"}]}"#, "expected a pair of numbers"),
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05], "material": "aluminum-6061-t6", "fracture": {}}]}"#, "cannot be combined with a metal profile"),
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05]}], "duration": 3}"#, "duration is 3 s"),
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05], "plasticity": {"response": "Elastoplastic", "table": {"points": [[0, 3e8], [0.1, 2e8]]}}}]}"#, "never decrease"),
        (#"{"parts": [{"name": "A" "size": [0.05, 0.05]}]}"#, "not valid JSON"),
        (#"{"parts": [{"name": "A", "size": [0.05, 0.05]}], "meshResolution": 9}"#, "use 1–7"),
    ]
    for (json, message) in cases {
        let found = errors(json)
        require(found.contains { $0.contains(message) }, "Expected \"\(message)\" in \(found)")
    }
    print("Hand-written forms: defaults, profiles, named references and \(cases.count) specific errors")

    // 4. The documented examples load, run, and re-export.
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    require(files.count >= 5, "Examples found in \(directory.path)")
    for file in files {
        if file.lastPathComponent == "invalid-example.json" {
            let issues = (try? AssemblyScene.open(file)).map { _ in [String]() } ?? {
                do { _ = try AssemblyScene.open(file); return [] } catch let error as SceneDocumentError { return error.issues } catch { return [] }
            }()
            for text in ["gravity", "fixed", "titanium", "did you mean \"velocity\"", "\"Ceiling\"", "duration is 2 s", "(width) is 0.5 m"] {
                require(issues.contains { $0.contains(text) }, "invalid-example.json explains \(text): \(issues)")
            }
            print("  invalid-example.json: \(issues.count) explained problems")
            issues.forEach { print("    • " + $0) }
            continue
        }
        let scene = try AssemblyScene.open(file)
        var run = try AssemblyRun(scene)
        require(run.simulation.initialIssue == nil, "\(file.lastPathComponent): \(run.simulation.initialIssue ?? "")")
        run.measureWork(parallelFEM: true)
        let started = ProcessInfo.processInfo.systemUptime
        var replay = AssemblyReplay(run)
        var steps = 0
        while run.step(recording: &replay) { steps += 1 }
        replay.finish(run)
        require(run.finished && run.simulation.failure == nil, "\(file.lastPathComponent) ran to completion")
        let initial = replay.frames[0].energies.total
        let drift = replay.frames.map { abs($0.energies.total - initial) / initial }.max()!
        require(drift < 0.02, "\(file.lastPathComponent) energy drift \(drift)")
        let contact = replay.events.contains { $0.label.lowercased().contains("contact") }
        let last = replay.frames.last!
        let behaviors = Set(replay.events.map { $0.label.split(separator: " ").prefix(2).joined(separator: " ") }).sorted().joined(separator: ", ")
        print(String(format: "  %@ final ledger: plastic %.3g J/m, fracture %.3g J/m; events: %@", file.lastPathComponent,
                     last.energies.plastic, last.energies.fracture, behaviors))
        // Export, then import the export: the solver sees the same scene.
        let exported = temp.appendingPathComponent(file.lastPathComponent)
        try scene.save(to: exported)
        require(try AssemblyScene.open(exported) == scene, "\(file.lastPathComponent) export re-imports identically")
        print(String(format: "  %@: %d bodies, %d steps in %.1f s, energy drift %.3f%%, contact %@, export re-imports identically",
                     file.lastPathComponent, scene.parts.count, steps, ProcessInfo.processInfo.systemUptime - started,
                     100 * drift, contact ? "yes" : "no"))
    }
    print("\nScene document checks passed")
}
