import simd

struct ContactResult {
    var energy = 0.0
    var penetration = 0.0
    var relativePenetration = 0.0
    var exposedFaceContact = false
    var normalLoad = 0.0
    var wallImpulse = 0.0
    var wallAngularImpulse = 0.0
    var matchingContacts: Set<Int> = []

    mutating func add(_ other: Self) {
        energy += other.energy
        penetration = max(penetration, other.penetration)
        relativePenetration = max(relativePenetration, other.relativePenetration)
        exposedFaceContact = exposedFaceContact || other.exposedFaceContact
        normalLoad += other.normalLoad
        wallImpulse += other.wallImpulse
        wallAngularImpulse += other.wallAngularImpulse
        if !other.matchingContacts.isEmpty { matchingContacts.formUnion(other.matchingContacts) }
    }
}

// Matching contacts are keyed by material node IDs, so the same rule
// applies after a fracture surface has been compacted for collision.
struct MatchingContact {
    let leftNodes, rightNodes: [Int]
    let seams: [SIMD3<Int>: Int]
}

struct ContactSurface: Sendable {
    let edges: [Edge]
    let nodes: [Int]
    let stiffness: [Double]

    init(body: Body) {
        self.init(edges: body.mesh.boundary, reference: body.mesh.reference, young: body.material.young)
    }

    init(edges: [Edge], reference: [Point], young: Double, sourceEdges: [Edge]? = nil) {
        self.edges = edges
        let nodes = Set(edges.flatMap { [$0.a, $0.b] }).sorted()
        var lengths: [Int: Double] = [:]
        for edge in sourceEdges ?? edges {
            let halfLength = 0.5 * simd_distance(reference[edge.a], reference[edge.b])
            lengths[edge.a, default: 0] += halfLength
            lengths[edge.b, default: 0] += halfLength
        }
        self.nodes = nodes
        // The two passes each carry half the tributary-length quadrature.
        stiffness = nodes.map { 0.5 * lengths[$0, default: 0] * young * 2500 }
    }
}

struct ContactBounds {
    var lower = Point(repeating: .infinity)
    var upper = Point(repeating: -.infinity)

    init(surface: ContactSurface, position: [Point]) {
        for i in surface.nodes {
            lower = simd_min(lower, position[i])
            upper = simd_max(upper, position[i])
        }
    }

    func intersects(_ other: Self) -> Bool {
        lower.x <= other.upper.x && upper.x >= other.lower.x
            && lower.y <= other.upper.y && upper.y >= other.lower.y
    }

    func contains(_ point: Point) -> Bool {
        point.x >= lower.x && point.x <= upper.x && point.y >= lower.y && point.y <= upper.y
    }
}

struct BoundaryContact: Sendable {
    private struct Hit {
        let edge: Edge
        let fraction: Double
        let normal: Point
        let distance: Double
        let length: Double
    }

    let left: ContactSurface
    let right: ContactSurface

    var maximumStiffness: Double {
        max(left.stiffness.max() ?? 0, right.stiffness.max() ?? 0)
    }

    func assemble(left leftPosition: [Point], right rightPosition: [Point],
                  leftForce: inout [Point], rightForce: inout [Point], accumulating: Bool = false) -> ContactResult {
        if !accumulating {
            for i in left.nodes { leftForce[i] = .zero }
            for i in right.nodes { rightForce[i] = .zero }
        }
        let leftBounds = ContactBounds(surface: left, position: leftPosition)
        let rightBounds = ContactBounds(surface: right, position: rightPosition)
        return accumulate(left: leftPosition, right: rightPosition, leftBounds: leftBounds, rightBounds: rightBounds,
                          leftForce: &leftForce, rightForce: &rightForce)
    }

    func accumulate(left leftPosition: [Point], right rightPosition: [Point],
                    leftBounds: ContactBounds, rightBounds: ContactBounds,
                    leftForce: inout [Point], rightForce: inout [Point],
                    leftExposed: Set<SIMD2<Int>> = [], rightExposed: Set<SIMD2<Int>> = [],
                    matching: MatchingContact? = nil) -> ContactResult {
        var result = ContactResult()
        guard leftBounds.intersects(rightBounds) else { return result }
        Self.apply(from: left, at: leftPosition, to: right, at: rightPosition, bounds: rightBounds,
                   sourceForce: &leftForce, targetForce: &rightForce, exposed: rightExposed, result: &result,
                   matching: matching, leftToRight: true)
        Self.apply(from: right, at: rightPosition, to: left, at: leftPosition, bounds: leftBounds,
                   sourceForce: &rightForce, targetForce: &leftForce, exposed: leftExposed, result: &result,
                   matching: matching, leftToRight: false)
        return result
    }

