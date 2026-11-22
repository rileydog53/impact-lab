import simd

private struct MaterialAnchor: Sendable {
    let element: Int
    let weights: SIMD3<Double>

    init(_ point: Point, mesh: Mesh) {
        let reference = mesh.reference
        for (i, triangle) in mesh.elements.enumerated() {
            let offset = point - reference[triangle.a]
            let b = simd_dot(offset, triangle.g1), c = simd_dot(offset, triangle.g2)
            if min(b, c, 1 - b - c) >= -1e-10 {
                element = i
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
        element = mesh.elements.firstIndex { triangle in
            let nodes = triangle.nodes
            return (0..<3).contains { nodes[$0] == nearest.a && nodes[($0 + 1) % 3] == nearest.b }
        }!
        let nodes = mesh.elements[element].nodes
        var weights = SIMD3<Double>.zero
        for i in 0..<3 {
            if nodes[i] == nearest.a { weights[i] = 1 - weight }
            if nodes[i] == nearest.b { weights[i] = weight }
        }
        self.weights = weights
    }

    func point(in positions: [Point], mesh: Mesh) -> Point {
        let nodes = mesh.elements[element].nodes
        return weights.x * positions[nodes.x] + weights.y * positions[nodes.y] + weights.z * positions[nodes.z]
    }

    func apply(_ force: Point, mesh: Mesh, to forces: inout [Point]) {
        let nodes = mesh.elements[element].nodes
        for i in 0..<3 { forces[nodes[i]] += weights[i] * force }
    }

    func budget(_ stiffness: Double, mesh: Mesh, into springs: inout [(Int, Double)]) {
        let nodes = mesh.elements[element].nodes
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
    public internal(set) var lastTime: Double
    public internal(set) var firstExposedTime: Double?
    public var onExposedFace: Bool { firstExposedTime != nil }
    public internal(set) var normalImpulse: Double
}

private struct FragmentPair: Hashable, Sendable {
    let parts, pieces: SIMD2<Int>
}

private struct FragmentLoad {
    let load: Double
    let onExposedFace: Bool
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
    package private(set) var rejectedEnergy: AssemblyEnergy?
    package private(set) var rejectedPenetration: Double?
    package private(set) var rejectedContactDomains: SIMD4<Int>?
    package private(set) var rejectedClosureEnergy: Double?
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
    private var openFragmentContacts: [FragmentPair: (event: Int, load: Double)] = [:]
    private var normalLoads: [SIMD2<Int>: Double] = [:]
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

    package func normalLoad(_ a: Int, _ b: Int) -> Double { normalLoads[SIMD2(min(a, b), max(a, b)), default: 0] }

    package func fragmentClearances(_ part: Int, to target: Int) -> [(piece: Int, distance: Double)] {
        guard let fracture = fractures[part] else { return [] }
        let targets = fractures[target]?.surfaces.map { ($0.surface, $0.positions(steps[target].body.position)) }
            ?? [(surfaces[target], steps[target].body.position)]
        return fracture.surfaces.map { proxy in
            let position = proxy.positions(steps[part].body.position)
            let distance = targets.map {
                BoundaryContact.clearance(proxy.surface.edges, at: position, to: $0.0.edges, at: $0.1)
            }.min() ?? .infinity
            return (proxy.id, distance)
        }
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
        try self.init(scene, refinement: scene.resolution.rawValue, stepLimit: .infinity)
    }

    package init(_ scene: AssemblyScene, refinement: Int, stepLimit: Double,
                 notchDepth: Double = 0, stepScale: Double = 1) throws {
        try scene.validate()
        precondition(refinement > 0 && stepLimit > 0 && stepScale > 0 && notchDepth >= 0)
        self.scene = scene
        let bodies = scene.parts.enumerated().map { i, part in
            part.makeBody(refinement: refinement, notchDepth: i == 0 ? notchDepth : 0)
        }
        let fractures = zip(bodies, scene.parts).map { body, part in
            part.fracture.map { MaterialFracture(body: body, settings: $0) }
        }
        self.fractures = fractures
        hasFracture = scene.parts.contains { $0.fracture != nil }
        let surfaces = bodies.map(ContactSurface.init)
        self.surfaces = surfaces
        steps = zip(bodies, scene.parts).map { body, part in
            BodyStep(body, j2: part.plasticity.response == .elastoplastic ? part.plasticity.model(for: body.material) : nil,
                     recordsTraction: part.fracture != nil)
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
                let start = left.point(in: bodies[a].position, mesh: bodies[a].mesh)
                let end = right.point(in: bodies[b].position, mesh: bodies[b].mesh)
                let length = simd_distance(start, end)
                if length < 0.0005 && issue == nil { issue = .coincidentAnchors(index) }
                let stiffness = connection.stiffness / Double(count)
                let law = connection.kind == .cohesive ? CohesiveLaw(
                    strength: stiffness * 0.25 * connection.criticalExtension, finalOpening: connection.criticalExtension) : nil
                left.budget(2 * stiffness, mesh: bodies[a].mesh, into: &springs[a])
                right.budget(2 * stiffness, mesh: bodies[b].mesh, into: &springs[b])
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
        let frequency = bodies.indices.map { i in
            if let fracture = fractures[i] {
                let ownContact = 8 * (surfaces[i].stiffness.max() ?? 0)
                return fracture.squaredFrequencyBound(body: bodies[i], contactAllowance: allowance[i] + ownContact,
                                                      springs: springs[i])
            }
            return Simulation.squaredFrequency(of: bodies[i], contact: surfaces[i], allowance: allowance[i], springs: springs[i])
        }.max() ?? 1e8
        dt = min(stepLimit, stepScale * 0.8 / frequency.squareRoot())
        initialEnergy = bodies.reduce(0) { $0 + Self.kinetic($1) }
        energy = AssemblyEnergy(kinetic: initialEnergy, elastic: 0, contact: 0, connection: 0, hardening: 0, plastic: 0, fracture: 0)
    }

    private static func kinetic(_ body: Body) -> Double {
        body.mass.indices.reduce(0) { $0 + 0.5 * body.mass[$1] * simd_length_squared(body.velocity[$1]) }
    }

    private mutating func fractureContact(fractures: inout [MaterialFracture?], energy: inout AssemblyEnergy,
                                          penetration: inout Double, active: inout [SIMD2<Int>],
                                          loads: inout [FragmentPair: FragmentLoad], normal: inout [SIMD2<Int>: Double],
                                          deepest: inout SIMD4<Int>?) {
        var domains: [ContactDomain] = []
        let matching = fractures.map { $0?.matchingFeatures() ?? [:] }
        var overlapping = Array(repeating: Set<Int>(), count: fractures.count)
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
                let siblingContact = partPair.x == partPair.y && !matching[partPair.x].isEmpty
                    ? MatchingContact(leftNodes: domains[a].proxy!.nodes, rightNodes: domains[b].proxy!.nodes,
                                      seams: matching[partPair.x]) : nil
                let contact = BoundaryContact(left: domains[a].surface, right: domains[b].surface)
                let result = domains.withUnsafeMutableBufferPointer { buffer in
                    let first = buffer.baseAddress!.advanced(by: a)
                    let second = buffer.baseAddress!.advanced(by: b)
                    let leftPosition = first.pointee.position, rightPosition = second.pointee.position
                    let leftFaces = first.pointee.proxy?.exposedEdges ?? [], rightFaces = second.pointee.proxy?.exposedEdges ?? []
                    return contact.accumulate(left: leftPosition, right: rightPosition, leftBounds: leftBounds,
                                              rightBounds: rightBounds, leftForce: &first.pointee.force,
                                              rightForce: &second.pointee.force, leftExposed: leftFaces, rightExposed: rightFaces,
                                              matching: siblingContact)
                }
                if !result.matchingContacts.isEmpty { overlapping[partPair.x].formUnion(result.matchingContacts) }
                energy.contact += result.energy
                if result.relativePenetration > penetration {
                    penetration = result.relativePenetration
                    deepest = SIMD4(partPair.x, pieces.x, partPair.y, pieces.y)
                }
                if result.penetration > 0 {
                    if !active.contains(partPair) { active.append(partPair) }
                    normal[partPair, default: 0] += result.normalLoad
                    if domains[a].proxy != nil || domains[b].proxy != nil {
                        let key = FragmentPair(parts: partPair, pieces: pieces)
                        loads[key] = FragmentLoad(load: result.normalLoad, onExposedFace: result.exposedFaceContact)
                    }
                }
            }
        }
        for i in fractures.indices where !matching[i].isEmpty {
            fractures[i]!.finishMatchingContact(position: steps[i].nextPosition, overlapping: overlapping[i])
        }
        for domain in domains {
            if let proxy = domain.proxy {
                proxy.apply(domain.force, to: &steps[domain.part].nextApplied)
            } else {
                steps[domain.part].nextApplied = domain.force
            }
        }
    }

    private mutating func recordFragmentLoads(_ loads: [FragmentPair: FragmentLoad]) {
        for (key, previous) in openFragmentContacts {
            fragmentContacts[previous.event].normalImpulse += 0.5 * dt * (previous.load + (loads[key]?.load ?? 0))
            if let current = loads[key] {
                fragmentContacts[previous.event].lastTime = time
                if current.onExposedFace && fragmentContacts[previous.event].firstExposedTime == nil {
                    fragmentContacts[previous.event].firstExposedTime = time
                }
                openFragmentContacts[key] = (previous.event, current.load)
            } else {
                openFragmentContacts.removeValue(forKey: key)
            }
        }
        let starting = loads.keys.filter { openFragmentContacts[$0] == nil }.sorted {
            ($0.parts.x, $0.parts.y, $0.pieces.x, $0.pieces.y) < ($1.parts.x, $1.parts.y, $1.pieces.x, $1.pieces.y)
        }
        for key in starting {
            let current = loads[key]!
            openFragmentContacts[key] = (fragmentContacts.count, current.load)
            fragmentContacts.append(FragmentContactReading(parts: key.parts, pieces: key.pieces, time: time, lastTime: time,
                                                            firstExposedTime: current.onExposedFace ? time : nil,
                                                            normalImpulse: 0.5 * dt * current.load))
        }
    }

    private mutating func intactContact(energy: inout AssemblyEnergy, penetration: inout Double,
                                        active: inout [SIMD2<Int>], normal: inout [SIMD2<Int>: Double]) {
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
                if result.penetration > 0 {
                    let key = SIMD2(pair.a, pair.b)
                    active.append(key)
                    normal[key] = result.normalLoad
                }
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
        var nextNormal: [SIMD2<Int>: Double] = [:]
        var penetration = 0.0
        var deepest: SIMD4<Int>?
        var closureEnergy = 0.0
        var nextFractures = fractures
        var fragmentLoads: [FragmentPair: FragmentLoad] = [:]
        var nextMaxima = maxima
        var beforeSplit: [(Int, BodyStep)] = []
        var accepted = false
        defer {
            if !accepted {
                for (i, original) in beforeSplit { steps[i] = original }
            }
        }
        for i in steps.indices {
            for j in steps[i].nextApplied.indices { steps[i].nextApplied[j] = .zero }
        }
        if hasFracture {
            for i in steps.indices where nextFractures[i] != nil {
                let position = steps[i].nextPosition
                let mesh = steps[i].body.mesh
                if let split = nextFractures[i]!.insert(position: position, piola: steps[i].trialPiola, mesh: mesh) {
                    beforeSplit.append((i, steps[i]))
                    let balance = steps[i].splitNodes(mesh: split.mesh, sources: split.sources, dt: dt)
                    nextFractures[i]!.record(balance)
                }
                let newPosition = steps[i].nextPosition
                let reference = steps[i].body.mesh.reference
                guard let closure = nextFractures[i]!.accumulate(position: newPosition, reference: reference,
                                                                force: &steps[i].nextApplied) else {
                    failure = "A cohesive face collapsed in \(scene.parts[i].name)."
                    return false
                }
                trial.contact += closure
                closureEnergy += closure
                trial.cohesive += nextFractures[i]!.reading.storedEnergy
                trial.fracture += nextFractures[i]!.reading.dissipation
            }
            if nextFractures.contains(where: { ($0?.reading.insertedEdges ?? 0) > 0 }) {
                fractureContact(fractures: &nextFractures, energy: &trial, penetration: &penetration,
                                active: &active, loads: &fragmentLoads, normal: &nextNormal, deepest: &deepest)
            } else {
                intactContact(energy: &trial, penetration: &penetration, active: &active, normal: &nextNormal)
            }
            guard penetration <= 0.10 else {
                rejectedPenetration = penetration
                rejectedContactDomains = deepest
                rejectedClosureEnergy = closureEnergy
                failure = "Contact overlapped by more than 10% of an edge. Try a slower impact or a different mesh."
                return false
            }
        } else {
            intactContact(energy: &trial, penetration: &penetration, active: &active, normal: &nextNormal)
        }

        var readings: [AssemblyLinkReading] = []
        for (i, link) in links.enumerated() {
            let a = link.firstBody, b = link.secondBody
            let meshA = steps[a].body.mesh, meshB = steps[b].body.mesh
            let start = link.first.point(in: steps[a].nextPosition, mesh: meshA)
            let end = link.second.point(in: steps[b].nextPosition, mesh: meshB)
            let length = simd_distance(start, end)
            let opening = length - link.restLength
            let sample = link.sample(extension: opening, previous: maxima[i])
            if sample.force != 0 {
                guard length > 1e-10 else {
                    failure = "A loaded connection collapsed to zero length."
                    return false
                }
                let force = sample.force / length * (end - start)
                link.first.apply(force, mesh: meshA, to: &steps[a].nextApplied)
                link.second.apply(-force, mesh: meshB, to: &steps[b].nextApplied)
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
                rejectedEnergy = trial
                rejectedPenetration = penetration
                rejectedContactDomains = deepest
                rejectedClosureEnergy = closureEnergy
                failure = "Energy imbalance exceeded 2%. Try a slower impact or a different mesh."
                return false
            }
        }
        for i in steps.indices { steps[i].accept() }
        fractures = nextFractures
        maxima = nextMaxima
        time += dt
        if !fragmentLoads.isEmpty || !openFragmentContacts.isEmpty { recordFragmentLoads(fragmentLoads) }
        energy = trial
        linkReadings = readings
        for pair in active where firstContactTimes[pair] == nil { firstContactTimes[pair] = time }
        activeContacts = active
        normalLoads = nextNormal
        peakRelativePenetration = max(peakRelativePenetration, penetration)
        accepted = true
        return true
    }
}
