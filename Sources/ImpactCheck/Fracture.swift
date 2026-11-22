import Foundation
import ImpactPhysics
import Darwin
import simd

private func moment(_ a: Point, _ b: Point) -> Double { a.x * b.y - a.y * b.x }

func slidingDetachmentPatch() {
    let length = 0.02
    let points = [Point(0, 0), Point(length, 0), Point(length / 2, length), Point(length / 2, -length)]
    let mesh = Mesh(reference: points, triangles: [(0, 1, 2), (1, 0, 3)],
                    boundary: [Edge(1, 2), Edge(2, 0), Edge(0, 3), Edge(3, 1)])
    let material = Material()
    let body = Body(mesh: mesh, material: material, position: points, velocity: .zero)
    let settings = MaterialFractureSettings()
    let strength = settings.strengthFraction * material.young
    let slipAtFailure = 2 * settings.energy / strength
    let expectedWork = length * settings.energy
    var patch = MaterialFracture(body: body, settings: settings)
    require(patch.probeContact(at: points).features.isEmpty, "The intact patch self-contacted")
    let piola = ElementPiola(.zero, Point(-strength, 0))
    let split = patch.insert(position: points, piola: [piola, piola], mesh: mesh)!
    let reference = split.mesh.reference
    let moving = split.mesh.elements[1]
    func positions(slip: Double, compression: Double) -> [Point] {
        var result = reference
        for node in [moving.a, moving.b, moving.c] { result[node] += Point(slip, compression) }
        return result
    }
    func state(_ position: [Point]) -> Int {
        var force = Array(repeating: Point.zero, count: reference.count)
        require(patch.accumulate(position: position, reference: reference, force: &force, pairedClosure: false) == 0,
                "Geometric closure was duplicated in the cohesive law")
        let torque = zip(position, force).reduce(0.0) { $0 + moment($1.0, $1.1) }
        require(simd_length(force.reduce(.zero, +)) < 1e-9 && abs(torque) < 1e-9,
                "The cohesive patch lost force or moment balance")
        return patch.reading.pieces
    }
    let inserted = state(reference)
    require(split.sources.count > points.count && inserted == 1,
            "Node splitting changed the collision topology or added contact energy at zero gap")
    let feature = SIMD3(0, 3, 4)
    let beforeSplitNode = mesh.elements[0].a
    let afterSplitNode = patch.contactTrack(feature, at: reference)
    require(afterSplitNode.nodes.x == beforeSplitNode && afterSplitNode.nodes.x != afterSplitNode.nodes.z
            && split.sources[afterSplitNode.nodes.z] == beforeSplitNode,
            "Material corners did not track the new sector of a split node")
    let compression = min(0.001 * length, 0.1 * slipAtFailure)
    let increment = 1e-8 * slipAtFailure
    let stiffness = 120 * material.young
    func probe(_ position: [Point]) -> TriangleContactProbe {
        let contact = probeTriangleContact(mesh: split.mesh, positions: position, stiffness: stiffness)
        let torque = zip(position, contact.force).reduce(0.0) { $0 + moment($1.0, $1.1) }
        require(simd_length(contact.force.reduce(.zero, +)) < 1e-9 && abs(torque) < 1e-9,
                "Triangle contact lost force or moment balance")
        return contact
    }
    require(probe(reference).energy == 0, "Splitting at zero gap seeded contact energy")
    let earlier = positions(slip: slipAtFailure - increment, compression: compression)
    let later = positions(slip: slipAtFailure + increment, compression: compression)
    let before = state(earlier), after = state(later)
    let beforeContact = probe(earlier), afterContact = probe(later)
    let forceJump = zip(beforeContact.force, afterContact.force).map { simd_length($0 - $1) }.max()!
    let forceScale = afterContact.force.map { simd_length($0) }.max()!
    require(before == 1 && after == 2 &&
            abs(patch.reading.dissipation - expectedWork) < 1e-12, "Patch did not detach at the prescribed work")
    require(afterContact.energy > 0 && abs(afterContact.energy - beforeContact.energy) < 1e-10 &&
            forceJump / forceScale < 1e-5, "Detachment changed live geometric closure")

    let slip = 0.15 * length
    let open = probe(positions(slip: slip, compression: -compression))
    require(open.energy == 0 && open.force.allSatisfy { $0 == .zero }, "Traction remained on an open seam")
    let small = 1e-4 * compression
    let touching = probe(positions(slip: slip, compression: small))
    let closedPosition = positions(slip: slip, compression: compression)
    let closed = probe(closedPosition)
    let slid = probe(positions(slip: 1.1 * slip, compression: compression))
    let reaction = -(closed.force[moving.a] + closed.force[moving.b] + closed.force[moving.c])
    let touchReaction = -(touching.force[moving.a] + touching.force[moving.b] + touching.force[moving.c])
    let incrementY = 1e-4 * compression
    let high = probe(positions(slip: slip, compression: compression + incrementY)).energy
    let low = probe(positions(slip: slip, compression: compression - incrementY)).energy
    require(closed.energy > 0 && closed.relativePenetration < 0.02 &&
            abs((high - low) / (2 * incrementY) - reaction.y) < 1e-5,
            "Recontact penalty work or penetration was inconsistent")
    require(abs(touchReaction.y / reaction.y - small / compression) < 1e-9 &&
            abs(slid.energy / closed.energy - 1) < 1e-6 && abs(reaction.x / reaction.y) < 1e-6,
            "Frictionless sliding or force activation was inconsistent")

    // Test a proper edge crossing with all six vertices outside the opposing triangle.
    let edgeCrossing = [Point(-0.02, -0.001), Point(0.02, -0.001), Point(0, 0.001),
                        Point(-0.001, -0.02), Point(0.001, -0.02), Point(0, 0.02)]
    let crossingMesh = Mesh(reference: edgeCrossing, triangles: [(0, 1, 2), (3, 4, 5)], boundary: [])
    let crossing = probeTriangleContact(mesh: crossingMesh, positions: edgeCrossing, stiffness: stiffness)
    require(crossing.energy > 0 && crossing.force.contains { simd_length($0) > 0 },
            "Contact missed an edge crossing with no contained vertices")
    let step = 1e-8
    var gradientError = 0.0
    for i in edgeCrossing.indices {
        for j in 0..<2 {
            var plus = edgeCrossing, minus = edgeCrossing
            plus[i][j] += step
            minus[i][j] -= step
            let upper = probeTriangleContact(mesh: crossingMesh, positions: plus, stiffness: stiffness).energy
            let lower = probeTriangleContact(mesh: crossingMesh, positions: minus, stiffness: stiffness).energy
            gradientError = max(gradientError, abs((upper - lower) / (2 * step) + crossing.force[i][j]))
        }
    }
    require(gradientError < 1e-6 * crossing.force.map { simd_length($0) }.max()!,
            "Edge crossing force is inconsistent with the contact potential")
    print(String(format: "Sliding patch: live energy change %+.2e J/m, relative force change %.2e, recontact %.4f%% penetration, work %.6f J/m",
                 afterContact.energy - beforeContact.energy, forceJump / forceScale,
                 100 * closed.relativePenetration, patch.reading.dissipation))
}

