import AppKit
import ImpactPhysics
import simd
import SwiftUI

let assemblyInk = Color(red: 0.85, green: 0.91, blue: 0.95)
let assemblyMint = Color(red: 0.43, green: 0.89, blue: 0.77)
let assemblyAmber = Color(red: 1, green: 0.67, blue: 0.39)
let assemblyPanel = Color(red: 0.085, green: 0.125, blue: 0.17)
private let crackColor = Color(red: 1, green: 0.39, blue: 0.33)

enum AssemblyField: String, CaseIterable {
    case strain = "Axial strain"
    case stress = "Von Mises stress"
    case maximum = "Maximum principal stress"
    case minimum = "Minimum principal stress"
    case pressure = "Mean pressure"
    case plastic = "Plastic strain"
    case damage = "Interface damage"
    case separation = "Crack separation"
    case speed = "Material speed"

    var signed: Bool { self == .strain || self == .pressure || self == .maximum || self == .minimum }
    var isStress: Bool { self == .stress || self == .pressure || self == .maximum || self == .minimum }

    var definition: String {
        switch self {
        case .strain: "Element Green–Lagrange axial strain. Negative is compression."
        case .stress: "Von Mises equivalent stress from the 3D Cauchy tensor in plane strain."
        case .maximum: "Largest principal Cauchy stress, including the out-of-plane component. Positive is tension."
        case .minimum: "Smallest principal Cauchy stress, including the out-of-plane component. Negative is compression."
        case .pressure: "Minus one third of the Cauchy stress trace. Positive is compression."
        case .plastic: "Accumulated equivalent plastic strain from the J2 history. Elastic bodies have no plastic field."
        case .damage: "Largest damage of adjacent cohesive faces (0 intact, 1 failed). Permanent layer bonds share nodes."
        case .separation: "Mean distance between matching face nodes, including slip. Failed faces can reclose."
        case .speed: "Magnitude of the mean nodal velocity in each element. Arrows show body mean velocity."
        }
    }

    var provenance: String {
        switch self {
        case .strain, .plastic, .damage, .separation: "Solver output"
        default: "Derived from the recorded solver state"
        }
    }

    func values(_ result: AssemblyReplayBody) -> [Double] {
        switch self {
        case .strain: return result.strain
        case .stress: return result.stress.map(\.equivalent)
        case .maximum: return result.stress.map(\.maximumPrincipal)
        case .minimum: return result.stress.map(\.minimumPrincipal)
        case .pressure: return result.stress.map(\.pressure)
        case .plastic: return result.plasticStrain
        case .damage: return result.damage
        case .separation: return []
        case .speed:
            let v = result.body.velocity
            return result.body.mesh.elements.map { simd_length((v[$0.a] + v[$0.b] + v[$0.c]) / 3) }
        }
    }

    func defaultLimit(metal: Bool) -> Double {
        switch self {
        case .strain: metal ? 0.01 : 0.08
        case .stress, .maximum, .minimum, .pressure: metal ? 300e6 : 60e3
        case .plastic: metal ? 0.025 : 0.08
        case .damage: 1
        case .separation: 0.010
        case .speed: metal ? 30 : 1.5
        }
    }

    func display(_ value: Double, limit: Double) -> String {
        switch self {
        case .stress, .maximum, .minimum, .pressure:
            let mpa = limit >= 1e6
            return String(format: "%.3g %@", value / (mpa ? 1e6 : 1000), mpa ? "MPa" : "kPa")
        case .strain, .plastic: return String(format: "%.3g%%", value * 100)
        case .separation: return String(format: "%.3g mm", value * 1000)
        case .speed: return String(format: "%.3g m/s", value)
        case .damage: return String(format: "%.3g", value)
        }
    }

    func shade(_ bin: Int) -> Color {
        let strength = Double(abs(bin)) / 6
        let base = (r: 0.16, g: 0.21, b: 0.26)
        let end = bin < 0 ? (r: 0.34, g: 0.67, b: 0.98)
            : (self == .damage || self == .separation ? (r: 1.0, g: 0.33, b: 0.29) : (r: 1.0, g: 0.71, b: 0.28))
        return Color(red: base.r + strength * (end.r - base.r), green: base.g + strength * (end.g - base.g),
                     blue: base.b + strength * (end.b - base.b))
    }

    func bin(_ value: Double, limit: Double) -> Int {
        Int((6 * min(1, max(-1, value / limit))).rounded())
    }

    func limit(for range: AssemblyFieldRange, frame: AssemblyReplayFrame?, metal: Bool) -> Double {
        let standard = defaultLimit(metal: metal)
        if self == .damage { return 1 }
        switch range {
        case .detail: return standard / 10
        case .standard: return standard
        case .wide: return standard * 4
        case .automatic:
            let peak = frame?.bodies.reduce(0.0) { prior, body in
                let values = self == .separation ? body.cracks.map(\.separation) : self.values(body)
                return max(prior, values.lazy.map(abs).max() ?? 0)
            } ?? 0
            return peak > 0 ? peak : standard
        }
    }
}

