import simd

private struct MaterialAnchor: Sendable {
    let nodes: SIMD3<Int>
    let weights: SIMD3<Double>

    init(_ point: Point, mesh: Mesh) {
        let reference = mesh.reference
        for triangle in mesh.elements {
            let offset = point - reference[triangle.a]
            let b = simd_dot(offset, triangle.g1), c = simd_dot(offset, triangle.g2)
            if min(b, c, 1 - b - c) >= -1e-10 {
                nodes = SIMD3(triangle.a, triangle.b, triangle.c)
                weights = SIMD3(1 - b - c, b, c)
                return
            }
        }
        var nearest = mesh.boundary[0]
        var distance = Double.infinity
        var weight = 0.0
        // Points in a cavity snap to the closest material boundary.
        for edge in mesh.boundary {
            let a = reference[edge.a], delta = reference[edge.b] - a
            let fraction = min(1, max(0, simd_dot(point - a, delta) / simd_length_squared(delta)))
            let separation = simd_length_squared(point - a - fraction * delta)
            if separation < distance {
                nearest = edge
                distance = separation
                weight = fraction
            }
        }
        nodes = SIMD3(nearest.a, nearest.b, nearest.a)
        weights = SIMD3(1 - weight, weight, 0)
    }

    func point(in positions: [Point]) -> Point {
        weights.x * positions[nodes.x] + weights.y * positions[nodes.y] + weights.z * positions[nodes.z]
    }

    func apply(_ force: Point, to forces: inout [Point]) {
        for i in 0..<3 { forces[nodes[i]] += weights[i] * force }
    }

    func budget(_ stiffness: Double, into springs: inout [(Int, Double)]) {
        for i in 0..<3 where weights[i] > 0 {
            springs.append((nodes[i], stiffness * weights[i]))
        }
    }
}

private struct AssemblyLink: Sendable {
    let connection: Int
    let firstBody, secondBody: Int
    let first, second: MaterialAnchor
    let restLength, stiffness: Double
    let law: CohesiveLaw?

    func sample(extension opening: Double, previous: Double) -> (force: Double, stored: Double, loss: Double, damage: Double, maximum: Double) {
        if let law {
            let value = law.evaluate(opening: max(0, opening), previousMaximum: previous, canSeparate: true)
            return (value.traction, value.bondEnergy, value.dissipated, law.damage(at: value.maximumOpening), value.maximumOpening)
        }
        let force = stiffness * opening
        return (force, 0.5 * force * opening, 0, 0, 0)
    }
}

public struct AssemblyLinkReading: Sendable {
    public let connection: Int
    public let start, end: Point
    public let extensionLength, force, damage: Double
    public let storedEnergy, fractureDissipation: Double
}

public struct AssemblyEnergy: Sendable {
    public internal(set) var kinetic, elastic, contact, connection, hardening, plastic, fracture: Double
    public var total: Double { kinetic + elastic + contact + connection + hardening + plastic + fracture }
}

public struct AssemblySimulation: Sendable {
    private struct Pair: Sendable {
        let a, b: Int
        let contact: BoundaryContact
    }

    public let scene: AssemblyScene
    public let dt: Double
    public let initialIssue: String?
    public private(set) var time = 0.0
    public private(set) var failure: String?
    public private(set) var peakRelativePenetration = 0.0
    public private(set) var firstContactTimes: [SIMD2<Int>: Double] = [:]
    public private(set) var activeContacts: [SIMD2<Int>] = []
    public private(set) var linkReadings: [AssemblyLinkReading] = []
    private var steps: [BodyStep]
    private let surfaces: [ContactSurface]
    private let pairs: [Pair]
    private let links: [AssemblyLink]
    private var maxima: [Double]
    private var energy: AssemblyEnergy
    public let initialEnergy: Double

    public var bodyCount: Int { steps.count }
    public func body(_ index: Int) -> Body { steps[index].body }
    public func strain(_ index: Int) -> [Double] { steps[index].strain }
    public func plasticStrain(_ index: Int) -> [Double] {
        steps[index].history?.current.map(\.equivalentStrain) ?? []
    }

    public func kineticEnergy(_ index: Int) -> Double { Self.kinetic(body(index)) }
    public var energies: AssemblyEnergy {
        var current = energy
        current.kinetic = steps.indices.reduce(0) { $0 + kineticEnergy($1) }
        return current
    }

