import Foundation
import ImpactPhysics
import simd

private struct AssemblyMeasurements {
    var energy = 0.0
    var momentum = 0.0
    var angular = 0.0
    var force = 0.0
    var work = 0.0
    var payloadShift = 0.0
    var firstCrest: Double?
    var peakConnectionEnergy = 0.0
    var final: AssemblySimulation
}

private func simulate(_ label: String, _ scene: AssemblyScene, refinement: Int = 1,
                      stepLimit: Double = .infinity) throws -> AssemblyMeasurements {
    var s = try AssemblySimulation(scene, refinement: refinement, stepLimit: stepLimit)
    require(s.initialIssue == nil, s.initialIssue ?? "")
    let initialP = s.momentum, initialL = s.angularMomentum
    var outcome = AssemblyMeasurements(final: s)
    // Avoid retaining the initial buffers in the simulation loop.
    var oldLinks = s.linkReadings
    var oldFracture = 0.0
    var maxShift = 0.0
    let initialOffset: Point = s.bodyCount > 1 ? s.body(1).centerOfMass - s.body(0).centerOfMass : .zero
    while s.step() {
        let e = s.energies
        outcome.peakConnectionEnergy = max(outcome.peakConnectionEnergy, e.connection)
        outcome.energy = max(outcome.energy, abs(e.total / s.initialEnergy - 1))
        outcome.momentum = max(outcome.momentum, simd_length(s.momentum - initialP))
        outcome.angular = max(outcome.angular, abs(s.angularMomentum - initialL))
        require(e.fracture >= oldFracture - 1e-12, "Damage healed")
        oldFracture = e.fracture
        for (old, new) in zip(oldLinks, s.linkReadings) {
            if scene.connections[new.connection].kind == .cohesive {
                outcome.work += 0.5 * (old.force + new.force) * (new.extensionLength - old.extensionLength)
                if new.damage == 1 { require(new.force == 0, "A failed link kept carrying tension") }
            }
            if scene.connections[new.connection].kind == .spring {
                require(abs(new.force - scene.connections[new.connection].stiffness * new.extensionLength) < 1e-9
                        || scene.connections[new.connection].span > 0, "Linear connection force differs from k × extension")
            }
            outcome.force = max(outcome.force, abs(new.force))
        }
        if let old = oldLinks.first, let new = s.linkReadings.first, s.time > 0.002,
           new.extensionLength < old.extensionLength, old.extensionLength > 0.0005, outcome.firstCrest == nil {
            outcome.firstCrest = s.time - s.dt
        }
        oldLinks = s.linkReadings
        if s.bodyCount > 1 {
            maxShift = max(maxShift, simd_length(s.body(1).centerOfMass - s.body(0).centerOfMass - initialOffset))
        }
    }
    outcome.final = s
    outcome.payloadShift = maxShift
    let pairs = s.firstContactTimes.sorted { $0.key.x == $1.key.x ? $0.key.y < $1.key.y : $0.key.x < $1.key.x }
        .map { String(format: "%d–%d %.3f ms", $0.key.x, $0.key.y, 1000 * $0.value) }.joined(separator: ", ")
    let firstCrest = outcome.firstCrest.map { String(format: "%.3f ms", $0 * 1000) } ?? "—"
    print(String(format: "%@: Δt %.3f µs; ΔP %.2e; ΔL %.2e; energy %.4f%%; overlap %.2f%%; force %.2f N/m; fracture %.5f (work %.5f) J/m; relative shift %.2f mm; first crest %@; contacts %@",
                 label, s.dt * 1e6, outcome.momentum, outcome.angular, outcome.energy * 100, s.peakRelativePenetration * 100,
                 outcome.force, s.energies.fracture, outcome.work, maxShift * 1000, firstCrest, pairs))
    require(s.failure == nil && s.time >= scene.duration, s.failure ?? "Assembly stopped early")
    require(outcome.momentum < 1e-9 && outcome.angular < 1e-9, "Assembly momentum balance")
    require(outcome.energy < 0.005 && s.peakRelativePenetration < 0.06, "Assembly energy or contact overlap exceeded tolerance")
    return outcome
}

private func relay() -> AssemblyScene {
    var scene = AssemblyScene()
    var a = AssemblyPart("Driver", center: Point(-0.084, 0.020), size: Point(0.041, 0.043))
    a.angle = -7
    a.velocity = Point(0.95, -0.04)
    let b = AssemblyPart("Coupler", center: .zero, size: Point(0.056, 0.055))
    let c = AssemblyPart("Follower", center: Point(0.110, -0.017), size: Point(0.056, 0.055))
    var link = AssemblyConnection(first: b.id, second: c.id)
    link.stiffness = 18_000
    scene.parts = [a, b, c]
    scene.connections = [link]
    scene.monitor = c.id
    scene.relativeTo = b.id
    return scene
}