enum AssemblyFieldRange: String, CaseIterable {
    case standard = "Standard"
    case detail = "Detail (10× narrower)"
    case wide = "Wide (4× wider)"
    case automatic = "Fit current frame"
}

struct AssemblyFieldLegend: View {
    let field: AssemblyField
    let limit: Double

    var body: some View {
        let low = field.signed ? -limit : 0
        HStack(spacing: 6) {
            Text(field.display(low, limit: limit))
            HStack(spacing: 0) {
                ForEach((field.signed ? -6 : 0)...6, id: \.self) { bin in field.shade(bin) }
            }.frame(width: 108, height: 8).clipShape(.capsule)
            Text(field.display(limit, limit: limit))
            if field.signed { Text("· center 0").foregroundStyle(.secondary) }
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color scale \(field.display(low, limit: limit)) to \(field.display(limit, limit: limit))")
        .help("Values outside the scale use the end colors. Local readings retain their full values.")
    }
}

func assemblyColor(_ index: Int) -> Color {
    let palette = [assemblyMint, assemblyAmber, Color(red: 0.55, green: 0.75, blue: 1),
                   Color(red: 0.83, green: 0.67, blue: 0.98),
                   .pink, .green, .cyan, .yellow]
    return palette[index % palette.count]
}

private struct AssemblyCamera {
    var center: Point
    var scale: Double

    init(center: Point = .zero, scale: Double = 1_250) {
        self.center = center
        self.scale = scale
    }

    @MainActor init(fitting indices: [Int], in size: CGSize, experiment: AssemblyExperiment) {
        var lower = Point(repeating: .infinity)
        var upper = Point(repeating: -.infinity)
        for index in indices {
            for point in experiment.displayedBody(index).position where point.x.isFinite && point.y.isFinite {
                lower = Point(min(lower.x, point.x), min(lower.y, point.y))
                upper = Point(max(upper.x, point.x), max(upper.y, point.y))
            }
        }
        guard lower.x.isFinite else {
            self.init()
            return
        }
        self.init()
        center = (upper + lower) / 2
        let span = upper - lower
        scale = Self.boundedScale(min(max(1, size.width - 80) / max(0.001, span.x),
                                     max(1, size.height - 96) / max(0.001, span.y)))
        center.y += 10 / scale
    }

    mutating func zoom(by factor: Double, at location: CGPoint, in viewport: CGSize) {
        let before = projection(in: viewport).world(location)
        scale = Self.boundedScale(scale * factor)
        center += before - projection(in: viewport).world(location)
    }

    func projection(in viewport: CGSize) -> AssemblyProjection {
        AssemblyProjection(center: center, viewport: viewport, scale: scale)
    }

    private static func boundedScale(_ scale: Double) -> Double {
        min(160_000, max(24, scale))
    }
}

private struct AssemblyProjection {
    let center: Point
    let viewport: CGSize
    let scale: Double

    func screen(_ p: Point) -> CGPoint {
        CGPoint(x: viewport.width / 2 + (p.x - center.x) * scale,
                y: viewport.height / 2 - (p.y - center.y) * scale)
    }

    func world(_ p: CGPoint) -> Point {
        center + worldDelta(CGSize(width: p.x - viewport.width / 2, height: p.y - viewport.height / 2))
    }

    func worldDelta(_ translation: CGSize) -> Point {
        Point(translation.width / scale, -translation.height / scale)
    }
}

struct AssemblyCanvas: View {
    private enum Handle: CaseIterable {
        case rotate, resize
    }

    private enum Drag {
        case pan(AssemblyCamera)
        case body(AssemblyPart, Handle)
        case move([AssemblyPart], anchor: AssemblyPart)
        case placement
        /// Dragging one end of the selected connection across its body.
        case linkAnchor(AssemblyConnection, second: Bool)
    }

