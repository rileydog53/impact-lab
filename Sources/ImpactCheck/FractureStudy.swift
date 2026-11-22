import Darwin
import Foundation
import ImpactPhysics
import simd

private struct AssemblyCase {
    let mesh: MaterialFractureSettings.MeshPattern
    let refinement: Int
    let scene: AssemblyScene

    var label: String { "\(mesh.rawValue) ×\(refinement)" }
}

private struct AssemblyOutcome {
    var error: String?
    var time = 0.0
    var firstSplit: Double?
    var work = 0.0
    var crackLength = 0.0
    var penetration = 0.0
    var imbalance = 0.0
    var momentum = 0.0
    var angularMomentum = 0.0
    var peakReceiverSpeed = 0.0
    var receiverEvents: [FragmentContactReading] = []
    var pieces: [MaterialPiece] = []
    var clearance: [Int: Double] = [:]
    var nodes = 0
    var initialNodes = 0
    var steps = 0
    var elapsed = 0.0
    var dt = 0.0
    var rejection: String?
    var energyChangeAtFormerRejection: Double?
    var firstSiblingContact: Double?
    var siblingImpulse = 0.0
}

private func simulateAssembly(_ test: AssemblyCase, stepLimit: Double = .infinity, stepScale: Double = 1,
                              recordClearance: Bool = true) throws -> AssemblyOutcome {
    var s = try AssemblySimulation(test.scene, refinement: test.refinement, stepLimit: stepLimit, stepScale: stepScale)
    let initialP = s.momentum, initialL = s.angularMomentum
    let start = ProcessInfo.processInfo.systemUptime
    var outcome = AssemblyOutcome(initialNodes: s.body(0).mesh.reference.count, dt: s.dt)
    var nextClearance = 0.0
    var previousEnergy = s.initialEnergy
    while s.step() {
        outcome.steps += 1
        let reading = s.fractureReading(0)!
        if reading.pieces > 1 && outcome.firstSplit == nil { outcome.firstSplit = s.time }
        let energy = s.energies.total
        outcome.imbalance = max(outcome.imbalance, abs(energy / s.initialEnergy - 1))
        if test.mesh == .staggered && test.refinement == 2 && s.time >= 0.028771373,
           outcome.energyChangeAtFormerRejection == nil {
            outcome.energyChangeAtFormerRejection = energy - previousEnergy
        }
        previousEnergy = energy
        outcome.momentum = max(outcome.momentum, simd_distance(s.momentum, initialP))
        outcome.angularMomentum = max(outcome.angularMomentum, abs(s.angularMomentum - initialL))
        if recordClearance && s.time >= nextClearance {
            outcome.peakReceiverSpeed = max(outcome.peakReceiverSpeed, simd_length(s.body(4).centerVelocity))
            if reading.pieces > 1 {
                for item in s.fragmentClearances(0, to: 4) {
                    outcome.clearance[item.piece] = min(outcome.clearance[item.piece, default: .infinity], item.distance)
                }
            }
            nextClearance += 0.0005
        }
    }
    outcome.error = s.failure ?? s.initialIssue
    outcome.time = s.time
    if let rejected = s.rejectedEnergy {
        let previous = s.energies
        outcome.rejection = String(format: "Rejected at %.6f ms: ΔE %+.6f, Δcontact %+.6f, Δelastic %+.6f, ΔK %+.6f, Δcohesive and fracture %+.6f J/m, trial penetration %.3f%%",
                                   (s.time + s.dt) * 1000, rejected.total - previous.total, rejected.contact - previous.contact,
                                   rejected.elastic - previous.elastic, rejected.kinetic - previous.kinetic,
                                   rejected.cohesive + rejected.fracture - previous.cohesive - previous.fracture,
                                   100 * (s.rejectedPenetration ?? 0))
    } else if let penetration = s.rejectedPenetration {
        outcome.rejection = String(format: "Rejected at %.6f ms: trial penetration %.3f%%",
                                   (s.time + s.dt) * 1000, 100 * penetration)
    }
    if let domains = s.rejectedContactDomains {
        outcome.rejection! += String(format: "; deepest penetration parts/pieces [%d:%d, %d:%d]; matching closure %.6f J/m",
                                    domains.x, domains.y, domains.z, domains.w, s.rejectedClosureEnergy ?? 0)
    }
    outcome.penetration = s.peakRelativePenetration
    outcome.work = s.fractureReading(0)!.dissipation
    outcome.crackLength = s.fractureReading(0)!.crackLength
    outcome.receiverEvents = s.fragmentContacts.filter { $0.parts == SIMD2(0, 4) }
    let siblings = s.fragmentContacts.filter { $0.parts == SIMD2(0, 0) && $0.pieces == SIMD2(0, 247) }
    outcome.firstSiblingContact = siblings.first?.time
    outcome.siblingImpulse = siblings.reduce(0.0) { $0 + $1.normalImpulse }
    for event in outcome.receiverEvents { outcome.clearance[event.pieces.x] = 0 }
    outcome.pieces = s.materialPieces(0)
    outcome.nodes = s.body(0).mesh.reference.count
    outcome.elapsed = ProcessInfo.processInfo.systemUptime - start
    return outcome
}

