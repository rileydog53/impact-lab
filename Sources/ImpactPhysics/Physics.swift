import Foundation
import simd

public typealias Point = SIMD2<Double>

public struct Material: Codable, Equatable, Sendable {
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

    var nodes: SIMD3<Int> { SIMD3(a, b, c) }
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
    public let interfaceNodes: [Int]

    package init(reference: [Point], triangles: [(Int, Int, Int)], boundary: [Edge],
         probe: [Int] = [], interfaceNodes: [Int] = []) {
        self.reference = reference
        elements = triangles.map { Triangle($0.0, $0.1, $0.2, reference) }
        self.boundary = boundary
        self.probe = probe
        self.interfaceNodes = interfaceNodes
    }

    public static func bar(columns: Int = 120, rows: Int = 6, width: Double = 1, height: Double = 0.1) -> Mesh {
        rectangle(columns: columns, rows: rows, probeColumn: columns / 2) { u, v in
            Point(width * (u - 1), height * (v - 0.5))
        }
    }

    static func rectangle(columns: Int, rows: Int, probeColumn: Int? = nil, interfaceColumn: Int? = nil,
                          staggerDiagonals: Bool = false,
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
                if let probeColumn, i == probeColumn - 1 || i == probeColumn {
                    probe.append(contentsOf: [triangles.count, triangles.count + 1])
                }
                let forward = staggerDiagonals
                    ? simd_length_squared(nodes[a] - nodes[c]) < simd_length_squared(nodes[b] - nodes[d])
                    : (i + j).isMultiple(of: 2)
                if forward {
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
        let interfaceNodes = interfaceColumn.map { column in (0...rows).map { node(column, $0) } } ?? []
        return Mesh(reference: nodes, triangles: triangles, boundary: edges, probe: probe, interfaceNodes: interfaceNodes)
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
    let hasWall: Bool
    let measuresVerticalStrain: Bool
    let elementMaterials: [Material]?

    init(mesh: Mesh, material: Material, velocity: Point, gap: Double, penalty: Double, tilt: Double,
         centerY: Double = 0) {
        let c = cos(tilt), s = sin(tilt)
        let rotated = mesh.reference.map { Point(c * $0.x - s * $0.y, s * $0.x + c * $0.y) }
        let offset = Point(rotated.map(\.x).max()! + gap, -centerY)
        self.init(mesh: mesh, material: material, position: rotated.map { $0 - offset },
                  velocity: velocity, wallPenalty: penalty)
    }

    package init(mesh: Mesh, material: Material, position: [Point], velocity: Point,
         wallPenalty: Double = 0, measuresVerticalStrain: Bool = false,
         elementMaterials: [Material]? = nil, velocityPerturbation: [Point]? = nil) {
        self.mesh = mesh
        self.material = material
        self.position = position
        hasWall = wallPenalty > 0
        self.measuresVerticalStrain = measuresVerticalStrain
        self.elementMaterials = elementMaterials
        self.velocity = velocityPerturbation?.map { velocity + $0 }
            ?? Array(repeating: velocity, count: position.count)
        var nodalMass = Array(repeating: 0.0, count: position.count)
        for (i, e) in mesh.elements.enumerated() {
            let share = (elementMaterials?[i].density ?? material.density) * e.area / 3
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
        wallStiffness = tributaryLength.map { $0 * material.young * wallPenalty }
    }

    public var centerVelocity: Point {
        zip(mass, velocity).reduce(.zero) { $0 + $1.0 * $1.1 } / totalMass
    }
}

public struct Diagnostics: Sendable {
    public let kinetic, elastic, contact: Double
    public let hardening, plasticDissipation, appliedWork, peakOutOfPlaneStress: Double
    public let bondEnergy, fractureDissipation: Double
    public let relativeEnergyError: Double
    public let momentum: Point
    public let angularMomentum: Double
}

struct ElementHistory: Sendable {
    let model: J2Model
    var current: [J2History]
    var next: [J2History]

    init(model: J2Model, count: Int) {
        self.model = model
        current = Array(repeating: J2History(), count: count)
        next = current
    }

    mutating func accept() { swap(&current, &next) }
}

struct ElementEnergy: Sendable {
    var elastic = 0.0
    var hardening = 0.0
    var dissipation = 0.0
    var peakOutOfPlaneStress = 0.0
    var meanPlasticStrain = 0.0
    var peakPlasticStrain = 0.0
    var total: Double { elastic + hardening + dissipation }
}

// First Piola stress columns. Traction and cohesive quadrature both use
// reference edge length, so there is no conversion to current-area stress.
package struct ElementPiola: Sendable {
    package let x, y: Point
    package init(_ x: Point, _ y: Point) { self.x = x; self.y = y }
    func traction(_ normal: Point) -> Point { normal.x * x + normal.y * y }

    func accumulate(_ e: Triangle, into force: inout [Point]) {
        let px = -e.area * x, py = -e.area * y
        force[e.a] += px * e.g0.x + py * e.g0.y
        force[e.b] += px * e.g1.x + py * e.g1.y
        force[e.c] += px * e.g2.x + py * e.g2.y
    }
}

struct BodyStep: Sendable {
    var body: Body
    var strain: [Double]
    var internalForce: [Point]
    var appliedForce: [Point]
    var nextInternal: [Point]
    var nextApplied: [Point]
    var nextPosition: [Point]
    var nextVelocity: [Point]
    var nextStrain: [Double]
    var history: ElementHistory?
    var trialPiola: [ElementPiola] = []

    init(_ body: Body, j2: J2Model? = nil, recordsTraction: Bool = false) {
        self.body = body
        strain = Array(repeating: 0, count: body.mesh.elements.count)
        nextStrain = strain
        internalForce = Array(repeating: .zero, count: body.mass.count)
        appliedForce = internalForce
        nextInternal = internalForce
        nextApplied = internalForce
        nextPosition = body.position
        nextVelocity = body.velocity
        history = j2.map { ElementHistory(model: $0, count: body.mesh.elements.count) }
        if recordsTraction { trialPiola = Array(repeating: ElementPiola(.zero, .zero), count: strain.count) }
    }

    mutating func drift(_ dt: Double) -> Bool {
        for i in body.mass.indices {
            let acceleration = (internalForce[i] + appliedForce[i]) / body.mass[i]
            let position = body.position[i] + dt * (body.velocity[i] + 0.5 * dt * acceleration)
            guard position.x.isFinite && position.y.isFinite else { return false }
            nextPosition[i] = position
        }
        return true
    }

    mutating func assemble() -> ElementEnergy? {
        Simulation.assemble(body: body, position: nextPosition, forces: &nextInternal, strain: &nextStrain,
                            history: &history, piola: &trialPiola)
    }

    // Drift already used the parent's acceleration. Redistribute the old
    // force by new lumped mass so every daughter receives the same first
    // half kick. The second half kick uses forces on the new connectivity.
    mutating func splitNodes(mesh: Mesh, sources: [Int], dt: Double) -> InsertionBalance {
        func balance(_ body: Body, _ positions: [Point], _ internalForce: [Point], _ appliedForce: [Point])
            -> (momentum: Point, angular: Double, kinetic: Double) {
            var result = (Point.zero, 0.0, 0.0)
            for i in body.mass.indices {
                let mass = body.mass[i]
                let velocity = body.velocity[i] + (0.5 * dt / mass) * (internalForce[i] + appliedForce[i])
                let momentum = mass * velocity
                result.0 += momentum
                result.1 += cross2D(positions[i], momentum)
                result.2 += 0.5 * mass * simd_length_squared(velocity)
            }
            return result
        }
        let before = balance(body, nextPosition, internalForce, appliedForce)
        let former = body
        body = Body(mesh: mesh, material: former.material, position: sources.map { former.position[$0] },
                    velocity: .zero, measuresVerticalStrain: former.measuresVerticalStrain,
                    elementMaterials: former.elementMaterials, velocityPerturbation: sources.map { former.velocity[$0] })
        nextPosition = sources.map { nextPosition[$0] }
        internalForce = sources.enumerated().map { i, old in internalForce[old] * (body.mass[i] / former.mass[old]) }
        appliedForce = sources.enumerated().map { i, old in appliedForce[old] * (body.mass[i] / former.mass[old]) }
        let after = balance(body, nextPosition, internalForce, appliedForce)
        nextVelocity = body.velocity
        nextApplied = Array(repeating: .zero, count: sources.count)
        nextInternal = nextApplied
        for (i, e) in mesh.elements.enumerated() { trialPiola[i].accumulate(e, into: &nextInternal) }
        return InsertionBalance(mass: abs(former.totalMass - body.totalMass),
                                momentum: simd_distance(before.momentum, after.momentum),
                                angularMomentum: abs(before.angular - after.angular),
                                kinetic: abs(before.kinetic - after.kinetic))
    }

    mutating func kick(_ dt: Double) -> Bool {
        for i in body.mass.indices {
            let force = internalForce[i] + appliedForce[i] + nextInternal[i] + nextApplied[i]
            let velocity = body.velocity[i] + (0.5 * dt / body.mass[i]) * force
            guard velocity.x.isFinite && velocity.y.isFinite else { return false }
            nextVelocity[i] = velocity
        }
        return true
    }

    mutating func guideTransversePositions() {
        for i in nextPosition.indices { nextPosition[i].y = body.position[i].y }
    }

    mutating func guidePositions(grip: CohesiveSeam.Grip, motion: CohesiveSeam.Motion) {
        // The seam experiment uses lateral guides for pure normal opening.
        guideTransversePositions()
        let position = grip.initialX + grip.direction * motion.displacement
        for i in grip.nodes { nextPosition[i].x = position }
    }

    mutating func guideTransverseVelocities() {
        for i in nextVelocity.indices { nextVelocity[i].y = 0 }
    }

    mutating func guideVelocitiesAndWork(grip: CohesiveSeam.Grip, before: CohesiveSeam.Motion,
                                         after: CohesiveSeam.Motion) -> Double {
        guideTransverseVelocities()
        var work = 0.0
        for i in grip.nodes {
            nextVelocity[i].x = grip.direction * after.velocity
            // Prescribed grip reactions include inertia. The transverse guides do no work.
            let oldReaction = body.mass[i] * grip.direction * before.acceleration
                - (internalForce[i].x + appliedForce[i].x)
            let newReaction = body.mass[i] * grip.direction * after.acceleration
                - (nextInternal[i].x + nextApplied[i].x)
            work += 0.5 * (oldReaction + newReaction) * (nextPosition[i].x - body.position[i].x)
        }
        return work
    }

    mutating func wallContact(at planeX: Double, dt: Double) -> ContactResult {
        var result = ContactResult()
        for i in body.boundaryNodes {
            let overlap = max(0, nextPosition[i].x - planeX)
            let reaction = body.wallStiffness[i] * overlap
            let previousReaction = -body.wallStiffness[i] * max(0, body.position[i].x - planeX)
            nextApplied[i] = Point(-reaction, 0)
            result.penetration = max(result.penetration, overlap)
            result.energy += 0.5 * reaction * overlap
            // Trapezoidal wall kicks match the velocity updates. Torque is
            // evaluated about the wall origin at each kick's own position.
            result.wallImpulse += 0.5 * dt * (reaction - previousReaction)
            result.wallAngularImpulse += 0.5 * dt * (nextPosition[i].y * reaction
                                                    - body.position[i].y * previousReaction)
        }
        return result
    }

    mutating func contact(with other: inout Self, using pair: BoundaryContact) -> ContactResult {
        pair.assemble(left: nextPosition, right: other.nextPosition,
                      leftForce: &nextApplied, rightForce: &other.nextApplied, accumulating: true)
    }

    mutating func accept() {
        swap(&body.velocity, &nextVelocity)
        swap(&body.position, &nextPosition)
        swap(&internalForce, &nextInternal)
        swap(&appliedForce, &nextApplied)
        swap(&strain, &nextStrain)
        history?.accept()
    }
}

public struct Simulation: Sendable {
    public let dt: Double
    public let gap: Double
    public var body: Body { primary.body }
    public var strain: [Double] { primary.strain }
    public var secondBody: Body? { secondary?.body }
    public var secondStrain: [Double]? { secondary?.strain }
    public var thirdBody: Body? { tertiary?.body }
    public var thirdStrain: [Double]? { tertiary?.strain }
    public var receiverBody: Body? { receiver?.body }
    public var receiverStrain: [Double]? { receiver?.strain }
    public private(set) var receiverInContact = false
    public var secondPlasticStrain: [Double] { secondary?.history?.current.map(\.equivalentStrain) ?? [] }
    public var plasticDissipation: Double { primaryEnergy.dissipation + secondaryEnergy.dissipation }
    public var facingMeanPlasticStrain: Double { secondaryEnergy.meanPlasticStrain }
    public var plasticStrain: [Double] { primary.history?.current.map(\.equivalentStrain) ?? [] }
    public var meanPlasticStrain: Double { primaryEnergy.meanPlasticStrain }
    public var peakPlasticStrain: Double { max(primaryEnergy.peakPlasticStrain, secondaryEnergy.peakPlasticStrain) }
    public var gaugeLength: Double? { tension?.length(of: body.position) }
    public var appliedTraction: Double { tension?.traction(at: time) ?? 0 }
    public var loadReleaseTime: Double? { tension?.releaseTime }
    public var seamFirstOpeningTime: Double? { seam?.grips == nil ? nil : seam?.phaseDuration }
    public private(set) var seamReadings: SeamReadings?
    public private(set) var impactEvents: LayeredImpactEvents?
    public private(set) var strikerInContact = false
    public private(set) var seamInCompression = false
    public private(set) var backstopInContact = false

    public var seamDamage: [Double] {
        guard let seam else { return [] }
        return seamMaxima.map { seam.law.damage(at: $0) }
    }

    private var leftSeamBody: Body { tertiary == nil ? body : secondary!.body }
    private var rightSeamBody: Body? { thirdBody ?? secondBody }

    public var seamFaces: (left: [Point], right: [Point])? {
        guard let seam, let right = rightSeamBody else { return nil }
        return (seam.pairs.map { leftSeamBody.position[$0.left] }, seam.pairs.map { right.position[$0.right] })
    }
    package var seamLinkReadings: [(opening: Double, force: Double)] {
        guard let seam, let right = rightSeamBody else { return [] }
        return zip(seam.pairs, seamMaxima).map { pair, maximum in
            let opening = seam.opening(for: right.position[pair.right] - leftSeamBody.position[pair.left])
            return (opening, pair.weight * seam.law.evaluate(opening: opening, previousMaximum: maximum,
                                                              canSeparate: seam.canSeparate).traction)
        }
    }
    public private(set) var time = 0.0
    public private(set) var failure: String?
    public private(set) var wallImpulse = 0.0
    public private(set) var wallAngularImpulse = 0.0
    public private(set) var peakPenetration = 0.0
    public private(set) var peakRelativePenetration = 0.0
    private let initialKinetic: Double
    private var primaryEnergy = ElementEnergy()
    private var secondaryEnergy = ElementEnergy()
    private var tertiaryEnergy = ElementEnergy()
    private var receiverEnergy = ElementEnergy()
    private var contactEnergy = 0.0
    public private(set) var lastWallContactTime: Double?
    private var bondEnergy = 0.0
    private var appliedWork = 0.0
    private var primary: BodyStep
    private var secondary: BodyStep?
    private var tertiary: BodyStep?
    private var receiver: BodyStep?
    private let freeContacts: FreeImpactContacts?
    private let rearStopX: Double?
    private let pairContact: BoundaryContact?
    private let tension: TensionLoad?
    private let seam: CohesiveSeam?
    private var seamMaxima: [Double]

    public init(mesh: Mesh = .bar(), material: Material = Material(), speed: Double = 0.4,
                gap: Double = 0.0005, penalty: Double = 2500, stepScale: Double = 1, tilt: Double = 0) {
        precondition(gap >= 0 && penalty > 0)
        let body = Body(mesh: mesh, material: material, velocity: Point(speed, 0), gap: gap, penalty: penalty, tilt: tilt)
        self.init(primary: body, gap: gap, stepScale: stepScale)
    }

    init(primary: Body, secondary: Body? = nil, pairContact: BoundaryContact? = nil,
         gap: Double, stepScale: Double, tension: TensionLoad? = nil, j2: J2Model? = nil,
         seam: CohesiveSeam? = nil, tertiary: Body? = nil, secondaryJ2: J2Model? = nil,
         rearStopX: Double? = nil, receiver: Body? = nil) {
        let material = primary.material
        precondition(material.young > 0 && material.density > 0 && abs(material.poisson) < 0.5)
        precondition(stepScale > 0 && stepScale <= 1)
        precondition((secondary == nil) == (pairContact == nil && seam == nil))
        precondition((tertiary != nil) == (pairContact != nil && seam != nil))
        self.primary = BodyStep(primary, j2: j2)
        self.secondary = secondary.map { BodyStep($0, j2: secondaryJ2) }
        self.tertiary = tertiary.map { BodyStep($0) }
        self.receiver = receiver.map { BodyStep($0) }
        let freeContacts = receiver.map { FreeImpactContacts(striker: pairContact!.left, facing: pairContact!.right, backing: tertiary!, receiver: $0) }
        self.freeContacts = freeContacts
        impactEvents = tertiary.map { _ in LayeredImpactEvents() }
        self.pairContact = pairContact
        self.rearStopX = rearStopX
        self.gap = gap
        self.tension = tension
        self.seam = seam
        seamMaxima = Array(repeating: 0, count: seam?.pairs.count ?? 0)
        seamReadings = seam?.initialReadings
        func kineticEnergy(_ body: Body) -> Double {
            zip(body.mass, body.velocity).reduce(0) { $0 + 0.5 * $1.0 * simd_length_squared($1.1) }
        }
        initialKinetic = kineticEnergy(primary) + (secondary.map(kineticEnergy) ?? 0)
            + (tertiary.map(kineticEnergy) ?? 0) + (receiver.map(kineticEnergy) ?? 0)
        // Budget both the node's own contact spring and reactions to opposing springs.
        let allowance = 8 * (pairContact?.maximumStiffness ?? 0)
        let seamStiffness = 2 * ((freeContacts == nil ? seam?.law.contactStiffness : seam?.law.stiffness) ?? 0)
        let layersAllowance = 8 * (freeContacts?.layerContact.maximumStiffness ?? 0)
        let backingReceiver = 8 * (freeContacts?.receiverContact.maximumStiffness ?? 0)
        let strikerBacking = 8 * (freeContacts?.strikerBacking.maximumStiffness ?? 0)
        let strikerReceiver = 8 * (freeContacts?.strikerReceiver.maximumStiffness ?? 0)
        let facingReceiver = 8 * (freeContacts?.facingReceiver.maximumStiffness ?? 0)
        let firstSprings = seam?.pairs.map { ($0.left, seamStiffness * $0.weight) } ?? []
        let secondSprings = seam?.pairs.map { ($0.right, seamStiffness * $0.weight) } ?? []
        let firstOmega = Self.squaredFrequency(of: primary, contact: pairContact?.left,
                                               allowance: allowance + strikerBacking + strikerReceiver,
                                               springs: tertiary == nil ? firstSprings : [])
        let secondOmega = secondary.map {
            Self.squaredFrequency(of: $0, contact: pairContact?.right,
                                  allowance: allowance + layersAllowance + facingReceiver,
                                  springs: tertiary == nil ? secondSprings : firstSprings)
        } ?? 0
        let thirdOmega = tertiary.map {
            Self.squaredFrequency(of: $0, contact: freeContacts?.layerContact.right,
                                  allowance: layersAllowance + backingReceiver + strikerBacking, springs: secondSprings)
        } ?? 0
        // Central difference is linearly stable for dt * omega < 2.
        // The margin also accommodates changes in the tangent during impact.
        let receiverOmega = receiver.map {
            Self.squaredFrequency(of: $0, contact: freeContacts?.receiverContact.right,
                                  allowance: backingReceiver + strikerReceiver + facingReceiver, springs: [])
        } ?? 0
        dt = stepScale * 0.8 / sqrt(max(firstOmega, secondOmega, thirdOmega, receiverOmega))
    }

    static func squaredFrequency(of body: Body, contact: ContactSurface?, allowance: Double,
                                         springs: [(Int, Double)]) -> Double {
        let uniformWaveSpeedSquared = pow(body.material.waveSpeed, 2)
        var stiffness = Array(repeating: 0.0, count: body.mass.count)
        for (i, e) in body.mesh.elements.enumerated() {
            // A lumped-mass bound on the initial elastic spectral radius.
            let gradientSum = simd_length(e.g0) + simd_length(e.g1) + simd_length(e.g2)
            let material = body.elementMaterials?[i]
            let density = material?.density ?? body.material.density
            let waveSpeedSquared = material.map { pow($0.waveSpeed, 2) } ?? uniformWaveSpeedSquared
            let scale = e.area * density * waveSpeedSquared * gradientSum
            stiffness[e.a] += scale * simd_length(e.g0)
            stiffness[e.b] += scale * simd_length(e.g1)
            stiffness[e.c] += scale * simd_length(e.g2)
        }
        if let contact {
            for i in contact.nodes { stiffness[i] += allowance }
        }
        for (node, spring) in springs { stiffness[node] += spring }
        return body.mass.indices.reduce(0) { max($0, (stiffness[$1] + body.wallStiffness[$1]) / body.mass[$1]) }
    }

    public var probeStrain: Double {
        body.mesh.probe.reduce(0) { $0 + strain[$1] } / Double(max(1, body.mesh.probe.count))
    }

    public var diagnostics: Diagnostics {
        var kinetic = 0.0
        var momentum = Point.zero
        var angularMomentum = 0.0
        func accumulate(_ body: Body) {
            for i in body.mass.indices {
                let nodalMomentum = body.mass[i] * body.velocity[i]
                momentum += nodalMomentum
                angularMomentum += cross2D(body.position[i], nodalMomentum)
                kinetic += 0.5 * body.mass[i] * simd_length_squared(body.velocity[i])
            }
        }
        accumulate(body)
        if let secondBody { accumulate(secondBody) }
        if let thirdBody { accumulate(thirdBody) }
        if let receiverBody { accumulate(receiverBody) }
        let fracture = seamReadings?.dissipated ?? 0
        let energy = kinetic + primaryEnergy.total + secondaryEnergy.total + tertiaryEnergy.total + receiverEnergy.total + contactEnergy + bondEnergy + fracture
        let seamScale = seam?.grips == nil ? nil : seam.map { $0.height * $0.law.fractureEnergy }
        let relativeError = (energy - initialKinetic - appliedWork)
            / max(seamScale ?? tension?.referenceEnergy ?? initialKinetic, Double.leastNormalMagnitude)
        return Diagnostics(kinetic: kinetic, elastic: primaryEnergy.elastic + secondaryEnergy.elastic + tertiaryEnergy.elastic + receiverEnergy.elastic, contact: contactEnergy,
                           hardening: primaryEnergy.hardening + secondaryEnergy.hardening,
                           plasticDissipation: plasticDissipation,
                           appliedWork: appliedWork,
                           peakOutOfPlaneStress: max(primaryEnergy.peakOutOfPlaneStress, secondaryEnergy.peakOutOfPlaneStress),
                           bondEnergy: bondEnergy, fractureDissipation: fracture,
                           relativeEnergyError: relativeError, momentum: momentum,
                           angularMomentum: angularMomentum)
    }

    package func internalForces(at position: [Point]) -> [Point]? {
        var forces = primary.internalForce
        var strain = strain
        var history = primary.history
        guard Self.assemble(body: body, position: position, forces: &forces, strain: &strain, history: &history) != nil
        else { return nil }
        return forces
    }

    package var nodalMass: [Double] { body.mass }

    @discardableResult public mutating func step() -> Bool {
        guard failure == nil else { return false }
        guard primary.drift(dt), secondary?.drift(dt) ?? true, tertiary?.drift(dt) ?? true, receiver?.drift(dt) ?? true else {
            failure = "Position became non-finite."
            return false
        }
        let grips = seam?.grips
        let motion = grips.map { _ in seam!.motion(at: time + dt) }
        if let grips, let motion {
            primary.guidePositions(grip: grips.left, motion: motion)
            secondary!.guidePositions(grip: grips.right, motion: motion)
        } else if tertiary != nil && freeContacts == nil {
            primary.guideTransversePositions()
            secondary!.guideTransversePositions()
            tertiary!.guideTransversePositions()
        }
        guard let firstEnergy = primary.assemble(),
              let secondEnergy = secondary == nil ? ElementEnergy() : secondary?.assemble(),
              let thirdEnergy = tertiary == nil ? ElementEnergy() : tertiary?.assemble(),
              let fourthEnergy = receiver == nil ? ElementEnergy() : receiver?.assemble() else {
            failure = "An element inverted or its stress became non-finite."
            return false
        }
        var contact = ContactResult()
        var work = 0.0
        var seamTrial: CohesiveSeam.Trial?
        var impactContact = ContactResult()
        var stopContact = ContactResult()
        var receiverContact = ContactResult()
        var layerContact = ContactResult()
        if let pairContact {
            impactContact = pairContact.assemble(left: primary.nextPosition, right: secondary!.nextPosition,
                                                 leftForce: &primary.nextApplied, rightForce: &secondary!.nextApplied)
            contact = impactContact
        }
        if let seam {
            let trial: CohesiveSeam.Trial
            if tertiary != nil {
                if let rearStopX {
                    stopContact = tertiary!.wallContact(at: rearStopX, dt: dt)
                } else if freeContacts != nil {
                    for i in tertiary!.body.boundaryNodes { tertiary!.nextApplied[i] = .zero }
                } else {
                    for pair in seam.pairs { tertiary!.nextApplied[pair.right] = .zero }
                }
                trial = seam.assemble(left: secondary!.nextPosition, right: tertiary!.nextPosition,
                                      maxima: seamMaxima, leftForce: &secondary!.nextApplied,
                                      rightForce: &tertiary!.nextApplied)
            } else {
                for pair in seam.pairs {
                    primary.nextApplied[pair.left] = .zero
                    secondary!.nextApplied[pair.right] = .zero
                }
                trial = seam.assemble(left: primary.nextPosition, right: secondary!.nextPosition,
                                      maxima: seamMaxima, leftForce: &primary.nextApplied,
                                      rightForce: &secondary!.nextApplied)
            }
            contact.add(trial.contact)
            contact.add(stopContact)
            seamTrial = trial
        } else if primary.body.hasWall {
            contact = primary.wallContact(at: 0, dt: dt)
        } else if let tension {
            work = tension.apply(from: primary.body.position, to: primary.nextPosition, time: time,
                                 dt: dt, forces: &primary.nextApplied)
        }
        if let freeContacts {
            for i in receiver!.body.boundaryNodes { receiver!.nextApplied[i] = .zero }
            layerContact = secondary!.contact(with: &tertiary!, using: freeContacts.layerContact)
            receiverContact = tertiary!.contact(with: &receiver!, using: freeContacts.receiverContact)
            contact.add(layerContact)
            contact.add(receiverContact)
            contact.add(primary.contact(with: &tertiary!, using: freeContacts.strikerBacking))
            contact.add(primary.contact(with: &receiver!, using: freeContacts.strikerReceiver))
            contact.add(secondary!.contact(with: &receiver!, using: freeContacts.facingReceiver))
        }
        let seamEnergy = (seamTrial?.bondEnergy ?? 0) + (seamTrial?.readings.dissipated ?? 0)
        guard (contact.energy + firstEnergy.total + secondEnergy.total + thirdEnergy.total + fourthEnergy.total + seamEnergy).isFinite,
              (wallImpulse + contact.wallImpulse).isFinite,
              (wallAngularImpulse + contact.wallAngularImpulse).isFinite else {
            failure = "Contact energy or impulse became non-finite."
            return false
        }
        guard primary.kick(dt), secondary?.kick(dt) ?? true, tertiary?.kick(dt) ?? true, receiver?.kick(dt) ?? true else {
            failure = "Velocity became non-finite."
            return false
        }
        if let seam, let grips, let motion {
            let before = seam.motion(at: time)
            work = primary.guideVelocitiesAndWork(grip: grips.left, before: before, after: motion)
            work += secondary!.guideVelocitiesAndWork(grip: grips.right, before: before, after: motion)
        } else if tertiary != nil && freeContacts == nil {
            primary.guideTransverseVelocities()
            secondary!.guideTransverseVelocities()
            tertiary!.guideTransverseVelocities()
        }
        guard (appliedWork + work).isFinite else {
            failure = "Applied work became non-finite."
            return false
        }
        primary.accept()
        secondary?.accept()
        tertiary?.accept()
        receiver?.accept()
        time += dt
        primaryEnergy = firstEnergy
        secondaryEnergy = secondEnergy
        tertiaryEnergy = thirdEnergy
        receiverEnergy = fourthEnergy
        receiverInContact = receiverContact.penetration > 0
        strikerInContact = impactContact.penetration > 0
        backstopInContact = stopContact.penetration > 0
        seamInCompression = layerContact.penetration > 0 || (seamTrial?.contact.penetration ?? 0) > 0
        contactEnergy = contact.energy
        if primary.body.hasWall && contact.penetration > 0 { lastWallContactTime = time }
        if let trial = seamTrial {
            seamReadings = trial.readings
            seamMaxima = trial.maxima
            bondEnergy = trial.bondEnergy
        }
        if var events = impactEvents {
            if strikerInContact && events.strike == nil { events.strike = time }
            if backstopInContact && events.backstop == nil { events.backstop = time }
            if receiverInContact && events.receiver == nil { events.receiver = time }
            if events.failure != nil && seamInCompression && events.reclosure == nil { events.reclosure = time }
            if (seamReadings?.separatedFraction ?? 0) > 1 - 1e-12 && events.failure == nil {
                events.failure = time
            }
            impactEvents = events
        }
        appliedWork += work
        wallImpulse += contact.wallImpulse
        wallAngularImpulse += contact.wallAngularImpulse
        peakPenetration = max(peakPenetration, contact.penetration)
        peakRelativePenetration = max(peakRelativePenetration, contact.relativePenetration)
        return true
    }

    static func assemble(body: Body, position: [Point], forces: inout [Point],
                                     strain: inout [Double], history: inout ElementHistory?) -> ElementEnergy? {
        var piola: [ElementPiola] = []
        return assemble(body: body, position: position, forces: &forces, strain: &strain, history: &history, piola: &piola)
    }

    static func assemble(body: Body, position: [Point], forces: inout [Point], strain: inout [Double],
                         history: inout ElementHistory?, piola: inout [ElementPiola]) -> ElementEnergy? {
        for i in forces.indices { forces[i] = .zero }
        let uniformMu = body.material.shear
        let uniformLambda = body.material.lambda
        var energy = ElementEnergy()
        var plasticArea = 0.0
        for (i, e) in body.mesh.elements.enumerated() {
            let material = body.elementMaterials?[i]
            let mu = material?.shear ?? uniformMu
            let lambda = material?.lambda ?? uniformLambda
            let u = position[e.b] - position[e.a]
            let v = position[e.c] - position[e.a]
            let fx = u * e.g1.x + v * e.g2.x
            let fy = u * e.g1.y + v * e.g2.y
            let j = cross2D(fx, fy)
            guard j > 0, j.isFinite else { return nil }
            let xx = simd_length_squared(fx)
            let yy = simd_length_squared(fy)
            strain[i] = 0.5 * ((body.measuresVerticalStrain ? yy : xx) - 1)
            let stress: ElementPiola
            if let model = history?.model {
                guard let response = model.update(x: fx, y: fy, from: history!.current[i]) else { return nil }
                history!.next[i] = response.history
                stress = ElementPiola(response.piolaX, response.piolaY)
                let alpha = response.history.equivalentStrain
                plasticArea += e.area
                energy.meanPlasticStrain += e.area * alpha
                energy.peakPlasticStrain = max(energy.peakPlasticStrain, alpha)
                energy.peakOutOfPlaneStress = max(energy.peakOutOfPlaneStress, abs(response.cauchyZZ))
                energy.elastic += e.area * response.elasticEnergy
                energy.hardening += e.area * response.hardeningEnergy
                energy.dissipation += e.area * response.dissipation
            } else {
                // P = mu F + (lambda ln J - mu) F^(-T), with Fzz = 1.
                let logJ = log(j)
                let pressure = (lambda * logJ - mu) / j
                stress = ElementPiola(mu * fx + pressure * Point(fy.y, -fy.x),
                                      mu * fy + pressure * Point(-fx.y, fx.x))
                energy.elastic += e.area * (0.5 * mu * (xx + yy - 2 - 2 * logJ) + 0.5 * lambda * logJ * logJ)
            }
            guard stress.x.x.isFinite && stress.x.y.isFinite && stress.y.x.isFinite && stress.y.y.isFinite else {
                return nil
            }
            if !piola.isEmpty { piola[i] = stress }
            stress.accumulate(e, into: &forces)
        }
        if plasticArea > 0 { energy.meanPlasticStrain /= plasticArea }
        return energy.total.isFinite ? energy : nil
    }
}

extension BodyStep {
    func equivalentCauchyStress() -> [Double] {
        body.mesh.elements.indices.map { cauchyFields($0, includePressure: false).equivalent }
    }

    func cauchyFields(_ index: Int, includePressure: Bool = true, includeEquivalent: Bool = true)
        -> (pressure: Double, equivalent: Double) {
        let e = body.mesh.elements[index]
        let u = body.position[e.b] - body.position[e.a]
        let v = body.position[e.c] - body.position[e.a]
        let x = u * e.g1.x + v * e.g2.x
        let y = u * e.g1.y + v * e.g2.y
        let jacobian = cross2D(x, y)
        if let history {
            let pressure = includePressure ? -history.model.bulk * log(jacobian) / jacobian : 0
            let equivalent = includeEquivalent
                ? (history.model.update(x: x, y: y, from: history.current[index])?.equivalentStress ?? 0) / jacobian : 0
            return (pressure, equivalent)
        }
        let material = body.elementMaterials?[index] ?? body.material
        // Plane strain has Fzz = 1. Pressure is positive in compression.
        let xx = x.x * x.x + y.x * y.x
        let yy = x.y * x.y + y.y * y.y
        let pressure = includePressure
            ? -(material.shear * (xx + yy - 2) / 3 + material.lambda * log(jacobian)) / jacobian : 0
        guard includeEquivalent else { return (pressure, 0) }
        let xy = x.x * x.y + y.x * y.y
        let norm = ((xx - yy) * (xx - yy) + (xx - 1) * (xx - 1) + (yy - 1) * (yy - 1)) / 2 + 3 * xy * xy
        return (pressure, material.shear / jacobian * norm.squareRoot())
    }
}
