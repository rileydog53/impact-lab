import Foundation
import ImpactPhysics
import simd

private let couponSize = Point(0.040, 0.025)
private let duration = 200e-6

private struct ElementQuality {
    let triangles: [Triangle]
    let twiceReferenceAreas: [Double]

    init(_ mesh: Mesh) {
        triangles = mesh.elements
        twiceReferenceAreas = triangles.map { t in
            let r = mesh.reference
            return Self.cross(r[t.b] - r[t.a], r[t.c] - r[t.a])
        }
    }

    private static func cross(_ a: Point, _ b: Point) -> Double {
        a.x * b.y - a.y * b.x
    }

    func measure(_ positions: [Point]) -> (minJ: Double, minQuality: Double, inverted: Int) {
        var minJ = Double.infinity
        var minQuality = Double.infinity
        var inverted = 0
        for (i, t) in triangles.enumerated() {
            let u = positions[t.b] - positions[t.a]
            let v = positions[t.c] - positions[t.a]
            let signedArea2 = Self.cross(u, v)
            let j = signedArea2 / twiceReferenceAreas[i]
            guard j.isFinite else { return (.nan, .nan, inverted) }
            minJ = min(minJ, j)
            if j <= 0 { inverted += 1 }
            let edgeSquares = simd_length_squared(u) + simd_length_squared(v) + simd_length_squared(v - u)
            let quality = edgeSquares > 0 ? 2 * sqrt(3.0) * signedArea2 / edgeSquares : 0
            minQuality = min(minQuality, quality)
        }
        return (minJ, minQuality, inverted)
    }
}

private struct FEMDiagnostics {
    var minJ = Double.infinity, minQuality = Double.infinity
    var peakEnergyError = 0.0, peakMomentumError = 0.0, peakAngularError = 0.0, peakMassError = 0.0
    var minCenterDistance = Double.infinity
    var peakLoad = 0.0, lastLoad = 0.0, normalLoadIntegral = 0.0
    var contactEpisodes = 0, lastContactTime = Double.nan
    var steps = 0

    mutating func sampleContact(load: Double, time: Double, dt: Double) {
        if load > 0 {
            if lastLoad == 0 { contactEpisodes += 1 }
            lastContactTime = time
        }
        peakLoad = max(peakLoad, load)
        normalLoadIntegral += 0.5 * dt * (lastLoad + load)
        lastLoad = load
    }
}

func femLimitStudy() throws {
    let control = copperWallFEMScene(speed: 150, resolution: .fine, duration: duration,
                                     elastic: false, size: couponSize)
    let production = try AssemblySimulation(control)
    require(production.initialIssue == nil, production.initialIssue ?? "")
    var overLimit = control
    overLimit.parts[0].velocity.x = 150.001
    require((try? AssemblySimulation(overLimit)) == nil, "Workshop accepted a velocity above 150 m/s")

    print("speed_m_s,mesh,case,triangles_per_block,dt_ns,steps,end_us,min_J,min_quality,"
          + "rejected_trial_J,rejected_nonpositive_J,energy_error_pct,momentum_error,angular_error,mass_error,"
          + "relative_overlap_pct,first_contact_us,last_contact_us,contact_episodes,contact_at_end,"
          + "peak_normal_load_N_m,normal_load_integral_N_s_m,min_center_distance_mm,left_length_mm,"
          + "left_front_span_mm,left_final_vx_m_s,plastic_dissipation_J_m,peak_plastic_strain,status")
    for speed in [150.0, 300.0, 450.0, 525.0, 600.0, 750.0] {
        let scene = copperWallFEMScene(speed: 0, resolution: .fine, duration: duration,
                                      elastic: false, size: couponSize)
        let velocities = [Point(speed, 0), Point(-speed, 0)]
        let fine = try AssemblySimulation(scene, refinement: 7, stepLimit: .infinity,
                                          comparisonVelocities: velocities)
        let base: [(Int, Double, Double, String)] = [
            (2, 1.0, Double.infinity, "nominal"),
            (4, 1.0, .infinity, "nominal"),
            (4, 1.0, fine.dt, "match_x7"),
            (4, 0.5, .infinity, "half_dt"),
            (7, 1.0, .infinity, "nominal"),
            (7, 0.5, .infinity, "half_dt"),
        ]
        let quarter = (7, 0.25, Double.infinity, "quarter_dt")
        let cases = switch speed {
        case 450: base + [quarter]
        case 525: Array(base.suffix(2)) + [quarter]
        case 600: base + [quarter, (7, 0.125, .infinity, "eighth_dt")]
        case 750: [quarter]
        default: base
        }
        for (mesh, scale, limit, name) in cases {
            let sim = try AssemblySimulation(scene, refinement: mesh, stepLimit: limit, stepScale: scale,
                                             comparisonVelocities: velocities)
            require(sim.initialIssue == nil, sim.initialIssue ?? "")
            if speed == 150, mesh == 2 {
                verifyComparisonSeed(production: production, seeded: sim)
            }
            print(runLimitCase(sim, speed: speed, mesh: mesh, name: name))
        }
    }
}

