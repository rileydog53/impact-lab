import Foundation
import simd

public typealias Point = SIMD2<Double>

public struct Material: Sendable {
    public var young: Double
    public var density: Double
    public var poisson: Double

    public init(young: Double = 1e6, density: Double = 1000, poisson: Double = 0) {
        self.young = young
        self.density = density
        self.poisson = poisson
    }

    var shear: Double { young / (2 * (1 + poisson)) }
    var lambda: Double { young * poisson / ((1 + poisson) * (1 - 2 * poisson)) }
    public var waveSpeed: Double { sqrt((lambda + 2 * shear) / density) }
}

public struct Triangle: Sendable {
    public let a, b, c: Int
    let g0, g1, g2: Point
    let area: Double

    init(_ a: Int, _ b: Int, _ c: Int, _ reference: [Point]) {
        let u = reference[b] - reference[a]
        let v = reference[c] - reference[a]
        let twiceArea = cross2D(u, v)
        precondition(twiceArea > 0)
        self.a = a
        self.b = b
        self.c = c
        g1 = Point(v.y, -v.x) / twiceArea
        g2 = Point(-u.y, u.x) / twiceArea
        g0 = -g1 - g2
        area = twiceArea / 2
    }
}

public struct Edge: Sendable {
    public let a, b: Int
    public init(_ a: Int, _ b: Int) { self.a = a; self.b = b }
}

public struct Mesh: Sendable {
    public let reference: [Point]
    public let elements: [Triangle]
    public let boundary: [Edge]
    public let probe: [Int]

    init(reference: [Point], triangles: [(Int, Int, Int)], boundary: [Edge], probe: [Int] = []) {
        self.reference = reference
        elements = triangles.map { Triangle($0.0, $0.1, $0.2, reference) }
        self.boundary = boundary
        self.probe = probe
    }

    public static func bar(columns: Int = 120, rows: Int = 6) -> Mesh {
        rectangle(columns: columns, rows: rows, hasProbe: true) { u, v in
            Point(u - 1, 0.1 * (v - 0.5))
        }
    }

    static func rectangle(columns: Int, rows: Int, hasProbe: Bool = false,
                          position: (Double, Double) -> Point) -> Mesh {
        precondition(columns >= 2 && rows >= 1)
        var nodes: [Point] = []
        var triangles: [(Int, Int, Int)] = []
        var edges: [Edge] = []
        var probe: [Int] = []
        func node(_ i: Int, _ j: Int) -> Int { j * (columns + 1) + i }
        for j in 0...rows {
            for i in 0...columns {
                nodes.append(position(Double(i) / Double(columns), Double(j) / Double(rows)))
            }
        }
        for j in 0..<rows {
            for i in 0..<columns {
                let a = node(i, j), b = node(i + 1, j)
                let c = node(i + 1, j + 1), d = node(i, j + 1)
                if hasProbe && (i == columns / 2 - 1 || i == columns / 2) {
                    probe.append(contentsOf: [triangles.count, triangles.count + 1])
                }
                if (i + j).isMultiple(of: 2) {
                    triangles.append(contentsOf: [(a, b, c), (a, c, d)])
                } else {
                    triangles.append(contentsOf: [(a, b, d), (b, c, d)])
                }
                if j == 0 { edges.append(Edge(a, b)) }
                if i == columns - 1 { edges.append(Edge(b, c)) }
                if j == rows - 1 { edges.append(Edge(c, d)) }
                if i == 0 { edges.append(Edge(d, a)) }
            }
        }
        return Mesh(reference: nodes, triangles: triangles, boundary: edges, probe: probe)
    }
}

@inline(__always) func cross2D(_ a: Point, _ b: Point) -> Double {
    a.x * b.y - a.y * b.x
}

public struct Body: Sendable {
    public let mesh: Mesh
    public let material: Material
    public internal(set) var position: [Point]
    public internal(set) var velocity: [Point]
    let mass: [Double]
    let totalMass: Double
    let referenceCenter: Point
    let boundaryNodes: [Int]
    let wallStiffness: [Double]