private func cohesivePatchCheck() {
    let length = 0.02
    let points = [Point(0, 0), Point(length, 0), Point(length / 2, length), Point(length / 2, -length)]
    let mesh = Mesh(reference: points, triangles: [(0, 1, 2), (1, 0, 3)],
                    boundary: [Edge(1, 2), Edge(2, 0), Edge(0, 3), Edge(3, 1)])
    let material = Material()
    let body = Body(mesh: mesh, material: material, position: points, velocity: .zero)
    let settings = MaterialFractureSettings()
    let strength = settings.strengthFraction * material.young
    let physicalSpan = 2 * settings.energy / strength
    let expected = length * settings.energy
    for (label, loading) in [("opening", Point(0, -1)), ("sliding", Point(1, 0)), ("mixed", Point(0.6, -0.8))] {
        var specimen = MaterialFracture(body: body, settings: settings)
        require(specimen.reading.insertedEdges == 0, "Patch starts with cohesive elements")
        let piola = ElementPiola(.zero, -strength * loading)
        let split = specimen.insert(position: points, piola: [piola, piola], mesh: mesh)!
        let reference = split.mesh.reference
        require(reference.count == 6 && specimen.reading.insertedEdges == 1, "Patch failed to split just its two endpoints")
        let right = split.mesh.elements[1]
        let rightNodes = Set([right.a, right.b, right.c])
        let increment = 1.1 * physicalSpan / 1600
        let initial = specimen
        var work = 0.0, previousReaction = 0.0, preloadError = 0.0
        let angle = 0.42
        func rotate(_ p: Point) -> Point {
            Point(cos(angle) * p.x - sin(angle) * p.y, sin(angle) * p.x + cos(angle) * p.y)
        }
        func positions(_ gap: Double) -> [Point] {
            reference.enumerated().map { i, p in
                rotate(p + (rightNodes.contains(i) ? gap * loading : .zero)) + Point(0.11, -0.08)
            }
        }
        for i in 0...1600 {
            let position = positions(Double(i) * increment)
            var force = Array(repeating: Point.zero, count: reference.count)
            require(specimen.accumulate(position: position, reference: reference, force: &force) != nil, "Cohesive patch failed")
            let rightForce = [right.a, right.b, right.c].reduce(Point.zero) { $0 + force[$1] }
            let reaction = -simd_dot(rightForce, rotate(loading))
            let torque = zip(position, force).reduce(0.0) { $0 + moment($1.0, $1.1) }
            require(simd_length(force.reduce(.zero, +)) < 1e-10 && abs(torque) < 1e-10, "Cohesive resultant or torque")
            if i == 0 {
                preloadError = simd_length(rightForce + length * strength * rotate(loading)) / (length * strength)
                require(abs(specimen.reading.storedEnergy) < 1e-13 && abs(specimen.reading.dissipation) < 1e-13,
                        "Insertion created energy")
            } else {
                work += 0.5 * (reaction + previousReaction) * increment
            }
            previousReaction = reaction
        }
        require(preloadError < 0.01 && abs(work / expected - 1) < 0.01, "Insertion traction or separation work")
        require(abs(specimen.reading.dissipation - expected) < 1e-12 && specimen.reading.failedEdges == 1
                    && specimen.reading.pieces == 2 && specimen.reading.storedEnergy == 0,
                "Fully spent patch did not account for Gc or become two independent faces")
        print(String(format: "Insertion patch %@: traction jump %.2e of strength, work %.8f vs %.8f J/m",
                     label, preloadError, work, expected))
        if label == "mixed" {
            var unloading = initial
            var force = Array(repeating: Point.zero, count: reference.count)
            _ = unloading.accumulate(position: positions(0.5 * physicalSpan), reference: reference, force: &force)
            let damage = unloading.reading.dissipation
            _ = unloading.accumulate(position: positions(0.2 * physicalSpan), reference: reference, force: &force)
            require(unloading.reading.dissipation == damage && damage > 0, "An inserted face healed on unloading")

            let distorted = reference.enumerated().map { i, p in
                rotate(p + (rightNodes.contains(i) ? Point(-1.2e-6 * Double(i), 2e-6) : .zero))
            }
            func potential(_ positions: [Point]) -> (Double, [Point]) {
                var patch = initial
                var force = Array(repeating: Point.zero, count: reference.count)
                let contact = patch.accumulate(position: positions, reference: reference, force: &force)!
                require(patch.reading.dissipation == 0, "Gradient patch must unload elastically")
                return (patch.reading.storedEnergy + contact, force)
            }
            let analytic = potential(distorted).1
            var error = 0.0
            for i in distorted.indices {
                for d in 0..<2 {
                    var plus = distorted, minus = distorted
                    plus[i][d] += 1e-8
                    minus[i][d] -= 1e-8
                    let derivative = (potential(plus).0 - potential(minus).0) / 2e-8
                    error = max(error, abs(analytic[i][d] + derivative))
                }
            }
            require(error < 1e-4, "Inserted cohesive force is not the negative potential gradient")
            print(String(format: "Inserted interface unloading force-gradient residual %.2e N/m", error))
        }
    }
}

