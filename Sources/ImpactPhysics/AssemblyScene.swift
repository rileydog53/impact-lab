import Foundation
import simd

public struct MaterialFractureSettings: Codable, Equatable, Sendable {
    public enum MeshPattern: String, CaseIterable, Codable, Sendable {
        case aligned = "Aligned"
        case staggered = "Staggered"
    }

    public static let strengthRange = 0.005...0.08
    public static let energyRange = 0.5...50.0
    public var strengthFraction = 0.030
    public var energy = 7.0
    public var meshPattern: MeshPattern?
    public var pattern: MeshPattern { meshPattern ?? .aligned }

    public init() {}

    var isValid: Bool {
        Self.strengthRange.contains(strengthFraction) && Self.energyRange.contains(energy)
    }
}

public struct AssemblyPart: Codable, Equatable, Identifiable, Sendable {
    public enum Shape: String, CaseIterable, Codable, Sendable {
        case block = "Block"
        case enclosure = "Enclosure"
    }

    public var id = UUID()
    public var name: String
    public var shape: Shape
    public var center: Point
    public var size: Point
    public var wall: Double = 0.012
    public var angle = 0.0
    public var velocity = Point.zero
    public var material = Material()
    public var plasticity = ImpactPlasticity(response: .elastic)
    public var fracture: MaterialFractureSettings?

    public init(_ name: String, shape: Shape = .block, center: Point = .zero,
                size: Point = Point(0.06, 0.06)) {
        self.name = name
        self.shape = shape
        self.center = center
        self.size = size
    }

    var isValid: Bool {
        (0.025...0.30).contains(size.x) && (0.025...0.30).contains(size.y)
            && (-1...1).contains(center.x) && (-1...1).contains(center.y)
            && (-360...360).contains(angle)
            && (-1.5...1.5).contains(velocity.x) && (-1.5...1.5).contains(velocity.y)
            && (shape == .block || (0.005...0.4 * min(size.x, size.y)).contains(wall))
            && SceneConfiguration.youngRange.contains(material.young)
            && SceneConfiguration.densityRange.contains(material.density)
            && SceneConfiguration.poissonRange.contains(material.poisson)
            && plasticity.isValid && (fracture?.isValid ?? true) && !name.isEmpty && name.count <= 48
    }

    func makeBody(refinement: Int, notchDepth: Double = 0) -> Body {
        let mesh: Mesh
        switch shape {
        case .block:
            let columns = max(3, Int((size.x / 0.009).rounded()))
            let nx = columns * refinement
            let ny = max(3, Int((size.y / 0.009).rounded())) * refinement
            let staggered = fracture?.pattern == .staggered
            mesh = .rectangle(columns: nx, rows: ny, staggerDiagonals: staggered) { u, v in
                var x = (u - 0.5) * size.x
                if staggered && u > 0 && u < 1 && v > 0 && v < 1 {
                    let row = Int((v * Double(ny)).rounded())
                    x += (row.isMultiple(of: 2) ? 0.24 : -0.24) * size.x / Double(nx)
                }
                // Verification uses a triangular notch with the same physical
                // boundary at each refinement and both interior mesh patterns.
                let rise = notchDepth * max(0, 1 - abs(x) * Double(columns) / size.x)
                return Point(x, (v - 0.5) * size.y + rise * (1 - v))
            }
        case .enclosure:
            mesh = .enclosure(size: size, wall: wall, refinement: refinement)
        }
        let radians = angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        let position = mesh.reference.map { center + Point(c * $0.x - s * $0.y, s * $0.x + c * $0.y) }
        return Body(mesh: mesh, material: material, position: position, velocity: velocity)
    }
}

public struct AssemblyConnection: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case spring = "Spring"
        case cohesive = "Breakable"
    }

    public var id = UUID()
    public var first: UUID
    public var second: UUID
    public var firstAnchor: Point
    public var secondAnchor: Point
    public var kind: Kind = .spring
    public var stiffness = 12_000.0
    public var criticalExtension = 0.006
    public var span = 0.0

    public init(first: UUID, second: UUID, firstAnchor: Point = Point(1, 0), secondAnchor: Point = Point(-1, 0)) {
        self.first = first
        self.second = second
        self.firstAnchor = firstAnchor
        self.secondAnchor = secondAnchor
    }

    var isValid: Bool {
        (500...250_000).contains(stiffness) && (0.0005...0.04).contains(criticalExtension)
            && (0...1.9).contains(span) && first != second
            && [firstAnchor.x, firstAnchor.y, secondAnchor.x, secondAnchor.y].allSatisfy { (-1...1).contains($0) }
            && abs(firstAnchor.y) + span / 2 <= 1.000001 && abs(secondAnchor.y) + span / 2 <= 1.000001
    }
}

public struct AssemblyScene: Codable, Equatable, Sendable {
    public enum Resolution: Int, CaseIterable, Codable, Sendable {
        case standard = 1, fine, extraFine

