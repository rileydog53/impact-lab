import Foundation

// Quality triangle mesh generation for polygon regions (prototype).
//
// Method: Ruppert's Delaunay refinement, J. Ruppert, "A Delaunay Refinement
// Algorithm for Quality 2-Dimensional Mesh Generation", J. Algorithms 18 (1995),
// with the conforming-segment approach (segments are split until they appear
// as Delaunay edges), Bowyer-Watson point insertion (Bowyer 1981, Watson 1981),
// and the "concentric shell" segment splitting and small-input-angle rule from
// J. R. Shewchuk, "Delaunay Refinement Algorithms for Triangular Mesh
// Generation", Computational Geometry 22 (2002). Written from those papers;
// no code is copied from Triangle or any other mesher.
//
// Output conventions match Impact Lab's existing FEM mesh: triangles are
// counter-clockwise, and each boundary edge is listed in the direction it
// appears in its triangle, so material is on the left.

public struct MeshRequest: Sendable {
    public var region: PolygonRegion
    /// Largest edge length wanted anywhere, in metres.
    public var targetEdgeLength: Double
    /// Smallest angle wanted in any triangle, in degrees. Ruppert's guarantee holds up to about 20.7°;
    /// in practice up to about 30° terminates for inputs without small corners.
    public var minimumAngle: Double
    /// Cap on inserted points; nil chooses one from the expected triangle count.
    public var pointBudget: Int?

    public init(region: PolygonRegion, targetEdgeLength: Double, minimumAngle: Double = 25, pointBudget: Int? = nil) {
        self.region = region
        self.targetEdgeLength = targetEdgeLength
        self.minimumAngle = minimumAngle
        self.pointBudget = pointBudget
    }
}

public struct TriangleMesh: Equatable, Sendable {
    public var points: [GeoPoint]
    /// Counter-clockwise node triples.
    public var triangles: [SIMD3<Int>]
    /// Boundary edges, oriented with material on the left (outer boundary counter-clockwise, holes clockwise).
    public var boundaryEdges: [SIMD2<Int>]
    /// Edges lying on interior lines (bonded interfaces, gauge lines).
    public var interfaceEdges: [SIMD2<Int>]
}

public struct MeshResult: Sendable {
    public let mesh: TriangleMesh?
    /// Reasons the region could not be meshed. Non-empty means `mesh` is nil.
    public let issues: [String]
    /// Things the person should know about a mesh that was produced.
    public let notes: [String]
    public let insertedPoints: Int
}

public enum Mesher {
    public static func generate(_ request: MeshRequest) -> MeshResult {
        let issues = request.region.validationIssues()
            + (request.targetEdgeLength > 0 && request.targetEdgeLength.isFinite ? [] : ["target edge length must be positive."])
            + ((1...34).contains(request.minimumAngle) ? [] : ["minimum angle must be between 1° and 34°."])
        guard issues.isEmpty else { return MeshResult(mesh: nil, issues: issues, notes: [], insertedPoints: 0) }
        let refiner = Refiner(request)
        if let problem = refiner.setupProblem {
            return MeshResult(mesh: nil, issues: [problem], notes: [], insertedPoints: 0)
        }
        refiner.run()
        return refiner.result()
    }
}

// MARK: - Triangulation with exact predicates on an integer grid

final class Triangulation {
    var x: [Double] = [], y: [Double] = []
    var vertices: [SIMD3<Int>] = []
    /// neighbors[t][i] is the triangle across the edge opposite vertex i, or -1.
    var neighbors: [SIMD3<Int>] = []
    var alive: [Bool] = []
    var freeSlots: [Int] = []
    var vertexTriangle: [Int] = []
    var mark: [UInt32] = []
    var currentMark: UInt32 = 0

    func addPoint(_ px: Double, _ py: Double) -> Int {
        x.append(px); y.append(py); vertexTriangle.append(-1)
        return x.count - 1
    }

    func removeLastPoint() { x.removeLast(); y.removeLast(); vertexTriangle.removeLast() }