func siblingContactCheck() throws {
    var scene = AssemblyScene.bendingFractureExample()
    scene.parts[0].fracture?.meshPattern = .staggered
    let test = AssemblyCase(mesh: .staggered, refinement: 2, scene: scene)
    let outcome = try simulateAssembly(test, recordClearance: false)
    printAssembly(test.label, outcome)
    print(String(format: "Sibling-contact regression, pieces 0 and 247: first %.3f ms, scalar impulse %.6f N·s/m, step ΔE at previous rejection %+.7f J/m",
                 1000 * (outcome.firstSiblingContact ?? 0), outcome.siblingImpulse,
                 outcome.energyChangeAtFormerRejection ?? .infinity))
    require(outcome.error == nil && outcome.time >= scene.duration, "The sibling-contact reproducer rejected a step")
    require((outcome.firstSiblingContact ?? .infinity) < 0.028771373 && outcome.siblingImpulse > 0,
            "Sibling contact was missing before the previous rejection")
    require(outcome.imbalance < 0.005 && abs(outcome.energyChangeAtFormerRejection ?? .infinity) < 1e-3,
            "Sibling-contact activation created an energy jump")
    require(max(outcome.momentum, outcome.angularMomentum) < 1e-9, "Sibling contact lost momentum")
    // The full study applies the separate 2% penetration gate.
}

private func percentChange(_ a: Double, _ b: Double) -> Double {
    100 * abs(b - a) / max(abs(a), abs(b), 1e-14)
}

private func printAssembly(_ label: String, _ outcome: AssemblyOutcome) {
    print(String(format: "%@, dt %.3f µs: split %@ ms, G %.4f J/m, crack %.2f mm, %d pieces, imbalance %.3f%%, penetration %.3f%%, receiver peak |v| %.4f m/s, ΔP %.2e, ΔL %.2e, nodes %d→%d, %d steps in %.2f s%@",
                 label, outcome.dt * 1e6, outcome.firstSplit.map { String(format: "%.3f", $0 * 1000) } ?? "none",
                 outcome.work, 1000 * outcome.crackLength, outcome.pieces.count, 100 * outcome.imbalance, 100 * outcome.penetration,
                 outcome.peakReceiverSpeed, outcome.momentum, outcome.angularMomentum, outcome.initialNodes, outcome.nodes,
                 outcome.steps, outcome.elapsed, outcome.error.map { " STOPPED: " + $0 } ?? ""))
    if let rejection = outcome.rejection { print("  " + rejection) }
    for piece in outcome.pieces {
        print(String(format: "  piece %d: M %.4f kg/m, final center (%+.2f,%+.2f) mm, v (%+.3f,%+.3f) m/s, sampled clearance %@ mm",
                     piece.id, piece.mass, 1000 * piece.center.x, 1000 * piece.center.y, piece.velocity.x, piece.velocity.y,
                     outcome.clearance[piece.id].map { String(format: "%.3f", 1000 * $0) } ?? "unavailable"))
    }
    for event in outcome.receiverEvents {
        print(String(format: "  receiver event piece %d: %.3f–%.3f ms; first tagged exposed %@ ms; scalar normal impulse %.6f N·s/m",
                     event.pieces.x, event.time * 1000, event.lastTime * 1000,
                     event.firstExposedTime.map { String(format: "%.3f", 1000 * $0) } ?? "none", event.normalImpulse))
    }
}

