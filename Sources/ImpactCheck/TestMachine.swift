import Foundation
import ImpactPhysics
import simd

// Virtual test machine (milestone "trustworthy ordinary experiments", docs/MILESTONE_trustworthy_ordinary_experiments.md):
// a moving grip pulls or pushes one edge of a coupon whose opposite edge is clamped. The test reads the grip force,
// the strain between two gauge marks in the middle of the coupon, the section force across the middle, the clamp
// force and the grip work, the way a materials-testing machine and an extensometer would.
//
// NUMERICAL VERIFICATION against the input material law and continuum theory, not experimental validation. The model
// is 2-D plane strain, so a coupon is a wide plate (no out-of-plane strain), not a round bar. In uniaxial stress
// with plane strain the elastic slope is the plane-strain modulus E' = E / (1 − ν²), and yield starts above the input
// yield stress, because the out-of-plane stress σzz = ν σxx adds to the von Mises stress.
//
// Criteria fixed before the first run (2026-11-25), from the milestone's pass table:
//  1. Elastic slope (least squares on the gauge stress-strain points between 10% and 50% of first yield) within 2% of E'.
//  2. 0.2%-offset yield within 2% of the reference. Offset method: the line through 0.2% strain with the slope
//     measured in (1) (ASTM E8/E8M practice); the yield is where the stress-strain curve first falls below that
//     line, interpolated linearly between samples. The reference is the same offset method applied to an independent
//     small-strain calculation of one material point in plane strain under uniaxial stress (σyy = 0, εzz = 0), using
//     the input E, ν and flow curve. It is written below without any solver code.
//  3. Grip force against the section force across the middle and against the clamp force: within 2% at every sample
//     after the ramp where the grip force is above 20% of its peak (quasi-static regime).
//  4. Grip work closes the energy ledger: |kinetic + stored + dissipated − grip work| at most 0.5% of the grip work,
//     at every sample where the grip work is above 10% of its final value.
//  5. Halving the grip speed changes the slope and the offset yield by under 2%.
//  6. Mesh refinement (fine against x4): slope and offset yield agree within 1% (declared here, reported, not tuned).
//  7. With no grip anywhere, every saved scene replays bit for bit (`--legacy-replay check`, run separately).
//  8. A brittle coupon pulled until it cracks: the fracture guard accepts every step (its energy scale includes the
//     grip work), every gripped node, including nodes a crack splits, stays exactly on the prescribed path, and a crack
//     opens.

private struct Coupon {
    enum Kind { case tension, compression }
    var kind: Kind
    var profile: MaterialProfile
    var resolution: AssemblyScene.Resolution = .x4
    /// Loading time in wave transits of the coupon's length.
    var transits = 150.0
    var length = 0.12
    var width: Double { kind == .tension ? 0.015 : 0.024 }
    /// Overall engineering strain the grip reaches.
    var strain = 0.01

    var axis: Int { kind == .tension ? 0 : 1 }
    var sign: Double { kind == .tension ? 1 : -1 }
    var waveSpeed: Double {
        let m = profile.material
        return (m.young * (1 - m.poisson) / (m.density * (1 + m.poisson) * (1 - 2 * m.poisson))).squareRoot()
    }
    var loadingTime: Double { transits * length / waveSpeed }
    var ramp: Double { 10 * length / waveSpeed }
    var speed: Double { strain * length / loadingTime }

    var scene: AssemblyScene {
        var scene = AssemblyScene()
        var part = AssemblyPart(kind == .tension ? "Tension coupon" : "Compression block",
                                size: kind == .tension ? Point(length, width) : Point(width, length))
        profile.apply(to: &part)
        part.support = kind == .tension ? .clampLeft : .clampBottom
        var velocity = Point.zero
        velocity[axis] = sign * speed
        part.grip = AssemblyPart.Grip(edge: kind == .tension ? .right : .top, velocity: velocity, ramp: ramp)
        scene.parts = [part]
        scene.meshResolution = resolution
        scene.duration = loadingTime + ramp / 2
        return scene
    }
}

private struct MachineSample {
    var strain, stress, grip, section, clamp, work, residual: Double
}

