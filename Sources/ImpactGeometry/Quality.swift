import Foundation

/// Solver-independent mesh quality measures. Definitions follow common usage, for example
/// J. R. Shewchuk, "What Is a Good Linear Finite Element?" (2002), and R. E. Bank's
/// shape measure q = 4√3·A / (l1² + l2² + l3²), which is 1 for an equilateral triangle.
public struct MeshQuality: Equatable, Sendable {
    public var nodes = 0
    public var triangles = 0
    public var minimumAngle = 0.0          // degrees
    public var maximumAngle = 0.0          // degrees
    public var trianglesBelow20 = 0
    public var trianglesBelow30 = 0
    public var worstRadiusEdgeRatio = 0.0  // circumradius / shortest edge; √3/3 ≈ 0.577 is ideal
    public var minimumShape = 0.0          // Bank's q, 1 is equilateral
    public var meanShape = 0.0
    public var shortestEdge = 0.0          // m
    public var longestEdge = 0.0           // m
    /// Smallest triangle altitude, in m. With a lumped-mass explicit solver the stable time step
    /// scales with this length divided by the wave speed, so it predicts run cost.
    public var smallestAltitude = 0.0
    public var area = 0.0                  // m²
    public var boundaryLength = 0.0        // m
    public var invertedTriangles = 0
    /// Edges used by more than two triangles, or boundary edges that do not match a one-sided edge.
    public var topologyErrors = 0
    /// Vertices − edges + triangles. Equals 1 − (number of holes) for one connected piece.
    public var eulerCharacteristic = 0

    public init() {}

    public init(_ mesh: TriangleMesh) {
        nodes = mesh.points.count
        triangles = mesh.triangles.count
        minimumAngle = 180
        minimumShape = 1
        shortestEdge = .infinity
        smallestAltitude = .infinity
        var shapeSum = 0.0
        var edgeUse: [SIMD2<Int>: Int] = [:]
        for t in mesh.triangles {
            let p = [mesh.points[t.x], mesh.points[t.y], mesh.points[t.z]]
            let l = [simdLength(p[2] - p[1]), simdLength(p[0] - p[2]), simdLength(p[1] - p[0])]
            let twiceArea = cross(p[1] - p[0], p[2] - p[0])
            if twiceArea <= 0 { invertedTriangles += 1; continue }
            area += twiceArea / 2
            for i in 0..<3 {
                let cosine = (l[(i + 1) % 3] * l[(i + 1) % 3] + l[(i + 2) % 3] * l[(i + 2) % 3] - l[i] * l[i])
                    / (2 * l[(i + 1) % 3] * l[(i + 2) % 3])
                let angle = acos(max(-1, min(1, cosine))) * 180 / .pi
                minimumAngle = min(minimumAngle, angle)
                maximumAngle = max(maximumAngle, angle)
                smallestAltitude = min(smallestAltitude, twiceArea / l[i])
            }
            let smallest = (0..<3).map { i -> Double in
                let cosine = (l[(i + 1) % 3] * l[(i + 1) % 3] + l[(i + 2) % 3] * l[(i + 2) % 3] - l[i] * l[i])
                    / (2 * l[(i + 1) % 3] * l[(i + 2) % 3])
                return acos(max(-1, min(1, cosine))) * 180 / .pi
            }.min()!
            if smallest < 20 { trianglesBelow20 += 1 }
            if smallest < 30 { trianglesBelow30 += 1 }
            let shortest = l.min()!, longest = l.max()!
            shortestEdge = min(shortestEdge, shortest)
            longestEdge = max(longestEdge, longest)
            worstRadiusEdgeRatio = max(worstRadiusEdgeRatio, l[0] * l[1] * l[2] / (2 * twiceArea) / shortest)
            let shape = 2 * 3.0.squareRoot() * twiceArea / (l[0] * l[0] + l[1] * l[1] + l[2] * l[2])
            minimumShape = min(minimumShape, shape)
            shapeSum += shape
            for (a, b) in [(t.x, t.y), (t.y, t.z), (t.z, t.x)] { edgeUse[SIMD2(min(a, b), max(a, b)), default: 0] += 1 }
        }
        meanShape = triangles > 0 ? shapeSum / Double(triangles) : 0
        // Every edge is shared by one or two triangles; the one-sided edges must be exactly the boundary edges.
        var oneSided = Set<SIMD2<Int>>()
        for (edge, uses) in edgeUse {
            if uses > 2 { topologyErrors += 1 }
            if uses == 1 { oneSided.insert(edge) }
        }
        let interface = Set(mesh.interfaceEdges.map { SIMD2(min($0.x, $0.y), max($0.x, $0.y)) })
        let listed = Set(mesh.boundaryEdges.map { SIMD2(min($0.x, $0.y), max($0.x, $0.y)) })
        topologyErrors += oneSided.symmetricDifference(listed).count + interface.filter { edgeUse[$0] != 2 }.count
        boundaryLength = mesh.boundaryEdges.reduce(0) { $0 + simdLength(mesh.points[$1.y] - mesh.points[$1.x]) }
        eulerCharacteristic = nodes - edgeUse.count + triangles
    }
}

