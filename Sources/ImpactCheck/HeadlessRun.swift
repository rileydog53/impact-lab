import CryptoKit
import Foundation
import ImpactPhysics

/// Headless runner: runs one saved assembly scene without the GUI and writes machine-readable results.
///
///   ImpactCheck run SCENE.json --out DIR [--timeout SECONDS] [--vtk]
///
/// It uses exactly the same path as the legacy-replay gate (AssemblyScene.open, AssemblyRun,
/// AssemblyReplay, replayFingerprint), so its fingerprint is comparable bit for bit with
/// docs/legacy-replay-baseline.txt. Nothing here changes the solver; it only reads results.
///
/// Writes into DIR:
///   manifest.json   scene hash, git commit, solver settings, material sources, fingerprint, wall time, outcome
///   energy.csv      energy ledger per recorded frame (J per metre of depth)
///   gauges.csv      every gauge reading per frame (only when the scene has gauges)
///   contacts.csv    every reported contact per frame (only when contacts occurred)
///   links.csv       every connection reading per frame (only when the scene has connections)
///   fields.pvd, vtk/  raw per-frame fields for ParaView (only with --vtk; see VTKExport.swift)
///
/// Exit status: 0 finished, 2 scene rejected or solver guard stopped the run, 3 timeout, 64 usage error.
/// A manifest is written in every case except a usage error, so a failed run still says why.
func headlessRun(_ arguments: [String]) -> Never {
    func usage(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\nUsage: ImpactCheck run SCENE.json --out DIR [--timeout SECONDS] [--vtk]\n".utf8))
        exit(64)
    }
    var scenePath: String?, outPath: String?, timeout: Double?, vtk = false
    var i = 0
    while i < arguments.count {
        switch arguments[i] {
        case "--out":
            guard i + 1 < arguments.count else { usage("--out needs a directory") }
            outPath = arguments[i + 1]; i += 2
        case "--vtk":
            vtk = true; i += 1
        case "--timeout":
            guard i + 1 < arguments.count, let t = Double(arguments[i + 1]), t > 0 else { usage("--timeout needs a positive number of seconds") }
            timeout = t; i += 2
        default:
            guard scenePath == nil, !arguments[i].hasPrefix("--") else { usage("Unexpected argument \(arguments[i])") }
            scenePath = arguments[i]; i += 1
        }
    }
    guard let scenePath, let outPath else { usage("Need a scene file and --out") }
    let out = URL(fileURLWithPath: outPath)
    let started = Date()
    let clock = ProcessInfo.processInfo.systemUptime

    var manifest: [String: Any] = [
        "format": "impactlab-run-manifest/1",
        "scene_file": scenePath,
        "started_utc": ISO8601DateFormatter().string(from: started),
        "git_commit": gitCommit(),
        "host": ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                 "cpu_count": ProcessInfo.processInfo.activeProcessorCount],
        "units": ["time": "s", "energy": "J/m (per metre of out-of-plane depth)", "length": "m"],
    ]
    func finish(_ outcome: String, _ code: Int32, message: String? = nil) -> Never {
        manifest["outcome"] = outcome
        if let message { manifest["message"] = message }
        manifest["wall_time_s"] = ProcessInfo.processInfo.systemUptime - clock
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: out.appendingPathComponent("manifest.json"))
        } catch {
            FileHandle.standardError.write(Data("Could not write manifest: \(error.localizedDescription)\n".utf8))
        }
        print("\(outcome): \(message ?? scenePath) -> \(out.path)/manifest.json")
        exit(code)
    }

    let data: Data
    do { data = try Data(contentsOf: URL(fileURLWithPath: scenePath)) }
    catch { finish("unreadable", 2, message: error.localizedDescription) }
    manifest["scene_sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

    let scene: AssemblyScene
    var run: AssemblyRun
    do {
        scene = try AssemblyScene.document(data)
        run = try AssemblyRun(scene)
    } catch { finish("rejected", 2, message: error.localizedDescription) }
    manifest["solver"] = [
        "method": "explicit Lagrangian FEM (AssemblySimulation)",
        "duration_s": scene.duration,
        "mesh_resolution": scene.resolution.label,
        "sample_interval_s": scene.sampleInterval,
        "dt_s": run.simulation.dt,
        "gravity_m_per_s2": scene.gravity ?? 0,
        "bulk_viscosity": scene.bulkViscosity != nil,
        "bodies": scene.parts.count,
        "connections": scene.connections.count,
    ] as [String: Any]
    manifest["materials"] = scene.parts.map { part -> [String: Any] in
        var m: [String: Any] = ["body": part.name, "young_Pa": part.material.young, "density_kg_per_m3": part.material.density,
                                "poisson": part.material.poisson,
                                "response": part.plasticity.response == .elastoplastic ? "elastoplastic (J2)" : "elastic",
                                "fracture": part.fracture != nil]
        if let p = part.material.provenance {
            m["source"] = ["name": p.name, "condition": p.condition, "source": p.sourceName,
                           "url": p.source.absoluteString, "custom": p.isCustom]
        } else { m["source"] = "none recorded (custom values)" }
        return m
    }
    if let issue = run.simulation.initialIssue { finish("rejected", 2, message: issue) }

    var replay = AssemblyReplay(run)
    var steps = 0
    var timedOut = false
    while run.step(recording: &replay) {
        steps += 1
        if let timeout, steps % 256 == 0, ProcessInfo.processInfo.systemUptime - clock > timeout { timedOut = true; break }
    }
    replay.finish(run)
    let last = replay.frames.last!
    manifest["steps"] = steps
    manifest["frames"] = replay.frames.count
    manifest["simulated_time_s"] = last.time
    manifest["replay_fingerprint"] = String(replayFingerprint(replay), radix: 16)
    manifest["final_energy_J_per_m"] = energyRecord(last.energies)
    manifest["events"] = replay.events.map { ["label": $0.label, "time_s": $0.time] as [String: Any] }

    do { manifest["files"] = try writeCSVs(replay, scene: scene, to: out) + (vtk ? VTKExport.write(replay, to: out) : []) }
    catch { finish("write-failed", 2, message: error.localizedDescription) }

    if timedOut { finish("timeout", 3, message: "Stopped after \(timeout!) s wall time at t = \(last.time) s") }
    if let failure = run.simulation.failure { finish("guard-stopped", 2, message: failure) }
    guard run.finished else { finish("ended-early", 2, message: "Run ended before the scene duration") }
    finish("finished", 0)
}

