import ImpactPhysics
import simd

func assemblyReplayCheck() throws {
    func record(_ scene: AssemblyScene) throws -> (AssemblyRun, AssemblyReplay) {
        var run = try AssemblyRun(scene)
        var replay = AssemblyReplay(run)
        while run.step() { replay.record(run) }
        replay.finish(run)
        require(run.finished && run.simulation.failure == nil, run.simulation.failure ?? "Replay run incomplete")
        require(replay.frames.first?.time == 0 && replay.frames.last?.time == run.simulation.time,
                "Replay skipped the initial or final accepted state")
        require(zip(replay.frames, replay.frames.dropFirst()).allSatisfy { $0.time < $1.time },
                "Frame times not strictly increasing")
        require(replay.events.allSatisfy { replay.frames[replay.index(at: $0.time)].time == $0.time },
                "Event jump does not resolve to the original accepted state")
        return (run, replay)
    }

    let copper = AssemblyScene.metalImpactExample()
    let (run, replay) = try record(copper)
    let sim = run.simulation
    let final = replay.frames.last!
    let firstContact = replay.events.first!
    let contactFrame = replay.frames[replay.index(at: firstContact.time)]
    require(replay.frames.first!.contacts.isEmpty
            && contactFrame.contacts.contains { $0.force > 0 && $0.impulse > 0 && $0.position != nil }
            && final.contacts.first!.impulse > contactFrame.contacts.first!.impulse,
            "Incorrect contact trace or unrecorded contact position")
    require(final.bodies[0].body.position == sim.body(0).position
            && final.bodies[0].plasticStrain == sim.plasticStrain(0)
            && (replay.frames.first!.bodies[0].plasticStrain.max() ?? 1) == 0
            && final.bodies[0].plasticStrain.max()! > 0.02,
            "Replay omitted a solver geometry or plastic history")
    require(replay.frames.allSatisfy {
        abs($0.energies.kinetic + $0.recoverableEnergy + $0.dissipatedEnergy - $0.energies.total) < 1e-8
            && simd_length($0.momentum - final.momentum) < 1e-9
    }, "Energy partition or replayed momentum disagrees")
    for i in final.bodies.indices {
        let stress = final.bodies[i].stress
        require(zip(stress, sim.stress(i)).allSatisfy {
            abs($0.equivalent - $1) <= 1e-6 * max(1, $1) && $0.minimumPrincipal <= $0.maximumPrincipal
        }, "Replay stress derivation disagrees with the existing equivalent stress")
        require(zip(stress, sim.pressure(i)).allSatisfy { abs($0.pressure - $1) < 0.1 },
                "Replay pressure disagrees with the solver")
    }
    require(zip(final.gauges, (copper.gauges ?? []).indices.map(sim.gaugeReading)).allSatisfy {
        $0.position == $1.position && $0.velocity == $1.velocity && $0.equivalentStress == $1.equivalentStress
    }, "Replay gauges differ from accepted solver readings")

    var aluminum = copper
    MaterialProfile.aluminum6061.apply(to: &aluminum.parts[0])
    let (_, other) = try record(aluminum)
    require(other.frames.last!.dissipatedEnergy < 0.2 * final.dissipatedEnergy,
            "Recorded material contrast missing")
    let (_, fracture) = try record(.bendingFractureExample())
    require(fracture.frames[0].bodies[0].cracks.isEmpty
            && fracture.frames.last!.bodies[0].cracks.contains { $0.damage > 0 && $0.separation > 0 }
            && fracture.events.contains { $0.label.hasPrefix("First interface damage") },
            "Replay did not retain the change in fracture topology and face state")
    require(fracture.frames.allSatisfy { frame in
        frame.bodies.allSatisfy { state in
            state.cracks.allSatisfy { face in
                [face.first.a, face.first.b, face.second.a, face.second.b].allSatisfy(state.body.position.indices.contains)
            }
        }
    }, "Recorded crack faces do not resolve on the replay frame mesh")
    print("Assembly replay: \(replay.frames.count) copper frames; \(other.frames.count) aluminum frames; \(fracture.frames.count) fracture frames. Geometry, stress, gauges, event jumps, contact and energy partition verified.")
}
