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
    public internal(set) var cohesive = 0.0
    public var total: Double { kinetic + elastic + contact + connection + hardening + plastic + fracture + cohesive }
}

public struct FragmentContactReading: Sendable {
    public let parts, pieces: SIMD2<Int>
    public let time: Double
    public let onExposedFace: Bool
}

public struct AssemblySimulation: Sendable {
    private struct Pair: Sendable {
        let a, b: Int
        let contact: BoundaryContact
    }

    private struct ContactDomain {
        let part: Int
        let proxy: FractureSurface?
        let surface: ContactSurface
        let position: [Point]
        let bounds: ContactBounds
        var force: [Point]

        init(part: Int, proxy: FractureSurface?, surface: ContactSurface, position: [Point]) {
            self.part = part
            self.proxy = proxy
            self.surface = surface
            self.position = position
            bounds = ContactBounds(surface: surface, position: position)
            force = Array(repeating: .zero, count: position.count)
        }
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
    public private(set) var fragmentContacts: [FragmentContactReading] = []
    private var steps: [BodyStep]
    private var fractures: [MaterialFracture?]
    private let hasFracture: Bool
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
    public func stress(_ index: Int) -> [Double] { steps[index].equivalentCauchyStress() }
    public func fractureReading(_ index: Int) -> MaterialFractureReading? { fractures[index]?.reading }
    public func crackFaces(_ index: Int) -> [CrackFace] {
        fractures[index]?.crackFaces(position: steps[index].body.position) ?? []
    }
    public func materialDamage(_ index: Int) -> [Double] { fractures[index]?.elementDamage() ?? [] }
    public func materialPieces(_ index: Int) -> [MaterialPiece] { fractures[index]?.pieceMotion(body(index)) ?? [] }

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
        try self.init(scene, refinement: scene.resolution.rawValue, stepLimit: .infinity)
    }

