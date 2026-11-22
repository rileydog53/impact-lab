import simd

struct ContactResult {
    var energy = 0.0
    var penetration = 0.0
    var relativePenetration = 0.0
    var wallImpulse = 0.0
    var wallAngularImpulse = 0.0
}

struct ContactSurface: Sendable {
    let edges: [Edge]
    let nodes: [Int]
    let stiffness: [Double]

    init(body: Body, edges: [Edge]) {
        self.edges = edges
        let reference = body.mesh.reference
        var lengths: [Int: Double] = [:]
        for edge in edges {
            let halfLength = 0.5 * simd_distance(reference[edge.a], reference[edge.b])
            lengths[edge.a, default: 0] += halfLength
            lengths[edge.b, default: 0] += halfLength
        }
        nodes = lengths.keys.sorted()
        // The two passes each carry half the tributary-length quadrature.
        stiffness = nodes.map { 0.5 * lengths[$0]! * body.material.young * 2500 }
    }
}

private struct ContactBounds {
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
    enum Geometry: Sendable {
        case opposingFaces
        case closedBoundaries
    }

    private struct Hit {
        let edge: Edge
        let fraction: Double
        let normal: Point
        let distance: Double
        let length: Double
    }

    let left: ContactSurface
    let right: ContactSurface
    let geometry: Geometry

    var maximumStiffness: Double {
        max(left.stiffness.max() ?? 0, right.stiffness.max() ?? 0)
    }

    func assemble(left leftPosition: [Point], right rightPosition: [Point],
                  leftForce: inout [Point], rightForce: inout [Point]) -> ContactResult {
        for i in left.nodes { leftForce[i] = .zero }
        for i in right.nodes { rightForce[i] = .zero }
        var result = ContactResult()
        let leftBounds: ContactBounds?
        let rightBounds: ContactBounds?
        switch geometry {
        case .opposingFaces:
            leftBounds = nil
            rightBounds = nil
        case .closedBoundaries:
            let a = ContactBounds(surface: left, position: leftPosition)
            let b = ContactBounds(surface: right, position: rightPosition)
            guard a.intersects(b) else { return result }
            leftBounds = a
            rightBounds = b
        }
        Self.apply(from: left, at: leftPosition, to: right, at: rightPosition, bounds: rightBounds,
                   sourceForce: &leftForce, targetForce: &rightForce, result: &result)
        Self.apply(from: right, at: rightPosition, to: left, at: leftPosition, bounds: leftBounds,
                   sourceForce: &rightForce, targetForce: &leftForce, result: &result)
        return result
    }

    private static func apply(from source: ContactSurface, at sourcePosition: [Point],
                              to target: ContactSurface, at targetPosition: [Point], bounds: ContactBounds?,
                              sourceForce: inout [Point], targetForce: inout [Point],
                              result: inout ContactResult) {
        for (i, stiffness) in zip(source.nodes, source.stiffness) {
            let node = sourcePosition[i]
            let hit: Hit?
            if let bounds {
                guard bounds.contains(node) else { continue }
                hit = closedBoundaryHit(node, target: target, position: targetPosition)
            } else {
                hit = opposingFaceHit(node, target: target, position: targetPosition)
            }
            guard let hit else { continue }
            let load = stiffness * hit.distance
            let force = load * hit.normal
            sourceForce[i] += force
            targetForce[hit.edge.a] -= (1 - hit.fraction) * force
            targetForce[hit.edge.b] -= hit.fraction * force
            result.energy += 0.5 * load * hit.distance
            result.penetration = max(result.penetration, hit.distance)
            result.relativePenetration = max(result.relativePenetration, hit.distance / hit.length)
        }
    }

    private static func opposingFaceHit(_ node: Point, target: ContactSurface, position: [Point]) -> Hit? {
        var nearest: (hit: Hit, gap: Double)?
        for edge in target.edges {
            let a = position[edge.a]
            let tangent = position[edge.b] - a
            let delta = node - a
            let lengthSquared = simd_length_squared(tangent)
            let fraction = simd_dot(delta, tangent) / lengthSquared
            // Allow roundoff at a shared vertex of the aligned faces.
            guard fraction >= -1e-10, fraction <= 1 + 1e-10 else { continue }
            let length = lengthSquared.squareRoot()
            let outward = Point(tangent.y, -tangent.x) / length
            let gap = simd_dot(delta, outward)
            if abs(gap) < abs(nearest?.gap ?? .infinity) {
                let hit = Hit(edge: edge, fraction: min(1, max(0, fraction)), normal: outward,
                              distance: abs(gap), length: length)
                nearest = (hit, gap)
            }
        }
        guard let nearest, nearest.gap < 0 else { return nil }
        return nearest.hit
    }

    private static func closedBoundaryHit(_ node: Point, target: ContactSurface, position: [Point]) -> Hit? {
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

extension Body {
    package func boundaryClearance(to other: Body) -> Double {
        func distanceSquared(_ point: Point, from origin: Point, along tangent: Point) -> Double {
            let delta = point - origin
            let fraction = min(1, max(0, simd_dot(delta, tangent) / simd_length_squared(tangent)))
            return simd_length_squared(delta - fraction * tangent)
        }

        var nearest = Double.infinity
        for first in mesh.boundary {
            let a = position[first.a], b = position[first.b]
            let ab = b - a
            for second in other.mesh.boundary {
                let c = other.position[second.a], d = other.position[second.b]
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