    private static func apply(from source: ContactSurface, at sourcePosition: [Point],
                              to target: ContactSurface, at targetPosition: [Point], bounds: ContactBounds,
                              sourceForce: inout [Point], targetForce: inout [Point],
                              exposed: Set<SIMD2<Int>>, result: inout ContactResult,
                              matching: MatchingContact?, leftToRight: Bool) {
        for (i, stiffness) in zip(source.nodes, source.stiffness) where stiffness > 0 {
            let node = sourcePosition[i]
            guard bounds.contains(node), let hit = boundaryHit(node, target: target, position: targetPosition) else {
                continue
            }
            result.relativePenetration = max(result.relativePenetration, hit.distance / hit.length)
            if let matching {
                let sourceNodes = leftToRight ? matching.leftNodes : matching.rightNodes
                let targetNodes = leftToRight ? matching.rightNodes : matching.leftNodes
                if let seam = matching.seams[SIMD3(sourceNodes[i], targetNodes[hit.edge.a], targetNodes[hit.edge.b])] {
                    result.matchingContacts.insert(seam)
                    continue // Its paired closure law supplies this reaction.
                }
            }
            let load = stiffness * hit.distance
            result.normalLoad += load
            let force = load * hit.normal
            sourceForce[i] += force
            targetForce[hit.edge.a] -= (1 - hit.fraction) * force
            targetForce[hit.edge.b] -= hit.fraction * force
            result.energy += 0.5 * load * hit.distance
            result.penetration = max(result.penetration, hit.distance)
            if !exposed.isEmpty, exposed.contains(SIMD2(hit.edge.a, hit.edge.b)) {
                result.exposedFaceContact = true
            }
        }
    }

    static func contains(_ node: Point, within surface: ContactSurface, position: [Point]) -> Bool {
        var inside = false
        for edge in surface.edges {
            let a = position[edge.a], b = position[edge.b]
            if (a.y > node.y) != (b.y > node.y),
               node.x < a.x + (node.y - a.y) * (b.x - a.x) / (b.y - a.y) {
                inside.toggle()
            }
        }
        return inside
    }

    private static func boundaryHit(_ node: Point, target: ContactSurface, position: [Point]) -> Hit? {
        var inside = false
        var nearest: (edge: Edge, fraction: Double, offset: Point, distanceSquared: Double, lengthSquared: Double)?
        for edge in target.edges {
            let a = position[edge.a]
            let b = position[edge.b]
            let tangent = b - a
            let delta = node - a
            // A horizontal ray with half-open y intervals counts a vertex once.
            if (a.y > node.y) != (b.y > node.y),
               node.x < a.x + delta.y * tangent.x / tangent.y {
                inside.toggle()
            }
            let lengthSquared = simd_length_squared(tangent)
            let fraction = min(1, max(0, simd_dot(delta, tangent) / lengthSquared))
            let offset = delta - fraction * tangent
            let distanceSquared = simd_length_squared(offset)
            if distanceSquared < (nearest?.distanceSquared ?? .infinity) {
                nearest = (edge, fraction, offset, distanceSquared, lengthSquared)
            }
        }
        // One closest location per interior node. At an endpoint the force
        // acts along the node-to-vertex normal, and the full reaction goes there.
        guard inside, let nearest, nearest.distanceSquared > 0 else { return nil }
        let distance = nearest.distanceSquared.squareRoot()
        return Hit(edge: nearest.edge, fraction: nearest.fraction, normal: -nearest.offset / distance,
                   distance: distance, length: nearest.lengthSquared.squareRoot())
    }
}

extension BoundaryContact {
    static func clearance(_ edges: [Edge], at position: [Point], to otherEdges: [Edge], at otherPosition: [Point]) -> Double {
        func distanceSquared(_ point: Point, from origin: Point, along tangent: Point) -> Double {
            let delta = point - origin
            let fraction = min(1, max(0, simd_dot(delta, tangent) / simd_length_squared(tangent)))
            return simd_length_squared(delta - fraction * tangent)
        }

        var nearest = Double.infinity
        for first in edges {
            let a = position[first.a], b = position[first.b]
            let ab = b - a
            for second in otherEdges {
                let c = otherPosition[second.a], d = otherPosition[second.b]
                let cd = d - c
                let det = cross2D(ab, cd)
                if det != 0 {
                    let t = cross2D(c - a, cd) / det
                    let u = cross2D(c - a, ab) / det
                    if t >= 0 && t <= 1 && u >= 0 && u <= 1 { return 0 }
                }
                nearest = min(nearest, distanceSquared(a, from: c, along: cd), distanceSquared(b, from: c, along: cd),
                              distanceSquared(c, from: a, along: ab), distanceSquared(d, from: a, along: ab))
            }
        }
        return nearest.squareRoot()
    }
}

extension Body {
    package func boundaryClearance(to other: Body) -> Double {
        BoundaryContact.clearance(mesh.boundary, at: position, to: other.mesh.boundary, at: other.position)
    }
}