/// Advisory guidance about resolution. Nothing here blocks a run; each note says what the
/// person may want to check and why, so the choice stays theirs.
public struct ResolutionAdvice: Equatable, Sendable {
    public enum Level: String, Sendable { case information, caution }
    public struct Note: Equatable, Sendable {
        public let level: Level
        public let text: String
        public let location: GeoPoint?
    }

    public let notes: [Note]
    /// Narrowest wall or ligament found between non-neighbouring boundary edges, in m.
    public let thinnestSection: Double?
    public let estimatedTriangles: Int

    public init(region: PolygonRegion, targetEdgeLength h: Double) {
        let region = region.normalized()
        var notes: [Note] = []
        estimatedTriangles = Int((2.31 * region.area / (h * h)).rounded())
        notes.append(Note(level: .information,
                          text: String(format: "About %d triangles at %.2f mm edge length (equilateral estimate).",
                                       estimatedTriangles, h * 1000), location: nil))
        // Thinnest section: closest approach of boundary edges that do not share a vertex.
        var edges: [(GeoPoint, GeoPoint, ring: Int, index: Int)] = []
        for (r, ring) in region.rings.enumerated() {
            for i in ring.indices { edges.append((ring[i], ring[(i + 1) % ring.count], r, i)) }
        }
        var thinnest: (distance: Double, at: GeoPoint)?
        for i in edges.indices {
            for j in (i + 1)..<edges.count {
                let e = edges[i], f = edges[j]
                if e.ring == f.ring {
                    let n = region.rings[e.ring].count
                    if f.index == (e.index + 1) % n || e.index == (f.index + 1) % n { continue }
                }
                // Only faces that look at each other (directions within 30° of opposite) bound a wall.
                let u = e.1 - e.0, w = f.1 - f.0
                guard dot(u, w) < -0.866 * simdLength(u) * simdLength(w) else { continue }
                let d = segmentDistance(e.0, e.1, f.0, f.1)
                let mid = 0.25 * (e.0 + e.1 + f.0 + f.1)
                // Only count gaps through material, not across a void.
                if region.contains(mid), d < (thinnest?.distance ?? .infinity) { thinnest = (d, mid) }
            }
        }
        thinnestSection = thinnest?.distance
        if let thinnest {
            let across = thinnest.distance / h
            if across < 3 {
                notes.append(Note(level: .caution, text: String(
                    format: "The narrowest part of the material (%.2f mm) is only about %.1f element%@ across. Linear triangles are too stiff in bending when few span a section; consider an edge length of %.2f mm or less there. Rule of thumb, not a guarantee.",
                    thinnest.distance * 1000, across, across < 1.5 ? "" : "s", thinnest.distance * 1000 / 4), location: thinnest.at))
            }
        }
        // Corners: re-entrant corners give singular elastic stress; very sharp corners limit mesh quality.
        for ring in region.rings {
            let n = ring.count
            for i in 0..<n {
                let prev = ring[(i + n - 1) % n], p = ring[i], next = ring[(i + 1) % n]
                let turn = cross(p - prev, next - p)
                let between = acos(max(-1, min(1, dot(prev - p, next - p) / (simdLength(prev - p) * simdLength(next - p))))) * 180 / .pi
                // Material is on the left, so a right turn (negative cross) is a re-entrant corner.
                let materialAngle = turn < 0 ? 360 - between : between
                if materialAngle > 200 {
                    notes.append(Note(level: .information, text: String(
                        format: "Re-entrant corner (%.0f° of material) at (%.1f, %.1f) mm: linear-elastic stress is singular at such corners (Williams 1952), so the peak stress there will keep rising as the mesh is refined. Read stresses a short distance away, or round the corner.",
                        materialAngle, p.x * 1000, p.y * 1000), location: p))
                } else if materialAngle < 30 {
                    notes.append(Note(level: .caution, text: String(
                        format: "Sharp corner (%.0f°) at (%.1f, %.1f) mm: triangles there cannot all reach the requested quality.",
                        materialAngle, p.x * 1000, p.y * 1000), location: p))
                }
            }
        }
        self.notes = notes
    }
}
