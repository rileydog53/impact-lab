import Foundation
import ImpactPhysics

/// Legacy-replay gate. Every scene that exists before the materials work
/// (shipped JSON examples, showcase scenes, built-in examples) is run to
/// completion and its replay fingerprint, step count and final energies are
/// compared with a recorded baseline taken on the base commit. Any
/// difference, however small, fails.
///
///   ImpactCheck --legacy-replay record PATH   write the baseline
///   ImpactCheck --legacy-replay check PATH    compare with the baseline
func legacyReplayCheck(mode: String, baseline: String) throws {
    var scenes: [(String, AssemblyScene)] = [
        ("builtin/metalImpactExample", .metalImpactExample()),
        ("builtin/enclosureExample", .enclosureExample()),
        ("builtin/bendingFractureExample", .bendingFractureExample()),
    ]
    for directory in ["docs/scene-examples", "docs/showcase"] {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".json") && $0 != "invalid-example.json" }.sorted()
        for file in files {
            scenes.append((directory + "/" + file, try AssemblyScene.open(URL(fileURLWithPath: directory + "/" + file))))
        }
    }
    var lines: [String] = []
    for (name, scene) in scenes {
        var run = try AssemblyRun(scene)
        require(run.simulation.initialIssue == nil, "\(name): \(run.simulation.initialIssue ?? "")")
        var replay = AssemblyReplay(run)
        var steps = 0
        while run.step(recording: &replay) { steps += 1 }
        replay.finish(run)
        require(run.simulation.failure == nil && run.finished, "\(name): \(run.simulation.failure ?? "ended early")")
        let last = replay.frames.last!
        let line = String(format: "%@ steps=%d frames=%d dt=%.17g fingerprint=%@ plastic=%.17g fracture=%.17g",
                          name, steps, replay.frames.count, run.simulation.dt,
                          String(replayFingerprint(replay), radix: 16), last.energies.plastic, last.energies.fracture)
        print(line)
        lines.append(line)
    }
    if mode == "record" {
        try (lines.joined(separator: "\n") + "\n").write(toFile: baseline, atomically: true, encoding: .utf8)
        print("Recorded \(lines.count) legacy scenes to \(baseline)")
    } else {
        let expected = try String(contentsOfFile: baseline, encoding: .utf8).split(separator: "\n").map(String.init)
        for (got, want) in zip(lines, expected) { require(got == want, "Legacy replay differs:\n  now  \(got)\n  base \(want)") }
        require(lines.count == expected.count, "Legacy scene count \(lines.count) differs from baseline \(expected.count)")
        print("Legacy replay identical on \(lines.count) scenes (bit-for-bit fingerprints, steps, dt, energies)")
    }
}
