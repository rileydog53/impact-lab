import Foundation
import ImpactPhysics

// Layered target plan, step 7: the three editable laminate presets (docs/layered-examples, also built into the app).
// Each must load, match the copy built into the app, save and reopen identically, and run to its end with the energy
// books balanced (under 2%, the fracture guard's own limit) through the same replay recorder the app uses. The events
// it finds (first crack, delamination, interior crack) are printed. Material values are sourced in each file's
// description; bonds are illustrative. Numerical results, not validation.
func layeredExamplesCheck() throws {
    print("Layered presets (plan step 7). Numerical results, not physical validation.")
    let directory = "docs/layered-examples"
    let files = try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.hasSuffix(".json") }.sorted()
    require(Set(files) == Set(LayeredExample.allCases.map(\.fileName)), "docs/layered-examples and LayeredExample disagree")
    for file in files {
        let text = try String(contentsOfFile: directory + "/" + file, encoding: .utf8)
        let example = LayeredExample.allCases.first { $0.fileName == file }!
        require(text.trimmingCharacters(in: .newlines) == example.json, "\(file) differs from the copy built into the app (LayeredExamples.swift)")
        let scene = try example.scene()
        require(scene.issues().isEmpty, "\(file): " + scene.issues().joined(separator: "; "))
        let saved = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("roundtrip-" + file)
        try scene.save(to: saved)
        require(try AssemblyScene.open(saved) == scene, "\(file): saved scene does not reopen identically")
        try? FileManager.default.removeItem(at: saved)
        var run = try AssemblyRun(scene)
        require(run.simulation.initialIssue == nil, "\(file): \(run.simulation.initialIssue ?? "")")
        var replay = AssemblyReplay(run)
        let initial = run.simulation.initialEnergy
        var worst = 0.0, steps = 0
        let start = ProcessInfo.processInfo.systemUptime
        while !run.finished {
            require(run.step(), "\(file): \(run.simulation.failure ?? "step rejected") at \(run.simulation.time)")
            replay.record(run)
            steps += 1
            worst = max(worst, abs(run.simulation.energies.total - initial) / initial)
            require(steps < 400_000, "\(file): more than 400,000 steps")
        }
        replay.finish(run)
        let sim = run.simulation
        let reading = sim.fractureReading(0)!
        let e = sim.energies
        print(String(format: "  %@: %d steps (dt %.3g µs) in %.1f s; energy error %.4f%%; plastic %.3g J/m, fracture %.3g J/m, viscous %.3g J/m of %.4g J/m; %d inserted faces, %d failed (%d on bonds, %.1f mm delaminated), %d pieces",
                     example.rawValue, steps, 1e6 * sim.dt, ProcessInfo.processInfo.systemUptime - start, 100 * worst,
                     e.plastic, e.fracture, e.viscous, initial, reading.insertedEdges, reading.failedEdges,
                     reading.failedBondEdges, 1000 * reading.bondCrackLength, reading.pieces))
        for event in replay.timeline { print(String(format: "     %8.2f µs  %@", 1e6 * event.time, event.label)) }
        require(worst < 0.02, "\(file): energy error above 2%")
        require(replay.timeline.contains { $0.label.hasPrefix("First crack") }, "\(file): no crack event")
    }
    print("Layered presets check passed.")
}
