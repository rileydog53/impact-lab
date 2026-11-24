import CClipper2
import Foundation

// Polygon boolean operations for the geometry editor (Cut and Join), done by Clipper2
// (Angus Johnson, Boost Software License 1.0; vendored in Sources/CClipper2, see its README).
// Clipper2 rounds coordinates to a fixed decimal grid; we keep 8 decimal places of a metre (10 nm),
// far below any mesh size the editor offers.

public enum PolygonBoolean {
    public enum Operation: Int32, Sendable {
        case intersection = 1, union = 2, difference = 3
    }

    /// Decimal places of a metre that Clipper2 keeps (its maximum).
    static let precision: Int32 = 8

    /// Combines regions. Every region's rings are oriented first (outer counter-clockwise, holes clockwise),
    /// so the non-zero fill rule treats each region as its material. The result is split into connected pieces,
    /// each a region with its own holes. Pieces smaller than `minimumArea` (m²) are dropped as slivers.
    public static func apply(_ operation: Operation, subjects: [PolygonRegion], clips: [PolygonRegion],
                             minimumArea: Double = 1e-10) -> [PolygonRegion] {
        func flatten(_ regions: [PolygonRegion]) -> (xy: [Double], sizes: [Int32]) {
            var xy: [Double] = [], sizes: [Int32] = []
            for region in regions.map({ $0.normalized() }) {
                for ring in region.rings where ring.count >= 3 {
                    for p in ring { xy += [p.x, p.y] }
                    sizes.append(Int32(ring.count))
                }
            }
            return (xy, sizes)
        }
        let s = flatten(subjects), c = flatten(clips)
        var result = CClipperResult()
        let status = s.xy.withUnsafeBufferPointer { sxy in
            s.sizes.withUnsafeBufferPointer { ss in
                c.xy.withUnsafeBufferPointer { cxy in
                    c.sizes.withUnsafeBufferPointer { cs in
                        cclipper_boolean(operation.rawValue, sxy.baseAddress, ss.baseAddress, Int32(ss.count),
                                         cxy.baseAddress, cs.baseAddress, Int32(cs.count), precision, &result)
                    }
                }
            }
        }
        defer { cclipper_free(&result) }
        guard status == 0 else { return [] }
        var pieces: [Int: PolygonRegion] = [:]
        var order: [Int] = []
        var offset = 0
        for r in 0..<Int(result.ringCount) {
            let count = Int(result.ringSizes[r])
            let ring = (0..<count).map { GeoPoint(result.xy[2 * (offset + $0)], result.xy[2 * (offset + $0) + 1]) }
            offset += count
            let piece = Int(result.ringPiece[r])
            if result.ringIsHole[r] != 0 {
                pieces[piece]?.holes.append(ring)
            } else {
                pieces[piece] = PolygonRegion(outer: ring)
                order.append(piece)
            }
        }
        return order.compactMap { pieces[$0] }
            .map { region -> PolygonRegion in
                var copy = region
                copy.holes.removeAll { abs(PolygonRegion.signedArea($0)) < minimumArea }
                return copy.normalized()
            }
            .filter { $0.area >= minimumArea }
    }

    /// The material of `target` with `cutter` removed (notches, holes, slots). May return several pieces.
    public static func cut(_ target: PolygonRegion, by cutter: PolygonRegion) -> [PolygonRegion] {
        apply(.difference, subjects: [target], clips: [cutter])
    }

    /// One region covering both inputs. Returns several pieces when they do not overlap or touch.
    public static func join(_ first: PolygonRegion, _ second: PolygonRegion) -> [PolygonRegion] {
        apply(.union, subjects: [first, second], clips: [])
    }
}