private struct MachineRun {
    var samples: [MachineSample]
    var slope: Double
    var offsetYield: Double?
    var worstBalance: Double
    var worstLedger: Double
    /// Grip work from the sampled force-displacement record (trapezoid), as a fraction of the solver's grip work.
    var recordedWorkGap: Double
    var steps: Int
    var dt: Double
}

/// Independent reference: one material point, small strain, plane strain (εzz = 0) under uniaxial stress (σyy = 0),
/// von Mises yield with isotropic hardening from the flow curve, radial return. Returns (εxx, σxx) pairs.
private func materialPointCurve(_ profile: MaterialProfile, to maximum: Double, increments: Int = 4000) -> [(Double, Double)] {
    let E = profile.material.young, nu = profile.material.poisson
    let G = E / (2 * (1 + nu)), K = E / (3 * (1 - 2 * nu))
    let points = profile.hardening.points.map { ($0.strain, $0.stress) }
    func flow(_ a: Double) -> Double {
        for k in 1..<points.count where a <= points[k].0 {
            let (a0, s0) = points[k - 1], (a1, s1) = points[k]
            return s0 + (s1 - s0) * (a - a0) / (a1 - a0)
        }
        return points.last!.1
    }
    struct State { var plastic = SIMD3<Double>(repeating: 0); var alpha = 0.0 }
    // Stress (xx, yy, zz) for total strain (exx, eyy, 0) from `state`; the returned state is the updated one.
    func stress(_ exx: Double, _ eyy: Double, _ state: State) -> (SIMD3<Double>, State) {
        let trace = exx + eyy
        let deviator = SIMD3(exx, eyy, 0) - SIMD3(repeating: trace / 3)
        var s = 2 * G * (deviator - state.plastic)
        var next = state
        let q = (1.5 * simd_length_squared(s)).squareRoot()
        if q > flow(state.alpha) {
            var low = 0.0, high = q / (3 * G)
            for _ in 0..<64 {
                let mid = (low + high) / 2
                if q - 3 * G * mid - flow(state.alpha + mid) > 0 { low = mid } else { high = mid }
            }
            let gamma = (low + high) / 2
            next.plastic += 1.5 * gamma * s / q
            next.alpha += gamma
            s *= 1 - 3 * G * gamma / q
        }
        return (s + SIMD3(repeating: K * trace), next)
    }
    var state = State()
    var eyy = 0.0
    var curve: [(Double, Double)] = [(0, 0)]
    for n in 1...increments {
        let exx = maximum * Double(n) / Double(increments)
        // σyy rises with εyy, so bisect for σyy = 0 around the last lateral strain.
        var low = eyy - 0.01, high = eyy + 0.01
        for _ in 0..<64 {
            let mid = (low + high) / 2
            if stress(exx, mid, state).0.y > 0 { high = mid } else { low = mid }
        }
        eyy = (low + high) / 2
        let (sigma, next) = stress(exx, eyy, state)
        state = next
        curve.append((exx, sigma.x))
    }
    return curve
}

/// First stress at which the curve falls below the line of slope `modulus` through `offset` strain.
private func offsetYield(_ curve: [(Double, Double)], modulus: Double, offset: Double = 0.002) -> Double? {
    func gap(_ p: (Double, Double)) -> Double { p.1 - modulus * (p.0 - offset) }
    for (a, b) in zip(curve, curve.dropFirst()) where gap(a) > 0 && gap(b) <= 0 {
        let f = gap(a) / (gap(a) - gap(b))
        return a.1 + f * (b.1 - a.1)
    }
    return nil
}

private func slope(_ points: [(Double, Double)]) -> Double {
    let n = Double(points.count)
    let mx = points.reduce(0) { $0 + $1.0 } / n, my = points.reduce(0) { $0 + $1.1 } / n
    let sxy = points.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }, sxx = points.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
    return sxy / sxx
}

