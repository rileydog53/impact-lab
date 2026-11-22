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
    var selfContactTopologyJump = 0.0
    var receiverImpulseAtObservation: Double?
}

private func simulateAssembly(_ test: AssemblyCase, stepLimit: Double = .infinity, stepScale: Double = 1,
                              recordClearance: Bool = true, auditDetachment: Bool = false,
                              receiverObservationTime: Double? = nil) throws -> AssemblyOutcome {
    var s = try AssemblySimulation(test.scene, refinement: test.refinement, stepLimit: stepLimit, stepScale: stepScale)
    s.probeDetachment = auditDetachment
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
        if let cutoff = receiverObservationTime, s.time >= cutoff, outcome.receiverImpulseAtObservation == nil {
            outcome.receiverImpulseAtObservation = s.fragmentContacts.filter { $0.parts == SIMD2(0, 4) }
                .reduce(0) { $0 + $1.normalImpulse }
        }
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
        outcome.rejection! += String(format: "; deepest penetration parts/pieces [%d:%d, %d:%d]; total contact energy %.6f J/m",
                                    domains.x, domains.y, domains.z, domains.w, s.rejectedContactEnergy ?? 0)
    }
    outcome.penetration = s.peakRelativePenetration
    outcome.work = s.fractureReading(0)!.dissipation
    outcome.crackLength = s.fractureReading(0)!.crackLength
    outcome.receiverEvents = s.fragmentContacts.filter { $0.parts == SIMD2(0, 4) }
    let siblings = s.fragmentContacts.filter { $0.parts == SIMD2(0, 0) && $0.pieces == SIMD2(0, 247) }
    outcome.firstSiblingContact = siblings.first?.time
    outcome.siblingImpulse = siblings.reduce(0.0) { $0 + $1.normalImpulse }
    outcome.selfContactTopologyJump = max(s.maxInsertionContactJump, s.detachmentProbes.map { abs($0.energyJump) }.max() ?? 0)
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
    let outcome = try simulateAssembly(test, recordClearance: false, auditDetachment: true)
    printAssembly(test.label, outcome)
    print(String(format: "Sibling-contact regression, pieces 0 and 247: first %.3f ms, scalar impulse %.6f N·s/m, step ΔE at previous rejection %+.7f J/m",
                 1000 * (outcome.firstSiblingContact ?? 0), outcome.siblingImpulse,
                 outcome.energyChangeAtFormerRejection ?? .infinity))
    require(outcome.error == nil && outcome.time >= scene.duration, "The sibling-contact reproducer rejected a step")
    // The corrected forces change the trajectory. Check the same material
    // pair at its actual collision and retain the former step as an energy check.
    require(outcome.firstSiblingContact != nil && outcome.siblingImpulse > 0,
            "Sibling contact was missing from the completed replay")
    require(outcome.imbalance < 0.005 && abs(outcome.energyChangeAtFormerRejection ?? .infinity) < 1e-3,
            "Sibling-contact activation created an energy jump")
    require(outcome.selfContactTopologyJump < 1e-10 && outcome.penetration <= 0.02,
            "Sibling contact added energy at fixed positions or exceeded the penetration gate")
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
        print(String(format: "Detachment %.6f ms, domains %d → %d, triangle contact energy at fixed positions %.8f → %.8f J/m",
                     1000 * event.time, event.oldTopology.pieces, event.newTopology.pieces, event.oldContact, event.newContact))
        for (label, snapshot) in [("legacy probe on old domains, trial positions", event.oldTopology),
                                  ("legacy probe on new domains, previous positions", event.newTopologyAtOldPositions),
                                  ("legacy probe on new domains, trial positions", event.newTopology)] {
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
    let maxActivation = s.detachmentProbes.map { abs($0.energyJump) }.max() ?? 0
    print(String(format: "dt %.3f µs, accepted through %.6f ms, accepted/attempted penetration %.3f%%/%.3f%%, max energy error %.4f%%, ΔP %.2e, ΔL %.2e",
                 s.dt * 1e6, s.time * 1000, s.peakRelativePenetration * 100, attemptedPeak * 100, imbalance * 100, momentum, angularMomentum))
    if let pair = s.rejectedContactDomains ?? s.peakContactDomains {
        print("Peak penetration parts/pieces [\(pair.x):\(pair.y), \(pair.z):\(pair.w)]")
    }
    print(String(format: "Largest fixed-position sibling contact energy change %.8f J/m (%.4f%% of initial energy)",
                 maxActivation, 100 * maxActivation / s.initialEnergy))
    print(String(format: "Largest fixed-position self-contact energy change at node splitting %.8e J/m", s.maxInsertionContactJump))
    print(String(format: "Largest fixed-position interbody contact energy change across topology %.8e J/m", s.maxInterbodyTopologyJump))
    if let failure = s.failure ?? s.initialIssue { print("STOPPED: \(failure)") }
    return s.failure == nil && s.initialIssue == nil && s.time >= scene.duration
        && s.detachmentProbes.contains { $0.newTopology.pieces >= 4 }
        && max(maxActivation, s.maxInsertionContactJump) < 1e-10 * max(1, s.initialEnergy)
        && s.maxInterbodyTopologyJump < 1e-10 * max(1, s.initialEnergy)
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
    var finalWork = BendWork()
    var compression = 0.0
    var energyError = 0.0
    var firstInsertion: (time: Double, distanceFromTip: Double)?
    var firstSupportContact: Double?
}

