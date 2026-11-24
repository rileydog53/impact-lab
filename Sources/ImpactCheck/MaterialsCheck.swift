import Foundation
import ImpactPhysics

/// Materials-plan gates: absolute strength in pascals, sourced toughness,
/// and exact equivalence with the legacy fraction-of-E path.
func materialsCheck() throws {
    // 1. Legacy settings encode with no new keys, so saved files stay byte-identical.
    let legacy = MaterialFractureSettings()
    let text = String(decoding: try JSONEncoder().encode(legacy), as: UTF8.self)
    require(!text.contains("\"strength\"") && !text.contains("energySource"), "Legacy fracture encoding gained keys: \(text)")
    require(try JSONDecoder().decode(MaterialFractureSettings.self, from: Data(text.utf8)) == legacy, "Legacy round trip")
    print("Legacy fracture settings encode unchanged: \(text)")

    // 2. strength = fraction x E in pascals replays bit-for-bit like the legacy fraction.
    func fingerprint(_ scene: AssemblyScene) throws -> (UInt64, Double) {
        require(scene.issues().isEmpty, "Scene issues: \(scene.issues())")
        var run = try AssemblyRun(scene)
        var replay = AssemblyReplay(run)
        while run.step(recording: &replay) {}
        replay.finish(run)
        require(run.simulation.failure == nil && run.finished, run.simulation.failure ?? "ended early")
        return (replayFingerprint(replay), replay.frames.last!.energies.fracture)
    }
    let base = AssemblyScene.bendingFractureExample()
    var absolute = base
    absolute.parts[0].fracture!.strength = base.parts[0].material.young * base.parts[0].fracture!.strengthFraction
    let (a, fa) = try fingerprint(base), (b, fb) = try fingerprint(absolute)
    require(a == b && fa == fb && fa > 0, "Absolute strength equal to fraction x E must replay identically (\(String(a, radix: 16)) vs \(String(b, radix: 16)))")
    print("Absolute strength \(absolute.parts[0].fracture!.strength!) Pa replays identically to fraction 0.030 x E: fingerprint \(String(a, radix: 16)), fracture energy \(fa) J/m")

    // 3. Sourced estimates: 6061 has one with a citation; the rest are off with a reason.
    for profile in MaterialProfile.references {
        switch profile.fractureEstimate {
        case let .available(strength, energy, source):
            require(profile.id != "copper-c11000-annealed" && source.status == "estimated" && source.url.hasPrefix("https://")
                    && !source.citation.isEmpty, "Estimate carries status and citation")
            if profile.id == "aluminum-6061-t6" {
                let expected = 29e6 * 29e6 * (1 - 0.33 * 0.33) / 68.9e9
                require(abs(energy - expected) < 1e-9 * expected, "G = K²(1−ν²)/E")
            }
            require(energy > 0.5 && energy <= MaterialFractureSettings.absoluteEnergyRange.upperBound, "Energy inside range")
            print(String(format: "%@: estimated strength %.0f MPa, fracture energy %.0f J/m² (%@)", profile.name, strength / 1e6, energy, source.citation))
                    case let .unavailable(reason):
            require(profile.defaultFracture == nil && !reason.isEmpty, "Unavailable estimate has a reason and no settings")
            print("\(profile.name): fracture toughness off. \(reason)")
        }
    }

    // 4. A 6061 body with the estimate runs, and the timestep cost is reported.
    var scene = AssemblyScene.metalImpactExample()
    MaterialProfile.aluminum6061.apply(to: &scene.parts[0], elasticOnly: true)
    let plainDt = try AssemblyRun(scene).simulation.dt
    scene.parts[0].fracture = MaterialProfile.aluminum6061.defaultFracture
    require(scene.issues().isEmpty, "6061 with estimate is valid: \(scene.issues())")
    let fractured = try AssemblyRun(scene)
    require(fractured.simulation.initialIssue == nil, fractured.simulation.initialIssue ?? "")
    print(String(format: "6061 with estimate: dt %.4g s vs %.4g s without fracture (%.1fx smaller)", fractured.simulation.dt, plainDt, plainDt / fractured.simulation.dt))
    for profile in [MaterialProfile.structuralSteel, MaterialProfile.stainless304] {
        var metal = AssemblyScene.metalImpactExample()
        profile.apply(to: &metal.parts[0], elasticOnly: true)
        metal.parts[0].fracture = profile.defaultFracture
        require(metal.issues().isEmpty, "\(profile.name) with estimate valid: \(metal.issues())")
        let run = try AssemblyRun(metal)
        require(run.simulation.initialIssue == nil, run.simulation.initialIssue ?? "")
        print(String(format: "%@ with estimate: dt %.4g s", profile.name, run.simulation.dt))
    }
    var legacyProfile = scene
    legacyProfile.parts[0].fracture = MaterialFractureSettings()
    require(!legacyProfile.issues().isEmpty, "Fraction-of-E fracture on a metal profile is still rejected")

    // 5. Document format.
    func errors(_ json: String) -> [String] {
        do { _ = try AssemblyScene.document(Data(json.utf8)); return [] }
        catch let error as SceneDocumentError { return error.issues } catch { return [error.localizedDescription] }
    }
    let part = #"{"name": "A", "size": [0.05, 0.05]"#
    let both = errors(#"{"parts": [\#(part), "fracture": {"strength": 3e8, "strengthFraction": 0.03, "energy": 100}}]}"#)
    require(both.contains { $0.contains("not both") }, "strength and strengthFraction exclusive: \(both)")
    let noEnergy = errors(#"{"parts": [\#(part), "fracture": {"strength": 3e8}}]}"#)
    require(noEnergy.contains { $0.contains("no default is assumed") }, "energy required: \(noEnergy)")
    let high = errors(#"{"parts": [\#(part), "material": {"young": 7e10, "density": 2700, "poisson": 0.33}, "fracture": {"strength": 3e8, "energy": 20000}}]}"#)
    require(high.isEmpty, "Metal-scale strength and energy accepted: \(high)")
    let fractionHigh = errors(#"{"parts": [\#(part), "fracture": {"energy": 20000}}]}"#)
    require(fractionHigh.contains { $0.contains("fracture.energy") }, "Legacy 50 J/m² cap unchanged: \(fractionHigh)")
    print("Scene document: strength (Pa) accepted with explicit energy; legacy cap, exclusivity and missing-energy errors verified")

    // 6. Reserved slots exist but nothing can set them, and monotone damage is declared.
    let names = MaterialStateSchema.channels.map(\.name)
    require(names.contains("temperature") && names.contains("damage"), "Temperature and damage slots reserved")
    require(MaterialStateSchema.reserved.map(\.name) == ["temperature"], "Only temperature is reserved")
    require(MaterialStateSchema.channels.first { $0.name == "damage" }!.monotonic, "Damage is monotone")
    let thermal = errors(#"{"parts": [{"name": "A", "size": [0.05, 0.05], "temperature": 300}]}"#)
    require(!thermal.isEmpty, "Scene temperature is still rejected: no thermal physics")
    print("State schema: temperature reserved (not computed, rejected in scenes); damage declared monotone 0…1")

    // 7. Run summary text.
    let summaryScene = AssemblyScene.metalImpactExample()
    var summaryRun = try AssemblyRun(summaryScene)
    var summaryReplay = AssemblyReplay(summaryRun)
    while summaryRun.step(recording: &summaryReplay) {}
    summaryReplay.finish(summaryRun)
    let summary = summaryReplay.textSummary(scene: summaryScene, frameIndex: summaryReplay.frames.count / 3)
    require(summary.contains("Shown frame") && summary.contains("Final") && summary.contains("% of run"), "Summary has shown and final state")
    print(summary)
}
