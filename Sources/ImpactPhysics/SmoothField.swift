import simd

// Display-only field recovery. Nothing here feeds back into any solver.
//
// The renderer's input is a generic "scalar field on a triangulated set of points": point
// positions, triangles, and one value per triangle. FEM elements, MPM background cells or any
// future method can be adapted to this shape. The recovered result is an INTERPOLATED DISPLAY of
// the solver output, not new physics.
//
// Method (adopted, not invented): Zienkiewicz-Zhu superconvergent patch recovery (SPR; Zienkiewicz
// and Zhu, Int. J. Numer. Meth. Eng. 33, 1331-1364, 1992). For each node, the per-element values of
// the elements around it are fitted with a least-squares plane (sampled at the element centroids)
// and the plane is evaluated at the node. This removes the diamond/star patterns that plain
// area-weighted nodal averaging (the "cell data to point data" of ParaView, Gmsh, Abaqus averaged
// contours) leaves around mesh vertices on coarse meshes. Two safeguards keep it honest: a node whose
// patch cannot fix a plane (fewer than 3 elements, or nearly collinear centroids) falls back to
// area-weighted averaging, and every recovered corner is clamped to the range of the element values
// in its patch, so the display never exceeds the solver's own range (no invented peaks, no negative
// plastic strain). Area-weighted averaging is kept as `areaWeightedCorners()` for comparison.

public struct ScalarFieldOnTriangles: Sendable {
    public var points: [Point]
    public var triangles: [SIMD3<Int>]
    /// One value per triangle.
    public var values: [Double]
    /// Optional discontinuity labels. Triangles that share a point average together only when they
    /// share a group, so a real jump (a material interface) is not smeared across.
    public var groups: [Int]?

    public init(points: [Point], triangles: [SIMD3<Int>], values: [Double], groups: [Int]? = nil) {
        precondition(values.count == triangles.count)
        precondition(groups == nil || groups!.count == triangles.count)
        self.points = points
        self.triangles = triangles
        self.values = values
        self.groups = groups
    }

    /// Corner values for every triangle by superconvergent patch recovery (see the file header).
    /// A uniform field and any linear field are reproduced exactly in the interior, and a corner never
    /// leaves the range of its patch's element values.
    public func recoveredCorners() -> [SIMD3<Double>] {
        struct Key: Hashable { var node: Int; var group: Int }
        var patches: [Key: [Int]] = [:]
        for (i, t) in triangles.enumerated() {
            for n in [t.x, t.y, t.z] { patches[Key(node: n, group: groups?[i] ?? 0), default: []].append(i) }
        }
        let fallback = areaWeightedCorners()
        var recovered: [Key: Double] = [:]
        for (key, members) in patches {
            guard members.count >= 3 else { continue }
            let origin = points[key.node]
            var scale = 0.0
            var centroids: [(x: Double, y: Double, v: Double)] = []
            for i in members {
                let t = triangles[i]
                let c = (points[t.x] + points[t.y] + points[t.z]) / 3 - origin
                centroids.append((c.x, c.y, values[i]))
                scale = max(scale, hypot(c.x, c.y))
            }
            guard scale > 0 else { continue }
            // Normal equations for v = a + b x + c y with x, y scaled to about unit size.
            var m = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3), r = [Double](repeating: 0, count: 3)
            for c in centroids {
                let p = [1, c.x / scale, c.y / scale]
                for a in 0..<3 { r[a] += p[a] * c.v; for b in 0..<3 { m[a][b] += p[a] * p[b] } }
            }
            let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
            // Conditioning: det of the normalised moment matrix is about n^3 times a spread factor; tiny means collinear.
            let n = Double(centroids.count)
            guard det > 1e-3 * n * n * n else { continue }
            // Value at the node (x = y = 0) is the constant term: Cramer's rule on the first unknown.
            let numer = r[0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (r[1] * m[2][2] - m[1][2] * r[2])
                + m[0][2] * (r[1] * m[2][1] - m[1][1] * r[2])
            let value = numer / det
            guard value.isFinite else { continue }
            let low = centroids.map(\.v).min()!, high = centroids.map(\.v).max()!
            recovered[key] = min(high, max(low, value))
        }
        return triangles.enumerated().map { i, t in
            func corner(_ n: Int, _ slot: Int) -> Double {
                recovered[Key(node: n, group: groups?[i] ?? 0)] ?? fallback[i][slot]
            }
            return SIMD3(corner(t.x, 0), corner(t.y, 1), corner(t.z, 2))
        }
    }