    let experiment: AssemblyExperiment
    let field: AssemblyField
    var showMesh: Bool
    var showInitial = false
    var showVelocity = false
    var limit = 1.0
    @State private var camera = AssemblyCamera()
    @State private var drag: Drag?
    @State private var dragStart = CGPoint.zero
    /// The connection as it would be after the anchor drag in progress.
    @State private var anchorPreview: AssemblyConnection?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            canvas(in: size)
                .overlay(alignment: .topTrailing) { cameraControls(in: size).padding(8) }
                .onAppear { fitAssembly(in: size) }
                .onChange(of: experiment.cameraRevision) {
                    cancelDrag()
                    fitAssembly(in: size)
                }
                .onChange(of: experiment.scene.parts.count) { old, new in
                    if new > old { fitAssembly(in: size) }
                }
                .onChange(of: experiment.canEdit) {
                    if !experiment.canEdit { cancelDrag() }
                }
        }
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func canvas(in viewport: CGSize) -> some View {
        let projection = camera.projection(in: viewport)
        let preview = experiment.previewParts
        let selected = selectedPart
        let drawOrder = experiment.displayIndices.reversed()
        return Canvas { context, size in
            drawGrid(context, size: size, projection: projection)
            for i in drawOrder {
                let part = experiment.scene.parts[i]
                drawBody(i, context: context, projection: projection, preview: preview[part.id])
            }
            if showInitial, let first = experiment.frames.first {
                for body in first.bodies {
                    let points = body.body.position.map(projection.screen)
                    context.stroke(edgePath(body.body.mesh.boundary, nodes: points),
                                   with: .color(assemblyInk.opacity(0.65)),
                                   style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            }
            drawConnections(context, projection: projection, preview: preview)
            if experiment.canEdit, let link = anchorPreview ?? selectedConnection {
                drawAnchorHandles(link, in: context, projection: projection)
            }
            drawGauges(context, projection: projection, preview: preview)
            if experiment.canEdit {
                for part in experiment.scene.parts where part.velocity != .zero {
                    let shown = preview[part.id] ?? part
                    drawVelocity(shown.velocity, at: shown.center, context: context, projection: projection)
                }
            }
            if let frame = experiment.frame {
                if showVelocity {
                    for state in frame.bodies {
                        drawVelocity(state.body.centerVelocity, at: state.body.centerOfMass, context: context, projection: projection)
                    }
                }
                for contact in frame.contacts {
                    guard let p = contact.position, contact.force > 0 else { continue }
                    let at = projection.screen(p)
                    let dot = Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(.white))
                    context.stroke(dot, with: .color(.black), lineWidth: 1)
                }
                if let i = experiment.probeBody, let e = experiment.probeElement {
                    let body = frame.bodies[i].body
                    let triangle = body.mesh.elements[e]
                    let point = (body.position[triangle.a] + body.position[triangle.b] + body.position[triangle.c]) / 3
                    let at = projection.screen(point)
                    let dot = Path(ellipseIn: CGRect(x: at.x - 5, y: at.y - 5, width: 10, height: 10))
                    context.stroke(dot, with: .color(.white), lineWidth: 1.5)
                }
            }
            if let anchor = experiment.linkPlacement?.first { drawAnchor(anchor, in: context, projection: projection) }
            if experiment.canEdit, !experiment.placingGauge, experiment.linkPlacement == nil,
               experiment.selectedParts.count == 1, let part = selected,
               handlesAreVisible(for: part, projection: projection) {
                drawHandles(for: part, in: context, projection: projection)
            }
            let y = size.height - 22
            let x = 22.0
            let millimetres = scaleBarMillimetres(at: projection.scale)
            let end = x + projection.scale * millimetres / 1_000
            context.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: y - 4))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: end, y: y))
                p.addLine(to: CGPoint(x: end, y: y - 4))
            }, with: .color(assemblyInk.opacity(0.6)))
            let caption = millimetres >= 1_000 ? "\((millimetres / 1_000).formatted()) m" : "\(millimetres.formatted()) mm"
            context.draw(Text(caption).font(.caption2.monospaced()), at: CGPoint(x: x, y: y - 7), anchor: .bottomLeading)
            if experiment.frame != nil {
                context.draw(Text("True scale · 1×").font(.caption2.monospaced()),
                             at: CGPoint(x: size.width - 19, y: y), anchor: .trailing)
            }
        }
        .accessibilityLabel("Assembly workspace")
        .accessibilityHint(experiment.frame == nil
            ? "Scroll or pinch to zoom. Drag the background to pan. Drag a body to move it. Shift-click adds to the selection. Select a connection, then drag its white end circles to move its anchors."
            : "Scroll or pinch to zoom. Drag to pan. Click a triangle to inspect its recorded field value.")
        .overlay {
            AssemblyCanvasInput { event, location in
                handle(event, at: location, viewport: viewport)
            }
        }
    }

    private func cameraControls(in size: CGSize) -> some View {
        HStack(spacing: 5) {
            Button("Fit Assembly", systemImage: "arrow.up.left.and.arrow.down.right") { fitAssembly(in: size) }
                .help("Fit all bodies in view")
            Button("Zoom to Selection", systemImage: "scope") {
                let indices = experiment.displayIndices.filter { experiment.selectedParts.contains(experiment.scene.parts[$0].id) }
                camera = AssemblyCamera(fitting: indices, in: size, experiment: experiment)
            }
            .disabled(experiment.selectedParts.isEmpty)
            .help("Fit the selected body in view")
            Button("Reset View", systemImage: "arrow.counterclockwise") { camera = AssemblyCamera() }
                .help("Center the view on the assembly origin at the default scale")
        }
        .controlSize(.small)
    }

    private func fitAssembly(in size: CGSize) {
        camera = AssemblyCamera(fitting: Array(0..<experiment.simulation.bodyCount), in: size, experiment: experiment)
    }

    private var selectedPart: AssemblyPart? {
        experiment.previewPart ?? experiment.selectedIndex.map { experiment.scene.parts[$0] }
    }

    private func handle(_ event: NSEvent, at location: CGPoint, viewport: CGSize) {
        let projection = camera.projection(in: viewport)
        switch event.type {
        case .leftMouseDown:
            beginDrag(at: location, projection: projection, additive: event.modifierFlags.contains(.shift))
        case .leftMouseDragged:
            updateDrag(at: location, projection: projection)
        case .leftMouseUp:
            endDrag(at: location, projection: projection)
        case .magnify where drag == nil:
            camera.zoom(by: exp(Double(event.magnification)), at: location, in: viewport)
        case .scrollWheel where drag == nil:
            let x = event.scrollingDeltaX, y = event.scrollingDeltaY
            if event.modifierFlags.contains(.option) || abs(x) > abs(y) {
                let scale = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
                camera.center -= projection.worldDelta(CGSize(width: scale * x, height: -scale * y))
            } else if event.momentumPhase.isEmpty {
                let sensitivity = event.hasPreciseScrollingDeltas ? 0.012 : 0.095
                let exponent = min(0.5, max(-0.5, Double(y) * sensitivity))
                camera.zoom(by: exp(exponent), at: location, in: viewport)
            }
        default:
            break
        }
    }

    private func beginDrag(at location: CGPoint, projection: AssemblyProjection, additive: Bool) {
        cancelDrag()
        dragStart = location
        let world = projection.world(location)
        if experiment.placingGauge || experiment.linkPlacement != nil {
            drag = .placement
        } else if experiment.canEdit, let link = selectedConnection,
                  let end = [false, true].first(where: { second in
                      guard let point = anchorPoint(link, second: second) else { return false }
                      let screen = projection.screen(point)
                      return hypot(screen.x - location.x, screen.y - location.y) <= 10
                  }) {
            drag = .linkAnchor(link, second: end)
            anchorPreview = link
        } else if additive, let id = part(at: world) {
            experiment.select(id, adding: true)
        } else if experiment.canEdit, experiment.selectedParts.count == 1,
                  let part = selectedPart, handlesAreVisible(for: part, projection: projection),
                  let handle = Handle.allCases.first(where: {
                      let position = handlePosition($0, part: part, projection: projection)
                      return hypot(position.x - location.x, position.y - location.y) <= 11
                  }) {
            drag = .body(part, handle)
        } else if let id = part(at: world), let anchor = experiment.scene.parts.first(where: { $0.id == id }) {
            if !experiment.selectedParts.contains(id) || !experiment.canEdit { experiment.select(id) }
            drag = experiment.canEdit ? .move(experiment.selectedBodyList, anchor: anchor) : .pan(camera)
        } else {
            drag = .pan(camera)
        }
    }

    private func updateDrag(at location: CGPoint, projection: AssemblyProjection) {
        let translation = CGSize(width: location.x - dragStart.x, height: location.y - dragStart.y)
        switch drag {
        case .pan(let start):
            camera.center = start.center - projection.worldDelta(translation)
        case .move(let originals, let anchor) where experiment.canEdit:
            experiment.previewMove(originals, anchor: anchor, delta: projection.worldDelta(translation))
        case .linkAnchor(let original, let second) where experiment.canEdit:
            anchorPreview = moved(original, second: second, to: projection.world(location))
        case .body(let original, let handle) where experiment.canEdit:
            var part = original
            switch handle {
            case .rotate:
                let initial = projection.world(dragStart) - part.center
                let current = projection.world(location) - part.center
                guard hypot(current.x, current.y) * projection.scale >= 5 else { return }
                let radians = atan2(current.y, current.x) - atan2(initial.y, initial.x)
                part.angle = (original.angle + radians * 180 / .pi).remainder(dividingBy: 360)
            case .resize:
                let delta = rotated(projection.worldDelta(translation), by: -part.angle)
                let size = part.size + 2 * delta
                let mesh = part.refinement ?? experiment.scene.resolution
                let widths = part.widthRange(resolution: mesh), heights = part.sizeRange(resolution: mesh)
                part.size = Point(min(widths.upperBound, max(widths.lowerBound, size.x)),
                                  min(heights.upperBound, max(heights.lowerBound, size.y)))
                experiment.fitWall(of: &part)
            }
            experiment.previewParts = [part.id: part]
        default:
            break
        }
    }

    private func endDrag(at location: CGPoint, projection: AssemblyProjection) {
        defer { cancelDrag() }
        let distance = hypot(location.x - dragStart.x, location.y - dragStart.y)
        switch drag {
        case .placement where distance < 4:
            let point = projection.world(location)
            if let id = part(at: point) {
                if experiment.placingGauge { experiment.addGauge(body: id, at: point) }
                else { experiment.pickLinkAnchor(on: id, at: point) }
            }
        case .move(let parts, let anchor) where experiment.canEdit:
            if distance >= 2 {
                updateDrag(at: location, projection: projection)
                experiment.commitPreview(parts.count == 1 ? "Move Body" : "Move Bodies")
            } else {
                experiment.select(anchor.id)
            }
        case .linkAnchor(let original, let second) where distance >= 2 && experiment.canEdit:
            let next = moved(original, second: second, to: projection.world(location))
            experiment.updateConnection(original.id, action: "Move Link Anchor") {
                $0.firstAnchor = next.firstAnchor
                $0.secondAnchor = next.secondAnchor
            }
        case .body(_, let handle) where distance >= 2 && experiment.canEdit:
            updateDrag(at: location, projection: projection)
            experiment.commitPreview(handle == .rotate ? "Rotate Body" : "Resize Body")
        case .pan where distance < 4 && experiment.frame != nil:
            let hit = element(at: projection.world(location))
            experiment.probeBody = hit?.body
            experiment.probeElement = hit?.element
        default:
            break
        }
    }

    private func cancelDrag() {
        drag = nil
        anchorPreview = nil
        experiment.previewParts.removeAll()
    }

    private var selectedConnection: AssemblyConnection? {
        experiment.scene.connections.first { $0.id == experiment.selectedConnection }
    }

    /// World position of a connection end, from its local fractions of the body half-size.
    private func anchorPoint(_ link: AssemblyConnection, second: Bool) -> Point? {
        guard let part = experiment.scene.parts.first(where: { $0.id == (second ? link.second : link.first) }) else { return nil }
        let fractions = second ? link.secondAnchor : link.firstAnchor
        return part.center + rotated(fractions * part.size / 2, by: part.angle)
    }

    /// The connection with one end moved to a world point, kept on its own body's local frame
    /// and within the same limits the numeric fields enforce (±100% of the half-size, band inside the body).
    private func moved(_ link: AssemblyConnection, second: Bool, to world: Point) -> AssemblyConnection {
        guard let part = experiment.scene.parts.first(where: { $0.id == (second ? link.second : link.first) }) else { return link }
        let local = rotated(world - part.center, by: -part.angle) / (part.size / 2)
        var gridded = local
        if experiment.gridStep > 0 {
            // Snap in millimetres along the body's own axes.
            let step = Point(repeating: experiment.gridStep) / (part.size / 2)
            gridded = (local / step).rounded(.toNearestOrAwayFromZero) * step
        }
        let yLimit = max(0, 1 - link.span / 2)
        let fractions = Point(min(1, max(-1, gridded.x)), min(yLimit, max(-yLimit, gridded.y)))
        var next = link
        if second { next.secondAnchor = fractions } else { next.firstAnchor = fractions }
        return next
    }

    private func drawAnchorHandles(_ link: AssemblyConnection, in context: GraphicsContext, projection: AssemblyProjection) {
        guard let a = anchorPoint(link, second: false), let b = anchorPoint(link, second: true) else { return }
        let start = projection.screen(a), end = projection.screen(b)
        if anchorPreview != nil {
            context.stroke(Path { p in p.move(to: start); p.addLine(to: end) }, with: .color(.white),
                           style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
        }
        for point in [start, end] {
            let ring = Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
            context.fill(ring, with: .color(assemblyPanel))
            context.stroke(ring, with: .color(.white), lineWidth: 2)
        }
    }

    private func drawAnchor(_ anchor: WorkshopLinkPlacement.Anchor, in context: GraphicsContext, projection: AssemblyProjection) {
        guard let part = experiment.scene.parts.first(where: { $0.id == anchor.body }) else { return }
        let point = projection.screen(part.center + rotated(anchor.fractions * part.size / 2, by: part.angle))
        let ring = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
        context.fill(ring, with: .color(assemblyPanel))
        context.stroke(ring, with: .color(assemblyMint), lineWidth: 2)
    }

    private func rotated(_ point: Point, by degrees: Double) -> Point {
        let radians = degrees * .pi / 180
        let c = cos(radians), s = sin(radians)
        return Point(c * point.x - s * point.y, s * point.x + c * point.y)
    }

    private func handlePosition(_ handle: Handle, part: AssemblyPart, projection: AssemblyProjection) -> CGPoint {
        let half = part.size / 2
        let local = handle == .resize ? half : Point(0, half.y + 24 / projection.scale)
        return projection.screen(part.center + rotated(local, by: part.angle))
    }

    private func handlesAreVisible(for part: AssemblyPart, projection: AssemblyProjection) -> Bool {
        if case .body = drag { return true }
        return min(part.size.x, part.size.y) * projection.scale >= 22
    }

    private func drawHandles(for part: AssemblyPart, in context: GraphicsContext, projection: AssemblyProjection) {
        let rotation = handlePosition(.rotate, part: part, projection: projection)
        let resize = handlePosition(.resize, part: part, projection: projection)
        let edge = projection.screen(part.center + rotated(Point(0, part.size.y / 2), by: part.angle))
        context.stroke(Path { path in
            path.move(to: edge)
            path.addLine(to: rotation)
        }, with: .color(.white), lineWidth: 1)
        let rotationDisc = Path(ellipseIn: CGRect(x: rotation.x - 9, y: rotation.y - 9, width: 18, height: 18))
        let resizeSquare = Path(roundedRect: CGRect(x: resize.x - 6, y: resize.y - 6, width: 12, height: 12), cornerRadius: 2)
        for shape in [rotationDisc, resizeSquare] {
            context.fill(shape, with: .color(assemblyPanel))
            context.stroke(shape, with: .color(.white), lineWidth: 1.5)
        }
        context.draw(Text(Image(systemName: "arrow.clockwise")).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white), at: rotation)
    }

    private func scaleBarMillimetres(at scale: Double) -> Double {
        let desiredMillimetres = 70_000 / scale
        let magnitude = pow(10, floor(log10(desiredMillimetres)))
        let fraction = desiredMillimetres / magnitude
        return (fraction >= 5 ? 5 : fraction >= 2 ? 2 : 1) * magnitude
    }

    private func drawGrid(_ context: GraphicsContext, size: CGSize, projection: AssemblyProjection) {
        let low = projection.world(CGPoint(x: 12, y: size.height - 39))
        let high = projection.world(CGPoint(x: size.width - 12, y: 18))
        let spacing = scaleBarMillimetres(at: projection.scale) / 1_000
        let snap = experiment.canEdit ? experiment.gridStep : 0
        let step = snap > 0 ? max(1, (spacing / snap).rounded()) * snap : spacing
        func lines(_ minValue: Double, _ maxValue: Double) -> Range<Int> {
            let start = Int(ceil(minValue / step)), end = Int(floor(maxValue / step)) + 1
            return start..<max(start, end)
        }
        let grid = Path { p in
            for i in lines(low.x, high.x) {
                let x = projection.screen(Point(Double(i) * step, 0)).x
                p.move(to: CGPoint(x: x, y: 18))
                p.addLine(to: CGPoint(x: x, y: size.height - 38))
            }
            for j in lines(low.y, high.y) {
                let y = projection.screen(Point(0, Double(j) * step)).y
                p.move(to: CGPoint(x: 12, y: y))
                p.addLine(to: CGPoint(x: size.width - 12, y: y))
            }
        }
        context.stroke(grid, with: .color(assemblyInk.opacity(0.08)))
    }

    private func previewPosition(_ point: Point, relativeTo part: AssemblyPart, preview: AssemblyPart?) -> Point {
        guard let preview, preview.id == part.id else { return point }
        if preview.angle == part.angle && preview.size == part.size {
            return point + (preview.center - part.center)
        }
        var local = rotated(point - part.center, by: -part.angle)
        if part.shape == .enclosure {
            // Keep both the outer dimensions and the actual wall thickness in the preview.
            func resized(_ component: Double, from old: Double, to new: Double) -> Double {
                let inner = old / 2 - part.wall
                let nextInner = new / 2 - preview.wall
                let magnitude = abs(component)
                let mapped = magnitude <= inner ? magnitude * nextInner / inner
                    : nextInner + (magnitude - inner) * preview.wall / part.wall
                return component.sign == .minus ? -mapped : mapped
            }
            local = Point(resized(local.x, from: part.size.x, to: preview.size.x),
                          resized(local.y, from: part.size.y, to: preview.size.y))
        } else {
            local *= preview.size / part.size
        }
        return preview.center + rotated(local, by: preview.angle)
    }

    private func drawVelocity(_ velocity: Point, at position: Point, context: GraphicsContext, projection: AssemblyProjection) {
        let speed = simd_length(velocity)
        guard speed > 1e-10 else { return }
        let direction = Point(velocity.x, -velocity.y) / speed
        let normal = Point(-direction.y, direction.x)
        let center = projection.screen(position)
        let start = Point(center.x, center.y)
        let end = start + direction * min(57, 26 + 10 * log1p(speed))
        let base = end - 7 * direction
        context.stroke(Path { path in
            path.move(to: CGPoint(x: start.x, y: start.y))
            path.addLine(to: CGPoint(x: end.x, y: end.y))
            path.move(to: CGPoint(x: base.x + 4 * normal.x, y: base.y + 4 * normal.y))
            path.addLine(to: CGPoint(x: end.x, y: end.y))
            path.addLine(to: CGPoint(x: base.x - 4 * normal.x, y: base.y - 4 * normal.y))
        }, with: .color(assemblyInk), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func drawBody(_ i: Int, context: GraphicsContext, projection: AssemblyProjection, preview: AssemblyPart?) {
        let part = experiment.scene.parts[i]
        let body = experiment.displayedBody(i)
        let positions = body.position.map { previewPosition($0, relativeTo: part, preview: preview) }
        let nodes = positions.map(projection.screen)
        let values = experiment.frame.map { field.values($0.bodies[i]) } ?? []
        let color = assemblyColor(i)
        var buckets = Array(repeating: Path(), count: 13)
        for (index, triangle) in body.mesh.elements.enumerated() {
            let value = values.isEmpty ? 0 : values[index]
            let slot = 6 + field.bin(value, limit: limit)
            buckets[slot].move(to: nodes[triangle.a])
            buckets[slot].addLine(to: nodes[triangle.b])
            buckets[slot].addLine(to: nodes[triangle.c])
            buckets[slot].closeSubpath()
        }
        for (i, path) in buckets.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(values.isEmpty ? color.opacity(0.20) : field.shade(i - 6)))
            if showMesh { context.stroke(path, with: .color(assemblyInk.opacity(0.17)), lineWidth: 0.45) }
        }
        if showMesh, experiment.canEdit, preview == nil {
            let thin = experiment.meshQuality[i].thinTriangles
            let warning = Path { path in
                for triangle in thin {
                    path.move(to: nodes[triangle.a])
                    path.addLine(to: nodes[triangle.b])
                    path.addLine(to: nodes[triangle.c])
                    path.closeSubpath()
                }
            }
            context.stroke(warning, with: .color(assemblyAmber.opacity(0.85)), lineWidth: 1)
        }
        let outline = edgePath(body.mesh.boundary, nodes: nodes)
        let active = experiment.frame?.contacts.contains { $0.force > 0 && ($0.pair.x == i || $0.pair.y == i) } ?? false
        let selected = experiment.selectedParts.contains(part.id)
        context.stroke(outline, with: .color(active ? .white : color), lineWidth: selected ? 2.3 : 1.3)
        if let support = part.support { drawSupport(support, part: preview ?? part, context: context, projection: projection) }
        for line in body.mesh.interfaceLines {
            guard let first = line.first else { continue }
            let bond = Path { path in
                path.move(to: nodes[first])
                for node in line.dropFirst() { path.addLine(to: nodes[node]) }
            }
            context.stroke(bond, with: .color(assemblyInk.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
        }
        let cracks = experiment.frame?.bodies[i].cracks ?? []
        for crack in cracks {
            let shade = field == .separation ? field.shade(field.bin(crack.separation, limit: limit)) : crackColor
            let faces = edgePath([crack.first, crack.second], nodes: nodes)
            context.stroke(faces, with: .color(shade.opacity(crack.failed ? 1 : 0.45 + 0.5 * crack.damage)),
                           style: StrokeStyle(lineWidth: crack.failed ? 2 : 1, dash: crack.failed ? [] : [3, 2]))
        }
        let center = previewPosition(body.centerOfMass, relativeTo: part, preview: preview)
        let bottom = positions.map(\.y).min()!
        let top = positions.map(\.y).max()!
        let interior = experiment.scene.parts.enumerated().contains { j, other in
            other.shape == .enclosure && j != i
                && abs(experiment.displayedBody(j).centerOfMass.x - center.x) < other.size.x * 0.38
                && abs(experiment.displayedBody(j).centerOfMass.y - center.y) < other.size.y * 0.38
        }
        let topLabel = i.isMultiple(of: 2) && !(selected && experiment.canEdit)
        var labelPosition = projection.screen(Point(center.x, interior ? center.y : topLabel ? top : bottom))
        if !interior { labelPosition.y += topLabel ? -14 : 14 }
        let label = Text(part.name).font(.caption.weight(.semibold)).foregroundStyle(color)
        context.draw(label, at: labelPosition)
        if selected {
            // The selected body also says whether material fracture is on, in the same place as its name.
            let status = part.fractureStatus
            let tag = Text(status.tag).font(.caption2.weight(.semibold))
                .foregroundStyle(status == .on ? assemblyAmber : assemblyInk.opacity(0.75))
            context.draw(tag, at: CGPoint(x: labelPosition.x, y: labelPosition.y + (topLabel ? -12 : 12)))
        }
    }

    /// Hatching marks a held edge, or the whole outline of a fixed support, in the usual engineering style.
    private func drawSupport(_ support: AssemblyPart.Support, part: AssemblyPart, context: GraphicsContext, projection: AssemblyProjection) {
        let h = part.size / 2
        let edges: [(Point, Point)] = switch support {
        case .fixed where part.shape == .round: []
        case .fixed: [(Point(-h.x, -h.y), Point(h.x, -h.y))]
        case .clampLeft: [(Point(-h.x, -h.y), Point(-h.x, h.y))]
        case .clampRight: [(Point(h.x, h.y), Point(h.x, -h.y))]
        case .clampBottom: [(Point(h.x, -h.y), Point(-h.x, -h.y))]
        case .clampTop: [(Point(-h.x, h.y), Point(h.x, h.y))]
        }
        for (a, b) in edges {
            let start = projection.screen(part.center + rotated(a, by: part.angle))
            let end = projection.screen(part.center + rotated(b, by: part.angle))
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 1 else { continue }
            // Outward normal on the screen (screen y points down).
            let ux = (end.x - start.x) / length, uy = (end.y - start.y) / length
            let nx = -uy, ny = ux
            let ticks = Path { path in
                path.move(to: start)
                path.addLine(to: end)
                var d = 0.0
                while d <= length {
                    let base = CGPoint(x: start.x + ux * d, y: start.y + uy * d)
                    path.move(to: base)
                    path.addLine(to: CGPoint(x: base.x + 7 * nx - 5 * ux, y: base.y + 7 * ny - 5 * uy))
                    d += 9
                }
            }
            context.stroke(ticks, with: .color(assemblyInk.opacity(0.8)), lineWidth: 1.2)
        }
        if support == .fixed {
            let label = Text("fixed").font(.caption2).foregroundStyle(assemblyInk.opacity(0.7))
            context.draw(label, at: projection.screen(part.center))
        }
    }

    private func drawConnections(_ context: GraphicsContext, projection: AssemblyProjection, preview: [UUID: AssemblyPart]) {
        let scene = experiment.scene
        for link in experiment.displayedLinks {
            let connection = scene.connections[link.connection]
            let selected = experiment.selectedConnection == connection.id
            let first = scene.parts.first { $0.id == connection.first }
            let second = scene.parts.first { $0.id == connection.second }
            let a = projection.screen(first.map { previewPosition(link.start, relativeTo: $0, preview: preview[$0.id]) } ?? link.start)
            let b = projection.screen(second.map { previewPosition(link.end, relativeTo: $0, preview: preview[$0.id]) } ?? link.end)
            if link.damage == 1 {
                for point in [a, b] {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                                 with: .color(assemblyAmber))
                }
                continue
            }
            let color = connection.kind == .spring ? assemblyInk : (link.damage > 0 ? assemblyAmber : assemblyMint)
            let path = Path { p in
                p.move(to: a)
                p.addLine(to: b)
            }
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: selected ? 2.8 : 1.7, dash: connection.kind == .spring ? [4, 2] : []))
        }
    }

    private func part(at point: Point) -> UUID? {
        element(at: point).map { experiment.scene.parts[$0.body].id }
    }

    private func element(at point: Point) -> (body: Int, element: Int)? {
        for i in experiment.displayIndices {
            let body = experiment.displayedBody(i)
            for (index, triangle) in body.mesh.elements.enumerated() {
                let a = body.position[triangle.a], b = body.position[triangle.b], c = body.position[triangle.c]
                func side(_ start: Point, _ end: Point) -> Double {
                    let edge = end - start, offset = point - start
                    return edge.x * offset.y - edge.y * offset.x
                }
                if min(side(a, b), side(b, c), side(c, a)) >= -1e-12 { return (i, index) }
            }
        }
        return nil
    }

    private func drawGauges(_ context: GraphicsContext, projection: AssemblyProjection, preview: [UUID: AssemblyPart]) {
        for (index, gauge) in experiment.gauges.enumerated() {
            let position = experiment.displayedGauge(index).position
            let part = experiment.scene.parts.first { $0.id == gauge.body }
            let at = projection.screen(part.map { previewPosition(position, relativeTo: $0, preview: preview[$0.id]) } ?? position)
            let dot = Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8))
            context.fill(dot, with: .color(.black))
            context.stroke(dot, with: .color(.white), lineWidth: 1.5)
            context.draw(Text(gauge.name).font(.caption2.monospaced()).foregroundStyle(.white),
                         at: CGPoint(x: at.x + 7, y: at.y - 7), anchor: .bottomLeading)
        }
    }
}

func edgePath(_ edges: [ImpactPhysics.Edge], nodes: [CGPoint]) -> Path {
    Path { path in
        for edge in edges {
            path.move(to: nodes[edge.a])
            path.addLine(to: nodes[edge.b])
        }
    }
}

private struct AssemblyCanvasInput: NSViewRepresentable {
    let handle: (NSEvent, CGPoint) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.toolTip = "Scroll or pinch to zoom. Drag the background to pan. Drag a body to move it. The circle rotates and the square resizes. Shift-click adds to the selection."
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.handle = handle
    }

    final class InputView: NSView {
        var handle: ((NSEvent, CGPoint) -> Void)?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            route(event)
        }

        override func mouseDragged(with event: NSEvent) { route(event) }
        override func mouseUp(with event: NSEvent) { route(event) }
        override func scrollWheel(with event: NSEvent) { route(event) }
        override func magnify(with event: NSEvent) { route(event) }

        private func route(_ event: NSEvent) {
            handle?(event, convert(event.locationInWindow, from: nil))
        }
    }
}
