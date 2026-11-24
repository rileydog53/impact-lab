import Foundation
import ImpactPhysics
import simd

enum WorkshopGeometry: String, CaseIterable {
    case block = "Block"
    case plate = "Rectangular Plate"
    case round = "Round Body"
    case enclosure = "Hollow Enclosure"
    case layered = "Bonded Layer Plate"
    case support = "Deformable Support"
    case bench = "Lab Bench (fixed)"
    case roller = "Fixed Roller Support"

    var icon: String {
        switch self {
        case .block: "square.fill"
        case .plate: "rectangle.fill"
        case .round: "circle.fill"
        case .enclosure: "square.dashed"
        case .layered: "square.3.layers.3d"
        case .support: "rectangle.bottomthird.inset.filled"
        case .bench: "rectangle.split.3x1"
        case .roller: "circle.bottomhalf.filled"
        }
    }

    func makePart(number: Int) -> AssemblyPart {
        let name = "\(rawValue) \(number)"
        switch self {
        case .block:
            return AssemblyPart(name, size: Point(0.060, 0.050))
        case .plate:
            return AssemblyPart(name, size: Point(0.110, 0.025))
        case .round:
            return AssemblyPart(name, shape: .round, size: Point(0.050, 0.050))
        case .enclosure:
            return AssemblyPart(name, shape: .enclosure, size: Point(0.130, 0.100))
        case .layered:
            var plate = AssemblyPart(name, size: Point(0.040, 0.110))
            plate.bondedLayer = AssemblyPart.BondedLayer()
            return plate
        case .support:
            var support = AssemblyPart(name, size: Point(0.045, 0.060))
            AssemblyMaterialProfile.stiff.apply(to: &support)
            return support
        case .bench:
            var bench = AssemblyPart("Lab bench \(number)", size: Point(0.400, 0.030))
            AssemblyMaterialProfile.stiff.apply(to: &bench)
            bench.support = .fixed
            return bench
        case .roller:
            var roller = AssemblyPart("Roller support \(number)", shape: .round, size: Point(0.025, 0.025))
            AssemblyMaterialProfile.stiff.apply(to: &roller)
            roller.support = .fixed
            return roller
        }
    }
}

enum WorkshopAlignment: String, CaseIterable {
    case centerX = "Align X Centers"
    case centerY = "Align Y Centers"
    case left = "Align Left Edges"
    case top = "Align Top Edges"
    case spaceX = "Space Left to Right"
    case spaceY = "Space Bottom to Top"
}

struct WorkshopLinkPlacement {
    let kind: AssemblyConnection.Kind
    var first: Anchor?
    var needsOtherBody = false

    struct Anchor {
        let body: UUID
        let fractions: Point
    }
}

struct WorkshopMeshQuality {
    static let thinThreshold = 0.20

    let triangleCount: Int
    let minimum: Double
    let thinTriangles: [Triangle]

    static func measure(_ simulation: AssemblySimulation) -> [Self] {
        (0..<simulation.bodyCount).map { index in
            let mesh = simulation.body(index).mesh
            var worst = 1.0
            var thin: [Triangle] = []
            for triangle in mesh.elements {
                let a = mesh.reference[triangle.a], b = mesh.reference[triangle.b], c = mesh.reference[triangle.c]
                let ab = b - a, ac = c - a
                let doubleArea = abs(ab.x * ac.y - ab.y * ac.x)
                let sum = simd_length_squared(ab) + simd_length_squared(ac) + simd_length_squared(c - b)
                let quality = 2 * sqrt(3.0) * doubleArea / sum
                worst = min(worst, quality)
                if quality < thinThreshold { thin.append(triangle) }
            }
            return Self(triangleCount: mesh.elements.count, minimum: worst, thinTriangles: thin)
        }
    }
}

@MainActor extension AssemblyExperiment {
    private struct Bounds {
        var low: Point
        var high: Point
    }

    var selectedBodyList: [AssemblyPart] {
        displayIndices.map { scene.parts[$0] }.filter { selectedParts.contains($0.id) }
    }

    func selectGroup(_ group: AssemblyGroup) {
        selectParts(Set(group.members))
    }

    func groupSelection() {
        let members = selectedBodyList.map(\.id)
        guard members.count > 1 else { return }
        edit("Group Bodies") {
            $0.removeFromGroups(Set(members))
            $0.groups = ($0.groups ?? []) + [AssemblyGroup(members: members)]
        }
    }

