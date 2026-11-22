import simd

package struct ContactFeatureTrack {
    package let nodes: SIMD3<Int>
    package let pieces: SIMD2<Int>
    package let gap, fraction: Double
}

// Element corners identify material features even when a shared FEM node
// splits, or the local indices and IDs of collision domains change.
package struct ContactFeatureProbe: Sendable {
    package let pieces: SIMD2<Int>
    package let nodeCorners: [Int]
    package let edgeCorners: SIMD2<Int>
    package let node: Int
    package let edge: SIMD2<Int>
    package let force: Point
    package let relativePenetration, fraction, energy: Double
    package let closureSeam: Int?
}

package struct ContactTopologyProbe: Sendable {
    package let pieces: Int
    package var features: [ContactFeatureProbe] = []
    package var crossings: [SIMD4<Int>] = []
    package var residualForce = Point.zero
    package var residualTorque = 0.0

    package var energy: Double { features.reduce(0) { $0 + $1.energy } }
}

package struct DetachmentContactProbe: Sendable {
    package let time: Double
    package let oldTopology, newTopologyAtOldPositions, newTopology: ContactTopologyProbe
    package let oldContact, newContact: Double

    package var energyJump: Double { newContact - oldContact }
}

extension MaterialFracture {
    package func probeContact(at positions: [Point]) -> ContactTopologyProbe {
        let matching = matchingFeatures()
        var probe = ContactTopologyProbe(pieces: surfaces.count)
        for (i, left) in surfaces.enumerated() {
            let lp = left.positions(positions)
            let lb = ContactBounds(surface: left.surface, position: lp)
            for right in surfaces.dropFirst(i + 1) {
                let rp = right.positions(positions)
                let rb = ContactBounds(surface: right.surface, position: rp)
                guard lb.intersects(rb) else { continue }
                var lf = Array(repeating: Point.zero, count: lp.count)
                var rf = Array(repeating: Point.zero, count: rp.count)
                let contact = BoundaryContact(left: left.surface, right: right.surface)
                let result = contact.accumulate(left: lp, right: rp, leftBounds: lb, rightBounds: rb, leftForce: &lf,
                                                rightForce: &rf, matching: MatchingContact(leftNodes: left.nodes,
                                                rightNodes: right.nodes, seams: matching), sample: true)
                for (positions, forces) in [(lp, lf), (rp, rf)] {
                    for (position, force) in zip(positions, forces) {
                        probe.residualForce += force
                        probe.residualTorque += position.x * force.y - position.y * force.x
                    }
                }
                for sample in result.samples {
                    let source = sample.leftToRight ? left : right
                    let target = sample.leftToRight ? right : left
                    let node = source.nodes[sample.node]
                    let edge = target.surface.edges[sample.edgeIndex]
                    let corners = target.edgeCorners[sample.edgeIndex]
                    probe.features.append(ContactFeatureProbe(pieces: SIMD2(source.id, target.id),
                        nodeCorners: contactCorners(at: node), edgeCorners: SIMD2(corners.a, corners.b),
                        node: node, edge: SIMD2(target.nodes[edge.a], target.nodes[edge.b]), force: sample.load * sample.normal,
                        relativePenetration: sample.relativePenetration, fraction: sample.fraction, energy: sample.energy,
                        closureSeam: sample.closureSeam))
                }
                for (j, a) in left.surface.edges.enumerated() {
                    let p = lp[a.a], u = lp[a.b] - p
                    for (k, b) in right.surface.edges.enumerated() {
                        let q = rp[b.a], v = rp[b.b] - q
                        let det = u.x * v.y - u.y * v.x
                        guard det != 0 else { continue }
                        let w = q - p
                        let s = (w.x * v.y - w.y * v.x) / det
                        let t = (w.x * u.y - w.y * u.x) / det
                        // Shared endpoints and coincident lips are not proper crossings.
                        if s > 1e-10 && s < 1 - 1e-10 && t > 1e-10 && t < 1 - 1e-10 {
                            probe.crossings.append(SIMD4(left.id, right.id, left.edgeCorners[j].a, right.edgeCorners[k].a))
                        }
                    }
                }
            }
        }
        return probe
    }
}
