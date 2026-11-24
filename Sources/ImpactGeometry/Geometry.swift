import Foundation

// Solver-independent geometry for Impact Lab (prototype, not used by the app or solver).
//
// A body's shape is a polygon region: one outer ring plus any number of holes.
// Notches, slots, windows and enclosures are ordinary vertices and holes, not
// special shape types. Interior polylines mark lines the mesh must follow
// (bonded material interfaces, gauge lines) without cutting the body.
// Coordinates are metres in the body's own frame.

public typealias GeoPoint = SIMD2<Double>

public struct PolygonRegion: Codable, Equatable, Sendable {
    /// Outer boundary, any orientation, without repeating the first point.
    public var outer: [GeoPoint]
    /// Holes, each strictly inside `outer` and disjoint from the others.
    public var holes: [[GeoPoint]]
    /// Lines inside the material that the mesh must follow. Endpoints must be
    /// strictly inside the material or coincide with a ring vertex.
    public var interiorLines: [[GeoPoint]]

    public init(outer: [GeoPoint], holes: [[GeoPoint]] = [], interiorLines: [[GeoPoint]] = []) {
        self.outer = outer
        self.holes = holes
        self.interiorLines = interiorLines
    }

    public var rings: [[GeoPoint]] { [outer] + holes }

    /// Material area (outer area minus hole areas), in m².
    public var area: Double { abs(Self.signedArea(outer)) - holes.reduce(0) { $0 + abs(Self.signedArea($1)) } }

    public var perimeter: Double {
        rings.reduce(0) { total, ring in
            total + ring.indices.reduce(0) { $0 + simdLength(ring[($1 + 1) % ring.count] - ring[$1]) }
        }
    }

    public var bounds: (min: GeoPoint, max: GeoPoint) {
        let all = rings.flatMap { $0 } + interiorLines.flatMap { $0 }
        var lo = all.first ?? .zero, hi = lo
        for p in all { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
        return (lo, hi)
    }

    /// Outer ring counter-clockwise, holes clockwise, so material is always on the left of every boundary edge.
    public func normalized() -> PolygonRegion {
        var copy = self
        if Self.signedArea(copy.outer) < 0 { copy.outer.reverse() }
        copy.holes = copy.holes.map { Self.signedArea($0) > 0 ? Array($0.reversed()) : $0 }
        return copy
    }

    /// True when `p` is inside the material (even-odd rule over all rings).
    public func contains(_ p: GeoPoint) -> Bool {
        rings.reduce(false) { $0 != Self.ringContains($1, p) }
    }

    /// Every reason this region cannot be meshed, in plain words. Empty means valid.
    public func validationIssues() -> [String] {
        var issues: [String] = []
        func label(_ r: Int) -> String { r == 0 ? "outer boundary" : "hole \(r)" }
        let rings = rings
        for (r, ring) in rings.enumerated() {
            if ring.count < 3 { issues.append("\(label(r)) needs at least 3 points (has \(ring.count))."); continue }
            if ring.contains(where: { !$0.x.isFinite || !$0.y.isFinite }) { issues.append("\(label(r)) has a non-finite coordinate."); continue }
            for i in ring.indices where ring[i] == ring[(i + 1) % ring.count] {
                issues.append("\(label(r)) repeats point \(i + 1) consecutively.")
            }
            if abs(Self.signedArea(ring)) <= 1e-18 { issues.append("\(label(r)) encloses no area.") }
        }
        guard issues.isEmpty else { return issues }
        let scale = max(simdLength(bounds.max - bounds.min), 1e-12)
        // Every pair of ring edges: only neighbours may touch, and only at their shared vertex.
        var edges: [(ring: Int, index: Int, a: GeoPoint, b: GeoPoint)] = []
        for (r, ring) in rings.enumerated() {
            for i in ring.indices { edges.append((r, i, ring[i], ring[(i + 1) % ring.count])) }
        }
        var reported = Set<String>()
        for i in edges.indices {
            for j in (i + 1)..<edges.count {
                let e = edges[i], f = edges[j]
                let n = rings[e.ring].count
                let adjacent = e.ring == f.ring && (f.index == (e.index + 1) % n || e.index == (f.index + 1) % n)
                if adjacent {
                    // Neighbours share one vertex; they must not fold back over each other.
                    let shared = f.index == (e.index + 1) % n ? e.b : e.a
                    let u = (f.index == (e.index + 1) % n ? e.a : e.b) - shared
                    let v = (f.index == (e.index + 1) % n ? f.b : f.a) - shared
                    if abs(cross(u, v)) <= 1e-12 * simdLength(u) * simdLength(v) && dot(u, v) > 0 {
                        let key = "spike\(e.ring)-\(min(e.index, f.index))"
                        if reported.insert(key).inserted { issues.append("\(label(e.ring)) folds back on itself near point \(f.index + 1).") }
                    }
                    continue
                }
                if segmentsTouch(e.a, e.b, f.a, f.b, tolerance: 1e-12 * scale) {
                    let key = e.ring == f.ring ? "self\(e.ring)" : "pair\(e.ring)-\(f.ring)"
                    guard reported.insert(key).inserted else { continue }
                    issues.append(e.ring == f.ring ? "\(label(e.ring)) crosses or touches itself."
                                  : "\(label(e.ring)) and \(label(f.ring)) cross or touch.")
                }
            }
        }
        for (h, hole) in holes.enumerated() {
            if !Self.ringContains(outer, hole[0]) { issues.append("hole \(h + 1) is not inside the outer boundary.") }
            for (k, other) in holes.enumerated() where k != h && Self.ringContains(other, hole[0]) {
                issues.append("hole \(h + 1) is inside hole \(k + 1); nested holes are not supported.")
            }
        }
        for (l, line) in interiorLines.enumerated() {
            if line.count < 2 { issues.append("interior line \(l + 1) needs at least 2 points."); continue }
            for p in line where !contains(p) && !rings.contains(where: { $0.contains(p) }) {
                issues.append("interior line \(l + 1) has a point outside the material that is not a boundary vertex.")
                break
            }
            for i in 0..<(line.count - 1) {
                let mid = 0.5 * (line[i] + line[i + 1])
                if !contains(mid) { issues.append("interior line \(l + 1) leaves the material."); break }
                let crosses = edges.contains { e in
                    let sharesEnd = [e.a, e.b].contains(line[i]) || [e.a, e.b].contains(line[i + 1])
                    return !sharesEnd && segmentsTouch(e.a, e.b, line[i], line[i + 1], tolerance: 1e-12 * scale)
                }
                if crosses { issues.append("interior line \(l + 1) crosses or touches a boundary away from a vertex."); break }
            }
        }
        return issues
    }

    public static func signedArea(_ ring: [GeoPoint]) -> Double {
        guard ring.count >= 3 else { return 0 }
        return 0.5 * ring.indices.reduce(0) { $0 + cross(ring[$1], ring[($1 + 1) % ring.count]) }
    }

    static func ringContains(_ ring: [GeoPoint], _ p: GeoPoint) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}

/// Ready-made regions. These are conveniences for building polygons, not special solver shapes.
public enum Shapes {
    public static func rectangle(width: Double, height: Double, center: GeoPoint = .zero) -> [GeoPoint] {
        let w = width / 2, h = height / 2
        return [GeoPoint(-w, -h), GeoPoint(w, -h), GeoPoint(w, h), GeoPoint(-w, h)].map { $0 + center }
    }