    package init(_ scene: AssemblyScene, refinement: Int, stepLimit: Double) throws {
        try scene.validate()
        precondition(refinement > 0 && stepLimit > 0)
        self.scene = scene
        let bodies = scene.parts.map { $0.makeBody(refinement: refinement) }
        let fractures = zip(bodies, scene.parts).map { body, part in
            part.fracture.map { MaterialFracture(body: body, settings: $0) }
        }
        self.fractures = fractures
        hasFracture = scene.parts.contains { $0.fracture != nil }
        let numericalBodies = zip(bodies, fractures).map { body, fracture in fracture?.discretize(body) ?? body }
        let surfaces = bodies.map(ContactSurface.init)
        self.surfaces = surfaces
        steps = zip(numericalBodies, scene.parts).map { body, part in
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
                let left = MaterialAnchor(0.5 * (connection.firstAnchor + offset) * scene.parts[a].size, mesh: numericalBodies[a].mesh)
                let right = MaterialAnchor(0.5 * (connection.secondAnchor + offset) * scene.parts[b].size, mesh: numericalBodies[b].mesh)
                let start = left.point(in: numericalBodies[a].position), end = right.point(in: numericalBodies[b].position)
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
        let frequency = numericalBodies.indices.map { i in
            if let fracture = fractures[i] {
                let ownContact = 8 * (surfaces[i].stiffness.max() ?? 0)
                return Simulation.squaredFrequency(of: numericalBodies[i], contact: nil, allowance: 0,
                    springs: springs[i] + fracture.stiffnessBudget(contactAllowance: allowance[i] + ownContact))
            }
            return Simulation.squaredFrequency(of: numericalBodies[i], contact: surfaces[i], allowance: allowance[i], springs: springs[i])
        }.max() ?? 1e8
        dt = min(stepLimit, 0.8 / frequency.squareRoot())
        initialEnergy = numericalBodies.reduce(0) { $0 + Self.kinetic($1) }
        energy = AssemblyEnergy(kinetic: initialEnergy, elastic: 0, contact: 0, connection: 0, hardening: 0, plastic: 0, fracture: 0)
    }

    private static func kinetic(_ body: Body) -> Double {
        body.mass.indices.reduce(0) { $0 + 0.5 * body.mass[$1] * simd_length_squared(body.velocity[$1]) }
    }

    private mutating func fractureContact(fractures: [MaterialFracture?], energy: inout AssemblyEnergy,
                                          penetration: inout Double, active: inout [SIMD2<Int>],
                                          events: inout [FragmentContactReading]) {
        var domains: [ContactDomain] = []
        for i in steps.indices {
            let position = steps[i].nextPosition
            if let fracture = fractures[i] {
                for proxy in fracture.surfaces {
                    domains.append(ContactDomain(part: i, proxy: proxy, surface: proxy.surface, position: proxy.positions(position)))
                }
            } else {
                domains.append(ContactDomain(part: i, proxy: nil, surface: surfaces[i], position: position))
            }
        }
        for a in domains.indices {
            for b in (a + 1)..<domains.count {
                let leftBounds = domains[a].bounds, rightBounds = domains[b].bounds
                guard leftBounds.intersects(rightBounds) else { continue }
                let partPair = SIMD2(domains[a].part, domains[b].part)
                let pieces = SIMD2(domains[a].proxy?.id ?? 0, domains[b].proxy?.id ?? 0)
                if partPair.x == partPair.y, fractures[partPair.x]!.suppressedPairs.contains(pieces) { continue }
                let contact = BoundaryContact(left: domains[a].surface, right: domains[b].surface)
                let result = domains.withUnsafeMutableBufferPointer { buffer in
                    let first = buffer.baseAddress!.advanced(by: a)
                    let second = buffer.baseAddress!.advanced(by: b)
                    let leftPosition = first.pointee.position, rightPosition = second.pointee.position
                    let leftFaces = first.pointee.proxy?.exposedEdges ?? [], rightFaces = second.pointee.proxy?.exposedEdges ?? []
                    return contact.accumulate(left: leftPosition, right: rightPosition, leftBounds: leftBounds,
                                              rightBounds: rightBounds, leftForce: &first.pointee.force,
                                              rightForce: &second.pointee.force, leftExposed: leftFaces, rightExposed: rightFaces)
                }
                energy.contact += result.energy
                penetration = max(penetration, result.relativePenetration)
                if result.penetration > 0 {
                    if !active.contains(partPair) { active.append(partPair) }
                    if (partPair.x == partPair.y || result.exposedFaceContact),
                       !events.contains(where: {
                           $0.parts == partPair && $0.pieces == pieces && $0.onExposedFace == result.exposedFaceContact
                       }) {
                        events.append(FragmentContactReading(parts: partPair, pieces: pieces, time: time + dt,
                                                                      onExposedFace: result.exposedFaceContact))
                    }
                }
            }
        }
        for domain in domains {
            if let proxy = domain.proxy {
                proxy.apply(domain.force, to: &steps[domain.part].nextApplied)
            } else {
                steps[domain.part].nextApplied = domain.force
            }
        }
    }

    private mutating func intactContact(energy: inout AssemblyEnergy, penetration: inout Double,
                                        active: inout [SIMD2<Int>]) {
        let bounds = steps.indices.map { ContactBounds(surface: surfaces[$0], position: steps[$0].nextPosition) }
        let contacts = pairs
        steps.withUnsafeMutableBufferPointer { buffer in
            for pair in contacts where bounds[pair.a].intersects(bounds[pair.b]) {
                // The two indices always differ, so the force buffers are disjoint.
                let a = buffer.baseAddress!.advanced(by: pair.a)
                let b = buffer.baseAddress!.advanced(by: pair.b)
                let result = pair.contact.accumulate(left: a.pointee.nextPosition, right: b.pointee.nextPosition,
                                                     leftBounds: bounds[pair.a], rightBounds: bounds[pair.b],
                                                     leftForce: &a.pointee.nextApplied, rightForce: &b.pointee.nextApplied)
                energy.contact += result.energy
                penetration = max(penetration, result.relativePenetration)
                if result.penetration > 0 { active.append(SIMD2(pair.a, pair.b)) }
            }
        }

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
        }
        var active: [SIMD2<Int>] = []
        var penetration = 0.0
        var nextFractures = fractures
        var nextContacts = fragmentContacts
        var nextMaxima = maxima
        for i in steps.indices {
            for j in steps[i].nextApplied.indices { steps[i].nextApplied[j] = .zero }
        }
        if hasFracture {
            for i in steps.indices where nextFractures[i] != nil {
                let position = steps[i].nextPosition
                guard let closure = nextFractures[i]!.accumulate(position: position, force: &steps[i].nextApplied) else {
                    failure = "A cohesive face collapsed in \(scene.parts[i].name)."
                    return false
                }
                trial.contact += closure
                trial.cohesive += nextFractures[i]!.reading.storedEnergy
                trial.fracture += nextFractures[i]!.reading.dissipation
                nextFractures[i]!.prepareFragmentContact(position: position)
            }
            fractureContact(fractures: nextFractures, energy: &trial, penetration: &penetration,
                            active: &active, events: &nextContacts)
            guard penetration <= 0.10 else {
                failure = "Contact overlapped by more than 10% of an edge. Try a slower impact or a different mesh."
                return false
            }
        } else {
            intactContact(energy: &trial, penetration: &penetration, active: &active)
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
            nextMaxima[i] = sample.maximum
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
        if hasFracture {
            for step in steps {
                for i in step.body.mass.indices {
                    trial.kinetic += 0.5 * step.body.mass[i] * simd_length_squared(step.nextVelocity[i])
                }
            }
            guard abs(trial.total - initialEnergy) <= max(1e-9, 0.02 * initialEnergy) else {
                failure = "Energy imbalance exceeded 2%. Try a slower impact or a different mesh."
                return false
            }
        }
        for i in steps.indices { steps[i].accept() }
        fractures = nextFractures
        fragmentContacts = nextContacts
        maxima = nextMaxima
        time += dt
        energy = trial
        linkReadings = readings
        for pair in active where firstContactTimes[pair] == nil { firstContactTimes[pair] = time }
        activeContacts = active
        peakRelativePenetration = max(peakRelativePenetration, penetration)
        return true
    }
}