    public var momentum: Point {
        steps.reduce(.zero) { sum, item in sum + item.body.totalMass * item.body.centerVelocity }
    }

    public var angularMomentum: Double {
        steps.reduce(0) { sum, item in
            let body = item.body
            return body.mass.indices.reduce(sum) { $0 + cross2D(body.position[$1], body.mass[$1] * body.velocity[$1]) }
        }
    }

    public init(_ scene: AssemblyScene) throws {
        try self.init(scene, refinement: 1, stepLimit: .infinity)
    }

    package init(_ scene: AssemblyScene, refinement: Int, stepLimit: Double) throws {
        try scene.validate()
        precondition(refinement > 0 && stepLimit > 0)
        self.scene = scene
        let bodies = scene.parts.map { $0.makeBody(refinement: refinement) }
        let surfaces = bodies.map(ContactSurface.init)
        self.surfaces = surfaces
        steps = zip(bodies, scene.parts).map { body, part in
            BodyStep(body, j2: part.plasticity.response == .elastoplastic ? part.plasticity.model(for: body.material) : nil)
        }

        var pairs: [Pair] = []
        var allowance = Array(repeating: 0.0, count: bodies.count)
        let bounds = zip(surfaces, bodies).map { ContactBounds(surface: $0, position: $1.position) }
        var issue: AssemblyError?
        for a in bodies.indices {
            for b in (a + 1)..<bodies.count {
                let contact = BoundaryContact(left: surfaces[a], right: surfaces[b])
                pairs.append(Pair(a: a, b: b, contact: contact))
                allowance[a] += 8 * contact.maximumStiffness
                allowance[b] += 8 * contact.maximumStiffness
                if issue == nil, bounds[a].intersects(bounds[b]) {
                    let pa = bodies[a].position, pb = bodies[b].position
                    let inside = surfaces[a].nodes.contains {
                        bounds[b].contains(pa[$0]) && BoundaryContact.contains(pa[$0], within: surfaces[b], position: pb)
                    } || surfaces[b].nodes.contains {
                        bounds[a].contains(pb[$0]) && BoundaryContact.contains(pb[$0], within: surfaces[a], position: pa)
                    }
                    if inside || bodies[a].boundaryClearance(to: bodies[b]) < 1e-8 {
                        issue = .overlap(scene.parts[a].name, scene.parts[b].name)
                    }
                }
            }
        }
        self.pairs = pairs

        let indices = Dictionary(uniqueKeysWithValues: scene.parts.enumerated().map { ($0.element.id, $0.offset) })
        var links: [AssemblyLink] = []
        var springs = Array(repeating: [(Int, Double)](), count: bodies.count)
        for (index, connection) in scene.connections.enumerated() {
            let a = indices[connection.first]!, b = indices[connection.second]!
            let count = connection.span > 0 ? 5 : 1
            for k in 0..<count {
                let fraction = count == 1 ? 0 : Double(k) / Double(count - 1) - 0.5
                let offset = Point(0, fraction * connection.span)
                let left = MaterialAnchor(0.5 * (connection.firstAnchor + offset) * scene.parts[a].size, mesh: bodies[a].mesh)
                let right = MaterialAnchor(0.5 * (connection.secondAnchor + offset) * scene.parts[b].size, mesh: bodies[b].mesh)
                let start = left.point(in: bodies[a].position), end = right.point(in: bodies[b].position)
                let length = simd_distance(start, end)
                if length < 0.0005 && issue == nil { issue = .coincidentAnchors(index) }
                let stiffness = connection.stiffness / Double(count)
                let law = connection.kind == .cohesive ? CohesiveLaw(
                    strength: stiffness * 0.25 * connection.criticalExtension, finalOpening: connection.criticalExtension) : nil
                left.budget(2 * stiffness, into: &springs[a])
                right.budget(2 * stiffness, into: &springs[b])
                links.append(AssemblyLink(connection: index, firstBody: a, secondBody: b, first: left, second: right,
                                          restLength: length, stiffness: stiffness, law: law))
                linkReadings.append(AssemblyLinkReading(connection: index, start: start, end: end,
                                                         extensionLength: 0, force: 0, damage: 0,
                                                         storedEnergy: 0, fractureDissipation: 0))
            }
        }
        self.links = links
        maxima = Array(repeating: 0, count: links.count)
        initialIssue = issue?.localizedDescription
        let frequency = bodies.indices.map {
            Simulation.squaredFrequency(of: bodies[$0], contact: surfaces[$0], allowance: allowance[$0], springs: springs[$0])
        }.max() ?? 1e8
        dt = min(stepLimit, 0.8 / frequency.squareRoot())
        initialEnergy = bodies.reduce(0) { $0 + Self.kinetic($1) }
        energy = AssemblyEnergy(kinetic: initialEnergy, elastic: 0, contact: 0, connection: 0, hardening: 0, plastic: 0, fracture: 0)
    }