private struct FractureOutcome {
    var dt = 0.0
    var energyError = 0.0
    var linearResidual = 0.0
    var angularResidual = 0.0
    var firstDamage = 0.0
    var firstSplit = 0.0
    var firstSplitX = 0.0
    var peakStress = 0.0
    var crackLength = 0.0
    var dissipation = 0.0
    var pieces = 0
    var receiverFaceTime: Double?
    var receiverSpeed = 0.0
}

private func intactComplianceCheck() throws {
    var scene = AssemblyScene()
    let specimen = AssemblyPart("Wave specimen", size: Point(0.16, 0.036))
    var striker = AssemblyPart("Weak pulse source", center: Point(-0.102, 0), size: Point(0.04, 0.036))
    striker.velocity.x = 0.08
    scene.parts = [specimen, striker]
    scene.duration = 0.042
    func stiffness(_ scene: AssemblyScene) throws -> (nodes: Int, axial: Double) {
        let body = try AssemblySimulation(scene).body(0)
        let probe = Simulation(mesh: body.mesh, material: body.material)
        let strain = 1e-4
        let right = body.mesh.reference.map(\.x).max()!
        let stretched = body.mesh.reference.map { Point((1 + strain) * $0.x, $0.y) }
        let force = probe.internalForces(at: stretched)!
        let reaction = body.mesh.reference.indices.filter { body.mesh.reference[$0].x == right }.reduce(0.0) { $0 - force[$1].x }
        return (body.mesh.reference.count, reaction / strain)
    }
    func arrival() throws -> Double {
        // Use identical contact compliance for the bulk response comparison.
        var s = try AssemblySimulation(scene, refinement: 1, stepLimit: 0.9e-6, interbodyStiffnessScale: 1)
        let mesh = s.body(0).mesh
        let gauge = mesh.elements.indices.filter { i in
            let e = mesh.elements[i]
            let x = (mesh.reference[e.a].x + mesh.reference[e.b].x + mesh.reference[e.c].x) / 3
            return (0.033...0.041).contains(x)
        }
        var crossing: Double?
        while s.step() {
            if crossing == nil {
                let strain = s.strain(0)
                let mean = gauge.reduce(0.0) { $0 + strain[$1] } / Double(gauge.count)
                if mean < -0.0004, let contact = s.firstContactTimes[SIMD2(0, 1)] { crossing = s.time - contact }
            }
        }
        require(s.failure == nil && (s.fractureReading(0)?.damagedEdges ?? 0) == 0, "Weak pulse initiated material fracture")
        require(crossing != nil, "Weak pulse never reached the gauge")
        return crossing!
    }
    let intact = try arrival()
    let shared = try stiffness(scene)
    scene.parts[0].fracture = MaterialFractureSettings()
    let eligible = try arrival()
    let insertionReady = try stiffness(scene)
    print(String(format: "Intact patch: %d shared nodes, axial stiffness %.4f vs %.4f N/m per unit strain; pulse %.3f vs %.3f ms",
                 shared.nodes, shared.axial, insertionReady.axial, intact * 1000, eligible * 1000))
    require(insertionReady.nodes == shared.nodes && abs(insertionReady.axial / shared.axial - 1) < 0.01
                && abs(eligible / intact - 1) < 0.01, "Undamaged enabled mesh diverges from shared-node stiffness")
}