    @discardableResult func makeTriangle(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let t: Int
        if let slot = freeSlots.popLast() {
            t = slot
            vertices[t] = SIMD3(a, b, c); neighbors[t] = SIMD3(-1, -1, -1); alive[t] = true; mark[t] = 0
        } else {
            t = vertices.count
            vertices.append(SIMD3(a, b, c)); neighbors.append(SIMD3(-1, -1, -1)); alive.append(true); mark.append(0)
        }
        vertexTriangle[a] = t; vertexTriangle[b] = t; vertexTriangle[c] = t
        return t
    }

    @inline(__always) func orient(_ a: Int, _ b: Int, _ px: Double, _ py: Double) -> Double {
        ImpactGeometry.orient(x[a], y[a], x[b], y[b], px, py)
    }

    @inline(__always) func inCircle(_ t: Int, _ px: Double, _ py: Double) -> Bool {
        let v = vertices[t]
        return inCircleSign(x[v.x], y[v.x], x[v.y], y[v.y], x[v.z], y[v.z], px, py) > 0
    }

    func nextMark() -> UInt32 {
        currentMark &+= 1
        if currentMark == 0 { for i in mark.indices { mark[i] = 0 }; currentMark = 1 }
        return currentMark
    }

    /// Visibility walk to a triangle containing (px, py), including its boundary.
    func locate(_ px: Double, _ py: Double, from hint: Int) -> Int? {
        var t = hint
        if t < 0 || t >= alive.count || !alive[t] { t = alive.lastIndex(of: true) ?? -1 }
        guard t >= 0 else { return nil }
        var steps = 0
        while steps < 4 * alive.count + 16 {
            let v = vertices[t]
            var moved = false
            for k in 0..<3 {
                let i = (k + steps) % 3
                if orient(v[(i + 1) % 3], v[(i + 2) % 3], px, py) < 0 {
                    let n = neighbors[t][i]
                    if n < 0 { return nil }
                    t = n
                    moved = true
                    break
                }
            }
            if !moved { return t }
            steps += 1
        }
        return nil
    }

    /// Triangles whose circumcircle strictly contains the point, grown from the containing triangle.
    func cavity(_ px: Double, _ py: Double, containing start: Int) -> [Int] {
        let m = nextMark()
        var cavity = [start]
        mark[start] = m
        var i = 0
        while i < cavity.count {
            let c = cavity[i]
            i += 1
            for k in 0..<3 {
                let n = neighbors[c][k]
                if n >= 0 && mark[n] != m && inCircle(n, px, py) {
                    mark[n] = m
                    cavity.append(n)
                }
            }
        }
        return cavity
    }

    /// Bowyer-Watson insertion. Returns the new point index and the new triangles,
    /// or nil when the point coincides with a vertex or the cavity is degenerate.
    func insert(_ px: Double, _ py: Double, hint: Int) -> (point: Int, triangles: [Int], removed: [SIMD3<Int>])? {
        guard let start = locate(px, py, from: hint) else { return nil }
        let cavity = cavity(px, py, containing: start)
        let m = mark[start]
        var rim: [(a: Int, b: Int, outer: Int)] = []
        for c in cavity {
            let v = vertices[c]
            for k in 0..<3 {
                let n = neighbors[c][k]
                if n < 0 || mark[n] != m {
                    let a = v[(k + 1) % 3], b = v[(k + 2) % 3]
                    // Exact arithmetic keeps the cavity star-shaped; a zero here means
                    // the point lies on a rim edge or coincides with a vertex.
                    guard orient(a, b, px, py) > 0 else { return nil }
                    rim.append((a, b, n))
                }
            }
        }
        let p = addPoint(px, py)
        let removed = cavity.map { vertices[$0] }
        for c in cavity { alive[c] = false; freeSlots.append(c) }
        var created: [Int] = []
        created.reserveCapacity(rim.count)
        for edge in rim {
            let t = makeTriangle(edge.a, edge.b, p)
            neighbors[t].z = edge.outer
            if edge.outer >= 0 {
                let o = vertices[edge.outer]
                for j in 0..<3 where o[j] != edge.a && o[j] != edge.b { neighbors[edge.outer][j] = t }
            }
            created.append(t)
        }
        // New triangle (a, b, p): across (b, p) is the one starting at b; across (p, a) is the one ending at a.
        for t in created {
            let v = vertices[t]
            for u in created {
                if vertices[u].x == v.y { neighbors[t].x = u }
                if vertices[u].y == v.x { neighbors[t].y = u }
            }
        }
        return (p, created, removed)
    }