private func verifyComparisonSeed(production: AssemblySimulation, seeded: AssemblySimulation) {
    var a = production
    var b = seeded
    require(a.dt == b.dt && a.initialEnergy == b.initialEnergy, "Comparison seed altered setup")
    while a.step() {
        require(b.step(), "Comparison seed stopped before the workshop solver")
        require(a.energies.total == b.energies.total && a.activeContacts == b.activeContacts,
                "Comparison seed changed energy or contact")
        for i in 0..<a.bodyCount {
            require(a.body(i).position == b.body(i).position && a.body(i).velocity == b.body(i).velocity,
                    "Comparison seed changed the trajectory")
        }
    }
    require(!b.step() && a.time >= duration && a.time == b.time && a.failure == nil && b.failure == nil,
            "Control comparison failed to finish identically")
}

private func runLimitCase(_ initial: AssemblySimulation, speed: Double, mesh: Int, name: String) -> String {
    var sim = initial
    let bodies = (0..<sim.bodyCount).map(sim.body)
    let elements = bodies.map { ElementQuality($0.mesh) }
    let initialMomentum = sim.momentum
    let initialAngular = sim.angularMomentum
    let initialMass = bodies.reduce(0) { $0 + $1.totalMass }
    let momentumScale = initialMass * speed
    var d = FEMDiagnostics()

    func sample() {
        let left = sim.body(0), right = sim.body(1)
        for (i, body) in [left, right].enumerated() {
            let quality = elements[i].measure(body.position)
            require(quality.minJ.isFinite && quality.inverted == 0, "Accepted state contains an invalid element")
            d.minJ = min(d.minJ, quality.minJ)
            d.minQuality = min(d.minQuality, quality.minQuality)
        }
        d.peakEnergyError = max(d.peakEnergyError, abs(sim.energies.total / sim.initialEnergy - 1))
        d.peakMomentumError = max(d.peakMomentumError, simd_length(sim.momentum - initialMomentum) / momentumScale)
        d.peakAngularError = max(d.peakAngularError, abs(sim.angularMomentum - initialAngular) / (momentumScale * couponSize.x))
        d.peakMassError = max(d.peakMassError, abs((left.totalMass + right.totalMass) / initialMass - 1))
        d.minCenterDistance = min(d.minCenterDistance, right.centerOfMass.x - left.centerOfMass.x)
        d.sampleContact(load: sim.normalLoad(0, 1), time: sim.time, dt: sim.dt)
    }

    sample()
    while sim.step() {
        d.steps += 1
        sample()
    }

    var rejectedJ = Double.nan
    var rejectedCount = ""
    if sim.failure != nil {
        let trials = elements.indices.compactMap { i in
            sim.comparisonTrialPositions(i).map { elements[i].measure($0) }
        }
        if trials.count == elements.count && trials.allSatisfy({ $0.minJ.isFinite }) {
            rejectedJ = trials.map(\.minJ).min()!
            rejectedCount = String(trials.reduce(0) { $0 + $1.inverted })
        }
    }
    let left = sim.body(0)
    let front = left.position.map(\.x).max()!
    let frontY = left.position.filter { $0.x > front - 0.002 }.map(\.y)
    let peakPlastic = (0..<sim.bodyCount).compactMap { sim.plasticStrain($0).max() }.max() ?? 0
    var status = sim.failure ?? "completed"
    if rejectedJ < 0 { status = "inverted" }
    if rejectedJ == 0 { status = "collapsed" }
    return [
        String(Int(speed)), String(mesh), name, String(elements[0].triangles.count),
        csv(sim.dt * 1e9), String(d.steps), csv(sim.time * 1e6),
        csv(d.minJ), csv(d.minQuality), csv(rejectedJ), rejectedCount,
        csv(d.peakEnergyError * 100), csv(d.peakMomentumError), csv(d.peakAngularError), csv(d.peakMassError),
        csv(sim.peakRelativePenetration * 100), csv((sim.firstContactTimes[SIMD2(0, 1)] ?? .nan) * 1e6),
        csv(d.lastContactTime * 1e6), String(d.contactEpisodes), d.lastLoad > 0 ? "yes" : "no",
        csv(d.peakLoad), csv(d.normalLoadIntegral), csv(d.minCenterDistance * 1e3),
        csv((front - left.position.map(\.x).min()!) * 1e3), csv((frontY.max()! - frontY.min()!) * 1e3),
        csv(left.centerVelocity.x), csv(sim.energies.plastic / 2), csv(peakPlastic),
        "\"" + status.replacingOccurrences(of: "\"", with: "\"\"") + "\"",
    ].joined(separator: ",")
}

private func csv(_ value: Double) -> String {
    value.isFinite ? String(value) : ""
}
