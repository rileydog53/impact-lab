import Foundation
import simd

/// Bounded 2-D plane-strain material point method prototype (explicit MLS-MPM
/// with APIC transfers and quadratic B-splines). It is independent of the FEM
/// solver and of the app; it reuses the FEM's verified Hencky–J2 constitutive
/// update so FEM/MPM comparisons isolate the spatial discretisation.
///
/// Scope: one or more bodies on one background grid (bodies that meet stick,
/// as in single-velocity-field MPM), an optional stationary frictionless rigid
/// wall at x = wallX, and free boundaries elsewhere.
package struct MPMSimulation {
    package struct Particle {
        package var position, velocity: Point
        var affine: simd_double2x2            // APIC velocity gradient C
        var deformation: simd_double2x2       // total F
        var history = J2History()
        var tau = simd_double2x2(0)           // Kirchhoff stress, in-plane block
        var elastic = 0.0, hardening = 0.0, dissipation = 0.0   // per reference volume
        package let mass, volume: Double
        package let body: Int
    }

    package private(set) var particles: [Particle] = []
    package private(set) var time = 0.0
    package private(set) var steps = 0
    package private(set) var failure: String?
    package let spacing: Double
    package let wallX: Double?
    private let origin: Point
    private let columns, rows: Int
    private var models: [J2Model] = []
    private var soundSpeed: [Double] = []
    private var gridMass: [Double]
    private var gridMomentum: [Point]
    package var courant = 0.3
    /// Total wall impulse in x (N·s per metre of depth), for reaction force histories.
    package private(set) var wallImpulse = 0.0

    package init(spacing: Double, domainMin: Point, domainMax: Point, wallX: Double? = nil) {
        self.spacing = spacing
        self.wallX = wallX
        origin = domainMin
        columns = Int(((domainMax.x - domainMin.x) / spacing).rounded(.up)) + 1
        rows = Int(((domainMax.y - domainMin.y) / spacing).rounded(.up)) + 1
        gridMass = Array(repeating: 0, count: columns * rows)
        gridMomentum = Array(repeating: .zero, count: columns * rows)
    }

    /// Fills a rectangle with `perCell`² particles per grid cell.
    package mutating func addBlock(center: Point, size: Point, velocity: Point, material: Material,
                                   table: HardeningTable?, perCell: Int = 2) {
        let body = models.count
        models.append(table.map { J2Model(material: material, table: $0) } ?? J2Model(material: material))
        soundSpeed.append(material.waveSpeed)
        let step = spacing / Double(perCell)
        let nx = Int((size.x / step).rounded()), ny = Int((size.y / step).rounded())
        let volume = (size.x / Double(nx)) * (size.y / Double(ny))
        for i in 0..<nx {
            for j in 0..<ny {
                let p = center - size / 2 + Point((Double(i) + 0.5) * size.x / Double(nx), (Double(j) + 0.5) * size.y / Double(ny))
                particles.append(Particle(position: p, velocity: velocity, affine: simd_double2x2(0),
                                          deformation: matrix_identity_double2x2, mass: volume * material.density,
                                          volume: volume, body: body))
            }
        }
    }

    /// Fills an ellipse (round body) the same way.
    package mutating func addDisc(center: Point, diameter: Double, velocity: Point, material: Material,
                                  table: HardeningTable?, perCell: Int = 2) {
        let body = models.count
        models.append(table.map { J2Model(material: material, table: $0) } ?? J2Model(material: material))
        soundSpeed.append(material.waveSpeed)
        let step = spacing / Double(perCell)
        let n = Int((diameter / step).rounded(.up))
        for i in 0..<n {
            for j in 0..<n {
                let offset = Point((Double(i) + 0.5) * step - diameter / 2, (Double(j) + 0.5) * step - diameter / 2)
                guard simd_length(offset) <= diameter / 2 else { continue }
                particles.append(Particle(position: center + offset, velocity: velocity, affine: simd_double2x2(0),
                                          deformation: matrix_identity_double2x2, mass: step * step * material.density,
                                          volume: step * step, body: body))
            }
        }
    }

    package var stableStep: Double {
        let speed = particles.map { simd_length($0.velocity) }.max() ?? 0
        return courant * spacing / ((soundSpeed.max() ?? 1) + speed)
    }

    /// Advances one explicit step. Returns false after a failure.
    @discardableResult
    package mutating func step(_ dt: Double) -> Bool {
        guard failure == nil else { return false }
        let inverseD = 4 / (spacing * spacing)
        for k in gridMass.indices { gridMass[k] = 0; gridMomentum[k] = .zero }

        // Particle to grid: mass, APIC momentum, and stress as an affine impulse.
        for p in particles {
            let local = (p.position - origin) / spacing
            let base = SIMD2<Int>(Int((local.x - 0.5).rounded(.down)), Int((local.y - 0.5).rounded(.down)))
            guard base.x >= 0, base.y >= 0, base.x + 2 < columns, base.y + 2 < rows else {
                failure = "A particle left the background grid."
                return false
            }
            let fx = local - Point(Double(base.x), Double(base.y))
            let w = weights(fx)
            let affine = -dt * p.volume * inverseD * p.tau + p.mass * p.affine
            for a in 0..<3 {
                for b in 0..<3 {
                    let weight = w.0[a] * w.1[b]
                    let offset = (Point(Double(a), Double(b)) - fx) * spacing
                    let k = (base.x + a) + (base.y + b) * columns
                    gridMass[k] += weight * p.mass
                    gridMomentum[k] += weight * (p.mass * p.velocity + affine * offset)
                }
            }
        }

        // Grid velocities and the frictionless rigid wall.
        var impulse = 0.0
        for k in gridMass.indices where gridMass[k] > 0 {
            var v = gridMomentum[k] / gridMass[k]
            if let wallX {
                let x = origin.x + Double(k % columns) * spacing
                if x >= wallX - 1e-12 && v.x > 0 { impulse += gridMass[k] * v.x; v.x = 0 }
            }
            gridMomentum[k] = v
        }
        wallImpulse += impulse

        // Grid to particle, then the shared FEM constitutive update.
        for index in particles.indices {
            var p = particles[index]
            let local = (p.position - origin) / spacing
            let base = SIMD2<Int>(Int((local.x - 0.5).rounded(.down)), Int((local.y - 0.5).rounded(.down)))
            let fx = local - Point(Double(base.x), Double(base.y))
            let w = weights(fx)
            var velocity = Point.zero
            var affine = simd_double2x2(0)
            for a in 0..<3 {
                for b in 0..<3 {
                    let weight = w.0[a] * w.1[b]
                    let offset = (Point(Double(a), Double(b)) - fx) * spacing
                    let v = gridMomentum[(base.x + a) + (base.y + b) * columns]
                    velocity += weight * v
                    affine += weight * inverseD * simd_double2x2(columns: (v * offset.x, v * offset.y))
                }
            }
            p.velocity = velocity
            p.affine = affine
            p.position += dt * velocity
            p.deformation = (matrix_identity_double2x2 + dt * affine) * p.deformation
            guard let response = models[p.body].update(x: p.deformation.columns.0, y: p.deformation.columns.1, from: p.history) else {
                failure = "A material point inverted (J ≤ 0)."
                return false
            }
            p.history = response.history
            // Kirchhoff in-plane block: tau = P Fᵀ.
            let x = p.deformation.columns.0, y = p.deformation.columns.1
            p.tau = simd_double2x2(columns: (response.piolaX * x.x + response.piolaY * y.x,
                                              response.piolaX * x.y + response.piolaY * y.y))
            p.elastic = response.elasticEnergy
            p.hardening = response.hardeningEnergy
            p.dissipation = response.dissipation
            particles[index] = p
        }
        time += dt
        steps += 1
        return true
    }

    private func weights(_ fx: Point) -> (SIMD3<Double>, SIMD3<Double>) {
        func axis(_ x: Double) -> SIMD3<Double> {
            SIMD3(0.5 * (1.5 - x) * (1.5 - x), 0.75 - (x - 1) * (x - 1), 0.5 * (x - 0.5) * (x - 0.5))
        }
        return (axis(fx.x), axis(fx.y))
    }

    // MARK: Measurements (per metre of depth)

    package struct Ledger { package let kinetic, elastic, hardening, plastic: Double; package var total: Double { kinetic + elastic + hardening + plastic } }

    package func ledger(body: Int? = nil) -> Ledger {
        var k = 0.0, e = 0.0, h = 0.0, d = 0.0
        for p in particles where body == nil || p.body == body {
            k += 0.5 * p.mass * simd_length_squared(p.velocity)
            e += p.volume * p.elastic
            h += p.volume * p.hardening
            d += p.volume * p.dissipation
        }
        return Ledger(kinetic: k, elastic: e, hardening: h, plastic: d)
    }

    package func centerVelocity(body: Int) -> Point {
        var m = 0.0, momentum = Point.zero
        for p in particles where p.body == body { m += p.mass; momentum += p.mass * p.velocity }
        return momentum / m
    }

    /// Bounding extents of a body's material points (extended by half a particle spacing).
    package func extent(body: Int) -> (min: Point, max: Point) {
        var low = Point(repeating: .infinity), high = Point(repeating: -.infinity)
        for p in particles where p.body == body {
            low = simd_min(low, p.position)
            high = simd_max(high, p.position)
        }
        let pad = Point(repeating: spacing / 4)
        return (low - pad, high + pad)
    }

    package func peakPlasticStrain(body: Int) -> Double {
        particles.filter { $0.body == body }.map(\.history.equivalentStrain).max() ?? 0
    }

    package func minimumJacobian(body: Int) -> Double {
        particles.filter { $0.body == body }.map { simd_determinant($0.deformation) }.min() ?? 1
    }
}