func fractureAssemblyCase(_ pattern: String, _ resolution: String) throws {
    guard let mesh = MaterialFractureSettings.MeshPattern.allCases.first(where: { $0.rawValue.lowercased() == pattern.lowercased() }),
          let refinement = Int(resolution), (1...3).contains(refinement) else {
        require(false, "Usage: --fracture-case aligned|staggered 1|2|3")
        return
    }
    var scene = AssemblyScene.bendingFractureExample()
    scene.parts[0].fracture?.meshPattern = mesh
    let test = AssemblyCase(mesh: mesh, refinement: refinement, scene: scene)
    let normal = try simulateAssembly(test)
    printAssembly(test.label, normal)
    printAssembly(test.label + ", half step", try simulateAssembly(test, stepLimit: normal.dt / 2))
}

func detachmentContactCheck() throws -> Bool {
    var scene = AssemblyScene.bendingFractureExample()
    scene.parts[0].fracture?.meshPattern = .aligned
    var s = try AssemblySimulation(scene, refinement: 3, stepLimit: .infinity, stepScale: 0.5)
    s.probeDetachment = true
    let initialP = s.momentum, initialL = s.angularMomentum
    var imbalance = 0.0, momentum = 0.0, angularMomentum = 0.0
    // The two material features implicated in the archived aligned ×3 case.
    let features = [SIMD3(2406, 2086, 2087), SIMD3(2087, 2411, 2409)]
    var previous = features.map { s.contactTrack($0, part: 0) }
    var firstPenetration: [Double?] = features.map { _ in nil }
    while s.step() {
        imbalance = max(imbalance, abs(s.energies.total / s.initialEnergy - 1))
        momentum = max(momentum, simd_distance(s.momentum, initialP))
        angularMomentum = max(angularMomentum, abs(s.angularMomentum - initialL))
        for (i, corners) in features.enumerated() {
            guard let sample = s.contactTrack(corners, part: 0) else { continue }
            if previous[i]?.nodes != sample.nodes || previous[i]?.pieces != sample.pieces {
                print(String(format: "Feature %@ at %.6f ms: FEM %@, domains %@, local gap %+.6f mm, fraction %.5f",
                             corners.description, 1000 * s.time, sample.nodes.description,
                             sample.pieces.description, 1000 * sample.gap, sample.fraction))
            }
            let isPenetrating = sample.gap < -1e-10 && (0...1).contains(sample.fraction)
                && sample.nodes.x != sample.nodes.y && sample.nodes.x != sample.nodes.z
            if isPenetrating {
                if firstPenetration[i] == nil { firstPenetration[i] = s.time }
            } else {
                firstPenetration[i] = nil
            }
            previous[i] = sample
        }
    }
    for (i, corners) in features.enumerated() {
        if let first = firstPenetration[i], let sample = previous[i] {
            print(String(format: "Feature %@: current interval of negative local gap began at %.6f ms; last gap %+.6f mm",
                         corners.description, 1000 * first, 1000 * sample.gap))
        }
    }
    for event in s.detachmentProbes {
        let oldClosure = event.oldClosure.map { String(format: "%.8f", $0) } ?? "unavailable"
        print(String(format: "Detachment %.6f ms, domains %d → %d, paired closure at fixed positions %@ → %.8f J/m",
                     1000 * event.time, event.oldTopology.pieces, event.newTopology.pieces, oldClosure, event.newClosure))
        for (label, snapshot) in [("old topology, trial positions", event.oldTopology),
                                  ("new topology, previous positions", event.newTopologyAtOldPositions),
                                  ("new topology, trial positions", event.newTopology)] {
            print(String(format: "  %@: %d samples, %d edge crossings, U %.8f J/m, |ΣF| %.2e N/m, |Στ| %.2e N",
                         label, snapshot.features.count, snapshot.crossings.count, snapshot.energy,
                         simd_length(snapshot.residualForce), abs(snapshot.residualTorque)))
            for feature in snapshot.features.sorted(by: { $0.relativePenetration > $1.relativePenetration }).prefix(4) {
                print(String(format: "    pieces %d→%d, material node %@ → edge %d:%d, FEM node %d → edge %d:%d, %.4f%%, fraction %.5f, F=(%.4f, %.4f) N/m, U %.8f J/m, closure %@",
                             feature.pieces.x, feature.pieces.y, feature.nodeCorners.description,
                             feature.edgeCorners.x, feature.edgeCorners.y, feature.node, feature.edge.x, feature.edge.y,
                             100 * feature.relativePenetration, feature.fraction, feature.force.x, feature.force.y,
                             feature.energy, feature.closureSeam.map(String.init) ?? "none"))
            }
            if !snapshot.crossings.isEmpty { print("    Edge crossings (piece pair, edge corner pair): \(snapshot.crossings)") }
        }
    }
    let attemptedPeak = max(s.peakRelativePenetration, s.rejectedPenetration ?? 0)
    let energyJumps = s.detachmentProbes.compactMap(\.energyJump)
    let maxActivation = energyJumps.map(abs).max() ?? 0
    print(String(format: "dt %.3f µs, accepted through %.6f ms, accepted/attempted penetration %.3f%%/%.3f%%, max energy error %.4f%%, ΔP %.2e, ΔL %.2e",
                 s.dt * 1e6, s.time * 1000, s.peakRelativePenetration * 100, attemptedPeak * 100, imbalance * 100, momentum, angularMomentum))
    print(String(format: "Largest fixed-position sibling contact energy change %.8f J/m (%.4f%% of initial energy)",
                 maxActivation, 100 * maxActivation / s.initialEnergy))
    if let failure = s.failure ?? s.initialIssue { print("STOPPED: \(failure)") }
    return s.failure == nil && s.initialIssue == nil && s.time >= scene.duration
        && s.detachmentProbes.contains { $0.newTopology.pieces >= 4 }
        && energyJumps.count == s.detachmentProbes.count && maxActivation < 1e-10 * max(1, s.initialEnergy)
        && attemptedPeak <= 0.02 && imbalance < 0.005 && max(momentum, angularMomentum) < 1e-9
}

