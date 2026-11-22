import simd

struct TriangleContact: Sendable {
    struct Bounds {
        let lower, upper: Point

        init(_ a: Point, _ b: Point, _ c: Point, padding: Point) {
            lower = simd_min(a, simd_min(b, c)) - padding
            upper = simd_max(a, simd_max(b, c)) + padding
        }

        init(_ a: Self, _ b: Self) {
            lower = simd_min(a.lower, b.lower)
            upper = simd_max(a.upper, b.upper)
        }

        func intersects(_ other: Self) -> Bool {
            lower.x < other.upper.x && upper.x > other.lower.x
                && lower.y < other.upper.y && upper.y > other.lower.y
        }
    }

    private struct Branch: Sendable {
        let first, second: Int
        var leaf: Bool { second < 0 }
    }

    struct State {
        let positions: [Point]
        let elements: [Triangle]
    }

    struct Workspace: Sendable {
        var origin: [Point] = []
        var candidates: [SIMD2<Int>] = []
    }

    struct Contact {
        let elements: SIMD2<Int>
        let force: [Point]
        let energy, relativePenetration, normalLoad: Double
        let face: Int
    }

    private struct FaceGap {
        let axis: Point
        let origin: Point
        let span: Point
        let length: Double
        let normalGaps: SIMD3<Double>
        let support: Double
    }

    private let tree: [Branch]
    private let padding: Double

    init(mesh: Mesh) {
        let centers = mesh.elements.map { (mesh.reference[$0.a] + mesh.reference[$0.b] + mesh.reference[$0.c]) / 3 }
        var nodes: [Branch] = []
        func build(_ elements: [Int]) -> Int {
            if elements.count == 1 {
                nodes.append(Branch(first: elements[0], second: -1))
            } else {
                let lower = elements.reduce(Point(repeating: .infinity)) { simd_min($0, centers[$1]) }
                let upper = elements.reduce(Point(repeating: -.infinity)) { simd_max($0, centers[$1]) }
                let axis = upper.x - lower.x > upper.y - lower.y ? 0 : 1
                let sorted = elements.sorted {
                    let a = centers[$0][axis], b = centers[$1][axis]
                    return a == b ? $0 < $1 : a < b
                }
                let half = sorted.count / 2
                let left = build(Array(sorted[..<half])), right = build(Array(sorted[half...]))
                nodes.append(Branch(first: left, second: right))
            }
            return nodes.count - 1
        }
        let active = Array(mesh.elements.indices)
        _ = build(active)
        tree = nodes
        padding = 0.02 * active.reduce(Double.infinity) { minimum, index in
            let e = mesh.elements[index]
            let a = mesh.reference[e.a], b = mesh.reference[e.b], c = mesh.reference[e.c]
            return min(minimum, simd_distance(a, b), simd_distance(b, c), simd_distance(c, a))
        }
    }

    func state(mesh: Mesh, position: [Point]) -> State {
        State(positions: position, elements: mesh.elements)
    }

    func visit(_ state: State, stiffness: Double, contact: (Contact) -> Void) {
        var workspace = Workspace()
        visit(state, stiffness: stiffness, workspace: &workspace, contact: contact)
    }

    func visit(_ state: State, stiffness: Double, workspace: inout Workspace, contact: (Contact) -> Void) {
        let positions = state.positions
        // Each triangle stays inside its padded box until any node travels
        // beyond the padding. Reusing the resulting pair list cannot miss
        // an overlapping pair within that displacement bound.
        if workspace.origin.count != positions.count
            || zip(workspace.origin, positions).contains(where: {
                let delta = $1 - $0
                return abs(delta.x) > padding || abs(delta.y) > padding
            }) {
            workspace.origin = positions
            rebuildCandidates(state, into: &workspace.candidates)
        }
        for pair in workspace.candidates {
            let a = state.elements[pair.x].nodes, b = state.elements[pair.y].nodes
            if !Self.separatedAtSharedVertex(a, b, at: positions),
               let hit = Self.overlap(pair.x, in: state, pair.y, in: state, stiffness: stiffness) {
                contact(hit)
            }
        }
    }

