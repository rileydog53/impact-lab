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
        fileprivate var candidates: [Candidate] = []
    }

    fileprivate struct Candidate: Sendable {
        let pair: SIMD2<Int>
        // A shared vertex and the four stencil nodes in cone order.
        let vertex: Int
        let stencil: SIMD4<Int>

        init?(_ a: Int, _ b: Int, elements: [Triangle]) {
            pair = SIMD2(a, b)
            let left = elements[a].nodes, right = elements[b].nodes
            for i in 0..<3 {
                let node = left[i]
                let j = node == right.x ? 0 : (node == right.y ? 1 : (node == right.z ? 2 : -1))
                if j < 0 { continue }
                let next = left[(i + 1) % 3], previous = left[(i + 2) % 3]
                let otherNext = right[(j + 1) % 3], otherPrevious = right[(j + 2) % 3]
                // Positive triangles sharing an edge have disjoint interiors.
                if next == otherNext || next == otherPrevious || previous == otherNext || previous == otherPrevious {
                    return nil
                }
                vertex = node
                stencil = SIMD4(next, previous, otherNext, otherPrevious)
                return
            }
            vertex = -1
            stencil = .zero
        }

        func separatedThroughoutPadding(at positions: [Point], padding: Double) -> Bool {
            guard vertex >= 0 else { return false }
            let origin = positions[vertex]
            let u = positions[stencil.x] - origin, v = positions[stencil.y] - origin
            let w = positions[stencil.z] - origin, z = positions[stencil.w] - origin
            // Each relative vector can change by at most twice the node
            // padding per component. Bound the change in each cross product
            // by expanding cross(a + da, b + db). The larger bound leaves
            // slack for rounding. Uncertain pairs keep the original test.
            let delta = 4 * padding
            func leftOf(_ a: Point, _ b: Point) -> Bool {
                let change = delta * (abs(a.x) + abs(a.y) + abs(b.x) + abs(b.y) + 2 * delta)
                return cross2D(a, b) > change
            }
            return (leftOf(w, u) && leftOf(z, u))
                || (leftOf(v, w) && leftOf(v, z))
                || (leftOf(u, w) && leftOf(v, w))
                || (leftOf(z, u) && leftOf(z, v))
        }

        func separated(at positions: [Point]) -> Bool {
            guard vertex >= 0 else { return false }
            let origin = positions[vertex]
            let u = positions[stencil.x] - origin, v = positions[stencil.y] - origin
            let w = positions[stencil.z] - origin, z = positions[stencil.w] - origin
            // These are the four separating axes through the shared vertex.
            return max(cross2D(u, w), cross2D(u, z)) <= 0
                || min(cross2D(v, w), cross2D(v, z)) >= 0
                || max(cross2D(w, u), cross2D(w, v)) <= 0
                || min(cross2D(z, u), cross2D(z, v)) >= 0
        }
    }

    struct Contact {
        let elements: SIMD2<Int>
        let force: [Point]
        let energy, relativePenetration, normalLoad: Double
        /// Absolute overlap (m) along the limiting face. Reporting only.
        let penetrationDepth: Double
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
        for candidate in workspace.candidates {
            if !candidate.separated(at: positions),
               let hit = Self.overlap(candidate.pair.x, in: state, candidate.pair.y, in: state, stiffness: stiffness) {
                contact(hit)
            }
        }
    }

    private func rebuildCandidates(_ state: State, into candidates: inout [Candidate]) {
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
                if a != b, let candidate = Candidate(l.first, r.first, elements: state.elements) {
                    if !candidate.separatedThroughoutPadding(at: positions, padding: padding) {
                        candidates.append(candidate)
                    }
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
                       penetrationDepth: minimumDepth, face: limitingFace)
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