private struct BendWork {
    // Spent notch network, other spent faces, partial faces touching the
    // notch network, and other partial faces, respectively.
    var terms = SIMD4<Double>.zero
    var total: Double { terms.sum() }
}

private struct BendOutcome {
    var peakLoad = 0.0
    var peakTime = 0.0
    var workAtPeak = 0.0
    var matched: (force: Double, work: BendWork, below: Double, above: Double, rawWork: SIMD2<Double>,
                  peakTime: Double, workAtPeak: Double)?
    var exits: [Double] = []
    var maxAdvance = 0.0
    var error: String?
}

private func notchedBend(_ test: AssemblyCase, stepLimit: Double, depth: Double) throws -> BendOutcome {
    // Same prescribed geometry, impact speed and material on every mesh.
    var scene = test.scene
    scene.duration = 0.045
    var simulation = try AssemblySimulation(scene, refinement: test.refinement, stepLimit: stepLimit, notchDepth: depth)
    let halfHeight = 0.5 * scene.parts[0].size.y
    let tip = Point(0, -halfHeight + depth)
    let advance = 0.5 * (halfHeight - tip.y)
    var outcome = BendOutcome()
    var failed = 0
    var workAtLastAdvance = BendWork()
    let toughness = scene.parts[0].fracture!.energy
    while simulation.step() {
        let reading = simulation.fractureReading(0)!
        let force = simulation.normalLoad(0, 1)
        if force > outcome.peakLoad {
            outcome.peakLoad = force
            outcome.peakTime = simulation.time
            outcome.workAtPeak = reading.dissipation
        }
        guard failed != reading.failedEdges else { continue }
        failed = reading.failedEdges
        let reference = simulation.body(0).mesh.reference
        var links: [Point: [Point]] = [:]
        let faces = simulation.crackFaces(0)
        for face in faces where face.damage == 1 {
            let a = reference[face.first.a], b = reference[face.first.b]
            links[a, default: []].append(b)
            links[b, default: []].append(a)
        }
        guard let seed = links.keys.first(where: { simd_distance($0, tip) < 1e-10 }) else { continue }
        var reached: Set<Point> = [seed]
        var queue = [seed]
        var i = 0
        while i < queue.count {
            for target in links[queue[i], default: []] where reached.insert(target).inserted { queue.append(target) }
            i += 1
        }
        let crackAdvance = queue.map(\.y).max()! - tip.y
        var work = BendWork()
        for face in faces where face.damage > 0 {
            let a = reference[face.first.a], b = reference[face.first.b]
            let touchesNotchNetwork = reached.contains(a) || reached.contains(b)
            let term = (face.damage == 1 ? 0 : 2) + (touchesNotchNetwork ? 0 : 1)
            work.terms[term] += toughness * simd_distance(a, b) * face.damage
        }
        require(abs(work.total - reading.dissipation) < 1e-10, "Notched-bend fracture-work partition does not close")
        if outcome.matched == nil && crackAdvance >= advance {
            let below = outcome.maxAdvance
            let fraction = (advance - below) / (crackAdvance - below)
            let interpolated = BendWork(terms: workAtLastAdvance.terms + fraction * (work.terms - workAtLastAdvance.terms))
            outcome.matched = (outcome.peakLoad, interpolated, below, crackAdvance, SIMD2(workAtLastAdvance.total, work.total),
                               outcome.peakTime, outcome.workAtPeak)
        }
        if crackAdvance < advance { workAtLastAdvance = work }
        outcome.maxAdvance = max(outcome.maxAdvance, crackAdvance)
        outcome.exits = queue.filter { abs($0.y - halfHeight) < 1e-10 }.map(\.x).sorted()
    }
    outcome.error = simulation.failure ?? simulation.initialIssue
    return outcome
}

