import Foundation
import simd

public struct MaterialFractureSettings: Codable, Equatable, Sendable {
    public enum MeshPattern: String, CaseIterable, Codable, Sendable {
        case aligned = "Aligned"
        case staggered = "Staggered"
    }

    /// Legacy range, as a fraction of Young's modulus.
    public static let strengthRange = 0.005...0.08
    /// Legacy range for energy, used while strength is a fraction of E.
    public static let energyRange = 0.5...50.0
    /// Absolute cohesive strength in pascals, used when `strength` is set.
    public static let absoluteStrengthRange = 1e4...4e9
    /// Fracture energy in J/m² when `strength` is set (metal values are far above the legacy cap).
    public static let absoluteEnergyRange = 0.5...1e5

    /// Legacy strength as a fraction of E. Ignored whenever `strength` is set.
    public var strengthFraction = 0.030
    /// Cohesive strength in Pa. nil keeps the legacy fraction-of-E behaviour bit for bit.
    public var strength: Double?
    public var energy = 7.0
    /// Where `energy` came from when it is an estimate rather than a typed value.
    public var energySource: FractureEstimateSource?
    public var meshPattern: MeshPattern?
    public var pattern: MeshPattern { meshPattern ?? .aligned }

    public init() {}

    public func resolvedStrength(young: Double) -> Double { strength ?? young * strengthFraction }
    public var usesAbsoluteStrength: Bool { strength != nil }
    public var activeEnergyRange: ClosedRange<Double> { usesAbsoluteStrength ? Self.absoluteEnergyRange : Self.energyRange }

    var isValid: Bool {
        (strength.map { Self.absoluteStrengthRange.contains($0) } ?? Self.strengthRange.contains(strengthFraction))
            && activeEnergyRange.contains(energy)
    }
}

public struct AssemblyPart: Codable, Equatable, Identifiable, Sendable {
    public struct Notch: Codable, Equatable, Sendable {
        public var centerFraction = 0.0
        public var widthFraction = 0.20
        public var depthFraction = 0.20

        public init() {}

        var isValid: Bool {
            (-0.30...0.30).contains(centerFraction) && (0.12...0.36).contains(widthFraction)
                && (0.02...0.45).contains(depthFraction)
        }
    }

    public struct BondedLayer: Codable, Equatable, Sendable {
        public struct ThirdLayer: Codable, Equatable, Sendable {
            public var interfaceFraction: Double
            public var material: Material

            public init(interfaceFraction: Double = 0.75, material: Material = Material()) {
                self.interfaceFraction = interfaceFraction
                self.material = material
            }
        }

        public static let minimumFraction = 0.10
        public var interfaceFraction = 0.5
        public var material = Material(young: 2e6, density: 2000)
        public var third: ThirdLayer?

        public init() {}

        var regions: [(fraction: Double, material: Material)] {
            var result = [(interfaceFraction, material)]
            if let third { result.append((third.interfaceFraction, third.material)) }
            return result
        }

        var isValid: Bool {
            let range = Self.minimumFraction...(1 - Self.minimumFraction)
            return regions.allSatisfy { fraction, material in
                range.contains(fraction) && material.isValidForAssembly
            } && (third.map { $0.interfaceFraction - interfaceFraction >= Self.minimumFraction - 1e-12 } ?? true)
        }
    }

    public enum Shape: String, CaseIterable, Codable, Sendable {
        case block = "Block"
        case enclosure = "Enclosure"
        case round = "Round body"
    }