    /// Corner values for every triangle after area-weighted averaging. A corner value is a convex
    /// combination of neighbouring triangle values, so it never exceeds the solver's own range and a
    /// uniform field is reproduced exactly.
    public func areaWeightedCorners() -> [SIMD3<Double>] {
        struct Key: Hashable { var node: Int; var group: Int }
        var sum: [Key: Double] = [:], weight: [Key: Double] = [:]
        var areas = [Double](repeating: 0, count: triangles.count)
        for (i, t) in triangles.enumerated() {
            let u = points[t.y] - points[t.x], v = points[t.z] - points[t.x]
            let area = abs(u.x * v.y - u.y * v.x) / 2
            areas[i] = area
            for n in [t.x, t.y, t.z] {
                let key = Key(node: n, group: groups?[i] ?? 0)
                sum[key, default: 0] += area * values[i]
                weight[key, default: 0] += area
            }
        }
        func corner(_ n: Int, _ i: Int) -> Double {
            let key = Key(node: n, group: groups?[i] ?? 0)
            let w = weight[key] ?? 0
            return w > 0 ? sum[key]! / w : values[i]
        }
        return triangles.enumerated().map { i, t in SIMD3(corner(t.x, i), corner(t.y, i), corner(t.z, i)) }
    }
}

public extension Body {
    /// Adapts one FEM body and an element field to the generic field-on-points shape. Triangles are
    /// grouped by connected components across shared edges, never crossing a bonded material
    /// interface (those share nodes but stress and strain may jump across them).
    func scalarField(elementValues: [Double], at positions: [Point]? = nil) -> ScalarFieldOnTriangles {
        let tris = mesh.elements.map { SIMD3($0.a, $0.b, $0.c) }
        var cut = Set<UInt64>()
        func edgeKey(_ a: Int, _ b: Int) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }
        for line in mesh.interfaceLines { for (a, b) in zip(line, line.dropFirst()) { cut.insert(edgeKey(a, b)) } }
        var owners: [UInt64: [Int]] = [:]
        for (i, t) in tris.enumerated() {
            for (a, b) in [(t.x, t.y), (t.y, t.z), (t.z, t.x)] { owners[edgeKey(a, b), default: []].append(i) }
        }
        var group = [Int](repeating: -1, count: tris.count), next = 0
        if cut.isEmpty {
            group = [Int](repeating: 0, count: tris.count)
        } else {
            for seed in tris.indices where group[seed] < 0 {
                group[seed] = next
                var stack = [seed]
                while let i = stack.popLast() {
                    let t = tris[i]
                    for (a, b) in [(t.x, t.y), (t.y, t.z), (t.z, t.x)] where !cut.contains(edgeKey(a, b)) {
                        for j in owners[edgeKey(a, b)] ?? [] where group[j] < 0 { group[j] = next; stack.append(j) }
                    }
                }
                next += 1
            }
        }
        return ScalarFieldOnTriangles(points: positions ?? position, triangles: tris,
                                      values: elementValues, groups: group)
    }
}

/// Perceptually ordered, colour-blind-safe colour maps, sampled at fixed stops and interpolated
/// linearly in sRGB.
///
/// Sequential: viridis (van der Walt and Smith, matplotlib, CC0 public domain).
/// Diverging: ColorBrewer RdBu 11-class reversed so negative is blue (Brewer and Harrower, Apache 2.0).
public enum FieldColormap: Sendable {
    case sequential
    case diverging

    private static let viridis: [SIMD3<Double>] = [
        0x440154, 0x482878, 0x3e4989, 0x31688e, 0x26828e, 0x1f9e89, 0x35b779, 0x6dcd59, 0xb4de2c, 0xfde725,
    ].map(rgb)
    private static let rdbu: [SIMD3<Double>] = [
        0x053061, 0x2166ac, 0x4393c3, 0x92c5de, 0xd1e5f0, 0xf7f7f7, 0xfddbc7, 0xf4a582, 0xd6604d, 0xb2182b, 0x67001f,
    ].map(rgb)

    private static func rgb(_ hex: Int) -> SIMD3<Double> {
        SIMD3(Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)) / 255
    }

    /// `t` in 0...1 (clamped). Returns sRGB components 0...1.
    public func color(_ t: Double) -> SIMD3<Double> {
        let stops = self == .sequential ? Self.viridis : Self.rdbu
        let x = min(1, max(0, t.isNaN ? 0 : t)) * Double(stops.count - 1)
        let i = min(stops.count - 2, Int(x))
        return stops[i] + (x - Double(i)) * (stops[i + 1] - stops[i])
    }

    /// Relative luminance (WCAG) of a map position, for the monotonic-lightness check.
    public func luminance(_ t: Double) -> Double {
        let c = color(t)
        func lin(_ u: Double) -> Double { u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.x) + 0.7152 * lin(c.y) + 0.0722 * lin(c.z)
    }

    /// Map a value to 0...1 for a symmetric (signed) or zero-based (unsigned) scale.
    public static func position(of value: Double, limit: Double, signed: Bool) -> Double {
        guard limit > 0 else { return 0 }
        let r = max(-1, min(1, value / limit))
        return signed ? (r + 1) / 2 : r
    }
}