    /// A polygon approximating an ellipse with `sides` straight edges.
    public static func ellipse(width: Double, height: Double, sides: Int, center: GeoPoint = .zero) -> [GeoPoint] {
        (0..<sides).map { i in
            let t = 2 * Double.pi * Double(i) / Double(sides)
            return center + GeoPoint(0.5 * width * cos(t), 0.5 * height * sin(t))
        }
    }

    /// A block with a V-shaped cut rising from its bottom edge, the shape of the legacy notch
    /// expressed as ordinary geometry. Fractions follow `AssemblyPart.Notch`.
    public static func notchedBlock(width: Double, height: Double, centerFraction: Double = 0,
                                    widthFraction: Double = 0.2, depthFraction: Double = 0.2) -> PolygonRegion {
        let cx = centerFraction * width, half = widthFraction * width / 2
        let bottom = -height / 2
        return PolygonRegion(outer: [
            GeoPoint(-width / 2, bottom), GeoPoint(cx - half, bottom), GeoPoint(cx, bottom + depthFraction * height),
            GeoPoint(cx + half, bottom), GeoPoint(width / 2, bottom), GeoPoint(width / 2, height / 2),
            GeoPoint(-width / 2, height / 2),
        ])
    }

    /// A hollow rectangle with uniform wall thickness, the legacy enclosure as a region with one hole.
    public static func enclosure(width: Double, height: Double, wall: Double) -> PolygonRegion {
        PolygonRegion(outer: rectangle(width: width, height: height),
                      holes: [rectangle(width: width - 2 * wall, height: height - 2 * wall)])
    }

    /// A block split by vertical bonded interfaces at the given fractions of its width (legacy bonded layers).
    public static func layeredBlock(width: Double, height: Double, interfaces: [Double]) -> PolygonRegion {
        let xs = interfaces.sorted().map { ($0 - 0.5) * width }
        let bottom = xs.map { GeoPoint($0, -height / 2) }
        let top = xs.reversed().map { GeoPoint($0, height / 2) }
        let outer = [GeoPoint(-width / 2, -height / 2)] + bottom + [GeoPoint(width / 2, -height / 2), GeoPoint(width / 2, height / 2)]
            + top + [GeoPoint(-width / 2, height / 2)]
        return PolygonRegion(outer: outer, interiorLines: xs.map { [GeoPoint($0, -height / 2), GeoPoint($0, height / 2)] })
    }
}

// MARK: - Small vector helpers (kept local so this module needs nothing but Foundation)

@inline(__always) func cross(_ a: GeoPoint, _ b: GeoPoint) -> Double { a.x * b.y - a.y * b.x }
@inline(__always) func dot(_ a: GeoPoint, _ b: GeoPoint) -> Double { a.x * b.x + a.y * b.y }
@inline(__always) func simdLength(_ a: GeoPoint) -> Double { (a.x * a.x + a.y * a.y).squareRoot() }

func segmentsTouch(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint, _ d: GeoPoint, tolerance: Double) -> Bool {
    segmentDistance(a, b, c, d) <= tolerance
}

/// Shortest distance between segments ab and cd (zero when they intersect).
func segmentDistance(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint, _ d: GeoPoint) -> Double {
    let d1 = cross(b - a, c - a), d2 = cross(b - a, d - a)
    let d3 = cross(d - c, a - c), d4 = cross(d - c, b - c)
    if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return 0 }
    func pointSegment(_ p: GeoPoint, _ s: GeoPoint, _ t: GeoPoint) -> Double {
        let st = t - s
        let f = min(1, max(0, dot(p - s, st) / max(dot(st, st), .leastNormalMagnitude)))
        return simdLength(p - s - f * st)
    }
    return min(pointSegment(a, c, d), pointSegment(b, c, d), pointSegment(c, a, b), pointSegment(d, a, b))
}
