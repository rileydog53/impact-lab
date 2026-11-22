import simd

public struct CrackFace: Sendable {
    public let first, second: Edge
    public let damage: Double
    public let separation: Double
}

public struct MaterialFractureReading: Sendable {
    public internal(set) var damagedEdges = 0
    public internal(set) var failedEdges = 0
    public internal(set) var pieces = 1
    public internal(set) var crackLength = 0.0
    public internal(set) var separation = 0.0
    public internal(set) var storedEnergy = 0.0
    public internal(set) var dissipation = 0.0
}

public struct MaterialPiece: Identifiable, Sendable {
    public let id: Int
    public let mass: Double
    public let center, velocity: Point
}

private struct Components {
    var parent: [Int]
    init(_ count: Int) { parent = Array(0..<count) }

    mutating func root(_ index: Int) -> Int {
        var i = index
        while parent[i] != i {
            parent[i] = parent[parent[i]]
            i = parent[i]
        }
        return i
    }

    mutating func join(_ a: Int, _ b: Int) {
        let left = root(a), right = root(b)
        parent[max(left, right)] = min(left, right)
    }
}

// The contact proxy closes sub-element jumps at connected vertices by averaging
// their positions. The transpose of that map returns contact loads to FEM nodes.
struct FractureSurface: Sendable {
    let id: Int
    let stencil: [[Int]]
    let surface: ContactSurface
    let exposedEdges: Set<SIMD2<Int>>

    func positions(_ position: [Point]) -> [Point] {
        stencil.map { nodes in
            nodes.reduce(.zero) { $0 + position[$1] } / Double(nodes.count)
        }
    }

    func apply(_ force: [Point], to result: inout [Point]) {
        for node in surface.nodes {
            let nodes = stencil[node]
            let share = force[node] / Double(nodes.count)
            for index in nodes { result[index] += share }
        }
    }
}

