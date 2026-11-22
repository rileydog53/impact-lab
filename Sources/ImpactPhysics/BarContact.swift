import simd

struct ContactResult {
    var energy = 0.0
    var penetration = 0.0
    var wallImpulse = 0.0
    var wallAngularImpulse = 0.0
}

struct BarFace: Sendable {
    let edges: [Edge]
    let nodes: [Int]
    let stiffness: [Double]

    init(body: Body) {
        let reference = body.mesh.reference
        edges = body.mesh.boundary.filter { reference[$0.a].x == 0 && reference[$0.b].x == 0 }
        var lengths: [Int: Double] = [:]
        for edge in edges {
            let halfLength = 0.5 * simd_distance(reference[edge.a], reference[edge.b])
            lengths[edge.a, default: 0] += halfLength
            lengths[edge.b, default: 0] += halfLength
        }
        nodes = lengths.keys.sorted()
        // Half the face quadrature in each direction gives one penalty for a
        // matching pair of face nodes, including the half-width corner weights.
        stiffness = nodes.map { 0.5 * lengths[$0]! * body.material.young * 2500 }
    }
}

struct BarContact: Sendable {
    let left: BarFace
    let right: BarFace

    func assemble(left leftPosition: [Point], right rightPosition: [Point],
                  leftForce: inout [Point], rightForce: inout [Point]) -> ContactResult {
        for i in left.nodes { leftForce[i] = .zero }
        for i in right.nodes { rightForce[i] = .zero }
        var result = ContactResult()
        Self.apply(from: left, at: leftPosition, to: right, at: rightPosition,
                   sourceForce: &leftForce, targetForce: &rightForce, result: &result)
        Self.apply(from: right, at: rightPosition, to: left, at: leftPosition,
                   sourceForce: &rightForce, targetForce: &leftForce, result: &result)
        return result
    }

    private static func apply(from source: BarFace, at sourcePosition: [Point],
                              to target: BarFace, at targetPosition: [Point],
                              sourceForce: inout [Point], targetForce: inout [Point],
                              result: inout ContactResult) {
        for (i, stiffness) in zip(source.nodes, source.stiffness) {
            var nearest: (edge: Edge, fraction: Double, outward: Point, gap: Double)?
            for edge in target.edges {
                let a = targetPosition[edge.a]
                let tangent = targetPosition[edge.b] - a
                let delta = sourcePosition[i] - a
                let lengthSquared = simd_length_squared(tangent)
                let fraction = simd_dot(delta, tangent) / lengthSquared
                // Reject projections beyond the face, allowing roundoff at
                // shared vertices. Keep the reaction on the contact normal.
                guard fraction >= -1e-10, fraction <= 1 + 1e-10 else { continue }
                let outward = Point(tangent.y, -tangent.x) / lengthSquared.squareRoot()
                let gap = simd_dot(delta, outward)
                if abs(gap) < abs(nearest?.gap ?? .infinity) {
                    nearest = (edge, min(1, max(0, fraction)), outward, gap)
                }
            }
            // Select one closest location per node, even at a shared vertex.
            // The oriented face detects a crossing between samples as well.
            guard let hit = nearest, hit.gap < 0 else { continue }
            let overlap = -hit.gap
            let load = stiffness * overlap
            let force = load * hit.outward
            sourceForce[i] += force
            targetForce[hit.edge.a] -= (1 - hit.fraction) * force
            targetForce[hit.edge.b] -= hit.fraction * force
            result.energy += 0.5 * load * overlap
            result.penetration = max(result.penetration, overlap)
        }
    }
}

extension Simulation {
    public static func alignedBars(material: Material = Material(), speed: Double = 0.4,
                                   stepScale: Double = 1) -> Simulation {
        let gap = 0.012
        let mesh = Mesh.rectangle(columns: 96, rows: 4) { u, v in
            Point(0.5 * (u - 1), 0.1 * (v - 0.5))
        }
        // Reflect the topology as well as the coordinates so the two bars have
        // mirror-identical mass and elastic response.
        let reflected = Mesh(reference: mesh.reference.map { Point(-$0.x, $0.y) },
                             triangles: mesh.elements.map { ($0.a, $0.c, $0.b) },
                             boundary: mesh.boundary.map { Edge($0.b, $0.a) })
        let offset = Point(gap / 2, 0)
        let left = Body(mesh: mesh, material: material, position: mesh.reference.map { $0 - offset }, speed: speed)
        let right = Body(mesh: reflected, material: material, position: reflected.reference.map { $0 + offset }, speed: 0)
        let contact = BarContact(left: BarFace(body: left), right: BarFace(body: right))
        return Simulation(primary: left, secondary: right, barContact: contact,
                          gap: gap, stepScale: stepScale)
    }
}