    func ungroupSelection() {
        let selected = selectedParts
        edit("Ungroup Bodies") { scene in
            scene.groups?.removeAll { !$0.members.allSatisfy { !selected.contains($0) } }
            if scene.groups?.isEmpty == true { scene.groups = nil }
        }
    }

    func removeSelection() {
        let selected = selectedParts
        edit(selected.count == 1 ? "Remove Body" : "Remove Bodies") { scene in
            for id in selected { scene.removePart(id) }
        }
    }

    func reorderSelection(toFront: Bool) {
        let ordered = scene.orderedBodyIDs
        let selected = ordered.filter(selectedParts.contains)
        let rest = ordered.filter { !selectedParts.contains($0) }
        let order = toFront ? selected + rest : rest + selected
        guard order != ordered else { return }
        edit("Reorder Bodies") { $0.bodyOrder = order }
    }

    func duplicateSelection() {
        let originals = selectedBodyList
        guard !originals.isEmpty, originals.count + scene.parts.count <= AssemblyScene.maximumParts else { return }
        let internalLinks = scene.connections.filter { selectedParts.contains($0.first) && selectedParts.contains($0.second) }
        guard internalLinks.count + scene.connections.count <= AssemblyScene.maximumConnections else {
            error = "Duplicating these bodies and their internal links would exceed the assembly’s link limit."
            return
        }

        let assemblyBounds = bounds(of: scene.parts.indices)
        let groupBounds = bounds(of: displayIndices.filter { selectedParts.contains(scene.parts[$0].id) })
        let gap = 0.012
        let offsets = [
            Point(assemblyBounds.high.x - groupBounds.low.x + gap, 0),
            Point(assemblyBounds.low.x - groupBounds.high.x - gap, 0),
            Point(0, assemblyBounds.high.y - groupBounds.low.y + gap),
            Point(0, assemblyBounds.low.y - groupBounds.high.y - gap),
        ]
        guard let offset = offsets.first(where: { delta in originals.allSatisfy { validCenter($0.center + delta) } }) else {
            error = "No room to place a clear copy within the assembly position limits."
            return
        }
        let copies = originals.map { original in
            var copy = original
            copy.id = UUID()
            copy.name = String(original.name.prefix(43)) + " copy"
            copy.center += offset
            return copy
        }
        let ids = Dictionary(uniqueKeysWithValues: zip(originals.map(\.id), copies.map(\.id)))
        let links = internalLinks.map { original in
            var copy = original
            copy.id = UUID()
            copy.first = ids[original.first]!
            copy.second = ids[original.second]!
            return copy
        }
        let groups = (scene.groups ?? []).compactMap { group -> AssemblyGroup? in
            let members = group.members.compactMap { ids[$0] }
            return members.count == group.members.count ? AssemblyGroup(members: members) : nil
        }
        let primary = selectedPart.flatMap { ids[$0] }
        edit("Duplicate Bodies") {
            $0.parts += copies
            $0.connections += links
            if !groups.isEmpty { $0.groups = ($0.groups ?? []) + groups }
        }
        if copies.allSatisfy({ copy in scene.parts.contains { $0.id == copy.id } }) {
            selectParts(Set(copies.map(\.id)), primary: primary)
        }
    }

    func alignSelection(_ alignment: WorkshopAlignment, gap: Double) {
        let indices = displayIndices.filter { selectedParts.contains(scene.parts[$0].id) }
        guard indices.count > 1, let primary = selectedIndex else { return }
        let reference = bounds(of: CollectionOfOne(primary))
        var changes: [UUID: Point] = [:]

        switch alignment {
        case .spaceX, .spaceY:
            let axis = alignment == .spaceX ? 0 : 1
            let ordered = indices.map { ($0, bounds(of: CollectionOfOne($0))) }
                .sorted { $0.1.low[axis] < $1.1.low[axis] }
            var next = ordered[0].1.high[axis] + gap
            for (index, bodyBounds) in ordered.dropFirst() {
                let part = scene.parts[index]
                var center = part.center
                center[axis] += next - bodyBounds.low[axis]
                changes[part.id] = center
                next += bodyBounds.high[axis] - bodyBounds.low[axis] + gap
            }
        default:
            for index in indices where index != primary {
                let part = scene.parts[index]
                var center = part.center
                let bodyBounds = bounds(of: CollectionOfOne(index))
                switch alignment {
                case .centerX: center.x = scene.parts[primary].center.x
                case .centerY: center.y = scene.parts[primary].center.y
                case .left: center.x += reference.low.x - bodyBounds.low.x
                case .top: center.y += reference.high.y - bodyBounds.high.y
                default: break
                }
                changes[part.id] = center
            }
        }
        guard changes.values.allSatisfy(validCenter) else {
            error = "That arrangement would move a body beyond the −1,000 to 1,000 mm position limits."
            return
        }
        edit(alignment.rawValue) { scene in
            for index in scene.parts.indices {
                if let center = changes[scene.parts[index].id] { scene.parts[index].center = center }
            }
        }
    }