private func notchedBend(_ test: AssemblyCase, stepLimit: Double, depth: Double, pad: StrikerPad? = nil) throws -> BendOutcome {
    // Same prescribed geometry, impact speed and material on every mesh.
    var scene = test.scene
    scene.duration = 0.045
    if let pad { scene.parts[1].center.y += pad.thickness }
    var simulation = try AssemblySimulation(scene, refinement: test.refinement, stepLimit: stepLimit, notchDepth: depth, strikerPad: pad)
    let halfHeight = 0.5 * scene.parts[0].size.y
    let tip = Point(0, -halfHeight + depth)
    let advance = 0.5 * (halfHeight - tip.y)
    var outcome = BendOutcome()
    var failed = 0
    var workAtLastAdvance = BendWork()
    let toughness = scene.parts[0].fracture!.energy
    func partition() -> (Double, BendWork, [Double]) {
        let reference = simulation.body(0).mesh.reference
        var links: [Point: [Point]] = [:]
        let faces = simulation.crackFaces(0)
        for face in faces where face.damage == 1 {
            let a = reference[face.first.a], b = reference[face.first.b]
            links[a, default: []].append(b)
            links[b, default: []].append(a)
        }
        let seed = links.keys.first(where: { simd_distance($0, tip) < 1e-10 }) ?? tip
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
        require(abs(work.total - simulation.fractureReading(0)!.dissipation) < 1e-10, "Notched-bend fracture-work partition does not close")
        let exits = queue.filter { abs($0.y - halfHeight) < 1e-10 }.map(\.x).sorted()
        return (crackAdvance, work, exits)
    }
    while simulation.step() {
        if pad != nil {
            outcome.energyError = max(outcome.energyError, abs(simulation.energies.total / simulation.initialEnergy - 1))
        }
        let reading = simulation.fractureReading(0)!
        if pad != nil && outcome.firstInsertion == nil && reading.insertedEdges > 0 {
            let p = simulation.body(0).mesh.reference
            let distance = simulation.crackFaces(0).map {
                simd_distance((p[$0.first.a] + p[$0.first.b]) / 2, tip)
            }.min()!
            outcome.firstInsertion = (simulation.time, distance)
        }
        let force = simulation.normalLoad(0, 1)
        if force > outcome.peakLoad {
            outcome.peakLoad = force
            outcome.peakTime = simulation.time
            outcome.workAtPeak = reading.dissipation
        }
        guard failed != reading.failedEdges else { continue }
        failed = reading.failedEdges
        let (crackAdvance, work, exits) = partition()
        if crackAdvance <= 0 { continue }
        if outcome.matched == nil && crackAdvance >= advance {
            let below = outcome.maxAdvance
            let fraction = (advance - below) / (crackAdvance - below)
            let interpolated = BendWork(terms: workAtLastAdvance.terms + fraction * (work.terms - workAtLastAdvance.terms))
            outcome.matched = (outcome.peakLoad, interpolated, below, crackAdvance, SIMD2(workAtLastAdvance.total, work.total),
                               outcome.peakTime, outcome.workAtPeak)
        }
        if crackAdvance < advance { workAtLastAdvance = work }
        outcome.maxAdvance = max(outcome.maxAdvance, crackAdvance)
        outcome.exits = exits
    }
    outcome.error = simulation.failure ?? simulation.initialIssue
    if pad != nil {
        outcome.finalWork = partition().1
        outcome.compression = simulation.padPeakCompression
        outcome.firstSupportContact = [SIMD2(0, 2), SIMD2(0, 3)].compactMap { simulation.firstContactTimes[$0] }.min()
    }
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

func elasticBendLoadingCheck() throws {
    let depth = 0.005
    let cases = studyCases()
    let penalties = [1.0, 2.0, 4.0]
    let stableSteps = try penalties.map { penalty in
        try cases.map {
            try AssemblySimulation($0.scene, refinement: $0.refinement, stepLimit: .infinity,
                                   notchDepth: depth, interbodyStiffnessScale: penalty, insertionEnabled: false).dt
        }.min()!
    }
    let commonStep = stableSteps.min()!
    // Reproduce the archived step, then vary the contact stiffness at one fixed step.
    for (penalty, dt) in [(1.0, stableSteps[0])] + penalties.map({ ($0, commonStep) }) {
        var peaks: [Double] = []
        for test in cases where test.refinement == 3 {
            // The original loading peaks were both before 4.3 ms.
            let scene = test.scene
            let endpoint = 0.006
            var run = try AssemblySimulation(scene, refinement: test.refinement, stepLimit: dt,
                                             notchDepth: depth, interbodyStiffnessScale: penalty, insertionEnabled: false)
            let specimen = run.body(0)
            let p = specimen.mesh.reference
            var masses = Array(repeating: 0.0, count: p.count)
            for e in specimen.mesh.elements {
                let u = p[e.b] - p[e.a], v = p[e.c] - p[e.a]
                let third = abs(u.x * v.y - u.y * v.x) * specimen.material.density / 6
                for i in [e.a, e.b, e.c] { masses[i] += third }
            }
            let striker = scene.parts[1], top = 0.5 * scene.parts[0].size.y
            let footprint = p.indices.filter { abs(p[$0].y - top) < 1e-10 &&
                abs(p[$0].x - striker.center.x) < 0.5 * striker.size.x }
            let footprintMasses = footprint.map { masses[$0] }
            var peak = 0.0, peakTime = 0.0
            while run.time < endpoint && run.step() {
                let load = run.normalLoad(0, 1)
                if load > peak {
                    peak = load
                    peakTime = run.time
                }
            }
            let reading = run.fractureReading(0)!
            require(run.time >= endpoint && run.failure == nil && peak > 0 &&
                    reading.insertedEdges == 0 && reading.dissipation == 0, "Elastic load control did not complete without damage")
            let contact = run.firstContactTimes[SIMD2(0, 1)]!
            print(String(format: "Penalty ×%.0f, %@, dt %.3f µs: peak %.2f N/m at %.3f ms (%.3f ms after contact). Struck boundary-node mass %.4f–%.4f kg/m, sum %.4f kg/m.",
                         penalty, test.label, dt * 1e6, peak, 1000 * peakTime, 1000 * (peakTime - contact),
                         footprintMasses.min()!, footprintMasses.max()!, footprintMasses.reduce(0, +)))
            peaks.append(peak)
        }
        print(String(format: "Damage-disabled peak difference at penalty ×%.0f: %.2f%%", penalty, percentChange(peaks[0], peaks[1])))
    }
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

func compliantStrikerCheck() throws {
    let pad = StrikerPad(thickness: 0.004, modulus: 250_000, samples: 32)
    let step = 0.45e-6
    let check = pad.response(length: 0.003, stiffness: pad.modulus * 0.025 / pad.thickness)
    require(abs(check.load - 1562.5) < 1e-10 && abs(check.energy - 0.78125) < 1e-12
                && pad.response(length: 0.005, stiffness: 1).load == 0, "Pad compression or work is incorrect")

    func trial(_ test: AssemblyCase, pad: StrikerPad?, penalty: Double, dt: Double) throws {
        var scene = test.scene
        if let pad { scene.parts[1].center.y += pad.thickness }
        var run = try AssemblySimulation(scene, refinement: test.refinement, stepLimit: dt, notchDepth: 0.005,
                                         interbodyStiffnessScale: penalty, insertionEnabled: false, strikerPad: pad)
        let initialVelocity = run.body(1).centerVelocity.y
        let mass = 2 * run.kineticEnergy(1) / (initialVelocity * initialVelocity)
        let initialP = run.momentum, initialL = run.angularMomentum
        var impulse = 0.0, verticalImpulse = 0.0, oldLoad = 0.0, oldTime = 0.0
        var peak = 0.0, peakTime = 0.0, imbalance = 0.0
        var earlyImpulse = 0.0, netForcePeak = 0.0
        while run.time < 0.008 && run.step() {
            let load = run.normalLoad(0, 1)
            let dy = run.body(1).centerVelocity.y - initialVelocity
            netForcePeak = max(netForcePeak, (mass * dy - verticalImpulse) / run.dt)
            verticalImpulse = mass * dy
            if load > peak { peak = load; peakTime = run.time }
            impulse += 0.5 * (oldLoad + load) * run.dt
            if oldTime < 0.00405 {
                let fraction = min(1, (0.00405 - oldTime) / run.dt)
                earlyImpulse += fraction * run.dt * (oldLoad + 0.5 * fraction * (load - oldLoad))
            }
            oldLoad = load
            oldTime = run.time
            imbalance = max(imbalance, abs(run.energies.total / run.initialEnergy - 1))
            require(run.activeContacts.allSatisfy { ($0.x != 1 && $0.y != 1) || $0 == SIMD2(0, 1) },
                    "Another part applied force to the striker")
        }
        require(run.time >= 0.008 && run.failure == nil && (run.fractureReading(0)?.insertedEdges ?? -1) == 0
                    && imbalance < 0.005 && simd_distance(run.momentum, initialP) < 1e-9
                    && abs(run.angularMomentum - initialL) < 1e-9, "Elastic loading control violated conservation or failed")
        if let pad { require(run.padPeakCompression < pad.thickness, "Pad faces crossed") }
        let onset = run.firstContactTimes[SIMD2(0, 1)]!
        print(String(format: "%@ %@, dt %.3f µs: peak %.2f (vertical step peak %.2f) N/m at %+.3f ms after onset, early impulse %.5f, 8 ms impulse %.5f (vertical %.5f) N·s/m, max pad compression %.3f mm, ΔE %.4f%%",
                     pad.map { "pad n=\($0.samples)" } ?? "penalty ×\(Int(penalty))", test.label, run.dt * 1e6,
                     peak, netForcePeak, 1000 * (peakTime - onset), earlyImpulse, impulse, verticalImpulse,
                     run.padPeakCompression * 1000, 100 * imbalance))
    }

    for test in studyCases() where test.refinement >= 2 {
        try trial(test, pad: pad, penalty: 2, dt: step)
        if test.refinement == 3 {
            try trial(test, pad: pad, penalty: 2, dt: step / 2)
            try trial(test, pad: StrikerPad(thickness: pad.thickness, modulus: pad.modulus, samples: 64), penalty: 2, dt: step)
            for penalty in [1.0, 2.0, 4.0] { try trial(test, pad: nil, penalty: penalty, dt: step) }
            try trial(test, pad: nil, penalty: 4, dt: step / 2)
            try trial(AssemblyCase(mesh: test.mesh, refinement: 4, scene: test.scene), pad: pad, penalty: 2, dt: step)
        }
    }
}

func compliantFractureCheck(_ orientation: String, refinement: Int, halfStep: Bool) throws {
    let pad = StrikerPad(thickness: 0.004, modulus: 250_000, samples: 64)
    var scene = AssemblyScene.bendingFractureExample()
    guard let mesh = MaterialFractureSettings.MeshPattern.allCases.first(where: { $0.rawValue.lowercased() == orientation }) else {
        require(false, "Expected aligned or staggered")
        return
    }
    scene.parts[0].fracture?.meshPattern = mesh
    let test = AssemblyCase(mesh: mesh, refinement: refinement, scene: scene)
    let dt = halfStep ? 0.225e-6 : 0.45e-6
    let run = try notchedBend(test, stepLimit: dt, depth: 0.005, pad: pad)
    print(String(format: "%@ at step limit %.3f µs: peak %.2f N/m, advance %.3f mm, pad compression %.3f mm, energy error %.4f%%",
                 test.label, dt * 1e6, run.peakLoad, 1000 * run.maxAdvance, 1000 * run.compression, 100 * run.energyError))
    let work = run.finalWork.terms
    print(String(format: "Final fracture work (J/m): spent notch %.6f, spent elsewhere %.6f, partial at notch %.6f, partial elsewhere %.6f. Total %.6f.",
                 work.x, work.y, work.z, work.w, run.finalWork.total))
    if let insertion = run.firstInsertion {
        print(String(format: "First insertion %.3f ms, nearest inserted face midpoint %.2f mm from notch tip.",
                     1000 * insertion.time, 1000 * insertion.distanceFromTip))
    }
    if let contact = run.firstSupportContact { print(String(format: "First support contact %.3f ms.", 1000 * contact)) }
    if let match = run.matched {
        print(String(format: "Work at matched advance %.6f J/m, raw bracket %.6f–%.6f", match.work.total, match.rawWork.x, match.rawWork.y))
    } else {
        print("The 10.5 mm matched advance was not reached.")
    }
    if let error = run.error { print("STOPPED: \(error)") }
    require(run.error == nil && run.compression < pad.thickness && run.energyError < 0.005,
            "The compliant fracture control failed its mechanical checks")
}

func receiverRefinementCheck(extended: Bool = false) throws {
    var scene = AssemblyScene.bendingFractureExample()
    scene.parts[0].fracture?.meshPattern = .staggered
    let cutoff = scene.duration
    if extended { scene.duration = 0.155 }
    let test = AssemblyCase(mesh: .staggered, refinement: 3, scene: scene)
    let run = try simulateAssembly(test, stepScale: extended ? 0.5 : 0.25,
                                   receiverObservationTime: extended ? cutoff : nil)
    printAssembly(test.label + (extended ? ", extended half step" : ", quarter step"), run)
    if let impulse = run.receiverImpulseAtObservation {
        print(String(format: "Receiver impulse at the original %.0f ms observation limit %.6f N·s/m", 1000 * cutoff, impulse))
    }
    print(String(format: "Receiver impulse %.6f N·s/m from %d episodes, %d tagged on newly exposed faces",
                 run.receiverEvents.map(\.normalImpulse).reduce(0, +),
                 run.receiverEvents.count, run.receiverEvents.filter(\.onExposedFace).count))
    require(run.error == nil && run.time >= scene.duration && run.penetration < 0.02 &&
            run.imbalance < 0.005 && max(run.momentum, run.angularMomentum) < 1e-9,
            "Receiver replay failed a contact or conservation check")
}

// Contact invariants under the production (recovered-stress) insertion
// criterion, on whatever trajectory that criterion produces. Same invariants
// as the pinned detachment replay, without its trajectory-specific piece count.
func contactHandoffCheck() throws -> Bool {
    var pass = true
    for pattern in MaterialFractureSettings.MeshPattern.allCases {
        var scene = AssemblyScene.bendingFractureExample()
        scene.parts[0].fracture?.meshPattern = pattern
        var s = try AssemblySimulation(scene, refinement: 3, stepLimit: .infinity)
        s.probeDetachment = true
        let initialP = s.momentum, initialL = s.angularMomentum
        var imbalance = 0.0, momentum = 0.0, angular = 0.0
        while s.step() {
            imbalance = max(imbalance, abs(s.energies.total / s.initialEnergy - 1))
            momentum = max(momentum, simd_distance(s.momentum, initialP))
            angular = max(angular, abs(s.angularMomentum - initialL))
        }
        let attempted = max(s.peakRelativePenetration, s.rejectedPenetration ?? 0)
        let detachment = s.detachmentProbes.map { abs($0.energyJump) }.max() ?? 0
        let pieces = s.fractureReading(0)!.pieces
        let ok = s.failure == nil && s.time >= scene.duration && !s.detachmentProbes.isEmpty
            && max(detachment, s.maxInsertionContactJump, s.maxInterbodyTopologyJump) < 1e-10 * max(1, s.initialEnergy)
            && attempted <= 0.02 && imbalance < 0.005 && max(momentum, angular) < 1e-9
        print(String(format: "%@ ×3 production insertion: %d pieces, %d detachments; fixed-position contact change at detachment %.2e, splitting %.2e, interbody %.2e J/m; penetration %.3f%%, energy %.4f%%, ΔP %.2e, ΔL %.2e — %@%@",
                     pattern.rawValue, pieces, s.detachmentProbes.count, detachment, s.maxInsertionContactJump, s.maxInterbodyTopologyJump,
                     100 * attempted, 100 * imbalance, momentum, angular, ok ? "PASS" : "FAIL", s.failure.map { " (\($0))" } ?? ""))
        pass = pass && ok
    }
    return pass
}
