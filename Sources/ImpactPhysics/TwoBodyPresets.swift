import simd

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
        let contact = BoundaryContact(
            left: ContactSurface(body: left, edges: Self.barImpactFace(left.mesh)),
            right: ContactSurface(body: right, edges: Self.barImpactFace(right.mesh)),
            geometry: .opposingFaces
        )
        return Simulation(primary: left, secondary: right, pairContact: contact,
                          gap: gap, stepScale: stepScale)
    }

    private static func barImpactFace(_ mesh: Mesh) -> [Edge] {
        mesh.boundary.filter { mesh.reference[$0.a].x == 0 && mesh.reference[$0.b].x == 0 }
    }

    public static func puckAndStrip(material: Material = Material(), speed: Double = 0.4,
                                    stepScale: Double = 1, finerBoundary: Bool = false) -> Simulation {
        let radius = 0.07
        let gap = 0.008
        let divisions = finerBoundary ? 36 : 24
        let puckMesh = Mesh.rectangle(columns: divisions, rows: divisions) { u, v in
            let p = Point(2 * u - 1, 2 * v - 1)
            let length = simd_length(p)
            guard length > 0 else { return .zero }
            // Radial projection from a square keeps the centre of the disk meshed.
            return p * (radius * max(abs(p.x), abs(p.y)) / length)
        }
        let stripMesh = Mesh.rectangle(columns: finerBoundary ? 9 : 6, rows: finerBoundary ? 96 : 64) { u, v in
            Point(0.04 * u, 0.42 * (v - 0.5))
        }
        let offset = Point(-radius - gap, 0.055)
        let puck = Body(mesh: puckMesh, material: material,
                        position: puckMesh.reference.map { $0 + offset }, speed: speed)
        let strip = Body(mesh: stripMesh, material: material, position: stripMesh.reference,
                         speed: 0, measuresVerticalStrain: true)
        let contact = BoundaryContact(
            left: ContactSurface(body: puck, edges: puckMesh.boundary),
            right: ContactSurface(body: strip, edges: stripMesh.boundary),
            geometry: .closedBoundaries
        )
        return Simulation(primary: puck, secondary: strip, pairContact: contact,
                          gap: gap, stepScale: stepScale)
    }
}
