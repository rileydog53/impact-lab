import Foundation
import ImpactGeometry
import ImpactPhysics
import simd

// General geometry editing (outline model, approved 2026-11-24): draw an outline, edit its points,
// cut one body with another, join two bodies, and convert a legacy shape to an outline.
// Every change is an ordinary undoable scene edit; the mesh is regenerated from the outline.

/// Ready-made outlines for the Add Body menu. They are only starting points: every one can be edited freely.
enum OutlinePrimitive: String, CaseIterable {
    case plate = "Outline Plate"
    case disc = "Outline Disc"
    case bracket = "L-Bracket"
    case holedPlate = "Plate with Hole"
    case wedge = "Wedge"
    case hexagon = "Hexagon"

    var icon: String {
        switch self {
        case .plate: "rectangle"
        case .disc: "circle"
        case .bracket: "l.square"
        case .holedPlate: "rectangle.center.inset.filled"
        case .wedge: "triangle"
        case .hexagon: "hexagon"
        }
    }

    var region: PolygonRegion {
        switch self {
        case .plate:
            return PolygonRegion(outer: Shapes.rectangle(width: 0.100, height: 0.030))
        case .disc:
            return PolygonRegion(outer: Shapes.ellipse(width: 0.050, height: 0.050, sides: 48))
        case .bracket:
            return PolygonRegion(outer: [Point(-0.040, -0.040), Point(0.040, -0.040), Point(0.040, -0.025),
                                         Point(-0.025, -0.025), Point(-0.025, 0.040), Point(-0.040, 0.040)])
        case .holedPlate:
            return PolygonRegion(outer: Shapes.rectangle(width: 0.120, height: 0.060),
                                 holes: [Shapes.ellipse(width: 0.024, height: 0.024, sides: 40)])
        case .wedge:
            return PolygonRegion(outer: [Point(-0.040, -0.015), Point(0.040, -0.015), Point(0.040, 0.015)])
        case .hexagon:
            return PolygonRegion(outer: Shapes.ellipse(width: 0.050, height: 0.050 * 0.866, sides: 6))
        }
    }
}

@MainActor extension AssemblyExperiment {
    // MARK: Coordinates

    func local(_ world: Point, in part: AssemblyPart) -> Point {
        let r = -part.angle * .pi / 180
        let d = world - part.center
        return Point(cos(r) * d.x - sin(r) * d.y, sin(r) * d.x + cos(r) * d.y)
    }

    func world(_ local: Point, in part: AssemblyPart) -> Point {
        let r = part.angle * .pi / 180
        return part.center + Point(cos(r) * local.x - sin(r) * local.y, sin(r) * local.x + cos(r) * local.y)
    }

    func snapped(_ point: Point) -> Point {
        gridStep > 0 ? (point / gridStep).rounded(.toNearestOrAwayFromZero) * gridStep : point
    }

    private func nextName(_ base: String) -> String {
        let used = Set(scene.parts.map(\.name))
        return (1...).lazy.map { "\(base) \($0)" }.first { !used.contains($0) }!
    }

    // MARK: Insert

    @discardableResult func insertOutline(_ primitive: OutlinePrimitive) -> UUID? {
        let region = primitive.region
        let (low, high) = region.bounds
        let placed = AssemblyPart(nextName(primitive.rawValue), shape: .outline, size: high - low)
            .reshaped(to: region)
        var part = placed
        part.center = insertionPoint(for: part.size)
        return add(part, action: "Add Outline Body")
    }

    private func add(_ part: AssemblyPart, action: String) -> UUID? {
        guard scene.parts.count < AssemblyScene.maximumParts else {
            error = "This assembly already has \(AssemblyScene.maximumParts) bodies, the most the editor accepts."
            return nil
        }
        edit(action) { $0.parts.append(part) }
        guard scene.parts.contains(where: { $0.id == part.id }) else { return nil }
        select(part.id)
        return part.id
    }

    // MARK: Draw

    func beginOutlineDrawing() {
        guard canEdit else { return }
        placingGauge = false
        linkPlacement = nil
        editingOutline = nil
        outlineDraft = []
    }

    func cancelOutlineDrawing() { outlineDraft = nil }

    func addDraftPoint(_ world: Point) {
        guard var draft = outlineDraft else { return }
        let point = snapped(world)
        if draft.last.map({ simd_distance($0, point) < 1e-6 }) ?? false { return }
        draft.append(point)
        outlineDraft = draft
    }

    func removeLastDraftPoint() {
        guard outlineDraft?.isEmpty == false else { return }
        outlineDraft?.removeLast()
    }

    /// Plain-language reasons the drawn outline cannot become a body, empty when it can.
    var draftIssues: [String] {
        guard let draft = outlineDraft else { return [] }
        if draft.count < 3 { return ["Click at least three points."] }
        return PolygonRegion(outer: draft).validationIssues()
    }

    func finishOutlineDrawing() {
        guard let draft = outlineDraft, draftIssues.isEmpty else { return }
        let region = PolygonRegion(outer: draft)
        // Drawn in world coordinates, so the body starts unrotated at the origin and is then placed.
        let part = AssemblyPart(nextName("Outline"), shape: .outline, center: .zero, size: Point(0.01, 0.01))
            .reshaped(to: region)
        outlineDraft = nil
        add(part, action: "Draw Outline")
    }

    // MARK: Edit points

    func beginPointEditing(_ id: UUID) {
        guard canEdit, scene.parts.first(where: { $0.id == id })?.shape == .outline else { return }
        outlineDraft = nil
        placingGauge = false
        linkPlacement = nil
        select(id)
        editingOutline = id
    }