private func compareBends(_ first: BendOutcome, _ second: BendOutcome, label: String, exitTolerance: Double) -> Bool {
    guard let a = first.matched, let b = second.matched, !first.exits.isEmpty, !second.exits.isEmpty,
          first.error == nil, second.error == nil else {
        print("\(label): FAIL, an uninterrupted crack from notch to exit was not observed in both cases.")
        return false
    }
    func directedExitGap(_ first: [Double], _ second: [Double]) -> Double {
        first.map { x in second.map { abs(x - $0) }.min()! }.max()!
    }
    let load = percentChange(a.force, b.force), work = percentChange(a.work.total, b.work.total)
    let exits = max(directedExitGap(first.exits, second.exits), directedExitGap(second.exits, first.exits))
    let pass = load <= 5 && work <= 5 && exits <= exitTolerance + 1e-12
    print(String(format: "%@: %@, peak load %.2f%%, work %.2f%%, crack exits %.2f mm (limit %.2f)",
                 label, pass ? "PASS" : "FAIL", load, work, exits * 1000, exitTolerance * 1000))
    return pass
}

private func studyCases() -> [AssemblyCase] {
    let base = AssemblyScene.bendingFractureExample()
    return MaterialFractureSettings.MeshPattern.allCases.flatMap { mesh in
        (1...3).map { refinement in
            var scene = base
            scene.parts[0].fracture?.meshPattern = mesh
            return AssemblyCase(mesh: mesh, refinement: refinement, scene: scene)
        }
    }
}