    public static let velocityRange = -150.0...150.0

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
    public var refinement: AssemblyScene.Resolution?
    public var notch: Notch?
    public var bondedLayer: BondedLayer?

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
            && Self.velocityRange.contains(velocity.x) && Self.velocityRange.contains(velocity.y)
            && (shape != .enclosure || (0.005...0.4 * min(size.x, size.y)).contains(wall))
            && material.isValidForAssembly
            && plasticity.isValid && (fracture.map { shape != .round && (material.provenance == nil || $0.usesAbsoluteStrength) && $0.isValid } ?? true)
            && !name.isEmpty && name.count <= 48
            && (notch.map { shape == .block && $0.isValid } ?? true)
            && (bondedLayer.map { shape == .block && $0.isValid && fracture == nil && notch == nil
                && plasticity.response == .elastic } ?? true)
    }

    func makeBody(refinement: Int, notchDepth: Double = 0) -> Body {
        let mesh: Mesh
        var elementMaterials: [Material]?
        switch shape {
        case .block:
            let columns = max(3, Int((size.x / 0.009).rounded()))
            let nx = columns * refinement
            let ny = max(3, Int((size.y / 0.009).rounded())) * refinement
            let staggered = fracture?.pattern == .staggered
            if notch != nil || bondedLayer != nil {
                (mesh, elementMaterials) = partitionedBlock(rows: ny, refinement: refinement, staggered: staggered)
            } else {
                mesh = .rectangle(columns: nx, rows: ny, staggerDiagonals: staggered) { u, v in
                    var x = (u - 0.5) * size.x
                    if staggered && u > 0 && u < 1 && v > 0 && v < 1 {
                        let row = Int((v * Double(ny)).rounded())
                        x += (row.isMultiple(of: 2) ? 0.24 : -0.24) * size.x / Double(nx)
                    }
                    // Preserve the mesh used by the archived verification notch.
                    let rise = notchDepth * max(0, 1 - abs(x) * Double(columns) / size.x)
                    return Point(x, (v - 0.5) * size.y + rise * (1 - v))
                }
            }
        case .enclosure:
            mesh = .enclosure(size: size, wall: wall, refinement: refinement)
        case .round:
            mesh = .ellipse(size: size, refinement: refinement)
        }
        let radians = angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        let position = mesh.reference.map { center + Point(c * $0.x - s * $0.y, s * $0.x + c * $0.y) }
        return Body(mesh: mesh, material: material, position: position, velocity: velocity,
                    elementMaterials: elementMaterials)
    }

    private func partitionedBlock(rows: Int, refinement: Int, staggered: Bool) -> (Mesh, [Material]?) {
        var cuts = [0.0, 1.0]
        let center = 0.5 + (notch?.centerFraction ?? 0)
        let halfWidth = (notch?.widthFraction ?? 0) / 2
        if let notch {
            cuts += [center - notch.widthFraction / 2, center, center + notch.widthFraction / 2]
        }
        let regions = bondedLayer?.regions ?? []
        cuts += regions.map(\.fraction)
        cuts.sort()
        var stations = [0.0]
        for (left, right) in zip(cuts, cuts.dropFirst()) {
            let count = max(1, Int(((right - left) * size.x / 0.009).rounded())) * refinement
            for i in 1..<count {
                stations.append(left + (right - left) * Double(i) / Double(count))
            }
            stations.append(right)
        }
        let columns = stations.count - 1
        let interfaces = regions.compactMap { stations.firstIndex(of: $0.fraction) }
        let mesh = Mesh.rectangle(columns: columns, rows: rows, interfaceColumn: interfaces.first,
                                  additionalInterfaceColumn: interfaces.dropFirst().first,
                                  staggerDiagonals: staggered) { u, v in
            let column = Int((u * Double(columns)).rounded())
            let row = Int((v * Double(rows)).rounded())
            var x = stations[column]
            if staggered && column > 0 && column < columns && row > 0 && row < rows {
                let direction = row.isMultiple(of: 2) ? 1 : -1
                // Keep the sloping notch cells aligned across rows.
                if stations[column + 1] <= center - halfWidth || stations[column - 1] >= center + halfWidth {
                    x += 0.24 * (stations[column + direction] - x)
                }
            }
            let rise = notch.map { size.y * $0.depthFraction * max(0, 1 - 2 * abs(x - center) / $0.widthFraction) } ?? 0
            return Point((x - 0.5) * size.x, (v - 0.5) * size.y + rise * (1 - v))
        }
        guard let first = interfaces.first else { return (mesh, nil) }
        let materials = mesh.elements.indices.map { index in
            let column = (index / 2) % columns
            if column < first { return material }
            if let second = interfaces.dropFirst().first, column >= second { return regions[1].material }
            return regions[0].material
        }
        return (mesh, materials)
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

public struct AssemblyGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var members: [UUID]

    public init(members: [UUID]) {
        id = UUID()
        self.members = members
    }
}

public struct AssemblyScene: Codable, Equatable, Sendable {
    public enum Resolution: Int, CaseIterable, Codable, Sendable {
        case standard = 1, fine, extraFine
        case x4, x5, x6, x7

        public var label: String {
            switch self {
            case .standard: "Standard (≈9 mm)"
            case .fine: "Fine (≈4.5 mm)"
            case .extraFine: "Extra fine (≈3 mm)"
            default: String(format: "×%d (≈%.2f mm)", rawValue, 9.0 / Double(rawValue))
            }
        }
    }
    public private(set) var assemblyVersion = 1
    public var parts: [AssemblyPart] = []
    public var connections: [AssemblyConnection] = []
    public static let durationRange = 0.0001...0.25
    public var duration = 0.12
    public var monitor: UUID?
    public var relativeTo: UUID?
    public var gauges: [AssemblyGauge]?
    // Optional on disk so scenes from 0.6 retain their original meshes.
    public var meshResolution: Resolution?
    public var resolution: Resolution { meshResolution ?? .standard }
    public var sampleInterval: Double { min(SceneRun.sampleInterval, duration / 80) }
    // Workshop organization does not affect body indices or contact order.
    public var bodyOrder: [UUID]?
    public var groups: [AssemblyGroup]?