    private static func kinetic(_ body: Body) -> Double {
        body.mass.indices.reduce(0) { $0 + 0.5 * body.mass[$1] * simd_length_squared(body.velocity[$1]) }
    }

    @discardableResult public mutating func step() -> Bool {
        guard initialIssue == nil, failure == nil, !steps.isEmpty, time < scene.duration else { return false }
        var trial = AssemblyEnergy(kinetic: 0, elastic: 0, contact: 0, connection: 0, hardening: 0, plastic: 0, fracture: 0)
        for i in steps.indices {
            guard steps[i].drift(dt), let element = steps[i].assemble() else {
                failure = "An element inverted or became non-finite in \(scene.parts[i].name)."
                return false
            }
            trial.elastic += element.elastic
            trial.hardening += element.hardening
            trial.plastic += element.dissipation
            for j in steps[i].nextApplied.indices { steps[i].nextApplied[j] = .zero }
        }
        let bounds = steps.indices.map { ContactBounds(surface: surfaces[$0], position: steps[$0].nextPosition) }
        var active: [SIMD2<Int>] = []
        var penetration = 0.0
        let contacts = pairs
        steps.withUnsafeMutableBufferPointer { buffer in
            for pair in contacts where bounds[pair.a].intersects(bounds[pair.b]) {
                // The two indices always differ, so the force buffers are disjoint.
                let a = buffer.baseAddress!.advanced(by: pair.a)
                let b = buffer.baseAddress!.advanced(by: pair.b)
                let result = pair.contact.accumulate(left: a.pointee.nextPosition, right: b.pointee.nextPosition,
                                                     leftBounds: bounds[pair.a], rightBounds: bounds[pair.b],
                                                     leftForce: &a.pointee.nextApplied, rightForce: &b.pointee.nextApplied)
                trial.contact += result.energy
                penetration = max(penetration, result.relativePenetration)
                if result.penetration > 0 { active.append(SIMD2(pair.a, pair.b)) }
            }
        }

        var readings: [AssemblyLinkReading] = []
        for (i, link) in links.enumerated() {
            let a = link.firstBody, b = link.secondBody
            let start = link.first.point(in: steps[a].nextPosition)
            let end = link.second.point(in: steps[b].nextPosition)
            let length = simd_distance(start, end)
            let opening = length - link.restLength
            let sample = link.sample(extension: opening, previous: maxima[i])
            if sample.force != 0 {
                guard length > 1e-10 else {
                    failure = "A loaded connection collapsed to zero length."
                    return false
                }
                let force = sample.force / length * (end - start)
                link.first.apply(force, to: &steps[a].nextApplied)
                link.second.apply(-force, to: &steps[b].nextApplied)
            }
            maxima[i] = sample.maximum
            trial.connection += sample.stored
            trial.fracture += sample.loss
            readings.append(AssemblyLinkReading(connection: link.connection, start: start, end: end,
                                                extensionLength: opening, force: sample.force, damage: sample.damage,
                                                storedEnergy: sample.stored, fractureDissipation: sample.loss))
        }
        guard trial.total.isFinite else {
            failure = "The energy calculation became non-finite."
            return false
        }
        for i in steps.indices {
            guard steps[i].kick(dt) else {
                failure = "Velocity became non-finite in \(scene.parts[i].name)."
                return false
            }
        }
        for i in steps.indices { steps[i].accept() }
        time += dt
        energy = trial
        linkReadings = readings
        for pair in active where firstContactTimes[pair] == nil { firstContactTimes[pair] = time }
        activeContacts = active
        peakRelativePenetration = max(peakRelativePenetration, penetration)
        return true
    }
}