func notchedBendStudy() throws -> Bool {
    let cases = studyCases()
    print("Notched bend: 5 mm notch, 10.5 mm vertical advance along fully spent connected faces. Peak striker normal load through crossing. Work interpolated between consecutive advances.")
    let depth = 0.005
    let commonStep = try cases.map {
        try AssemblySimulation($0.scene, refinement: $0.refinement, stepLimit: .infinity, notchDepth: depth).dt
    }.min()!
    print(String(format: "Common notched-bend step %.3f µs, 45 ms endpoint.", commonStep * 1e6))
    var bends: [BendOutcome] = []
    for test in cases {
        let bend = try notchedBend(test, stepLimit: commonStep, depth: depth)
        bends.append(bend)
        let match = bend.matched.map {
            String(format: "%.2f N/m, %.4f J/m (advance bracket %.2f–%.2f mm, work bracket %.4f–%.4f J/m)",
                   $0.force, $0.work.total, $0.below * 1000, $0.above * 1000, $0.rawWork.x, $0.rawWork.y)
        } ?? "unreached"
        print(String(format: "%@: %@; max crack advance %.2f mm, max load %.2f N/m, exits %@%@",
                     test.label, match, bend.maxAdvance * 1000, bend.peakLoad,
                     bend.exits.map { String(format: "%.2f", $0 * 1000) }.joined(separator: ", "),
                     bend.error.map { " STOPPED: " + $0 } ?? ""))
        if let observation = bend.matched {
            let w = observation.work.terms
            print(String(format: "  Work (J/m): spent notch %.4f, spent elsewhere %.4f, partial at notch %.4f, partial elsewhere %.4f; max-load time %.3f ms, fracture work then %.4f J/m",
                         w.x, w.y, w.z, w.w, observation.peakTime * 1000, observation.workAtPeak))
        }
    }
    var crackPass = true
    for (a, b) in [(0, 1), (1, 2), (3, 4), (4, 5), (1, 4), (2, 5)] {
        let fine = Double(max(cases[a].refinement, cases[b].refinement))
        let pass = compareBends(bends[a], bends[b], label: "\(cases[a].label) vs \(cases[b].label)",
                                exitTolerance: 0.163 / (18 * fine))
        crackPass = crackPass && pass
    }
    return crackPass
}

func fractureStudy() throws -> Bool {
    let crackPass = try notchedBendStudy()
    print("Unnotched assembly: 115 ms. Receiver clearance is sampled every 0.5 ms after split, set to zero for recorded contact. Normal impulse sums scalar normal loads from both directions.")
    var timestepPass = true
    var contacts: [Bool] = []
    var taggedContacts: [Bool] = []
    for test in studyCases() {
        let normal = try simulateAssembly(test)
        let half = try simulateAssembly(test, stepLimit: normal.dt / 2)
        printAssembly(test.label, normal)
        printAssembly(test.label + ", half step", half)
        let timing = normal.firstSplit.flatMap { time in half.firstSplit.map { percentChange(time, $0) } }
        let work = percentChange(normal.work, half.work)
        let pass = normal.error == nil && half.error == nil && (timing ?? .infinity) < 2 && work < 2
            && max(normal.imbalance, half.imbalance) < 0.005 && max(normal.penetration, half.penetration) < 0.02
        let timingText = timing.map { String(format: "%.2f%%", $0) } ?? "unavailable"
        print(String(format: "  step sensitivity %@: split %@, work %.2f%%", pass ? "PASS" : "FAIL", timingText, work))
        timestepPass = timestepPass && pass
        for outcome in [normal, half] {
            contacts.append(!outcome.receiverEvents.isEmpty)
            taggedContacts.append(outcome.receiverEvents.contains(where: \.onExposedFace))
        }
    }
    let consistentHit = contacts.allSatisfy { $0 }
    let consistentTaggedHit = taggedContacts.allSatisfy { $0 }
    print("Gate summary: fracture consistency \(crackPass ? "PASS" : "FAIL"); timestep, energy and overlap \(timestepPass ? "PASS" : "FAIL"); receiver hits \(contacts.filter { $0 }.count)/\(contacts.count), exposed hits \(taggedContacts.filter { $0 }.count)/\(taggedContacts.count).")
    return crackPass && timestepPass && consistentHit && consistentTaggedHit
}

func fractureStabilityProbe() throws {
    let test = AssemblyCase(mesh: .aligned, refinement: 1, scene: .bendingFractureExample())
    for scale in [1.0, 2, 4, 8] {
        let run = try simulateAssembly(test, stepScale: scale, recordClearance: false)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print(String(format: "Step ×%.0f, %.3f µs, %d steps in %.3f s, %.3f%% energy, %.3f%% penetration, peak RSS %.2f MiB%@",
                     scale, run.dt * 1e6, run.steps, run.elapsed, 100 * run.imbalance, 100 * run.penetration,
                     Double(usage.ru_maxrss) / 1_048_576, run.error.map { " STOPPED: " + $0 } ?? ""))
    }
}