    init(mesh: Mesh, material: Material, speed: Double, gap: Double, penalty: Double, tilt: Double) {
        self.mesh = mesh
        self.material = material
        let c = cos(tilt), s = sin(tilt)
        let rotated = mesh.reference.map { Point(c * $0.x - s * $0.y, s * $0.x + c * $0.y) }
        let offset = Point(rotated.map(\.x).max()! + gap, 0)
        position = rotated.map { $0 - offset }
        velocity = Array(repeating: Point(speed, 0), count: position.count)
        var nodalMass = Array(repeating: 0.0, count: position.count)
        for e in mesh.elements {
            let share = material.density * e.area / 3
            nodalMass[e.a] += share
            nodalMass[e.b] += share
            nodalMass[e.c] += share
        }
        mass = nodalMass
        totalMass = nodalMass.reduce(0, +)
        referenceCenter = zip(nodalMass, mesh.reference).reduce(.zero) { $0 + $1.0 * $1.1 } / totalMass
        var tributaryLength = Array(repeating: 0.0, count: position.count)
        for edge in mesh.boundary {
            let halfLength = simd_length(mesh.reference[edge.a] - mesh.reference[edge.b]) / 2
            tributaryLength[edge.a] += halfLength
            tributaryLength[edge.b] += halfLength
        }
        boundaryNodes = tributaryLength.indices.filter { tributaryLength[$0] > 0 }
        wallStiffness = tributaryLength.map { $0 * material.young * penalty }
    }
}

public struct Diagnostics: Sendable {
    public let kinetic, elastic, contact: Double
    public let relativeEnergyError: Double
    public let momentum: Point
    public let angularMomentum: Double
}

public struct Simulation: Sendable {
    public let dt: Double
    public let gap: Double
    public private(set) var body: Body
    public private(set) var time = 0.0
    public private(set) var strain: [Double]
    public private(set) var failure: String?
    public private(set) var wallImpulse = 0.0
    public private(set) var wallAngularImpulse = 0.0
    public private(set) var peakPenetration = 0.0
    private let initialKinetic: Double
    private var elasticEnergy = 0.0
    private var contactEnergy = 0.0
    private var internalForce: [Point]
    private var contactForce: [Point]
    private var nextInternal: [Point]
    private var nextContact: [Point]
    private var nextPosition: [Point]
    private var nextVelocity: [Point]
    private var nextStrain: [Double]

    public init(mesh: Mesh = .bar(), material: Material = Material(), speed: Double = 0.4,
                gap: Double = 0.0005, penalty: Double = 2500, stepScale: Double = 1, tilt: Double = 0) {
        precondition(material.young > 0 && material.density > 0 && abs(material.poisson) < 0.5)
        precondition(gap >= 0 && penalty > 0 && stepScale > 0 && stepScale <= 1)
        body = Body(mesh: mesh, material: material, speed: speed, gap: gap, penalty: penalty, tilt: tilt)
        self.gap = gap
        initialKinetic = 0.5 * body.totalMass * speed * speed
        var stiffness = Array(repeating: 0.0, count: body.mass.count)
        for e in mesh.elements {
            // A lumped-mass bound on the initial elastic spectral radius.
            let gradientSum = simd_length(e.g0) + simd_length(e.g1) + simd_length(e.g2)
            let scale = e.area * material.density * pow(material.waveSpeed, 2) * gradientSum
            stiffness[e.a] += scale * simd_length(e.g0)
            stiffness[e.b] += scale * simd_length(e.g1)
            stiffness[e.c] += scale * simd_length(e.g2)
        }
        var omegaSquared = 0.0
        for i in body.mass.indices {
            omegaSquared = max(omegaSquared, (stiffness[i] + body.wallStiffness[i]) / body.mass[i])
        }
        // Central difference is linearly stable for dt * omega < 2.
        // The margin also accommodates changes in the tangent during impact.
        dt = stepScale * 0.8 / sqrt(omegaSquared)
        strain = Array(repeating: 0, count: mesh.elements.count)
        nextStrain = strain
        internalForce = Array(repeating: .zero, count: body.mass.count)
        contactForce = internalForce
        nextInternal = internalForce
        nextContact = internalForce
        nextPosition = body.position
        nextVelocity = body.velocity
    }

    public var probeStrain: Double {
        body.mesh.probe.reduce(0) { $0 + strain[$1] } / Double(max(1, body.mesh.probe.count))
    }

    public var diagnostics: Diagnostics {
        var kinetic = 0.0
        var momentum = Point.zero
        var angularMomentum = 0.0
        for i in body.mass.indices {
            let nodalMomentum = body.mass[i] * body.velocity[i]
            momentum += nodalMomentum
            angularMomentum += cross2D(body.position[i], nodalMomentum)
            kinetic += 0.5 * body.mass[i] * simd_length_squared(body.velocity[i])
        }
        let relativeError = (kinetic + elasticEnergy + contactEnergy - initialKinetic)
            / max(initialKinetic, Double.leastNormalMagnitude)
        return Diagnostics(kinetic: kinetic, elastic: elasticEnergy, contact: contactEnergy,
                           relativeEnergyError: relativeError, momentum: momentum,
                           angularMomentum: angularMomentum)
    }