package struct MaterialFracture: Sendable {
    private struct Interface: Sendable {
        let a, b: Int
        let left, right: Edge // Both directed along the left element's original edge.
        let length: Double
        let law: CohesiveLaw
        var maxima = Point.zero
        var handedOff = false

        var failed: Bool { min(maxima.x, maxima.y) >= law.finalOpening }

        func frame(_ positions: [Point]) -> (tangent: Point, normal: Point, length: Double) {
            // A material face supplies the corotating frame. An average
            // of opposite tangents can approach zero during fracture.
            let chord = positions[left.b] - positions[left.a]
            let length = simd_length(chord)
            let t = chord / length
            return (t, Point(t.y, -t.x), length)
        }

        func gap(_ positions: [Point]) -> (Point, Point) {
            (positions[right.a] - positions[left.a], positions[right.b] - positions[left.b])
        }
    }

    private var interfaces: [Interface]
    private let exterior: [(Int, Edge)]
    private let reference: [Point]
    private let young: Double
    private var pieces: [Int] = []
    private(set) var surfaces: [FractureSurface] = []
    private(set) var suppressedPairs: Set<SIMD2<Int>> = []
    package private(set) var reading = MaterialFractureReading()
    private var failedCount = 0

    package init(body: Body, settings: MaterialFractureSettings) {
        var pending: [SIMD2<Int>: (Int, Edge)] = [:]
        var interfaces: [Interface] = []
        var reference: [Point] = []
        for (i, triangle) in body.mesh.elements.enumerated() {
            let original = [triangle.a, triangle.b, triangle.c]
            reference.append(contentsOf: original.map { body.mesh.reference[$0] })
            for j in 0..<3 {
                let k = (j + 1) % 3
                let key = SIMD2(min(original[j], original[k]), max(original[j], original[k]))
                if let (neighbor, left) = pending.removeValue(forKey: key) {
                    let right = Edge(3 * i + k, 3 * i + j)
                    let length = simd_distance(reference[left.a], reference[left.b])
                    let strength = body.material.young * settings.strengthFraction
                    let altitude = min(triangle.area, body.mesh.elements[neighbor].area) * 2 / length
                    let finalOpening = 2 * settings.energy / strength
                    // Mesh-scaled initial compliance, with an onset below the
                    // softening interval even for the lowest toughness settings.
                    let stiffness = max(30 * body.material.young / altitude, 4 * strength / finalOpening)
                    interfaces.append(Interface(a: neighbor, b: i, left: left, right: right, length: length,
                                                law: CohesiveLaw(strength: strength, finalOpening: finalOpening,
                                                                 initialStiffness: stiffness)))
                } else {
                    pending[key] = (i, Edge(3 * i + j, 3 * i + k))
                }
            }
        }
        self.reference = reference
        young = body.material.young
        self.interfaces = interfaces
        exterior = pending.sorted {
            ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y)
        }.map(\.value)
        rebuildTopology()
    }

    package func discretize(_ body: Body) -> Body {
        let triangles = body.mesh.elements.indices.map { (3 * $0, 3 * $0 + 1, 3 * $0 + 2) }
        let position = body.mesh.elements.flatMap { [body.position[$0.a], body.position[$0.b], body.position[$0.c]] }
        return Body(mesh: Mesh(reference: reference, triangles: triangles, boundary: exterior.map(\.1)),
                    material: body.material, position: position, velocity: body.velocity[0])
    }

    func stiffnessBudget(contactAllowance: Double) -> [(Int, Double)] {
        // Local penalty and consistent two-point quadrature; row-sum bound
        // includes both sides of an interface and all potential boundary nodes.
        var springs = Array(repeating: contactAllowance, count: reference.count)
        for seam in interfaces {
            let bound = seam.length * seam.law.contactStiffness
            for i in [seam.left.a, seam.left.b, seam.right.a, seam.right.b] { springs[i] += bound }
        }
        return springs.enumerated().map { ($0.offset, $0.element) }
    }

    private mutating func rebuildTopology() {
        var corners = Components(reference.count)
        var elements = Components(reference.count / 3)
        for seam in interfaces where !seam.failed {
            elements.join(seam.a, seam.b)
            corners.join(seam.left.a, seam.right.a)
            corners.join(seam.left.b, seam.right.b)
        }
        pieces = (0..<(reference.count / 3)).map { elements.root($0) }

        var faces: [Int: [(Edge, Bool)]] = [:]
        for (element, edge) in exterior { faces[pieces[element], default: []].append((edge, false)) }
        for seam in interfaces where seam.failed {
            faces[pieces[seam.a], default: []].append((seam.left, true))
            faces[pieces[seam.b], default: []].append((Edge(seam.right.b, seam.right.a), true))
        }
        let exposedCorners = Set(faces.values.flatMap { $0.flatMap { [$0.0.a, $0.0.b] } }.map { corners.root($0) })
        var members: [Int: [Int]] = [:]
        for i in reference.indices {
            let root = corners.root(i)
            if exposedCorners.contains(root) { members[root, default: []].append(i) }
        }
        surfaces = faces.keys.sorted().map { id in
            var index: [Int: Int] = [:]
            var stencil: [[Int]] = []
            var points: [Point] = []
            func locate(_ node: Int) -> Int {
                let root = corners.root(node)
                if let existing = index[root] { return existing }
                let next = stencil.count
                index[root] = next
                stencil.append(members[root]!)
                points.append(reference[node])
                return next
            }
            var exposed: Set<SIMD2<Int>> = []
            let edges = faces[id]!.map { edge, cracked in
                let face = Edge(locate(edge.a), locate(edge.b))
                if cracked { exposed.insert(SIMD2(face.a, face.b)) }
                return face
            }
            return FractureSurface(id: id, stencil: stencil, surface: ContactSurface(edges: edges, reference: points, young: young),
                                   exposedEdges: exposed)
        }
    }

    // Positive opening and sliding share one effective separation and toughness.
    // Compression is reversible and independent of cohesive damage.
    package mutating func accumulate(position: [Point], force: inout [Point]) -> Double? {
        var values = MaterialFractureReading()
        var contactEnergy = 0.0
        let abscissa = Point(repeating: 0.5) + Point(-1, 1) / (2 * Double(3).squareRoot())
        for i in interfaces.indices {
            var seam = interfaces[i]
            if seam.handedOff {
                let (a, b) = seam.gap(position)
                values.damagedEdges += 1
                values.failedEdges += 1
                values.crackLength += seam.length
                values.separation = max(values.separation, simd_length(a), simd_length(b))
                values.dissipation += seam.length * seam.law.fractureEnergy
                continue
            }
            let frame = seam.frame(position)
            guard frame.length > 0.15 * seam.length else { return nil }
            let (gapA, gapB) = seam.gap(position)
            let openingA = simd_dot(gapA, frame.normal), openingB = simd_dot(gapB, frame.normal)
            let weight = 0.5 * seam.length
            for q in 0..<2 {
                let b = abscissa[q], a = 1 - b
                let opening = a * openingA + b * openingB
                let shear = simd_dot(a * gapA + b * gapB, frame.tangent)
                let effective = simd_length(Point(max(0, opening), shear))
                let sample = seam.law.evaluate(opening: effective, previousMaximum: seam.maxima[q], canSeparate: true)
                seam.maxima[q] = sample.maximumOpening
                let secant = (1 - seam.law.damage(at: sample.maximumOpening)) * seam.law.stiffness
                let compression = min(0, opening) * seam.law.contactStiffness
                let normal = secant * max(0, opening) + compression
                let tangential = secant * shear
                let traction = weight * (normal * frame.normal + tangential * frame.tangent)
                // Gradient through the rotating face frame, so cohesive forces
                // remain objective and their total torque is zero under sliding.
                let rotation = -weight * (normal * shear - tangential * opening) / frame.length * frame.normal
                force[seam.left.a] += a * traction + rotation
                force[seam.left.b] += b * traction - rotation
                force[seam.right.a] -= a * traction
                force[seam.right.b] -= b * traction
                values.storedEnergy += weight * sample.bondEnergy
                values.dissipation += weight * sample.dissipated
                contactEnergy += 0.5 * weight * compression * opening
            }
            if max(seam.maxima.x, seam.maxima.y) > seam.law.onset { values.damagedEdges += 1 }
            if seam.failed {
                values.failedEdges += 1
                values.crackLength += seam.length
                values.separation = max(values.separation, simd_length(gapA), simd_length(gapB))
            }
            interfaces[i] = seam
        }
        if values.failedEdges != failedCount {
            failedCount = values.failedEdges
            rebuildTopology()
        }
        values.pieces = surfaces.count
        reading = values
        return contactEnergy
    }

    // Switch from face closure to ordinary fragment contact only at zero
    // local penalty energy, and only after *all* shared broken faces are clear.
    mutating func prepareFragmentContact(position: [Point]) {
        suppressedPairs.removeAll(keepingCapacity: true)
        guard surfaces.count > 1 else { return }
        var pending: [(Int, SIMD2<Int>)] = []
        for (i, seam) in interfaces.enumerated() where seam.failed && !seam.handedOff {
            let a = pieces[seam.a], b = pieces[seam.b]
            guard a != b else { continue }
            let pair = SIMD2(min(a, b), max(a, b))
            let frame = seam.frame(position)
            let (gapA, gapB) = seam.gap(position)
            if min(simd_dot(gapA, frame.normal), simd_dot(gapB, frame.normal)) < 0 {
                suppressedPairs.insert(pair)
            }
            pending.append((i, pair))
        }
        for (i, pair) in pending where !suppressedPairs.contains(pair) { interfaces[i].handedOff = true }
    }

    func crackFaces(position: [Point]) -> [CrackFace] {
        interfaces.compactMap { seam in
            let damage = 0.5 * (seam.law.damage(at: seam.maxima.x) + seam.law.damage(at: seam.maxima.y))
            if damage == 0 { return nil }
            let (a, b) = seam.gap(position)
            return CrackFace(first: seam.left, second: seam.right, damage: damage,
                             separation: 0.5 * (simd_length(a) + simd_length(b)))
        }
    }

    func elementDamage() -> [Double] {
        var result = Array(repeating: 0.0, count: pieces.count)
        for seam in interfaces {
            let value = max(seam.law.damage(at: seam.maxima.x), seam.law.damage(at: seam.maxima.y))
            result[seam.a] = max(result[seam.a], value)
            result[seam.b] = max(result[seam.b], value)
        }
        return result
    }

    func pieceMotion(_ body: Body) -> [MaterialPiece] {
        var totals: [Int: (mass: Double, center: Point, momentum: Point)] = [:]
        for (element, id) in pieces.enumerated() {
            var sum = totals[id] ?? (0, .zero, .zero)
            for i in (3 * element)..<(3 * element + 3) {
                let mass = body.mass[i]
                sum.mass += mass
                sum.center += mass * body.position[i]
                sum.momentum += mass * body.velocity[i]
            }
            totals[id] = sum
        }
        return totals.keys.sorted().map { id in
            let total = totals[id]!
            return MaterialPiece(id: id, mass: total.mass, center: total.center / total.mass, velocity: total.momentum / total.mass)
        }
    }
}