private func runMachine(_ coupon: Coupon, firstYield: Double) throws -> MachineRun {
    let scene = coupon.scene
    require(scene.issues().isEmpty, scene.issues().joined(separator: "; "))
    var sim = try AssemblySimulation(scene)
    require(sim.initialIssue == nil, sim.initialIssue ?? "")
    let axis = coupon.axis, sign = coupon.sign
    let reference = sim.body(0).mesh.reference
    // Gauge marks: the node lines nearest a quarter of the length either side of the middle.
    let stations = Set(reference.map { ($0[axis] * 1e9).rounded() / 1e9 }).sorted()
    func nearest(_ target: Double) -> Double { stations.min { abs($0 - target) < abs($1 - target) }! }
    let lower = nearest(-coupon.length / 4), upper = nearest(coupon.length / 4)
    let lowerNodes = reference.indices.filter { abs(reference[$0][axis] - lower) < 1e-9 }
    let upperNodes = reference.indices.filter { abs(reference[$0][axis] - upper) < 1e-9 }
    let beyondMiddle = reference.indices.filter { reference[$0][axis] > 1e-9 }
    func mean(_ nodes: [Int], _ position: [Point]) -> Double { nodes.reduce(0) { $0 + position[$1][axis] } / Double(nodes.count) }
    let gauge = upper - lower
    var samples: [MachineSample] = []
    var steps = 0
    var recordedWork = 0.0, lastForce = Point.zero, lastDisplacement = Point.zero
    while sim.time < scene.duration - 1e-15 {
        require(sim.step(), "\(scene.parts[0].name): \(sim.failure ?? "step rejected") at \(sim.time)")
        steps += 1
        let force = sim.gripReaction(0), displacement = sim.gripDisplacement(0)
        recordedWork += 0.5 * simd_dot(force + lastForce, displacement - lastDisplacement)
        (lastForce, lastDisplacement) = (force, displacement)
        guard steps.isMultiple(of: 10) else { continue }
        let position = sim.body(0).position
        let strain = sign * ((mean(upperNodes, position) - mean(lowerNodes, position)) / gauge - 1)
        let grip = sign * sim.gripReaction(0)[axis]
        let section = -sign * beyondMiddle.reduce(0) { $0 + sim.internalForce(0)[$1][axis] }
        let clamp = -sign * sim.supportReaction(0)[axis]
        let energy = sim.energies
        samples.append(MachineSample(strain: strain, stress: grip / coupon.width, grip: grip, section: section, clamp: clamp,
                                     work: energy.gripWork, residual: energy.total - sim.initialEnergy))
    }
    let elastic = samples.filter { $0.stress >= 0.1 * firstYield && $0.stress <= 0.5 * firstYield }.map { ($0.strain, $0.stress) }
    require(elastic.count >= 20, "too few elastic samples (\(elastic.count))")
    let measured = slope(elastic)
    let peak = samples.map(\.grip).max()!
    let quasiStatic = samples.indices.filter { Double($0 + 1) * 10 * sim.dt > coupon.ramp && samples[$0].grip > 0.2 * peak }
    let balance = quasiStatic.map { k -> Double in
        let s = samples[k]
        return max(abs(s.section - s.grip), abs(s.clamp - s.grip)) / s.grip
    }.max() ?? .infinity
    let finalWork = samples.last!.work
    let ledger = samples.filter { $0.work > 0.1 * finalWork }.map { abs($0.residual) / $0.work }.max() ?? .infinity
    return MachineRun(samples: samples, slope: measured,
                      offsetYield: offsetYield(samples.map { ($0.strain, $0.stress) }, modulus: measured),
                      worstBalance: balance, worstLedger: ledger,
                      recordedWorkGap: abs(recordedWork / sim.energies.gripWork - 1), steps: steps, dt: sim.dt)
}

func testMachineCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Virtual test machine: moving grip, tension and compression coupons. Numerical verification, not experimental validation.")
    for (name, profile) in [("Structural steel (A36-like)", MaterialProfile.structuralSteel),
                            ("6061-T6 aluminium", MaterialProfile.aluminum6061)] {
        let E = profile.material.young, nu = profile.material.poisson
        let planeStrain = E / (1 - nu * nu)
        let yieldStress = profile.hardening.points[0].stress
        let firstYield = yieldStress / (1 - nu + nu * nu).squareRoot()
        let point = materialPointCurve(profile, to: 0.012)
        let referenceYield = try unwrap(offsetYield(point, modulus: planeStrain), "reference curve never crosses the offset line")
        print(String(format: "  %@: E %.1f GPa, ν %.2f, plane-strain modulus E' %.1f GPa; input yield %.0f MPa, first yield in plane-strain uniaxial stress %.1f MPa, 0.2%%-offset yield of the material-point reference %.1f MPa",
                     name, E / 1e9, nu, planeStrain / 1e9, yieldStress / 1e6, firstYield / 1e6, referenceYield / 1e6))
        for kind in [Coupon.Kind.tension, .compression] {
            var results: [(label: String, run: MachineRun)] = []
            for (label, resolution, transits) in [("x4", AssemblyScene.Resolution.x4, 150.0), ("x4, half speed", .x4, 300.0),
                                                  ("fine", .fine, 150.0)] {
                var coupon = Coupon(kind: kind, profile: profile)
                coupon.resolution = resolution
                coupon.transits = transits
                let started = Date()
                let run = try runMachine(coupon, firstYield: firstYield)
                let yield = try unwrap(run.offsetYield, "\(name) \(kind) \(label): the curve never crossed the offset line")
                print(String(format: "    %@ %@: grip %.3f m/s, slope %.2f GPa (%+.2f%% vs E'), 0.2%%-offset yield %.1f MPa (%+.2f%% vs reference), grip vs section and clamp force within %.2f%%, ledger residual %.2g of grip work (%.4g J/m at the end; force × displacement record agrees within %.2g), %d steps, dt %.3g µs, %.0f s",
                             kind == .tension ? "tension" : "compression", label, coupon.speed, run.slope / 1e9,
                             100 * (run.slope / planeStrain - 1), yield / 1e6, 100 * (yield / referenceYield - 1),
                             100 * run.worstBalance, run.worstLedger, run.samples.last!.work, run.recordedWorkGap, run.steps, 1e6 * run.dt, Date().timeIntervalSince(started)))
                require(abs(run.slope / planeStrain - 1) <= 0.02, "\(name) \(kind) \(label): slope more than 2% from E'")
                require(abs(yield / referenceYield - 1) <= 0.02, "\(name) \(kind) \(label): offset yield more than 2% from the reference")
                require(run.worstBalance <= 0.02, "\(name) \(kind) \(label): grip, section and clamp forces differ by more than 2%")
                require(run.worstLedger <= 0.005, "\(name) \(kind) \(label): grip work does not close the ledger within 0.5%")
                results.append((label, run))
            }
            let base = results[0].run, half = results[1].run, fine = results[2].run
            let rateSlope = abs(half.slope / base.slope - 1), rateYield = abs(half.offsetYield! / base.offsetYield! - 1)
            let meshSlope = abs(fine.slope / base.slope - 1), meshYield = abs(fine.offsetYield! / base.offsetYield! - 1)
            print(String(format: "    %@: half speed changes slope %.2f%%, yield %.2f%%; fine against x4 mesh: slope %.2f%%, yield %.2f%%",
                         kind == .tension ? "tension" : "compression", 100 * rateSlope, 100 * rateYield, 100 * meshSlope, 100 * meshYield))
            require(rateSlope < 0.02 && rateYield < 0.02, "\(name) \(kind): halving the speed changed slope or yield by 2% or more")
            require(meshSlope <= 0.01 && meshYield <= 0.01, "\(name) \(kind): fine and x4 meshes differ by more than 1%")
        }
    }
    try brittleGripCheck()
    try gripDocumentCheck()
    print("Test machine check passed.")
}

