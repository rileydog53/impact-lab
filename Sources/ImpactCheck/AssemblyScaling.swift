import Darwin
import Foundation
import ImpactPhysics

func assemblyScalingCheck(_ workload: String, sceneFile: String? = nil) throws {
    var scene: AssemblyScene
    switch workload {
    case "copper", "elastic", "linear":
        scene = .metalImpactExample()
        scene.meshResolution = .x7
        scene.parts[0].size.y = 0.135
        scene.parts[1].size.y = 0.135
        scene.duration = 0.00025
        if workload == "elastic" { scene.parts[0].plasticity.response = .elastic }
        if workload == "linear" { scene.parts[0].plasticity.table = nil }
    case "enclosure":
        scene = .enclosureExample()
        scene.meshResolution = .x4
        scene.duration = 0.042
        let original = scene.parts
        let copies = original.map { source in
            var part = source
            part.id = UUID()
            part.name += " · second lane"
            part.center.y += 0.25
            return part
        }
        scene.parts += copies
        for var link in scene.connections {
            link.id = UUID()
            link.first = copies[original.firstIndex { $0.id == link.first }!].id
            link.second = copies[original.firstIndex { $0.id == link.second }!].id
            scene.connections.append(link)
        }
    case "fracture":
        scene = .bendingFractureExample()
        scene.meshResolution = .extraFine
    default:
        require(false, "Use copper, elastic, linear, enclosure or fracture for --assembly-scaling.")
        return
    }
    if let sceneFile { try scene.save(to: URL(fileURLWithPath: sceneFile)) }
    let setup = ProcessInfo.processInfo.systemUptime
    var run = try AssemblyRun(scene)
    let parallel = CommandLine.arguments.contains("--parallel-fem")
    run.measureWork(sampleKernels: CommandLine.arguments.contains("--kernel-profile"), parallelFEM: parallel)
    let sim = run.simulation
    require(sim.initialIssue == nil, sim.initialIssue ?? "")
    var replay = AssemblyReplay(run)
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print(String(format: "%@: %d bodies, %d elements, dt %.8g s, setup %.4f s, setup peak RSS %.2f MiB",
                 workload, sim.bodyCount, (0..<sim.bodyCount).reduce(0) { $0 + sim.body($1).mesh.elements.count },
                 sim.dt, ProcessInfo.processInfo.systemUptime - setup, Double(usage.ru_maxrss) / 1048576))
    let initialCPU = cpuSeconds(usage)
    let started = ProcessInfo.processInfo.systemUptime
    var steps = 0
    let retry = CommandLine.arguments.contains("--resume-check")
    var checkpointed = false
    while run.step(recording: &replay) {
        steps += 1
        if retry && steps == 100 {
            let bytes = replay.fieldPayloadBytes
            replay.checkpoint(run)
            require(replay.frames.last?.time == run.simulation.time, "Checkpoint must show last accepted state")
            replay.resume()
            require(replay.fieldPayloadBytes == bytes, "Checkpoint altered recording payload")
            checkpointed = true
        }
    }
    require(!retry || checkpointed, "Resume check did not reach its checkpoint")
    replay.finish(run)
    let wall = ProcessInfo.processInfo.systemUptime - started
    getrusage(RUSAGE_SELF, &usage)
    let final = run.simulation
    require(final.failure == nil && run.finished, final.failure ?? "Run ended early")
    require(!replay.events.isEmpty, "Expected physical contact")
    let imbalance = replay.frames.map { abs($0.energies.total - sim.initialEnergy) / sim.initialEnergy }.max()!
    require(imbalance < 0.02, "Excess energy drift")
    let momentum = replay.frames.map { hypot($0.momentum.x - sim.momentum.x, $0.momentum.y - sim.momentum.y) }.max()!
    require(momentum < 1e-8 * max(1, hypot(sim.momentum.x, sim.momentum.y)), "Momentum regression")
    print(String(format: "%d steps, %d frames, %.4f s wall, %.3f µs/step, %.3f CPU-s, %.2f MiB peak RSS, drift %.6g, momentum %.6g, penetration %.6g",
                 steps, replay.frames.count, wall, wall * 1e6 / Double(steps), cpuSeconds(usage) - initialCPU,
                 Double(usage.ru_maxrss) / 1048576,
                 imbalance, momentum, final.peakRelativePenetration))

    if let work = run.work {
        let payload = final.statePayload
        let el = payload.elasticElements + payload.plasticElements
        print(String(format: "Drift %.3f s, FEM %.3f s, fracture %.3f s, contact %.3f s, integration %.3f s, output %.3f s, parallel position + FEM %.3f s (%d steps)",
                     Double(work.drift) / 1e9, Double(work.fem) / 1e9, Double(work.fracture) / 1e9,
                     Double(work.contact) / 1e9, Double(work.integration) / 1e9, Double(work.output) / 1e9,
                     Double(work.parallelPreparation) / 1e9, work.parallelSteps))
        print(String(format: "State buffers %.2f MiB / %.1f B per element (%d J2, %d traction), replay fields %.2f MiB",
                     Double(payload.bytes) / 1048576, Double(payload.bytes) / Double(el), payload.plasticElements,
                     payload.tractionElements, Double(replay.fieldPayloadBytes) / 1048576))
        let kernel = work.kernel
        if kernel.elements > 0 {
            let count = Double(kernel.elements)
            print(String(format: "Sampled %d element updates: geometry %.1f ns/element, law/history %.1f ns, force scatter %.1f ns (includes timer overhead)",
                         kernel.elements, Double(kernel.kinematics) / count, Double(kernel.constitutive) / count,
                         Double(kernel.scatter) / count))
        }
    }

    // Roll floating-point bit patterns into a fingerprint in replay order.
    var hash: UInt64 = 14695981039346656037
    func add(_ value: Double) { hash = (hash ^ value.bitPattern) &* 1099511628211 }
    for frame in replay.frames {
        [frame.time, frame.energies.kinetic, frame.energies.elastic, frame.energies.hardening,
         frame.energies.plastic, frame.energies.fracture, frame.energies.cohesive, frame.energies.contact,
         frame.energies.connection, frame.angularMomentum, frame.peakRelativePenetration].forEach(add)
        for body in frame.bodies {
            for p in body.body.position { add(p.x); add(p.y) }
            for v in body.body.velocity { add(v.x); add(v.y) }
            for e in body.body.mesh.elements { add(Double(e.a)); add(Double(e.b)); add(Double(e.c)) }
            body.strain.forEach(add)
            body.plasticStrain.forEach(add)
            body.damage.forEach(add)
            for s in body.stress { [s.equivalent, s.pressure, s.maximumPrincipal, s.minimumPrincipal].forEach(add) }
        }
        for c in frame.contacts { add(Double(c.pair.x)); add(Double(c.pair.y)); add(c.force); add(c.impulse) }
        for g in frame.gauges { add(g.strain); add(g.equivalentStress) }
    }
    for e in replay.events { add(e.time) }
    print("Replay fingerprint \(String(hash, radix: 16))")
}

private func cpuSeconds(_ usage: rusage) -> Double {
    Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}