private func coupledPlasticityCheck(_ base: AssemblyScene) throws {
    var scene = base
    scene.parts[0].plasticity.response = .elastoplastic
    scene.parts[0].fracture?.strengthFraction = 0.018
    scene.duration = 0.022
    var simulation = try AssemblySimulation(scene)
    while simulation.step() {}
    let energy = simulation.energies
    let reading = simulation.fractureReading(0)!
    require(simulation.failure == nil && simulation.time >= scene.duration, simulation.failure ?? "Coupled run stopped early")
    require(reading.dissipation > 0 && energy.plastic > 0 && (simulation.plasticStrain(0).max() ?? 0) > 0,
            "Plastic deformation and cohesive damage did not coexist in the same specimen")
    print(String(format: "Coupled J2 and fracture: plastic %.4f, material fracture %.4f J/m",
                 energy.plastic, reading.dissipation))
}

private func runFracture(_ label: String, _ scene: AssemblyScene, stepLimit: Double = .infinity) throws -> FractureOutcome {
    var simulation = try AssemblySimulation(scene, refinement: scene.resolution.rawValue, stepLimit: stepLimit)
    require(simulation.initialIssue == nil, simulation.initialIssue ?? "")
    let initialP = simulation.momentum, initialL = simulation.angularMomentum
    let initialMass = simulation.materialPieces(0).reduce(0) { $0 + $1.mass }

    let start = ProcessInfo.processInfo.systemUptime
    var outcome = FractureOutcome(dt: simulation.dt)
    var sampleAt = 0.0
    var stepCount = 0, previousEdges = 0, previousPieces = 1
    var previousLoss = 0.0
    while simulation.step() {
        stepCount += 1
        let reading = simulation.fractureReading(0)!
        let e = simulation.energies
        outcome.energyError = max(outcome.energyError, abs(e.total / simulation.initialEnergy - 1))
        outcome.linearResidual = max(outcome.linearResidual, simd_length(simulation.momentum - initialP))
        outcome.angularResidual = max(outcome.angularResidual, abs(simulation.angularMomentum - initialL))
        require(reading.failedEdges >= previousEdges && reading.pieces >= previousPieces && reading.dissipation >= previousLoss - 1e-12,
                "Irreversible topology or dissipation regressed")
        if outcome.firstDamage == 0, reading.damagedEdges > 0 { outcome.firstDamage = simulation.time }
        if reading.pieces > previousPieces {
            let sum = simulation.materialPieces(0).reduce(0) { $0 + $1.mass }
            require(abs(sum / initialMass - 1) < 1e-12, "Topology transition did not preserve mass")
            if outcome.firstSplit == 0 {
                outcome.firstSplit = simulation.time
                let faces = simulation.crackFaces(0).filter { $0.damage == 1 }
                let position = simulation.body(0).mesh.reference
                let span = faces.reduce(0.0) { $0 + simd_distance(position[$1.first.a], position[$1.first.b]) }
                outcome.firstSplitX = faces.reduce(0.0) {
                    let a = position[$1.first.a], b = position[$1.first.b]
                    return $0 + 0.5 * (a.x + b.x) * simd_distance(a, b)
                } / span
            }
        }
        if simulation.time >= sampleAt {
            // Sample the spatial peak on a common physical-time grid.
            outcome.peakStress = max(outcome.peakStress, simulation.stress(0).max() ?? 0)
            sampleAt += SceneRun.sampleInterval
        }
        previousEdges = reading.failedEdges
        previousPieces = reading.pieces
        previousLoss = reading.dissipation
    }
    require(simulation.failure == nil && simulation.time >= scene.duration, "\(label): \(simulation.failure ?? "stopped early") at \(simulation.time * 1000) ms")
    let reading = simulation.fractureReading(0)!
    let balance = reading.insertionBalance
    outcome.crackLength = reading.crackLength
    outcome.dissipation = reading.dissipation
    outcome.pieces = reading.pieces
    outcome.receiverFaceTime = simulation.fragmentContacts.first {
        $0.parts == SIMD2(0, 4) && $0.onExposedFace
    }?.firstExposedTime
    outcome.receiverSpeed = simd_length(simulation.body(4).centerVelocity)
    let triangles = (0..<simulation.bodyCount).reduce(0) { $0 + simulation.body($1).mesh.elements.count }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print(String(format: "%@: %d triangles, %d steps × %.3f µs in %.2f s; damage %.3f ms, split %.3f ms at x̄ %.2f mm; %d pieces, L %.2f mm, G %.4f J/m; peak VM %.2f kPa; receiver face %.3f ms, |v| %.3f m/s; overlap %.2f%%, E %.3f%%, ΔP %.2e, ΔL %.2e",
                 label, triangles, stepCount, simulation.dt * 1e6, elapsed, outcome.firstDamage * 1000,
                 outcome.firstSplit * 1000, outcome.firstSplitX * 1000, reading.pieces, reading.crackLength * 1000,
                 reading.dissipation, outcome.peakStress / 1000, (outcome.receiverFaceTime ?? 0) * 1000, outcome.receiverSpeed,
                 simulation.peakRelativePenetration * 100, outcome.energyError * 100,
                 outcome.linearResidual, outcome.angularResidual))
    print(String(format: "Insertion balance ΔM %.2e kg/m, ΔP %.2e N·s/m, ΔL %.2e N·s, ΔK %.2e J/m; seeded jump %.2e, adjacent bulk traction disagreement %.2f × strength",
                 balance.mass, balance.momentum, balance.angularMomentum, balance.kinetic,
                 reading.peakSeedTractionError, reading.peakBulkTractionGap))
    require(max(balance.mass, balance.momentum, balance.angularMomentum, balance.kinetic) < 1e-12
                && reading.peakSeedTractionError < 0.01, "Insertion failed the state transfer or resolved-traction check")
    require(outcome.linearResidual < 1e-9 && outcome.angularResidual < 1e-9, "Fracture assembly lost momentum")
    require(outcome.energyError < 0.008 && simulation.peakRelativePenetration < 0.05, "Fracture run exceeded verification envelope")
    require(outcome.firstDamage > 0 && outcome.firstDamage < outcome.firstSplit && reading.pieces >= 2,
            "The load did not nucleate damage followed by separation")
    require(reading.dissipation + 1e-12 >= scene.parts[0].fracture!.energy * reading.crackLength,
            "The assembly undercounted fracture work on broken faces")

    return outcome
}

func fractureCheck() throws {
    cohesivePatchCheck()
    let base = AssemblyScene.bendingFractureExample()
    try intactComplianceCheck()
    try coupledPlasticityCheck(base)
    _ = try runFracture("Standard", base)
    var alternate = base
    alternate.parts[0].fracture?.meshPattern = .staggered
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: file) }
    try alternate.save(to: file)
    require(try AssemblyScene.open(file) == alternate, "Mesh pattern or fracture settings did not round-trip")
}