    private func rebuildCandidates(_ state: State, into candidates: inout [SIMD2<Int>]) {
        var bounds: [Bounds] = []
        bounds.reserveCapacity(tree.count)
        let positions = state.positions
        for branch in tree {
            if branch.leaf {
                let e = state.elements[branch.first]
                let offset = Point(repeating: padding)
                let a = positions[e.a], b = positions[e.b], c = positions[e.c]
                bounds.append(Bounds(a, b, c, padding: offset))
            } else {
                bounds.append(Bounds(bounds[branch.first], bounds[branch.second]))
            }
        }
        candidates.removeAll(keepingCapacity: true)
        func traverse(_ a: Int, _ b: Int) {
            if !bounds[a].intersects(bounds[b]) { return }
            let l = tree[a], r = tree[b]
            if l.leaf && r.leaf {
                if a != b {
                    let v = state.elements[l.first].nodes, w = state.elements[r.first].nodes
                    let shared = (0..<3).reduce(0) { count, i in
                        count + (v[i] == w.x || v[i] == w.y || v[i] == w.z ? 1 : 0)
                    }
                    if shared < 2 { candidates.append(SIMD2(l.first, r.first)) }
                }
            } else if a == b {
                traverse(l.first, l.first)
                traverse(l.first, l.second)
                traverse(l.second, l.second)
            } else if !l.leaf && (r.leaf || a > b) {
                traverse(l.first, b)
                traverse(l.second, b)
            } else {
                traverse(a, r.first)
                traverse(a, r.second)
            }
        }
        traverse(tree.count - 1, tree.count - 1)
    }

    private static func separatedAtSharedVertex(_ a: SIMD3<Int>, _ b: SIMD3<Int>, at position: [Point]) -> Bool {
        for i in 0..<3 {
            let shared = a[i]
            let j = shared == b.x ? 0 : (shared == b.y ? 1 : (shared == b.z ? 2 : -1))
            guard j >= 0 else { continue }
            let aNext = a[(i + 1) % 3], aPrevious = a[(i + 2) % 3]
            let bNext = b[(j + 1) % 3], bPrevious = b[(j + 2) % 3]
            // Positive triangles with a shared edge have disjoint interiors.
            if aNext == bPrevious || aPrevious == bNext { return true }
            let p = position[shared]
            let u = position[aNext] - p, v = position[aPrevious] - p
            let w = position[bNext] - p, z = position[bPrevious] - p
            // The four sides of the two cones at the shared point are
            // separating axes for the triangles themselves.
            return max(cross2D(u, w), cross2D(u, z)) <= 0
                || min(cross2D(v, w), cross2D(v, z)) >= 0
                || max(cross2D(w, u), cross2D(w, v)) <= 0
                || min(cross2D(z, u), cross2D(z, v)) >= 0
        }
        return false
    }

    private static func overlap(_ a: Int, in left: State, _ b: Int, in right: State, stiffness: Double) -> Contact? {
        let v = left.elements[a], w = right.elements[b]
        let p = left.positions, q = right.positions
        let pa = p[v.a], pb = p[v.b], pc = p[v.c]
        let qa = q[w.a], qb = q[w.b], qc = q[w.c]
        if separates(pa, pb, q: qa, qb, qc) || separates(pb, pc, q: qa, qb, qc)
            || separates(pc, pa, q: qa, qb, qc) || separates(qa, qb, q: pa, pb, pc)
            || separates(qb, qc, q: pa, pb, pc) || separates(qc, qa, q: pa, pb, pc) {
            return nil
        }
        let x = SIMD8(pa.x, pb.x, pc.x, qa.x, qb.x, qc.x, 0, 0)
        let y = SIMD8(pa.y, pb.y, pc.y, qa.y, qb.y, qc.y, 0, 0)
        return withUnsafeTemporaryAllocation(of: FaceGap.self, capacity: 6) { gaps in
            overlap(a, b, x: x, y: y, stiffness: stiffness, gaps: gaps)
        }
    }

