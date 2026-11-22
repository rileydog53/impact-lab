import Foundation
import simd

extension Simulation {
    public static func alignedBars(material: Material = Material(), speed: Double = 0.4,
                                   stepScale: Double = 1) -> Simulation {
        var scene = SceneConfiguration.standard(.twoBars)
        scene.first.material = material
        scene.second?.material = material
        scene.speed = speed
        return alignedBars(scene: scene, stepScale: stepScale)
    }

    static func alignedBars(scene: SceneConfiguration, stepScale: Double = 1) -> Simulation {
        let second = scene.second!
        let mesh = Mesh.rectangle(columns: 96, rows: 4) { u, v in
            Point(scene.first.width * (u - 1), scene.first.height! * (v - 0.5))
        }
        // Reflect the diagonal pattern to preserve symmetry for equal bars.
        let widthRatio = second.width / scene.first.width
        let reflected = Mesh(reference: mesh.reference.map { Point(-$0.x * widthRatio, $0.y) },
                             triangles: mesh.elements.map { ($0.a, $0.c, $0.b) },
                             boundary: mesh.boundary.map { Edge($0.b, $0.a) })
        let leftOffset = Point(scene.targetX - scene.gap, scene.centerY)
        let rightOffset = Point(scene.targetX, scene.centerY)
        let left = Body(mesh: mesh, material: scene.first.material,
                        position: mesh.reference.map { $0 + leftOffset },
                        velocity: Point(scene.targetVelocityX + scene.speed, scene.velocityY))
        let right = Body(mesh: reflected, material: second.material,
                         position: reflected.reference.map { $0 + rightOffset },
                         velocity: Point(scene.targetVelocityX, scene.velocityY))
        // A closed boundary lets an exposed corner unload as the bars change height.
        let contact = BoundaryContact(
            left: ContactSurface(body: left),
            right: ContactSurface(body: right)
        )
        return Simulation(primary: left, secondary: right, pairContact: contact,
                          gap: scene.gap, stepScale: stepScale)
    }

    public static func puckAndStrip(material: Material = Material(), speed: Double = 0.4,
                                    stepScale: Double = 1, finerBoundary: Bool = false) -> Simulation {
        var scene = SceneConfiguration.standard(.puckStrip)
        scene.first.material = material
        scene.second?.material = material
        scene.speed = speed
        return puckAndStrip(scene: scene, stepScale: stepScale, finerBoundary: finerBoundary)
    }

    static func puckAndStrip(scene: SceneConfiguration, stepScale: Double = 1,
                             finerBoundary: Bool = false) -> Simulation {
        let second = scene.second!
        let radius = scene.first.width / 2
        let divisions = finerBoundary ? 36 : 24
        let puckMesh = Mesh.rectangle(columns: divisions, rows: divisions) { u, v in
            let p = Point(2 * u - 1, 2 * v - 1)
            let length = simd_length(p)
            guard length > 0 else { return .zero }
            // Radial projection from a square keeps the centre of the disk meshed.
            return p * (radius * max(abs(p.x), abs(p.y)) / length)
        }
        let stripMesh = Mesh.rectangle(columns: finerBoundary ? 9 : 6, rows: finerBoundary ? 96 : 64) { u, v in
            Point(second.width * u, second.height! * (v - 0.5))
        }
        let puckOffset = Point(scene.targetX - radius - scene.gap, scene.centerY + scene.puckOffsetY)
        let stripOffset = Point(scene.targetX, scene.centerY)
        let puck = Body(mesh: puckMesh, material: scene.first.material,
                        position: puckMesh.reference.map { $0 + puckOffset },
                        velocity: Point(scene.targetVelocityX + scene.speed, scene.velocityY))
        let strip = Body(mesh: stripMesh, material: second.material,
                         position: stripMesh.reference.map { $0 + stripOffset },
                         velocity: Point(scene.targetVelocityX, scene.velocityY), measuresVerticalStrain: true)
        let contact = BoundaryContact(
            left: ContactSurface(body: puck),
            right: ContactSurface(body: strip)
        )
        return Simulation(primary: puck, secondary: strip, pairContact: contact,
                          gap: scene.gap, stepScale: stepScale)
    }

    static func bondedBar(scene: SceneConfiguration) -> Simulation {
        let left = scene.first
        let right = scene.second!
        let leftColumns = 104
        let columns = leftColumns + 80
        let interfaceFraction = Double(leftColumns) / Double(columns)
        let probeColumn = Int((0.76 * Double(leftColumns)).rounded())
        // One rectangular grid, with one shared column along the material interface.
        let mesh = Mesh.rectangle(columns: columns, rows: 4, probeColumn: probeColumn,
                                  interfaceColumn: leftColumns) { u, v in
            let x = u < interfaceFraction ? left.width * (u / interfaceFraction - 1)
                : right.width * (u - interfaceFraction) / (1 - interfaceFraction)
            return Point(x, left.height! * (v - 0.5))
        }
        let materials = mesh.elements.map { element in
            let sumX = mesh.reference[element.a].x + mesh.reference[element.b].x + mesh.reference[element.c].x
            return sumX < 0 ? left.material : right.material
        }
        // A compact velocity pulse in the left material splits into left- and
        // right-going waves. The probe sees the right-going wave before its reflection.
        let perturbations = mesh.reference.map { node in
            let s = (node.x / left.width + 0.54) / 0.075
            return Point(abs(s) < 1 ? 0.5 * scene.speed * (1 + cos(.pi * s)) : 0, 0)
        }
        let offset = Point(scene.targetX, scene.centerY)
        let body = Body(mesh: mesh, material: left.material, position: mesh.reference.map { $0 + offset },
                        velocity: Point(scene.targetVelocityX, scene.velocityY),
                        elementMaterials: materials, velocityPerturbation: perturbations)
        return Simulation(primary: body, gap: 0, stepScale: 1)
    }
}