    /// Triangles that contain vertex v.
    func star(_ v: Int) -> [Int] {
        let m = nextMark()
        let first = vertexTriangle[v]
        guard first >= 0 else { return [] }
        var result = [first]
        mark[first] = m
        var i = 0
        while i < result.count {
            let t = result[i]
            i += 1
            for k in 0..<3 {
                let n = neighbors[t][k]
                if n >= 0 && mark[n] != m && alive[n] {
                    let w = vertices[n]
                    if w.x == v || w.y == v || w.z == v { mark[n] = m; result.append(n) }
                }
            }
        }
        return result
    }

    /// The triangle in which a is followed by b counter-clockwise, and its third vertex.
    func triangle(withEdge a: Int, _ b: Int) -> (triangle: Int, apex: Int)? {
        for t in star(a) {
            let v = vertices[t]
            for i in 0..<3 where v[i] == a && v[(i + 1) % 3] == b { return (t, v[(i + 2) % 3]) }
        }
        return nil
    }
}

// MARK: - Refinement

final class Refiner {
    struct Segment { let a: Int; let b: Int; let boundary: Bool }

    let request: MeshRequest
    let region: PolygonRegion
    let mesh = Triangulation()
    var setupProblem: String?

    // Grid mapping: grid = (world - origin) * scale.
    var origin = GeoPoint.zero
    var scale = 1.0
    var hGrid = 1.0
    let radiusEdgeLimit: Double

    // Per vertex.
    var isInput: [Bool] = []
    var onSegment: [Int] = []
    var world: [GeoPoint?] = []

    var segments: [Segment] = []
    var incident: [Int: [Int]] = [:]   // input vertex -> segment ids (lookup only)

    // Subsegments: list for deterministic passes, dictionary for lookup.
    var subsegments: [SIMD2<Int>] = []
    var subsegmentSegment: [Int] = []
    var subsegmentAlive: [Bool] = []
    var subsegmentStuck: [Bool] = []
    var subsegmentIndex: [UInt64: Int] = [:]

    var gridRings: [[GeoPoint]] = []
    var splitQueue: [Int] = []
    var badQueue: [(t: Int, v: SIMD3<Int>)] = []
    var inserted = 0
    var budget = 0
    var budgetReached = false
    var skippedNearSmallAngle = 0
    var stuckSplits = 0
    var failedInsertions = 0

    static let superCorners: [(Double, Double)] = [(-8_388_608, -8_388_608), (16_777_216, -8_388_608), (-8_388_608, 16_777_216)]
    static let domainExtent = 2_097_152.0   // 2^21

    init(_ request: MeshRequest) {
        self.request = request
        region = request.region.normalized()
        radiusEdgeLimit = 1 / (2 * sin(request.minimumAngle * .pi / 180))
        setUp()
    }

    // MARK: Setup