    @inline(__always) private static func separates(_ a: Point, _ b: Point, q: Point, _ r: Point, _ s: Point) -> Bool {
        let span = b - a
        return max(cross2D(span, q - a), cross2D(span, r - a), cross2D(span, s - a)) <= 1e-16
    }

    private static func overlap(_ a: Int, _ b: Int, x: SIMD8<Double>, y: SIMD8<Double>,
                                stiffness: Double, gaps: UnsafeMutableBufferPointer<FaceGap>) -> Contact? {
        func point(_ i: Int) -> Point { Point(x[i], y[i]) }
        var minimumSupport = Double.infinity
        var minimumDepth = Double.infinity
        var limitingFace = 0
        for i in 0..<6 {
            let side = i < 3 ? 0 : 3
            let opposite = 3 - side
            let origin = point(i), span = point(side + (i + 1) % 3) - origin
            let delta0 = point(opposite) - origin, delta1 = point(opposite + 1) - origin, delta2 = point(opposite + 2) - origin
            let area = SIMD3(cross2D(span, delta0), cross2D(span, delta1), cross2D(span, delta2))
            if area.max() <= 1e-16 { return nil }
            let length = simd_length(span)
            let depth = area.max() / length
            if depth < minimumDepth {
                minimumDepth = depth
                limitingFace = i
            }
            let normalGaps = simd_max(.zero, area / length)
            let support = simd_length(normalGaps)
            minimumSupport = min(minimumSupport, support)
            gaps.baseAddress!.advanced(by: i).initialize(to: FaceGap(axis: Point(span.y, -span.x) / length, origin: origin, span: span,
                                length: length, normalGaps: normalGaps, support: support))
        }

        // The positive half-space support on each of the six axes is a norm
        // of signed vertex depths. A smooth minimum gives a zero-contact
        // exterior and distributes the reaction across competing features.
        let inverseSum = gaps.reduce(0.0) { partial, gap in
            let r = minimumSupport / gap.support, r2 = r * r
            return partial + r2 * r2 * r2
        }
        let depth = minimumSupport / pow(inverseSum, 1.0 / 6)
        var force = Array(repeating: Point.zero, count: 6)
        for (i, gap) in gaps.enumerated() {
            let side = i < 3 ? 0 : 3
            let opposite = 3 - side
            let end = side + (i + 1) % 3
            let r = depth / gap.support, r2 = r * r, r4 = r2 * r2
            let scale = stiffness * r4 * r4
            for j in 0..<3 where gap.normalGaps[j] > 0 {
                let p = opposite + j
                let f = (scale * gap.normalGaps[j]) * gap.axis
                let fraction = simd_dot(point(p) - gap.origin, gap.span) / (gap.length * gap.length)
                force[p] += f
                force[i] -= (1 - fraction) * f
                force[end] -= fraction * f
            }
        }
        let load = simd_length(force[0] + force[1] + force[2])
        return Contact(elements: SIMD2(a, b), force: force, energy: 0.5 * stiffness * depth * depth,
                       relativePenetration: minimumDepth / gaps[limitingFace].length, normalLoad: load,
                       face: limitingFace)
    }
}

package struct TriangleContactProbe {
    package let force: [Point]
    package let energy, relativePenetration: Double
}

package func probeTriangleContact(mesh: Mesh, positions: [Point], stiffness: Double) -> TriangleContactProbe {
    let tree = TriangleContact(mesh: mesh)
    let state = tree.state(mesh: mesh, position: positions)
    var force = Array(repeating: Point.zero, count: positions.count)
    var energy = 0.0, penetration = 0.0
    tree.visit(state, stiffness: stiffness) { hit in
        let a = mesh.elements[hit.elements.x].nodes, b = mesh.elements[hit.elements.y].nodes
        for i in 0..<3 {
            force[a[i]] += hit.force[i]
            force[b[i]] += hit.force[i + 3]
        }
        energy += hit.energy
        penetration = max(penetration, hit.relativePenetration)
    }
    return TriangleContactProbe(force: force, energy: energy, relativePenetration: penetration)
}
