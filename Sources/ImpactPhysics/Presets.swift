import Foundation

public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case bar = "Bar impact"
    case ring = "Ring impact"

    public var id: Self { self }

    public func makeSimulation(material: Material = Material(), speed: Double = 0.4) -> Simulation {
        switch self {
        case .bar: Simulation(mesh: .bar(), material: material, speed: speed)
        case .ring: Simulation(mesh: .ring(), material: material, speed: speed, gap: 0.004)
        }
    }
}

extension Mesh {
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
