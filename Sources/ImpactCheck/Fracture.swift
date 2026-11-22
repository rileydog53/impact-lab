import Foundation
import ImpactPhysics
import Darwin
import simd

private func moment(_ a: Point, _ b: Point) -> Double { a.x * b.y - a.y * b.x }

private func cohesivePatchCheck() {
    let length = 0.02
    let points = [Point(0, 0), Point(length, 0), Point(length / 2, length), Point(length / 2, -length)]
    let mesh = Mesh(reference: points, triangles: [(0, 1, 2), (1, 0, 3)],
                    boundary: [Edge(1, 2), Edge(2, 0), Edge(0, 3), Edge(3, 1)])
    let material = Material()
    let body = Body(mesh: mesh, material: material, position: points, velocity: .zero)
    let settings = MaterialFractureSettings()
    let initial = MaterialFracture(body: body, settings: settings)
    let base = initial.discretize(body).position
    let strength = settings.strengthFraction * material.young
    let finalOpening = 2 * settings.energy / strength
    var specimen = initial
    var work = 0.0, previousForce = 0.0
    let count = 2400

    // Drive two triangles in translated, rotated mixed mode with equal mode toughness.
    let loading = Point(0.6, -0.8)
    let angle = 0.42
    func rotate(_ p: Point) -> Point { Point(cos(angle) * p.x - sin(angle) * p.y, sin(angle) * p.x + cos(angle) * p.y) }
    func positions(_ opening: Double) -> [Point] {
        base.enumerated().map { i, p in rotate(p + (i >= 3 ? opening * loading : .zero)) + Point(0.11, -0.08) }
    }
    let increment = 1.15 * finalOpening / Double(count)
    for i in 0...count {
        let p = positions(Double(i) * increment)
        var force = Array(repeating: Point.zero, count: base.count)
        require(specimen.accumulate(position: p, force: &force) != nil, "Cohesive patch failed")
        let reaction = -simd_dot(force[3...].reduce(.zero, +), rotate(loading))
        let torque = zip(p, force).reduce(0.0) { $0 + moment($1.0, $1.1) }
        require(simd_length(force.reduce(.zero, +)) < 1e-10 && abs(torque) < 1e-10, "Cohesive resultant or torque")
        if i > 0 { work += 0.5 * (reaction + previousForce) * increment }
        previousForce = reaction
    }
    let expected = length * settings.energy
    require(abs(work / expected - 1) < 0.0001 && abs(specimen.reading.dissipation - expected) < 1e-12,
            "Mixed-mode work or damage dissipation differs from Gc times edge length")
    require(specimen.reading.failedEdges == 1 && specimen.reading.pieces == 2 && specimen.reading.storedEnergy == 0,
            "Fully spent cohesive edge did not become two independent faces")

    // Reloading below a previous tensile maximum cannot heal the interface.
    var unloading = initial
    var force = Array(repeating: Point.zero, count: base.count)
    _ = unloading.accumulate(position: positions(0.6 * finalOpening), force: &force)
    let damaged = unloading.reading
    force = Array(repeating: .zero, count: base.count)
    _ = unloading.accumulate(position: positions(0.2 * finalOpening), force: &force)
    require(unloading.reading.dissipation == damaged.dissipation &&
            abs(unloading.reading.storedEnergy / damaged.storedEnergy - 1.0 / 9) < 1e-10,
            "Unloading changed history or deviated from the damaged secant")

    // Differentiate the mixed-mode energy in an oblique, nonuniform closed patch.
    // This checks the torque correction from the rotating frame, including compression.
    let distorted = base.enumerated().map { i, p in
        rotate(p + (i >= 3 ? Point(1.2e-6 * Double(i - 2), 2.0e-6) : .zero))
    }
    func potential(_ p: [Point]) -> (Double, [Point]) {
        var s = initial
        var f = Array(repeating: Point.zero, count: p.count)
        let contact = s.accumulate(position: p, force: &f)!
        require(s.reading.dissipation == 0, "Finite-difference patch must remain elastic")
        return (s.reading.storedEnergy + contact, f)
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
    print(String(format: "Cohesive patch: mixed-mode work %.8f J/m vs Gc L %.8f J/m; max force-gradient residual %.2e N/m",
                 work, expected, error))
    require(error < 1e-6, "Cohesive force is not the negative energy gradient")
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
    func arrival() throws -> Double {
        var s = try AssemblySimulation(scene, refinement: 1, stepLimit: 0.9e-6)
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
    scene.parts[0].fracture = MaterialFractureSettings()
    let eligible = try arrival()
    print(String(format: "Undamaged pulse delay: shared nodes %.3f ms, cohesive mesh %.3f ms (%+.2f%%)",
                 intact * 1000, eligible * 1000, 100 * (eligible / intact - 1)))
    require(abs(eligible / intact - 1) < 0.08, "Excessive undamaged cohesive compliance in the pulse check")
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
    let position = simulation.body(0).mesh.reference
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
    outcome.crackLength = reading.crackLength
    outcome.dissipation = reading.dissipation
    outcome.pieces = reading.pieces
    outcome.receiverFaceTime = simulation.fragmentContacts.first {
        $0.parts == SIMD2(0, 4) && $0.onExposedFace
    }?.time
    outcome.receiverSpeed = simd_length(simulation.body(4).centerVelocity)
    let triangles = (0..<simulation.bodyCount).reduce(0) { $0 + simulation.body($1).mesh.elements.count }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print(String(format: "%@: %d triangles, %d steps × %.3f µs in %.2f s; damage %.3f ms, split %.3f ms at x̄ %.2f mm; %d pieces, L %.2f mm, G %.4f J/m; peak VM %.2f kPa; receiver face %.3f ms, |v| %.3f m/s; overlap %.2f%%, E %.3f%%, ΔP %.2e, ΔL %.2e",
                 label, triangles, stepCount, simulation.dt * 1e6, elapsed, outcome.firstDamage * 1000,
                 outcome.firstSplit * 1000, outcome.firstSplitX * 1000, reading.pieces, reading.crackLength * 1000,
                 reading.dissipation, outcome.peakStress / 1000, (outcome.receiverFaceTime ?? 0) * 1000, outcome.receiverSpeed,
                 simulation.peakRelativePenetration * 100, outcome.energyError * 100,
                 outcome.linearResidual, outcome.angularResidual))
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
    let reference = try runFracture("Standard", base)
    let half = try runFracture("Standard, half step", base, stepLimit: reference.dt / 2)
    var fine = base
    fine.meshResolution = .fine
    var extraFine = base
    extraFine.meshResolution = .extraFine
    let commonStep = min(half.dt, try AssemblySimulation(extraFine).dt)
    let refined = try runFracture("Fine, common step", fine, stepLimit: commonStep)
    let extra = try runFracture("Extra fine, common step", extraFine, stepLimit: commonStep)
    var usage = rusage()
    if getrusage(RUSAGE_SELF, &usage) == 0 {
        print(String(format: "Process peak resident memory %.2f MiB", Double(usage.ru_maxrss) / 1_048_576))
    }
    var shifted = base
    shifted.parts[1].center.x = 0.023
    let changed = try runFracture("Striker moved +41 mm", shifted)
    require(abs(reference.firstSplitX - changed.firstSplitX) > 0.02,
            "Moving the striker did not change the through-fracture location")
    require([reference, half].allSatisfy { ($0.receiverFaceTime ?? 0) > $0.firstSplit && $0.receiverSpeed > 0.10 },
            "Missing contact with a detached specimen's newly exposed face")

    require(changed.receiverSpeed > 0.10, "The relocated-striker experiment did not transfer momentum to its receiver")

    let timeDelta = abs(half.firstSplit / reference.firstSplit - 1)
    let meshDelta = abs(extra.firstSplit / refined.firstSplit - 1)
    let localDelta = abs(extra.peakStress / refined.peakStress - 1)
    print(String(format: "Sensitivity: step halving first split %.2f%%; fine → extra fine first split %.2f%%, sampled local stress peak %.2f%%",
                 100 * timeDelta, 100 * meshDelta, 100 * localDelta))
    require(timeDelta < 0.04 && abs(reference.firstSplitX - half.firstSplitX) < 0.009,
            "Standard result is too sensitive to timestep")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    try extraFine.save(to: url)
    let reopened = try AssemblyScene.open(url)
    require(reopened == extraFine && reopened.resolution == .extraFine, "Fracture scene settings did not round-trip")
}
