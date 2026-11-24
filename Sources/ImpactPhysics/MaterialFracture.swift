import simd

public struct CrackFace: Sendable {
    public let first, second: Edge
    public let damage: Double
    public let separation: Double
    public let failed: Bool
    public let seed: Point // Normal and shear traction at insertion.
}

public struct MaterialFractureReading: Sendable {
    public internal(set) var insertedEdges = 0
    public internal(set) var damagedEdges = 0
    public internal(set) var failedEdges = 0
    public internal(set) var pieces = 1
    public internal(set) var crackLength = 0.0
    public internal(set) var separation = 0.0
    public internal(set) var storedEnergy = 0.0
    public internal(set) var dissipation = 0.0
    public internal(set) var peakSeedTractionError = 0.0
    public internal(set) var peakBulkTractionGap = 0.0
    package var insertionBalance = InsertionBalance()
}

package struct InsertionBalance: Sendable {
    package var mass = 0.0
    package var momentum = 0.0
    package var angularMomentum = 0.0
    package var kinetic = 0.0

    mutating func accumulate(_ other: Self) {
        mass = max(mass, other.mass)
        momentum = max(momentum, other.momentum)
        angularMomentum = max(angularMomentum, other.angularMomentum)
        kinetic = max(kinetic, other.kinetic)
    }
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

struct FractureSurface: Sendable {
    let id: Int
    let nodes: [Int]
    let surface: ContactSurface
    let exposedEdges: Set<SIMD2<Int>>
    let edgeCorners: [Edge]

    func positions(_ position: [Point]) -> [Point] { nodes.map { position[$0] } }

    func apply(_ force: [Point], to result: inout [Point]) {
        for i in surface.nodes { result[nodes[i]] += force[i] }
    }
}

// A shifted radial law gives a finite initial traction with zero physical gap.
// Translating by the virtual onset preserves an objective mixed-mode potential.
// On the proportional loading ray the envelope is triangular over the physical
// displacement 2 Gc / peak. Secant unloading keeps the maximum irreversible.
private struct InsertedLaw: Sendable {
    let peak, energy, closureStiffness, onset, finalOpening: Double
    let offset, seed: Point

    init(traction: Point, energy: Double, stiffness: Double) {
        peak = simd_length(traction)
        self.energy = energy
        closureStiffness = 4 * stiffness
        onset = peak / stiffness
        finalOpening = onset + 2 * energy / peak
        offset = traction / stiffness
        seed = traction
    }

    func progress(_ maximum: Double) -> Double {
        min(1, max(0, (maximum - onset) / (finalOpening - onset)))
    }

    func evaluate(gap: Point, previous: Double, closes: Bool)
        -> (traction: Point, maximum: Double, stored: Double, loss: Double, closure: Double) {
        let shifted = gap + offset
        let effective = Point(max(0, shifted.x), shifted.y)
        let radiusSquared = simd_length_squared(effective)
        let maximum = max(previous, radiusSquared.squareRoot())
        let fraction = progress(maximum)
        let secant = peak * (1 - fraction) / maximum
        let compression = closes ? min(0, gap.x) : 0
        // Remove the virtual preload energy in proportion to remaining
        // envelope traction. Only the work available after insertion is Gc.
        let stored = 0.5 * secant * (radiusSquared - onset * maximum)
        return (secant * effective + Point(closureStiffness * compression, 0), maximum, stored,
                energy * fraction, 0.5 * closureStiffness * compression * compression)
    }
}

package struct MaterialFracture: Sendable {
    // Insertion stress measure. Recovered: linear least-squares patch recovery
    // at the face endpoints (default). Element: the
    // mean of the two adjacent constant-strain triangles (legacy 0.8 criterion,
    // retained only for A/B verification via ImpactCheck --legacy-insertion).
    package nonisolated(unsafe) static var recoveredInsertionStress = true
    private struct Face: Sendable {
        let left, right: Edge // Element corner IDs, both in the left triangle's orientation.
        let normal: Point
        let length, stiffness: Double
        var a: Int { left.a / 3 }
        var b: Int { right.a / 3 }
    }

    private struct Interface: Sendable {
        let face: Int
        let law: InsertedLaw
        var left, right: Edge // FEM node IDs.
        var maxima: Point

        var failed: Bool { min(maxima.x, maxima.y) >= law.finalOpening }

        func frame(_ positions: [Point]) -> (tangent: Point, normal: Point, length: Double) {
            let chord = positions[left.b] - positions[left.a]
            let length = simd_length(chord)
            let t = chord / length
            return (t, Point(t.y, -t.x), length)
        }

        func gap(_ positions: [Point]) -> (Point, Point) {
            (positions[right.a] - positions[left.a], positions[right.b] - positions[left.b])
        }
    }

    private let faces: [Face]
    private let exterior: [Edge] // Element corner IDs.
    private let young, density, strength, toughness: Double
    private let cornerStiffness: [Double]
    private var slots: [Int]
    private var recovery: [[(element: Int, weight: Double)]]
    private var interfaces: [Interface] = []
    private var exposedCorners: Set<Int> = []
    let contactTree: TriangleContact
    private var pieces: [Int]
    private var cornerNodes: [Int]
    private(set) var surfaces: [FractureSurface] = []
    package private(set) var reading = MaterialFractureReading()

    mutating func record(_ balance: InsertionBalance) { reading.insertionBalance.accumulate(balance) }

    func contactCorners(at node: Int) -> [Int] {
        cornerNodes.indices.filter { cornerNodes[$0] == node }
    }

    package init(body: Body, settings: MaterialFractureSettings) {
        let mesh = body.mesh
        young = body.material.young
        density = body.material.density
        strength = settings.resolvedStrength(young: young)
        toughness = settings.energy
        cornerNodes = mesh.elements.flatMap { [$0.a, $0.b, $0.c] }
        var pending: [SIMD2<Int>: Edge] = [:]
        var faces: [Face] = []
        var stiffnesses = Array(repeating: 0.0, count: cornerNodes.count)
        for (i, triangle) in mesh.elements.enumerated() {
            for j in 0..<3 {
                let k = (j + 1) % 3
                let a = triangle.nodes[j], b = triangle.nodes[k]
                let key = SIMD2(min(a, b), max(a, b))
                if let left = pending.removeValue(forKey: key) {
                    let delta = mesh.reference[cornerNodes[left.b]] - mesh.reference[cornerNodes[left.a]]
                    let length = simd_length(delta)
                    let altitude = min(triangle.area, mesh.elements[left.a / 3].area) * 2 / length
                    let stiffness = max(30 * young / altitude, 2 * strength * strength / toughness)
                    let right = Edge(3 * i + k, 3 * i + j)
                    faces.append(Face(left: left, right: right, normal: Point(delta.y, -delta.x) / length,
                                      length: length, stiffness: stiffness))
                    for corner in [left.a, left.b, right.a, right.b] { stiffnesses[corner] += 4 * length * stiffness }
                } else {
                    pending[key] = Edge(3 * i + j, 3 * i + k)
                }
            }
        }
        self.faces = faces
        cornerStiffness = stiffnesses
        exterior = pending.sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }.map(\.value)
        contactTree = TriangleContact(mesh: mesh)
        slots = Array(repeating: -1, count: faces.count)
        recovery = Self.recoveryWeights(mesh: mesh)
        pieces = Array(repeating: 0, count: mesh.elements.count)
        rebuildSurfaces(reference: mesh.reference)
    }

    // Bound every possible future vertex sector by its individual corner
    // masses. A sector's stiffness/mass is a weighted average of these
    // bounds, so topology changes do not require a different time grid.
    func squaredFrequencyBound(body: Body, contactAllowance: Double, springs: [(Int, Double)]) -> Double {
        var anchors = Array(repeating: 0.0, count: body.mesh.reference.count)
        for (node, value) in springs { anchors[node] += value }
        let bulk = density * body.material.waveSpeed * body.material.waveSpeed
        var bound = 0.0
        for (i, e) in body.mesh.elements.enumerated() {
            let g = Point(simd_length(e.g0), simd_length(e.g1))
            let third = simd_length(e.g2)
            let scale = bulk * e.area * (g.x + g.y + third)
            let mass = density * e.area / 3
            for (j, gradient) in [g.x, g.y, third].enumerated() {
                let stiffness = scale * gradient + cornerStiffness[3 * i + j] + contactAllowance + anchors[e.nodes[j]]
                bound = max(bound, stiffness / mass)
            }
        }
        return bound
    }

    private func edge(_ corners: Edge) -> Edge { Edge(cornerNodes[corners.a], cornerNodes[corners.b]) }

    private func sectors(excluding cuts: [Bool]) -> Components {
        var fans = Components(cornerNodes.count)
        for (i, face) in faces.enumerated() where slots[i] < 0 && !cuts[i] {
            fans.join(face.left.a, face.right.a)
            fans.join(face.left.b, face.right.b)
        }
        return fans
    }

    package mutating func insert(position: [Point], piola: [ElementPiola], mesh: Mesh) -> (mesh: Mesh, sources: [Int])? {
        var pending: [(index: Int, traction: Point, bulkGap: Double)] = []
        let strengthSquared = strength * strength
        // A cheap upper bound avoids projecting every face in weak elastic
        // waves. The remaining candidates are evaluated in fixed mesh order.
        if !piola.contains(where: { simd_length_squared($0.x) + simd_length_squared($0.y) >= strengthSquared }) {
            return nil
        }
        let patch = MaterialFracture.recoveredInsertionStress ? Self.recover(piola, weights: recovery) : []
        for (i, face) in faces.enumerated() where slots[i] < 0 {
            let left = piola[face.a].traction(face.normal), right = piola[face.b].traction(face.normal)
            var mean = 0.5 * (left + right)
            if MaterialFracture.recoveredInsertionStress {
                mean = .zero
                for corner in [face.left.a, face.left.b, face.right.a, face.right.b] {
                    mean += 0.25 * patch[cornerNodes[corner]].traction(face.normal)
                }
            }
            // Relative 1e-12 allowance absorbs roundoff from the recovery average.
            guard simd_length_squared(mean) >= strengthSquared * (1 - 1e-12) else { continue }
            let direction = edge(face.left)
            let tangent = simd_normalize(position[direction.b] - position[direction.a])
            let normal = Point(tangent.y, -tangent.x)
            let traction = Point(simd_dot(mean, normal), simd_dot(mean, tangent))
            // Opening and shear fracture are supported under noncompressive
            // normal traction. Matching-face closure is separately unilateral.
            guard traction.x >= 0 else { continue }
            pending.append((i, traction, simd_distance(left, right) / strength))
        }
        guard !pending.isEmpty else { return nil }
        var cuts = Array(repeating: false, count: faces.count)
        for item in pending { cuts[item.index] = true }
        var fans = sectors(excluding: cuts)
        pending.removeAll { item in
            let face = faces[item.index]
            return fans.root(face.left.a) == fans.root(face.right.a) && fans.root(face.left.b) == fans.root(face.right.b)
        }
        // Reinstating a face whose ends were already joined cannot change
        // the groups. Each retained cut releases at least one endpoint.
        guard !pending.isEmpty else { return nil }
        var rootForNode = Array(repeating: -1, count: mesh.reference.count)
        var nodeForRoot = Array(repeating: -1, count: cornerNodes.count)
        var sources = Array(mesh.reference.indices)
        for corner in cornerNodes.indices {
            let root = fans.root(corner)
            if nodeForRoot[root] < 0 {
                let parent = cornerNodes[corner]
                if rootForNode[parent] < 0 {
                    rootForNode[parent] = root
                    nodeForRoot[root] = parent
                } else {
                    nodeForRoot[root] = sources.count
                    sources.append(parent)
                }
            }
            cornerNodes[corner] = nodeForRoot[root]
        }
        for i in interfaces.indices {
            let face = faces[interfaces[i].face]
            interfaces[i].left = edge(face.left)
            interfaces[i].right = edge(face.right)
        }
        for item in pending {
            let face = faces[item.index]
            let law = InsertedLaw(traction: item.traction, energy: toughness, stiffness: face.stiffness)
            let seed = law.evaluate(gap: .zero, previous: law.onset, closes: true)
            reading.peakSeedTractionError = max(reading.peakSeedTractionError, simd_distance(seed.traction, item.traction) / strength)
            reading.peakBulkTractionGap = max(reading.peakBulkTractionGap, item.bulkGap)
            exposedCorners.insert(face.left.a)
            exposedCorners.insert(face.right.b)
            slots[item.index] = interfaces.count
            interfaces.append(Interface(face: item.index, law: law, left: edge(face.left), right: edge(face.right),
                                        maxima: Point(repeating: law.onset)))
        }
        reading.insertedEdges = interfaces.count
        let reference = sources.map { mesh.reference[$0] }
        let triangles = mesh.elements.indices.map { i in
            (cornerNodes[3 * i], cornerNodes[3 * i + 1], cornerNodes[3 * i + 2])
        }
        rebuildSurfaces(reference: reference)
        let remeshed = Mesh(reference: reference, triangles: triangles, boundary: exterior.map(edge), probe: mesh.probe)
        recovery = Self.recoveryWeights(mesh: remeshed)
        return (remeshed, sources)
    }

    // Linear least-squares patch recovery of the first Piola stress at each
    // node, fitted to element-centroid values over the incident elements in
    // the current connectivity, so the fit never spans an open crack. A linear
    // fit reproduces any linear stress field exactly, including at free
    // surfaces where plain nodal averaging underestimates bending stress.
    // The fit is a fixed linear operator of the element stresses, so its
    // weights are rebuilt only when the connectivity changes.
    package static func recoveryWeights(mesh: Mesh) -> [[(element: Int, weight: Double)]] {
        let count = mesh.reference.count
        var incident = Array(repeating: [Int](), count: count)
        for (i, e) in mesh.elements.enumerated() { for n in [e.a, e.b, e.c] { incident[n].append(i) } }
        let centroid = mesh.elements.map { (mesh.reference[$0.a] + mesh.reference[$0.b] + mesh.reference[$0.c]) / 3 }
        var mark = Array(repeating: -1, count: mesh.elements.count)
        return (0..<count).map { n in
            // One ring of incident elements; widen to two rings only where one
            // ring cannot determine a linear field (corners and crack flanks).
            var patch = incident[n]
            if patch.count < 4 {
                for e in incident[n] { mark[e] = n }
                for e in incident[n] {
                    let t = mesh.elements[e]
                    for m in [t.a, t.b, t.c] {
                        for f in incident[m] where mark[f] != n { mark[f] = n; patch.append(f) }
                    }
                }
            }
            let origin = mesh.reference[n]
            let scale = patch.map { simd_length(centroid[$0] - origin) }.max()!
            let basis = patch.map { e -> SIMD3<Double> in
                let d = (centroid[e] - origin) / scale
                return SIMD3(1, d.x, d.y)
            }
            var normal = simd_double3x3(0)
            for v in basis { normal += simd_double3x3(rows: [v * v.x, v * v.y, v * v.z]) }
            // Fall back to the patch mean if the centroids are nearly collinear.
            guard patch.count >= 3, abs(normal.determinant) > 1e-9 * pow(Double(patch.count), 3) else {
                return patch.map { ($0, 1 / Double(patch.count)) }
            }
            // Value at the node = first row of (AᵀA)⁻¹Aᵀ applied to the samples.
            let row = normal.inverse.transpose.columns.0
            return zip(patch, basis).map { ($0, simd_dot(row, $1)) }
        }
    }

    /// Verification access: recovery with the cached weights, and with weights
    /// rebuilt from scratch for a given mesh.
    package func cachedRecovery(_ piola: [ElementPiola]) -> [ElementPiola] { Self.recover(piola, weights: recovery) }
    package static func freshRecovery(_ piola: [ElementPiola], mesh: Mesh) -> [ElementPiola] {
        recover(piola, weights: recoveryWeights(mesh: mesh))
    }

    private static func recover(_ piola: [ElementPiola], weights: [[(element: Int, weight: Double)]]) -> [ElementPiola] {
        weights.map { patch in
            var x = Point.zero, y = Point.zero
            for (e, w) in patch { x += w * piola[e].x; y += w * piola[e].y }
            return ElementPiola(x, y)
        }
    }

    private mutating func rebuildSurfaces(reference: [Point]) {
        var components = Components(cornerNodes.count / 3)
        for (i, face) in faces.enumerated() where slots[i] < 0 || !interfaces[slots[i]].failed {
            components.join(face.a, face.b)
        }
        pieces = pieces.indices.map { components.root($0) }
        var boundaries: [Int: [(corners: Edge, lip: Bool, failed: Bool)]] = [:]
        for exteriorEdge in exterior {
            boundaries[pieces[exteriorEdge.a / 3], default: []].append((exteriorEdge, false, false))
        }
        for seam in interfaces {
            let face = faces[seam.face]
            boundaries[pieces[face.a], default: []].append((face.left, true, seam.failed))
            boundaries[pieces[face.b], default: []].append((Edge(face.right.b, face.right.a), true, seam.failed))
        }
        surfaces = boundaries.keys.sorted().map { id in
            var index: [Int: Int] = [:]
            var nodes: [Int] = []
            func locate(_ node: Int) -> Int {
                if let existing = index[node] { return existing }
                let next = nodes.count
                index[node] = next
                nodes.append(node)
                return next
            }
            var exposed: Set<SIMD2<Int>> = []
            var sourceEdges: [Edge] = []
            let edges = boundaries[id]!.map { item in
                let materialEdge = edge(item.corners)
                let face = Edge(locate(materialEdge.a), locate(materialEdge.b))
                if item.lip { exposed.insert(SIMD2(face.a, face.b)) }
                if !item.lip || item.failed { sourceEdges.append(face) }
                return face
            }
            let surface = ContactSurface(edges: edges, reference: nodes.map { reference[$0] }, young: young, sourceEdges: sourceEdges)
            return FractureSurface(id: id, nodes: nodes, surface: surface, exposedEdges: exposed,
                                   edgeCorners: boundaries[id]!.map(\.corners))
        }
    }

    package mutating func accumulate(position: [Point], reference: [Point], force: inout [Point],
                                     pairedClosure: Bool = true) -> Double? {
        guard !interfaces.isEmpty else { return 0 }
        var values = reading
        values.damagedEdges = 0
        values.failedEdges = 0
        values.crackLength = 0
        values.separation = 0
        values.storedEnergy = 0
        values.dissipation = 0
        var contactEnergy = 0.0
        for i in interfaces.indices {
            var seam = interfaces[i]
            let length = faces[seam.face].length
            let frame = seam.frame(position)
            guard frame.length.isFinite && frame.length > 0.15 * length else { return nil }
            let (gapA, gapB) = seam.gap(position)
            let weight = 0.5 * length
            for q in 0..<2 {
                let b = q == 0 ? 0.21132486540518713 : 0.7886751345948129
                let a = 1 - b
                let gap = a * gapA + b * gapB
                let local = Point(simd_dot(gap, frame.normal), simd_dot(gap, frame.tangent))
                let sample = seam.law.evaluate(gap: local, previous: seam.maxima[q], closes: pairedClosure)
                seam.maxima[q] = sample.maximum
                let traction = weight * (sample.traction.x * frame.normal + sample.traction.y * frame.tangent)
                // Differentiate the rotating local frame as well as the gap.
                let rotation = -weight * (sample.traction.x * local.y - sample.traction.y * local.x)
                    / frame.length * frame.normal
                force[seam.left.a] += a * traction + rotation
                force[seam.left.b] += b * traction - rotation
                force[seam.right.a] -= a * traction
                force[seam.right.b] -= b * traction
                values.storedEnergy += weight * sample.stored
                values.dissipation += weight * sample.loss
                contactEnergy += weight * sample.closure
            }
            if max(seam.maxima.x, seam.maxima.y) > seam.law.onset + 1e-14 { values.damagedEdges += 1 }
            if seam.failed {
                values.failedEdges += 1
                values.crackLength += length
                values.separation = max(values.separation, simd_length(gapA), simd_length(gapB))
            }
            interfaces[i] = seam
        }
        if values.failedEdges != reading.failedEdges { rebuildSurfaces(reference: reference) }
        values.pieces = surfaces.count
        reading = values
        return contactEnergy
    }

    func piece(for element: Int) -> Int { pieces[element] }

    func isExposed(corner: Int) -> Bool { exposedCorners.contains(corner) }

    func matchingFeatures() -> [SIMD3<Int>: Int] {
        guard surfaces.count > 1 else { return [:] }
        var features: [SIMD3<Int>: Int] = [:]
        // The legacy boundary probe labels matching hits for comparison
        // with the old paired-closure formulation.
        for (i, seam) in interfaces.enumerated() where seam.failed {
            let face = faces[seam.face]
            guard pieces[face.a] != pieces[face.b] else { continue }
            for node in [seam.left.a, seam.left.b] { features[SIMD3(node, seam.right.b, seam.right.a)] = i }
            for node in [seam.right.a, seam.right.b] { features[SIMD3(node, seam.left.a, seam.left.b)] = i }
        }
        return features
    }

    func crackFaces(position: [Point]) -> [CrackFace] {
        interfaces.map { seam in
            let damage = 0.5 * (seam.law.progress(seam.maxima.x) + seam.law.progress(seam.maxima.y))
            let (a, b) = seam.gap(position)
            return CrackFace(first: seam.left, second: seam.right, damage: damage,
                             separation: 0.5 * (simd_length(a) + simd_length(b)), failed: seam.failed, seed: seam.law.seed)
        }
    }

    func elementDamage() -> [Double] {
        var result = Array(repeating: 0.0, count: pieces.count)
        for seam in interfaces {
            let face = faces[seam.face]
            let value = seam.law.progress(max(seam.maxima.x, seam.maxima.y))
            result[face.a] = max(result[face.a], value)
            result[face.b] = max(result[face.b], value)
        }
        return result
    }

    func elementDamage(_ element: Int) -> Double {
        interfaces.reduce(0.0) { damage, seam in
            let face = faces[seam.face]
            guard face.a == element || face.b == element else { return damage }
            return max(damage, seam.law.progress(max(seam.maxima.x, seam.maxima.y)))
        }
    }

    func pieceMotion(_ body: Body) -> [MaterialPiece] {
        var totals: [Int: (mass: Double, center: Point, momentum: Point)] = [:]
        for (element, id) in pieces.enumerated() {
            let triangle = body.mesh.elements[element]
            let mass = density * triangle.area / 3
            var sum = totals[id] ?? (0, .zero, .zero)
            for node in [triangle.a, triangle.b, triangle.c] {
                sum.mass += mass
                sum.center += mass * body.position[node]
                sum.momentum += mass * body.velocity[node]
            }
            totals[id] = sum
        }
        return totals.keys.sorted().map { id in
            let total = totals[id]!
            return MaterialPiece(id: id, mass: total.mass, center: total.center / total.mass, velocity: total.momentum / total.mass)
        }
    }

    package func contactTrack(_ corners: SIMD3<Int>, at positions: [Point]) -> ContactFeatureTrack {
        let node = cornerNodes[corners.x], a = cornerNodes[corners.y], b = cornerNodes[corners.z]
        let chord = positions[b] - positions[a], offset = positions[node] - positions[a]
        let length = simd_length(chord)
        return ContactFeatureTrack(nodes: SIMD3(node, a, b), pieces: SIMD2(pieces[corners.x / 3], pieces[corners.y / 3]),
                                   gap: (chord.y * offset.x - chord.x * offset.y) / length,
                                   fraction: simd_dot(chord, offset) / (length * length))
    }
}