    public static let maximumParts = 8
    public static let maximumConnections = 12

    public init() {}

    public mutating func removePart(_ id: UUID) {
        parts.removeAll { $0.id == id }
        bodyOrder?.removeAll { $0 == id }
        removeFromGroups([id])
        connections.removeAll { $0.first == id || $0.second == id }
        gauges?.removeAll { $0.body == id }
        if monitor == id { monitor = nil }
        if relativeTo == id || relativeTo == (monitor ?? parts.first?.id) { relativeTo = nil }
    }

    public mutating func removeFromGroups(_ ids: Set<UUID>) {
        guard var updated = groups else { return }
        for i in updated.indices { updated[i].members.removeAll { ids.contains($0) } }
        updated.removeAll { $0.members.count < 2 }
        groups = updated.isEmpty ? nil : updated
    }

    public var orderedBodyIDs: [UUID] {
        let order = bodyOrder ?? []
        let listed = Set(order)
        return order + parts.map(\.id).filter { !listed.contains($0) }
    }

    func validate() throws {
        let ids = Set(parts.map(\.id))
        let groups = groups ?? []
        let members = groups.flatMap(\.members)
        let order = bodyOrder ?? []
        guard assemblyVersion == 1, parts.count <= Self.maximumParts, connections.count <= Self.maximumConnections,
              ids.count == parts.count, Set(connections.map(\.id)).count == connections.count,
              Set(order).count == order.count, order.allSatisfy(ids.contains),
              Set(groups.map(\.id)).count == groups.count, groups.allSatisfy({ $0.members.count >= 2 }),
              Set(members).count == members.count, members.allSatisfy(ids.contains),
              Self.durationRange.contains(duration), monitor.map(ids.contains) ?? true,
              relativeTo.map({ ids.contains($0) && $0 != (monitor ?? parts.first?.id) }) ?? true,
              (gauges?.count ?? 0) <= AssemblyGauge.limit,
              Set(gauges?.map(\.id) ?? []).count == (gauges?.count ?? 0),
              gauges?.allSatisfy({ $0.isValid && ids.contains($0.body) }) ?? true,
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
        try document(try Data(contentsOf: url, options: .mappedIfSafe))
    }
}

enum AssemblyError: LocalizedError {
    case invalidSettings
    case overlap(String, String)
    case coincidentAnchors(Int)
    case gaugeOutsideMaterial(String)

    var errorDescription: String? {
        switch self {
        case .invalidSettings: "Assembly settings are outside the supported ranges."
        case .overlap(let a, let b): "\(a) and \(b) overlap or touch at the start. Leave a small clearance."
        case .coincidentAnchors(let index): "Connection \(index + 1) needs at least 0.5 mm between its start anchors."
        case .gaugeOutsideMaterial(let name): "\(name) must be inside its body's reference material."
        }
    }
}

extension Mesh {
    static func ellipse(size: Point, refinement: Int) -> Mesh {
        let rings = max(3, Int((max(size.x, size.y) / 0.018).rounded())) * refinement
        let sectors = 8
        var points: [Point] = [.zero]
        var triangles: [(Int, Int, Int)] = []
        var boundary: [Edge] = []

        for ring in 1...rings {
            let start = points.count
            let previous = start - sectors * (ring - 1)
            let count = sectors * ring
            let radius = size * (0.5 * Double(ring) / Double(rings))
            for i in 0..<count {
                let theta = 2 * Double.pi * Double(i) / Double(count)
                points.append(radius * Point(cos(theta), sin(theta)))
            }
            for sector in 0..<sectors {
                for i in 0..<ring {
                    let outer = sector * ring + i
                    let a = start + outer
                    let b = start + (outer + 1) % count
                    let inner = ring == 1 ? 0
                        : previous + (sector * (ring - 1) + i) % (sectors * (ring - 1))
                    triangles.append((inner, a, b))
                    if i < ring - 1 {
                        let next = previous + (sector * (ring - 1) + i + 1) % (sectors * (ring - 1))
                        triangles.append((inner, b, next))
                    }
                    if ring == rings { boundary.append(Edge(a, b)) }
                }
            }
        }
        return Mesh(reference: points, triangles: triangles, boundary: boundary)
    }

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