    package func internalForces(at position: [Point]) -> [Point]? {
        var forces = internalForce
        var strain = strain
        guard Self.assemble(body: body, position: position, forces: &forces, strain: &strain) != nil
        else { return nil }
        return forces
    }

    package var nodalMass: [Double] { body.mass }

    @discardableResult public mutating func step() -> Bool {
        guard failure == nil else { return false }
        for i in body.mass.indices {
            let acceleration = (internalForce[i] + contactForce[i]) / body.mass[i]
            let position = body.position[i] + dt * (body.velocity[i] + 0.5 * dt * acceleration)
            guard position.x.isFinite && position.y.isFinite else {
                failure = "Position became non-finite."
                return false
            }
            nextPosition[i] = position
        }
        guard let nextElastic = Self.assemble(body: body, position: nextPosition,
                                               forces: &nextInternal, strain: &nextStrain) else {
            failure = "An element inverted or its stress became non-finite."
            return false
        }
        var nextContactEnergy = 0.0
        var impulse = 0.0
        var angularImpulse = 0.0
        var penetration = 0.0
        for i in body.boundaryNodes {
            let overlap = max(0, nextPosition[i].x)
            let reaction = body.wallStiffness[i] * overlap
            nextContact[i] = Point(-reaction, 0)
            penetration = max(penetration, overlap)
            nextContactEnergy += 0.5 * reaction * overlap
            // Trapezoidal wall kicks match the velocity updates. Torque is
            // evaluated about the wall origin at each kick's own position.
            impulse += 0.5 * dt * (reaction - contactForce[i].x)
            angularImpulse += 0.5 * dt * (nextPosition[i].y * reaction
                                         - body.position[i].y * contactForce[i].x)
        }
        guard (nextContactEnergy + nextElastic).isFinite, (wallImpulse + impulse).isFinite,
              (wallAngularImpulse + angularImpulse).isFinite else {
            failure = "Contact energy or impulse became non-finite."
            return false
        }
        for i in body.mass.indices {
            let force = internalForce[i] + contactForce[i] + nextInternal[i] + nextContact[i]
            let velocity = body.velocity[i] + (0.5 * dt / body.mass[i]) * force
            guard velocity.x.isFinite && velocity.y.isFinite else {
                failure = "Velocity became non-finite."
                return false
            }
            nextVelocity[i] = velocity
        }
        swap(&body.velocity, &nextVelocity)
        swap(&body.position, &nextPosition)
        swap(&internalForce, &nextInternal)
        swap(&contactForce, &nextContact)
        swap(&strain, &nextStrain)
        time += dt
        elasticEnergy = nextElastic
        contactEnergy = nextContactEnergy
        wallImpulse += impulse
        wallAngularImpulse += angularImpulse
        peakPenetration = max(peakPenetration, penetration)
        return true
    }

    static func assemble(body: Body, position: [Point], forces: inout [Point],
                         strain: inout [Double]) -> Double? {
        for i in forces.indices { forces[i] = .zero }
        let mu = body.material.shear
        let lambda = body.material.lambda
        var energy = 0.0
        for (i, e) in body.mesh.elements.enumerated() {
            let u = position[e.b] - position[e.a]
            let v = position[e.c] - position[e.a]
            let fx = u * e.g1.x + v * e.g2.x
            let fy = u * e.g1.y + v * e.g2.y
            let j = cross2D(fx, fy)
            guard j > 0, j.isFinite else { return nil }
            // P = mu F + (lambda ln J - mu) F^(-T), with Fzz = 1.
            let logJ = log(j)
            let pressure = (lambda * logJ - mu) / j
            let px = -e.area * (mu * fx + pressure * Point(fy.y, -fy.x))
            let py = -e.area * (mu * fy + pressure * Point(-fx.y, fx.x))
            guard px.x.isFinite && px.y.isFinite && py.x.isFinite && py.y.isFinite else {
                return nil
            }
            forces[e.a] += px * e.g0.x + py * e.g0.y
            forces[e.b] += px * e.g1.x + py * e.g1.y
            forces[e.c] += px * e.g2.x + py * e.g2.y
            let xx = simd_length_squared(fx)
            let yy = simd_length_squared(fy)
            strain[i] = 0.5 * (xx - 1)
            energy += e.area * (0.5 * mu * (xx + yy - 2 - 2 * logJ)
                                + 0.5 * lambda * logJ * logJ)
        }
        return energy.isFinite ? energy : nil
    }
}