    func endPointEditing() { editingOutline = nil }

    /// Replaces a body's outline with `region` (in its own frame). The body's centre and box follow the new
    /// outline, so the unchanged points stay exactly where they were in the world.
    func reshape(_ id: UUID, to region: PolygonRegion, action: String) {
        let issues = region.validationIssues()
        guard issues.isEmpty else {
            error = "That change would make an invalid outline: " + issues.joined(separator: " ")
            return
        }
        guard let part = scene.parts.first(where: { $0.id == id }) else { return }
        let next = part.reshaped(to: region)
        edit(action) { $0.replace(part, with: next) }
    }

    func setMeshSize(_ id: UUID, _ size: Double?) {
        updatePart(id, action: "Set Mesh Size") { $0.outline?.meshSize = size }
    }

    // MARK: Convert, Cut, Join

    func convertToOutline(_ id: UUID) {
        guard let part = scene.parts.first(where: { $0.id == id }), part.shape != .outline else { return }
        if part.bondedLayer != nil {
            error = "A bonded-layer block cannot become an outline yet: region materials are not part of the outline model. Remove the bonded layers first."
            return
        }
        let next = part.reshaped(to: part.region())
        edit("Convert to Outline") { $0.replace(part, with: next) }
    }

    /// The region of `part`, expressed in the frame of `frame`.
    private func region(of part: AssemblyPart, inFrameOf frame: AssemblyPart) -> PolygonRegion {
        let source = part.region()
        let map = { (p: Point) in self.local(self.world(p, in: part), in: frame) }
        return PolygonRegion(outer: source.outer.map(map), holes: source.holes.map { $0.map(map) })
    }

    /// Whether `cut` and `join` can act on the current selection: exactly two bodies, the primary one first.
    var booleanPair: (target: AssemblyPart, tool: AssemblyPart)? {
        guard selectedParts.count == 2, let primary = selectedPart,
              let target = scene.parts.first(where: { $0.id == primary }),
              let tool = scene.parts.first(where: { $0.id != primary && selectedParts.contains($0.id) }) else { return nil }
        return (target, tool)
    }

    /// Why Cut or Join cannot be used on this pair, or nil.
    func booleanConflict(_ target: AssemblyPart, _ tool: AssemblyPart) -> String? {
        for part in [target, tool] where part.bondedLayer != nil {
            return "\(part.name) has bonded layers; region materials are not part of the outline model yet."
        }
        return nil
    }

    /// Removes the material of `tool` from `target`, then deletes `tool`. A target cut into separate pieces
    /// becomes several bodies with the same material and motion.
    func cut(target id: UUID, tool toolID: UUID) {
        guard let target = scene.parts.first(where: { $0.id == id }),
              let tool = scene.parts.first(where: { $0.id == toolID }) else { return }
        if let conflict = booleanConflict(target, tool) { error = conflict; return }
        let pieces = PolygonBoolean.cut(target.region(), by: region(of: tool, inFrameOf: target))
        apply(pieces, to: target, removing: tool, action: "Cut \(tool.name) out of \(target.name)",
              empty: "\(tool.name) covers all of \(target.name); nothing would be left.")
    }

    /// Merges `other` into `target` (target's name, material and motion are kept), then deletes `other`.
    func join(target id: UUID, with otherID: UUID) {
        guard let target = scene.parts.first(where: { $0.id == id }),
              let other = scene.parts.first(where: { $0.id == otherID }) else { return }
        if let conflict = booleanConflict(target, other) { error = conflict; return }
        let pieces = PolygonBoolean.join(target.region(), region(of: other, inFrameOf: target))
        if pieces.count > 1 {
            error = "\(target.name) and \(other.name) do not overlap or touch, so they cannot be joined into one body. Move one so they overlap, or connect them with a spring or breakable link."
            return
        }
        apply(pieces, to: target, removing: other, action: "Join \(other.name) into \(target.name)", empty: "The join produced no material.")
    }

    private func apply(_ pieces: [PolygonRegion], to target: AssemblyPart, removing tool: AssemblyPart, action: String, empty: String) {
        guard let first = pieces.first else { error = empty; return }
        if let issue = pieces.lazy.flatMap({ $0.validationIssues() }).first {
            error = "The result could not be used as an outline: \(issue)"
            return
        }
        guard scene.parts.count - 1 + pieces.count <= AssemblyScene.maximumParts else {
            error = "The result has \(pieces.count) separate pieces, which would exceed \(AssemblyScene.maximumParts) bodies."
            return
        }
        var extras: [AssemblyPart] = []
        for (n, piece) in pieces.dropFirst().enumerated() {
            var copy = target.reshaped(to: piece)
            copy.id = UUID()
            copy.name = "\(target.name) piece \(n + 2)"
            extras.append(copy)
        }
        edit(action) { scene in
            scene.removePart(tool.id)
            guard let current = scene.parts.first(where: { $0.id == target.id }) else { return }
            let reshaped = current.reshaped(to: first)
            scene.replace(current, with: reshaped)
            // Gauges left outside the new material are removed rather than snapped to an edge.
            let region = reshaped.outline!.region
            scene.gauges?.removeAll { gauge in
                gauge.body == target.id && !region.contains(gauge.materialLocation(in: reshaped))
            }
            if scene.gauges?.isEmpty == true { scene.gauges = nil }
            scene.parts.append(contentsOf: extras)
        }
        selectParts([target.id], primary: target.id)
        if pieces.count > 1 {
            error = "\(target.name) was cut into \(pieces.count) separate pieces; each is now its own body."
        }
    }
}