private func springControl() throws {
    var scene = AssemblyScene()
    let size = Point(0.065, 0.05)
    var a = AssemblyPart("Left", center: Point(-0.066, 0), size: size)
    a.material.young = 4e6
    a.velocity.x = -0.16
    var b = a
    b.id = UUID()
    b.name = "Right"
    b.center.x *= -1
    b.velocity.x *= -1
    var link = AssemblyConnection(first: a.id, second: b.id)
    link.stiffness = 4500
    scene.parts = [a, b]
    scene.connections = [link]
    scene.duration = 0.075
    let run = try simulate("Spring control", scene)
    let mass = a.size.x * a.size.y * a.material.density
    let expected = 0.5 * .pi * sqrt(mass / (2 * link.stiffness))
    let observed = run.firstCrest ?? 0
    print(String(format: "Spring first extension crest %.3f ms; lumped-mass prediction %.3f ms", 1000 * observed, 1000 * expected))
    require(abs(observed / expected - 1) < 0.025 && run.final.firstContactTimes.isEmpty,
            "Spring control disagrees with the low-compliance analytical limit")
}

func assemblyCheck() throws {
    let scene = AssemblyScene.enclosureExample()
    let base = try simulate("Enclosure impact", scene)
    let half = try simulate("Enclosure half step", scene, stepLimit: base.final.dt / 2)
    let fine = try simulate("Enclosure finer mesh", scene, refinement: 2, stepLimit: base.final.dt / 2)
    let bond = scene.connections[1]
    let predictedFracture = 0.125 * bond.stiffness * bond.criticalExtension * bond.criticalExtension
    for run in [base, half, fine] {
        let s = run.final
        guard let impact = s.firstContactTimes[SIMD2(0, 2)], let layers = s.firstContactTimes[SIMD2(2, 3)],
              let cavity = s.firstContactTimes[SIMD2(0, 1)] else {
            require(false, "The enclosure, layered obstacle, or its cavity did not make contact")
            return
        }
        require(impact < layers && layers < cavity && scene.duration - impact > 0.10,
                "The expected sequence or its aftermath was lost")
        require(run.payloadShift > 0.012 && run.peakConnectionEnergy > 0.25 && s.energies.plastic > 0,
                "The enclosure did not transfer energy or plastically deform")
        require(abs(s.energies.fracture / predictedFracture - 1) < 1e-10
                && abs(run.work / predictedFracture - 1) < 0.01,
                "Integrated work and failed-link fracture accounting disagree")
    }

    func sensitivity(_ reference: AssemblyMeasurements, _ candidate: AssemblyMeasurements,
                     _ label: String, limit: Double) {
        let pairs: [SIMD2<Int>] = [SIMD2(0, 2), SIMD2(2, 3), SIMD2(0, 1)]
        var readings = pairs.map { (reference.final.firstContactTimes[$0]!, candidate.final.firstContactTimes[$0]!) }
        readings += [(reference.payloadShift, candidate.payloadShift),
                     (reference.firstCrest!, candidate.firstCrest!)]
        let maxChange = readings.map { abs($1 / $0 - 1) }.max()!
        let forceChange = abs(candidate.force / reference.force - 1)
        print(String(format: "%@ max change in event times, payload travel and first crest %.2f%%; peak link force change %.2f%%",
                     label, maxChange * 100, forceChange * 100))
        require(maxChange < limit && forceChange < 0.20, "\(label) refinement exceeded tolerance")
    }
    sensitivity(base, half, "Timestep", limit: 0.01)
    sensitivity(half, fine, "Mesh at common timestep", limit: 0.09)

    let second = try simulate("Three-body relay", relay())
    require(second.final.firstContactTimes[SIMD2(0, 1)] != nil
            && second.final.firstContactTimes[SIMD2(1, 2)] == nil
            && second.final.kineticEnergy(2) > 0.01 && second.peakConnectionEnergy > 0.05,
            "The relay did not transfer energy to a noncontacting follower")

    var overlap = scene
    overlap.parts[1].center.x = overlap.parts[0].center.x + 0.064
    var invalid = try AssemblySimulation(overlap)
    require(invalid.initialIssue != nil && !invalid.step(), "An initially overlapping enclosure was allowed to run")
    try springControl()
}