    private func key(_ a: Int, _ b: Int) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }

    private func addVertex(_ gx: Double, _ gy: Double, input: Bool, segment: Int, world point: GeoPoint?) -> Int {
        let v = mesh.addPoint(gx, gy)
        isInput.append(input); onSegment.append(segment); world.append(point)
        return v
    }

    private func setUp() {
        let bounds = region.bounds
        origin = bounds.min
        let extent = max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y)
        scale = Self.domainExtent / extent
        hGrid = request.targetEdgeLength * scale
        func grid(_ p: GeoPoint) -> GeoPoint { ((p - origin) * scale).rounded(.toNearestOrEven) }

        for (cx, cy) in Self.superCorners { _ = addVertex(cx, cy, input: false, segment: -1, world: nil) }
        mesh.makeTriangle(0, 1, 2)

        // Input vertices, deduplicated by exact world coordinates.
        var lookup: [SIMD2<UInt64>: Int] = [:]
        var gridLookup: [SIMD2<Double>: Int] = [:]
        func vertex(_ p: GeoPoint) -> Int? {
            let k = SIMD2(p.x.bitPattern, p.y.bitPattern)
            if let existing = lookup[k] { return existing }
            let g = grid(p)
            if gridLookup[g] != nil {
                setupProblem = "two different points are closer than the mesher's coordinate resolution (\(String(format: "%.2g", 1 / scale)) m)."
                return nil
            }
            guard let inserted = mesh.insert(g.x, g.y, hint: mesh.vertices.count - 1) else {
                setupProblem = "an input point could not be inserted (it lies on an existing edge in a degenerate way)."
                return nil
            }
            isInput.append(true); onSegment.append(-1); world.append(p)
            lookup[k] = inserted.point
            gridLookup[g] = inserted.point
            return inserted.point
        }
        var chains: [(ids: [Int], boundary: Bool, closed: Bool)] = []
        for ring in region.rings {
            var ids: [Int] = []
            for p in ring { guard let v = vertex(p) else { return }; ids.append(v) }
            chains.append((ids, true, true))
            gridRings.append(ring.map(grid))
        }
        for line in region.interiorLines {
            var ids: [Int] = []
            for p in line { guard let v = vertex(p) else { return }; ids.append(v) }
            chains.append((ids, false, false))
        }
        for chain in chains {
            let count = chain.closed ? chain.ids.count : chain.ids.count - 1
            for i in 0..<count {
                let a = chain.ids[i], b = chain.ids[(i + 1) % chain.ids.count]
                let id = segments.count
                segments.append(Segment(a: a, b: b, boundary: chain.boundary))
                incident[a, default: []].append(id)
                incident[b, default: []].append(id)
            }
        }

        // Pre-split every segment into equal pieces no longer than the target edge length.
        for (id, s) in segments.enumerated() {
            let a = GeoPoint(mesh.x[s.a], mesh.y[s.a]), b = GeoPoint(mesh.x[s.b], mesh.y[s.b])
            let pieces = max(1, Int((simdLength(b - a) / hGrid).rounded(.up)))
            var previous = s.a
            for k in 1..<max(pieces, 1) {
                let g = (a + (b - a) * (Double(k) / Double(pieces))).rounded(.toNearestOrEven)
                guard let ins = mesh.insert(g.x, g.y, hint: mesh.vertexTriangle[previous]) else {
                    setupProblem = "a boundary point could not be placed; the target edge length may be below the coordinate resolution."
                    return
                }
                isInput.append(false); onSegment.append(id); world.append(nil)
                addSubsegment(previous, ins.point, segment: id)
                previous = ins.point
            }
            if pieces == 1 || previous != s.b { addSubsegment(previous, s.b, segment: id) }
        }
        let expected = 2.31 * region.area / pow(request.targetEdgeLength, 2) + region.perimeter / request.targetEdgeLength
        budget = request.pointBudget ?? max(5_000, Int(20 * expected))
    }

    private func addSubsegment(_ a: Int, _ b: Int, segment: Int) {
        subsegmentIndex[key(a, b)] = subsegments.count
        subsegments.append(SIMD2(a, b)); subsegmentSegment.append(segment)
        subsegmentAlive.append(true); subsegmentStuck.append(false)
    }

    private func subsegment(_ a: Int, _ b: Int) -> Int? { subsegmentIndex[key(a, b)] }

    // MARK: Queries

    private func point(_ v: Int) -> GeoPoint { GeoPoint(mesh.x[v], mesh.y[v]) }

    /// Missing from the triangulation, or a neighbouring apex sits in its closed diametral circle.
    private func needsSplit(_ s: Int) -> Bool {
        guard subsegmentAlive[s], !subsegmentStuck[s] else { return false }
        let a = subsegments[s].x, b = subsegments[s].y
        let first = mesh.triangle(withEdge: a, b), second = mesh.triangle(withEdge: b, a)
        guard first != nil || second != nil else { return true }
        for apex in [first?.apex, second?.apex].compactMap({ $0 }) where encroaches(apex, s) { return true }
        return false
    }

    private func encroaches(_ v: Int, _ s: Int) -> Bool { encroaches(point(v), s) }

    private func encroaches(_ p: GeoPoint, _ s: Int) -> Bool {
        // Closed diametral disk: angle a-p-b of 90° or more. Exact on the grid.
        dot(point(subsegments[s].x) - p, point(subsegments[s].y) - p) <= 0
    }

    private func insideByCentroid(_ t: Int) -> Bool {
        let v = mesh.vertices[t]
        guard v.x > 2, v.y > 2, v.z > 2 else { return false }
        let c = (point(v.x) + point(v.y) + point(v.z)) / 3
        return gridRings.reduce(false) { $0 != PolygonRegion.ringContains($1, c) }
    }

    private func segmentsThrough(_ v: Int) -> [Int] {
        isInput[v] ? (incident[v] ?? []) : (onSegment[v] >= 0 ? [onSegment[v]] : [])
    }

    /// Shewchuk's rule: a skinny triangle whose shortest edge joins two segments meeting
    /// at a small input angle cannot be improved without endless splitting, so leave it.
    private func causedBySmallInputAngle(_ p: Int, _ q: Int) -> Bool {
        for s1 in segmentsThrough(p) {
            for s2 in segmentsThrough(q) where s1 != s2 {
                let a = segments[s1], b = segments[s2]
                let shared = [a.a, a.b].first { $0 == b.a || $0 == b.b }
                guard let apex = shared else { continue }
                let u = point(a.a == apex ? a.b : a.a) - point(apex)
                let w = point(b.a == apex ? b.b : b.a) - point(apex)
                let angle = acos(max(-1, min(1, dot(u, w) / (simdLength(u) * simdLength(w)))))
                if angle < .pi / 3 { return true }
            }
        }
        return false
    }

    // MARK: Splitting and insertion

    private func queueTriangles(_ ts: [Int]) {
        for t in ts { badQueue.append((t, mesh.vertices[t])) }
    }

    /// After any insertion: queue rim subsegments the new point encroaches, and any
    /// subsegment that was an edge inside the cavity and is no longer in the triangulation.
    private func queueAfterInsertion(_ ins: (point: Int, triangles: [Int], removed: [SIMD3<Int>])) {
        queueEncroachedRim(of: ins.triangles, by: ins.point)
        for v in ins.removed {
            for i in 0..<3 {
                guard let s = subsegment(v[i], v[(i + 1) % 3]) else { continue }
                let a = subsegments[s].x, b = subsegments[s].y
                if mesh.triangle(withEdge: a, b) == nil && mesh.triangle(withEdge: b, a) == nil { splitQueue.append(s) }
            }
        }
    }

    private func queueEncroachedRim(of ts: [Int], by p: Int) {
        for t in ts {
            let v = mesh.vertices[t]
            for i in 0..<3 where v[i] == p {
                if let s = subsegment(v[(i + 1) % 3], v[(i + 2) % 3]), encroaches(p, s) { splitQueue.append(s) }
            }
        }
    }

    /// Splits a subsegment that is missing, encroached by a neighbouring apex, or (when
    /// `forced`) encroached by a rejected circumcenter.
    private func split(_ s: Int, forced: Bool = false) {
        guard subsegmentAlive[s], !subsegmentStuck[s], forced || needsSplit(s) else { return }
        let a = subsegments[s].x, b = subsegments[s].y
        let segment = segments[subsegmentSegment[s]]
        let pa = point(a), pb = point(b)
        let length = simdLength(pb - pa)
        let aIsEnd = a == segment.a || a == segment.b, bIsEnd = b == segment.a || b == segment.b
        var p: GeoPoint
        if aIsEnd != bIsEnd {
            // Concentric shells: split at a power-of-two distance from the input vertex, so
            // subsegments around a sharp corner end up with matching lengths.
            let apex = aIsEnd ? pa : pb, other = aIsEnd ? pb : pa
            let distance = pow(2, (log2(length / 2)).rounded())
            p = apex + (other - apex) * (distance / length)
        } else {
            p = 0.5 * (pa + pb)
        }
        p = p.rounded(.toNearestOrEven)
        guard length >= 4, p != pa, p != pb,
              let ins = mesh.insert(p.x, p.y, hint: mesh.vertexTriangle[a]) else {
            subsegmentStuck[s] = true
            stuckSplits += 1
            return
        }
        isInput.append(false); onSegment.append(subsegmentSegment[s]); world.append(nil)
        inserted += 1
        subsegmentAlive[s] = false
        subsegmentIndex[key(a, b)] = nil
        let first = subsegments.count
        addSubsegment(a, ins.point, segment: subsegmentSegment[s])
        addSubsegment(ins.point, b, segment: subsegmentSegment[s])
        splitQueue.append(first)
        splitQueue.append(first + 1)
        queueAfterInsertion(ins)
        queueTriangles(ins.triangles)
    }

    private func drainSplits() {
        while let s = splitQueue.popLast() {
            if inserted >= budget { budgetReached = true; splitQueue.removeAll(); return }
            split(s)
        }
    }

    private func refine(_ t: Int) {
        let v = mesh.vertices[t]
        let p = [point(v.x), point(v.y), point(v.z)]
        let edges = [simdLength(p[2] - p[1]), simdLength(p[0] - p[2]), simdLength(p[1] - p[0])]
        let shortest = edges.min()!, longest = edges.max()!
        let area2 = abs(cross(p[1] - p[0], p[2] - p[0]))
        guard area2 > 0 else { return }
        let circumradius = edges[0] * edges[1] * edges[2] / (2 * area2)
        let skinny = circumradius / shortest > radiusEdgeLimit
        let big = longest > hGrid
        guard skinny || big else { return }
        if skinny && !big {
            let i = edges.firstIndex(of: shortest)!
            if causedBySmallInputAngle(v[(i + 1) % 3], v[(i + 2) % 3]) { skippedNearSmallAngle += 1; return }
        }
        // Circumcenter, relative to the first vertex.
        let b = p[1] - p[0], c = p[2] - p[0]
        let d = 2 * cross(b, c)
        let bb = dot(b, b), cc = dot(c, c)
        let center = (p[0] + GeoPoint(c.y * bb - b.y * cc, b.x * cc - c.x * bb) / d).rounded(.toNearestOrEven)
        guard center.x > -4_194_304, center.y > -4_194_304, center.x + center.y < 7_340_032,
              let start = mesh.locate(center.x, center.y, from: t) else { return }
        // Ruppert: a circumcenter that encroaches a subsegment is not inserted; the subsegment is split instead.
        var encroached: [Int] = []
        var blocked = false
        for c in mesh.cavity(center.x, center.y, containing: start) {
            let w = mesh.vertices[c]
            for i in 0..<3 {
                guard let s = subsegment(w[i], w[(i + 1) % 3]), encroaches(center, s) else { continue }
                if subsegmentStuck[s] { blocked = true } else if !encroached.contains(s) { encroached.append(s) }
            }
        }
        // A piece at the resolution limit cannot be split, so never insert a point that would remove it.
        if blocked && encroached.isEmpty { failedInsertions += 1; return }
        if !encroached.isEmpty {
            for s in encroached where inserted < budget { split(s, forced: true) }
            drainSplits()
            if mesh.alive[t] && mesh.vertices[t] == v { badQueue.append((t, v)) }
            return
        }
        guard let ins = mesh.insert(center.x, center.y, hint: start) else { failedInsertions += 1; return }
        isInput.append(false); onSegment.append(-1); world.append(nil)
        inserted += 1
        queueAfterInsertion(ins)
        drainSplits()
        queueTriangles(ins.triangles)
    }

    func run() {
        // 1. Recover every segment and clear encroachment (Ruppert's first phase).
        splitQueue = Array(subsegments.indices.reversed())
        drainSplits()
        // 2. Refine skinny and oversized triangles inside the material.
        queueTriangles(mesh.alive.indices.filter { mesh.alive[$0] })
        var head = 0
        while head < badQueue.count {
            if inserted >= budget { budgetReached = true; break }
            let (t, v) = badQueue[head]
            head += 1
            if head > 65_536 { badQueue.removeFirst(head); head = 0 }
            guard mesh.alive[t], mesh.vertices[t] == v, insideByCentroid(t) else { continue }
            refine(t)
        }
    }

    // MARK: Output

    func result() -> MeshResult {
        var notes: [String] = []
        // Classify triangles topologically: start outside, flip across every boundary subsegment.
        let count = mesh.vertices.count
        var state = Array(repeating: -1, count: count)
        let start = mesh.vertexTriangle[0]
        state[start] = 0
        var queue = [start]
        var conflicts = 0
        var i = 0
        while i < queue.count {
            let t = queue[i]
            i += 1
            let v = mesh.vertices[t]
            for k in 0..<3 {
                let n = mesh.neighbors[t][k]
                guard n >= 0 else { continue }
                let s = subsegment(v[(k + 1) % 3], v[(k + 2) % 3])
                let flips = s.map { segments[subsegmentSegment[$0]].boundary } ?? false
                let next = state[t] ^ (flips ? 1 : 0)
                if state[n] < 0 { state[n] = next; queue.append(n) }
                else if state[n] != next { conflicts += 1 }
            }
        }
        let missing = subsegments.indices.filter { subsegmentAlive[$0] && mesh.triangle(withEdge: subsegments[$0].x, subsegments[$0].y) == nil
            && mesh.triangle(withEdge: subsegments[$0].y, subsegments[$0].x) == nil }.count
        guard conflicts == 0, missing == 0 else {
            return MeshResult(mesh: nil, issues: ["internal error: \(missing) boundary pieces missing, \(conflicts) inside/outside conflicts (\(stuckSplits) unsplittable pieces, \(failedInsertions) skipped points, \(inserted) inserted)."],
                              notes: [], insertedPoints: inserted)
        }
        var map = Array(repeating: -1, count: mesh.x.count)
        var points: [GeoPoint] = []
        var triangles: [SIMD3<Int>] = []
        func output(_ v: Int) -> Int {
            if map[v] >= 0 { return map[v] }
            map[v] = points.count
            points.append(worldPoint(v))
            return map[v]
        }
        var insideSlots: [Int] = []
        for t in 0..<count where mesh.alive[t] && state[t] == 1 { insideSlots.append(t) }
        // Number nodes in vertex-creation order so the output does not depend on slot reuse.
        let used = Set(insideSlots.flatMap { [mesh.vertices[$0].x, mesh.vertices[$0].y, mesh.vertices[$0].z] })
        for v in 0..<mesh.x.count where used.contains(v) { _ = output(v) }
        var boundary: [SIMD2<Int>] = []
        var disagreements = 0
        for t in insideSlots {
            let v = mesh.vertices[t]
            if !insideByCentroid(t) { disagreements += 1 }
            triangles.append(SIMD3(map[v.x], map[v.y], map[v.z]))
            for k in 0..<3 {
                let a = v[(k + 1) % 3], b = v[(k + 2) % 3]
                if let s = subsegment(a, b), segments[subsegmentSegment[s]].boundary { boundary.append(SIMD2(map[a], map[b])) }
            }
        }
        let interface = subsegments.indices.filter { subsegmentAlive[$0] && !segments[subsegmentSegment[$0]].boundary }
            .map { SIMD2(map[subsegments[$0].x], map[subsegments[$0].y]) }
        let inverted = triangles.filter { cross(points[$0.y] - points[$0.x], points[$0.z] - points[$0.x]) <= 0 }.count
        if inverted > 0 { notes.append("\(inverted) triangles have non-positive area after conversion to metres.") }
        if disagreements > 0 { notes.append("\(disagreements) triangles were classified differently by the centroid test (diagnostic).") }
        if budgetReached { notes.append("Stopped at the point budget (\(budget)); some triangles may be larger or skinnier than requested.") }
        if skippedNearSmallAngle > 0 {
            notes.append("Left \(skippedNearSmallAngle) skinny triangles near corners sharper than 60°, where further splitting would not terminate.")
        }
        if stuckSplits > 0 { notes.append("\(stuckSplits) boundary pieces reached the coordinate resolution and were not split further.") }
        if failedInsertions > 0 { notes.append("\(failedInsertions) refinement points were skipped as degenerate.") }
        return MeshResult(mesh: TriangleMesh(points: points, triangles: triangles, boundaryEdges: boundary, interfaceEdges: interface),
                          issues: [], notes: notes, insertedPoints: inserted)
    }

    /// World coordinates. Input points keep their exact values; points on a segment are
    /// projected back onto the original straight segment, removing grid rounding across it.
    private func worldPoint(_ v: Int) -> GeoPoint {
        if let exact = world[v] { return exact }
        let w = origin + point(v) / scale
        guard onSegment[v] >= 0, let a = world[segments[onSegment[v]].a], let b = world[segments[onSegment[v]].b] else { return w }
        let ab = b - a
        let f = min(1, max(0, dot(w - a, ab) / dot(ab, ab)))
        return a + f * ab
    }
}