/// Criterion 8: a glass-like coupon pulled until it cracks.
private func brittleGripCheck() throws {
    let text = #"""
    { "duration": 0.0006, "meshResolution": "fine",
      "parts": [ { "name": "Brittle coupon", "size": [0.12, 0.015], "center": [0, 0], "support": "clampLeft",
                   "material": { "young": 7.2e10, "density": 2500, "poisson": 0.23 },
                   "fracture": { "strength": 4.1e7, "energy": 7.4 },
                   "grip": { "edge": "right", "velocity": [2, 0], "ramp": 0.0001 } } ] }
    """#
    let scene = try AssemblyScene.document(Data(text.utf8))
    var sim = try AssemblySimulation(scene)
    require(sim.initialIssue == nil, sim.initialIssue ?? "")
    let edge = scene.parts[0].size.x / 2
    let grip = scene.parts[0].grip!
    var worstPath = 0.0
    var ledger: [(work: Double, residual: Double)] = []
    var firstCrack: Double?
    while sim.time < scene.duration - 1e-15 {
        require(sim.step(), "brittle coupon: \(sim.failure ?? "step rejected") at \(sim.time)")
        let body = sim.body(0)
        let motion = grip.motion(at: sim.time)
        for i in body.mesh.reference.indices where body.mesh.reference[i].x >= edge - 1e-9 * edge {
            worstPath = max(worstPath, simd_length(body.position[i] - body.mesh.reference[i] - motion.displacement),
                            simd_length(body.velocity[i] - motion.velocity))
        }
        let energy = sim.energies
        ledger.append((energy.gripWork, abs(energy.total - sim.initialEnergy)))
        if firstCrack == nil, (sim.fractureReading(0)?.insertedEdges ?? 0) > 0 { firstCrack = sim.time }
    }
    let crack = try unwrap(firstCrack, "brittle coupon never cracked")
    // Scaled as the fracture guard scales it: by the largest grip work so far, once that is 10% of the final value.
    var peak = 0.0, worstLedger = 0.0
    for (work, residual) in ledger {
        peak = max(peak, work)
        if peak > 0.1 * ledger.last!.work { worstLedger = max(worstLedger, residual / peak) }
    }
    print(String(format: "  Brittle coupon, fracture on, pulled at 2 m/s: first crack at %.1f µs (grip moved %.1f µm), %d crack faces, %d pieces at the end; every step accepted, gripped nodes off their path by at most %.3g (m or m/s), ledger residual at most %.3f%% of the largest grip work so far (%.4g J/m at the end)",
                 1e6 * crack, 1e6 * grip.motion(at: crack).displacement.x, sim.crackFaces(0).count, sim.materialPieces(0).count,
                 worstPath, 100 * worstLedger, ledger.last!.work))
    require(worstPath < 1e-12, "a gripped node left the prescribed path")
}

/// Scene files: a grip parses, and the combinations it cannot use are explained.
private func gripDocumentCheck() throws {
    func issues(_ part: String) -> [String] {
        let text = #"{ "parts": [ \#(part) ] }"#
        do { _ = try AssemblyScene.document(Data(text.utf8)); return [] } catch let error as SceneDocumentError { return error.issues }
        catch { return ["\(error)"] }
    }
    let block = #""name": "c", "size": [0.1, 0.02], "material": { "young": 2e11, "density": 7850, "poisson": 0.3 }"#
    let good = #"{ \#(block), "support": "clampLeft", "grip": { "edge": "right", "velocity": [0.4, 0], "ramp": 0.0002 } }"#
    require(issues(good).isEmpty, "a valid grip was refused: \(issues(good))")
    let cases: [(String, String)] = [
        (#"{ \#(block), "support": "clampTop", "grip": { "edge": "right", "velocity": [0.4, 0], "ramp": 0.0002 } }"#, "Clamp the edge opposite"),
        (#"{ \#(block), "support": "fixed", "grip": { "edge": "right", "velocity": [0.4, 0], "ramp": 0.0002 } }"#, "fixed support never moves"),
        (#"{ \#(block), "velocity": [1, 0], "grip": { "edge": "right", "velocity": [0.4, 0], "ramp": 0.0002 } }"#, "starts at rest"),
        (#"{ \#(block), "grip": { "edge": "right", "velocity": [40, 0], "ramp": 0.0002 } }"#, "at most 10 m/s"),
        (#"{ \#(block), "grip": { "edge": "middle", "velocity": [0.4, 0], "ramp": 0.0002 } }"#, "is not one of"),
        (#"{ \#(block), "grip": { "edge": "right", "velocity": [0.4, 0] } }"#, "speeds up from rest"),
    ]
    for (part, expected) in cases {
        let found = issues(part)
        require(found.contains { $0.contains(expected) }, "expected an issue containing \"\(expected)\", got \(found)")
    }
    print("  Scene files: a grip parses; the opposite-edge rule, fixed support, moving start, speed limit, unknown edge and missing ramp are each explained")
}