    func previewMove(_ originals: [AssemblyPart], anchor: AssemblyPart, delta: Point) {
        var delta = delta
        if gridStep > 0 {
            let center = anchor.center + delta
            delta = Point((center.x / gridStep).rounded(), (center.y / gridStep).rounded()) * gridStep - anchor.center
        }
        for axis in 0..<2 {
            let centers = originals.map { $0.center[axis] }
            delta[axis] = min(1 - centers.max()!, max(-1 - centers.min()!, delta[axis]))
        }
        previewParts = Dictionary(uniqueKeysWithValues: originals.map { original in
            var part = original
            part.center += delta
            return (part.id, part)
        })
    }

    func commitPreview(_ action: String) {
        let preview = previewParts
        edit(action) { scene in
            for index in scene.parts.indices {
                if let part = preview[scene.parts[index].id] { scene.parts[index] = part }
            }
        }
    }

    func startLinkPlacement(_ kind: AssemblyConnection.Kind) {
        placingGauge = false
        linkPlacement = WorkshopLinkPlacement(kind: kind)
    }

    func pickLinkAnchor(on id: UUID, at world: Point) {
        guard var placement = linkPlacement, let part = scene.parts.first(where: { $0.id == id }) else { return }
        let radians = -part.angle * .pi / 180
        let relative = world - part.center
        let local = Point(cos(radians) * relative.x - sin(radians) * relative.y,
                          sin(radians) * relative.x + cos(radians) * relative.y)
        let fraction = 2 * local / part.size
        let anchor = Point(min(1, max(-1, fraction.x)), min(1, max(-1, fraction.y)))
        if let first = placement.first, first.body != id {
            var link = AssemblyConnection(first: first.body, second: id, firstAnchor: first.fractions, secondAnchor: anchor)
            link.kind = placement.kind
            if addConnection(link) != nil { linkPlacement = nil }
        } else {
            if placement.first == nil { placement.first = .init(body: id, fractions: anchor) }
            else { placement.needsOtherBody = true }
            linkPlacement = placement
        }
    }

    /// A bench goes just under everything already placed, with a 0.5 mm starting gap.
    func benchPoint(for size: Point) -> Point {
        guard !scene.parts.isEmpty else { return Point(0, -0.06) }
        let current = bounds(of: scene.parts.indices)
        return Point(0.5 * (current.low.x + current.high.x), current.low.y - size.y / 2 - 0.0005)
    }

    func insertionPoint(for size: Point) -> Point {
        guard !scene.parts.isEmpty else { return .zero }
        let current = bounds(of: scene.parts.indices)
        let gap = 0.012
        return [Point(current.high.x + size.x / 2 + gap, 0), Point(current.low.x - size.x / 2 - gap, 0),
                Point(0, current.high.y + size.y / 2 + gap), Point(0, current.low.y - size.y / 2 - gap)]
            .first(where: validCenter) ?? .zero
    }

    private func bounds(of indices: some Sequence<Int>) -> Bounds {
        var low = Point(repeating: .infinity)
        var high = Point(repeating: -.infinity)
        for index in indices {
            for point in simulation.body(index).position {
                low = Point(min(low.x, point.x), min(low.y, point.y))
                high = Point(max(high.x, point.x), max(high.y, point.y))
            }
        }
        return Bounds(low: low, high: high)
    }

    private func validCenter(_ center: Point) -> Bool {
        (-1...1).contains(center.x) && (-1...1).contains(center.y)
    }
}