private func energyRecord(_ e: AssemblyEnergy) -> [String: Double] {
    ["kinetic": e.kinetic, "elastic": e.elastic, "contact": e.contact, "connection": e.connection,
     "hardening": e.hardening, "plastic": e.plastic, "fracture": e.fracture, "cohesive": e.cohesive,
     "gravitational": e.gravitational, "viscous": e.viscous, "total": e.total]
}

/// Values are written with full round-trip precision ("\(Double)"), not rounded.
private func writeCSVs(_ replay: AssemblyReplay, scene: AssemblyScene, to out: URL) throws -> [String] {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var written: [String] = []
    func write(_ name: String, _ header: [String], _ rows: [[String]]) throws {
        guard !rows.isEmpty else { return }
        let text = ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try text.write(to: out.appendingPathComponent(name), atomically: true, encoding: .utf8)
        written.append(name)
    }
    func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    func s(_ v: Double) -> String { String(v) }

    let keys = ["kinetic", "elastic", "contact", "connection", "hardening", "plastic", "fracture", "cohesive",
                "gravitational", "viscous", "total"]
    try write("energy.csv", ["time_s"] + keys.map { "\($0)_J_per_m" } + ["peak_relative_penetration", "angular_momentum_kg_m2_per_s_per_m"],
              replay.frames.map { f in
                  let e = energyRecord(f.energies)
                  return [s(f.time)] + keys.map { s(e[$0]!) } + [s(f.peakRelativePenetration), s(f.angularMomentum)]
              })

    let gaugeNames = (scene.gauges ?? []).map(\.name)
    try write("gauges.csv", ["time_s", "gauge", "x_m", "y_m", "vx_m_per_s", "vy_m_per_s", "strain", "pressure_Pa",
                             "von_mises_stress_Pa", "plastic_strain", "damage"],
              replay.frames.flatMap { f in
                  f.gauges.enumerated().map { i, g in
                      [s(f.time), q(i < gaugeNames.count ? gaugeNames[i] : "gauge \(i + 1)"), s(g.position.x), s(g.position.y),
                       s(g.velocity.x), s(g.velocity.y), s(g.strain), s(g.pressure), s(g.equivalentStress),
                       s(g.plasticStrain), s(g.damage)]
                  }
              })

    let names = scene.parts.map(\.name)
    func name(_ i: Int) -> String { i >= 0 && i < names.count ? names[i] : "body \(i)" }
    try write("contacts.csv", ["time_s", "body_a", "body_b", "force_N_per_m", "impulse_N_s_per_m"],
              replay.frames.flatMap { f in
                  f.contacts.map { [s(f.time), q(name(Int($0.pair.x))), q(name(Int($0.pair.y))), s($0.force), s($0.impulse)] }
              })

    try write("links.csv", ["time_s", "connection", "extension_m", "force_N_per_m", "damage", "stored_energy_J_per_m",
                            "fracture_dissipation_J_per_m"],
              replay.frames.flatMap { f in
                  f.links.map { [s(f.time), String($0.connection + 1), s($0.extensionLength), s($0.force), s($0.damage),
                                 s($0.storedEnergy), s($0.fractureDissipation)] }
              })
    return written
}

private func gitCommit() -> String {
    if let sha = ProcessInfo.processInfo.environment["GITHUB_SHA"] { return sha }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["git", "rev-parse", "HEAD"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "unknown" }
    p.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return p.terminationStatus == 0 && !text.isEmpty ? text : "unknown"
}
