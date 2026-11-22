import Foundation
import simd

public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case bar = "Bar impact"
    case ring = "Ring impact"
    case block = "Tilted block"
    case twoBars = "Two-bar collision"
    case puckStrip = "Puck and strip"

    public var id: Self { self }

    public static let blockTilt = Double.pi / 10

    public func makeSimulation(material: Material = Material(), speed: Double = 0.4,
                               mirrored: Bool = false) -> Simulation {
        switch self {
        case .bar: Simulation(mesh: .bar(), material: material, speed: speed)
        case .ring: Simulation(mesh: .ring(), material: material, speed: speed, gap: 0.004)
        case .block:
            Simulation(mesh: .roundedBlock(), material: material, speed: speed, gap: 0.004,
                       tilt: mirrored ? -Self.blockTilt : Self.blockTilt)
        case .twoBars:
            Simulation.alignedBars(material: material, speed: speed)
        case .puckStrip:
            Simulation.puckAndStrip(material: material, speed: speed)
        }
    }
}

extension Mesh {
    public static func roundedBlock(columns: Int = 36, rows: Int = 24) -> Mesh {
        let halfWidth = 0.18, halfHeight = 0.115, radius = 0.035
        let corner = Point(halfWidth - radius, halfHeight - radius)
        return rectangle(columns: columns, rows: rows) { u, v in
            let p = Point((2 * u - 1) * halfWidth, (2 * v - 1) * halfHeight)
            let scale = max(abs(p.x) / halfWidth, abs(p.y) / halfHeight)
            guard scale > 0 else { return p }
            let boundary = Point(abs(p.x), abs(p.y)) / scale
            guard boundary.x > corner.x && boundary.y > corner.y else { return p }
            // Intersect the ray with the circle forming the rounded corner.
            let a = simd_length_squared(boundary)
            let b = simd_dot(boundary, corner)
            let c = simd_length_squared(corner) - radius * radius
            let factor = (b + sqrt(max(0, b * b - a * c))) / a
            return p * factor
        }
    }

    public static func ring(sectors: Int = 96, layers: Int = 8) -> Mesh {
        precondition(sectors >= 8 && sectors.isMultiple(of: 4) && layers > 0)
        var nodes: [Point] = []
        var triangles: [(Int, Int, Int)] = []
        var edges: [Edge] = []
        func node(_ i: Int, _ j: Int) -> Int { j * sectors + i % sectors }
        for j in 0...layers {
            let radius = 0.11 + 0.09 * Double(j) / Double(layers)
            for i in 0..<sectors {
                let theta = 2 * Double.pi * Double(i) / Double(sectors)
                nodes.append(Point(radius * cos(theta) - 0.2, radius * sin(theta)))
            }
        }
        for j in 0..<layers {
            for i in 0..<sectors {
                let a = node(i, j), b = node(i, j + 1)
                let c = node(i + 1, j + 1), d = node(i + 1, j)
                if (i + j).isMultiple(of: 2) {
                    triangles.append(contentsOf: [(a, b, c), (a, c, d)])
                } else {
                    triangles.append(contentsOf: [(a, b, d), (b, c, d)])
                }
                if j == 0 { edges.append(Edge(d, a)) }
                if j == layers - 1 { edges.append(Edge(b, c)) }
            }
        }
        return Mesh(reference: nodes, triangles: triangles, boundary: edges)
    }
}

extension Body {
    public var diameters: Point {
        var lower = position[0], upper = position[0]
        for i in boundaryNodes {
            let p = position[i]
            lower = Point(min(lower.x, p.x), min(lower.y, p.y))
            upper = Point(max(upper.x, p.x), max(upper.y, p.y))
        }
        return upper - lower
    }
}

extension Body {
    public var probePosition: Point? {
        guard !mesh.probe.isEmpty else { return nil }
        var sum = Point.zero
        for i in mesh.probe {
            let e = mesh.elements[i]
            sum += position[e.a] + position[e.b] + position[e.c]
        }
        return sum / Double(3 * mesh.probe.count)
    }
}

extension Body {
    public var centerOfMass: Point {
        zip(mass, position).reduce(.zero) { $0 + $1.0 * $1.1 } / totalMass
    }

    public var orientation: Double {
        // Mass-weighted best-fit rotation between reference and current nodes.
        let center = centerOfMass
        var sine = 0.0, cosine = 0.0
        for i in mass.indices {
            let reference = mesh.reference[i] - referenceCenter
            let current = position[i] - center
            sine += mass[i] * cross2D(reference, current)
            cosine += mass[i] * simd_dot(reference, current)
        }
        return atan2(sine, cosine)
    }
}
