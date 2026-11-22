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
        var nodes: [Point] = []
        var triangles: [(Int, Int, Int)] = []
        var edges: [Edge] = []
        var probe: [Int] = []
        func node(_ i: Int, _ j: Int) -> Int { j * (columns + 1) + i }
        for j in 0...rows {
            for i in 0...columns {
                nodes.append(Point(Double(i) / Double(columns) - 1,
                                   0.1 * (Double(j) / Double(rows) - 0.5)))
            }
        }
        for j in 0..<rows {
            for i in 0..<columns {
                let a = node(i, j), b = node(i + 1, j)
                let c = node(i + 1, j + 1), d = node(i, j + 1)
                if i == columns / 2 - 1 || i == columns / 2 {
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
    let boundaryNodes: [Int]
    let wallStiffness: [Double]

    init(mesh: Mesh, material: Material, speed: Double, gap: Double, penalty: Double) {
        self.mesh = mesh
        self.material = material
        position = mesh.reference.map { $0 - Point(gap, 0) }
        velocity = Array(repeating: Point(speed, 0), count: position.count)
        var nodalMass = Array(repeating: 0.0, count: position.count)
        for e in mesh.elements {
            let share = material.density * e.area / 3
            nodalMass[e.a] += share
            nodalMass[e.b] += share
            nodalMass[e.c] += share
        }
        mass = nodalMass
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

public struct Simulation: Sendable {
    public let dt: Double
    public let gap: Double
    public private(set) var body: Body
    public private(set) var time = 0.0
    public private(set) var strain: [Double]
    public private(set) var failure: String?
    private var internalForce: [Point]
    private var contactForce: [Point]
    private var nextInternal: [Point]
    private var nextContact: [Point]
    private var nextPosition: [Point]
    private var nextStrain: [Double]

    public init(mesh: Mesh = .bar(), material: Material = Material(), speed: Double = 0.4,
                gap: Double = 0.0005, penalty: Double = 2500, stepScale: Double = 1) {
        body = Body(mesh: mesh, material: material, speed: speed, gap: gap, penalty: penalty)
        self.gap = gap
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
    }

    public var probeStrain: Double {
        body.mesh.probe.reduce(0) { $0 + strain[$1] } / Double(max(1, body.mesh.probe.count))
    }

    public var penetration: Double {
        body.boundaryNodes.reduce(0) { max($0, body.position[$1].x) }
    }

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
        guard Self.assemble(body: body, position: nextPosition, forces: &nextInternal,
                            strain: &nextStrain) else {
            failure = "An element inverted or its stress became non-finite."
            return false
        }
        for i in body.boundaryNodes {
            nextContact[i] = Point(-body.wallStiffness[i] * max(0, nextPosition[i].x), 0)
        }
        for i in body.mass.indices {
            let force = internalForce[i] + contactForce[i] + nextInternal[i] + nextContact[i]
            let velocity = body.velocity[i] + (0.5 * dt / body.mass[i]) * force
            guard velocity.x.isFinite && velocity.y.isFinite else {
                failure = "Velocity became non-finite."
                return false
            }
        }
        for i in body.mass.indices {
            let force = internalForce[i] + contactForce[i] + nextInternal[i] + nextContact[i]
            body.velocity[i] += (0.5 * dt / body.mass[i]) * force
        }
        swap(&body.position, &nextPosition)
        swap(&internalForce, &nextInternal)
        swap(&contactForce, &nextContact)
        swap(&strain, &nextStrain)
        time += dt
        return true
    }

    static func assemble(body: Body, position: [Point], forces: inout [Point],
                         strain: inout [Double]) -> Bool {
        for i in forces.indices { forces[i] = .zero }
        let mu = body.material.shear
        let lambda = body.material.lambda
        for (i, e) in body.mesh.elements.enumerated() {
            let u = position[e.b] - position[e.a]
            let v = position[e.c] - position[e.a]
            let fx = u * e.g1.x + v * e.g2.x
            let fy = u * e.g1.y + v * e.g2.y
            let j = cross2D(fx, fy)
            guard j > 0, j.isFinite else { return false }
            // P = mu F + (lambda ln J - mu) F^(-T), with Fzz = 1.
            let pressure = (lambda * log(j) - mu) / j
            let px = -e.area * (mu * fx + pressure * Point(fy.y, -fy.x))
            let py = -e.area * (mu * fy + pressure * Point(-fx.y, fx.x))
            guard px.x.isFinite && px.y.isFinite && py.x.isFinite && py.y.isFinite else {
                return false
            }
            forces[e.a] += px * e.g0.x + py * e.g0.y
            forces[e.b] += px * e.g1.x + py * e.g1.y
            forces[e.c] += px * e.g2.x + py * e.g2.y
            strain[i] = 0.5 * (simd_length_squared(fx) - 1)
        }
        return true
    }
}