        public var label: String {
            switch self {
            case .standard: "Standard (≈9 mm)"
            case .fine: "Fine (≈4.5 mm)"
            case .extraFine: "Extra fine (≈3 mm)"
            }
        }
    }
    public private(set) var assemblyVersion = 1
    public var parts: [AssemblyPart] = []
    public var connections: [AssemblyConnection] = []
    public var duration = 0.12
    public var monitor: UUID?
    public var relativeTo: UUID?
    // Optional on disk so scenes from 0.6 retain their original meshes.
    public var meshResolution: Resolution?
    public var resolution: Resolution { meshResolution ?? .standard }

    public static let maximumParts = 8
    public static let maximumConnections = 12

    public init() {}

    public mutating func removePart(_ id: UUID) {
        parts.removeAll { $0.id == id }
        connections.removeAll { $0.first == id || $0.second == id }
        if monitor == id { monitor = nil }
        if relativeTo == id || relativeTo == (monitor ?? parts.first?.id) { relativeTo = nil }
    }

    func validate() throws {
        let ids = Set(parts.map(\.id))
        guard assemblyVersion == 1, parts.count <= Self.maximumParts, connections.count <= Self.maximumConnections,
              ids.count == parts.count, Set(connections.map(\.id)).count == connections.count,
              (0.02...0.25).contains(duration), monitor.map(ids.contains) ?? true,
              relativeTo.map({ ids.contains($0) && $0 != (monitor ?? parts.first?.id) }) ?? true,
              parts.allSatisfy(\.isValid), connections.allSatisfy({ $0.isValid && ids.contains($0.first) && ids.contains($0.second) })
        else { throw AssemblyError.invalidSettings }
    }

    public func save(to url: URL) throws {
        _ = try AssemblySimulation(self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func open(_ url: URL) throws -> Self {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 128 * 1024 else { throw AssemblyError.invalidSettings }
        let scene = try JSONDecoder().decode(Self.self, from: data)
        _ = try AssemblySimulation(scene)
        return scene
    }
}

enum AssemblyError: LocalizedError {
    case invalidSettings
    case overlap(String, String)
    case coincidentAnchors(Int)

    var errorDescription: String? {
        switch self {
        case .invalidSettings: "Assembly settings are outside the supported ranges."
        case .overlap(let a, let b): "\(a) and \(b) overlap or touch at the start. Leave a small clearance."
        case .coincidentAnchors(let index): "Connection \(index + 1) needs at least 0.5 mm between its start anchors."
        }
    }
}

extension Mesh {
    static func enclosure(size: Point, wall: Double, refinement: Int) -> Mesh {
        let layers = 2 * refinement
        func coordinates(_ width: Double) -> [Double] {
            let interior = max(3, Int(((width - 2 * wall) / 0.009).rounded())) * refinement
            let edge = width / 2
            let left = (0..<layers).map { -edge + wall * Double($0) / Double(layers) }
            let innerEdge = wall - edge
            let interiorStep = (width - 2 * wall) / Double(interior)
            let center = (0...interior).map { innerEdge + interiorStep * Double($0) }
            let right = (1...layers).map { edge - wall + wall * Double($0) / Double(layers) }
            return left + center + right
        }
        let x = coordinates(size.x), y = coordinates(size.y)
        let nx = x.count - 1, ny = y.count - 1
        func solid(_ i: Int, _ j: Int) -> Bool {
            guard (0..<nx).contains(i), (0..<ny).contains(j) else { return false }
            return i < layers || i >= nx - layers || j < layers || j >= ny - layers
        }
        var points: [Point] = []
        var indices: [Int: Int] = [:]
        var triangles: [(Int, Int, Int)] = []
        var edges: [Edge] = []
        func node(_ i: Int, _ j: Int) -> Int {
            let key = i + j * x.count
            if let existing = indices[key] { return existing }
            let index = points.count
            points.append(Point(x[i], y[j]))
            indices[key] = index
            return index
        }
        for j in 0..<ny {
            for i in 0..<nx where solid(i, j) {
                let a = node(i, j), b = node(i + 1, j), c = node(i + 1, j + 1), d = node(i, j + 1)
                if (i + j).isMultiple(of: 2) {
                    triangles.append(contentsOf: [(a, b, c), (a, c, d)])
                } else {
                    triangles.append(contentsOf: [(a, b, d), (b, c, d)])
                }
                if !solid(i, j - 1) { edges.append(Edge(a, b)) }
                if !solid(i + 1, j) { edges.append(Edge(b, c)) }
                if !solid(i, j + 1) { edges.append(Edge(c, d)) }
                if !solid(i - 1, j) { edges.append(Edge(d, a)) }
            }
        }
        return Mesh(reference: points, triangles: triangles, boundary: edges)
    }
}
