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
    case pressure = "Mean pressure"
    case plastic = "Plastic strain"
    case damage = "Interface damage"
    case separation = "Crack separation"

    var scale: Double {
        switch self {
        case .strain, .plastic: 0.08
        case .stress, .pressure: 60_000
        case .damage: 1
        case .separation: 0.010
        }
    }

    var legend: String {
        switch self {
        case .strain: "Axial strain · −8% compression / +8% tension"
        case .stress: "Cauchy von Mises stress · 0–60 kPa"
        case .pressure: "Cauchy pressure · −60 kPa tension / +60 kPa compression"
        case .plastic: "Accumulated equivalent plastic strain · 0–8%"
        case .damage: "Interface damage · 0–1 · red lines mark failed faces"
        case .separation: "Face separation · 0–10 mm · color on faces"
        }
    }

    func values(_ index: Int, in simulation: AssemblySimulation) -> [Double] {
        switch self {
        case .strain: simulation.strain(index)
        case .stress: simulation.stress(index)
        case .pressure: simulation.pressure(index)
        case .plastic: simulation.plasticStrain(index)
        case .damage: simulation.materialDamage(index)
        case .separation: []
        }
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
            for point in experiment.simulation.body(index).position where point.x.isFinite && point.y.isFinite {
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
        case body(AssemblyPart, Handle?)
        case gauge
    }

    let experiment: AssemblyExperiment
    let field: AssemblyField
    var showMesh: Bool
    @State private var camera = AssemblyCamera()
    @State private var drag: Drag?
    @State private var dragStart = CGPoint.zero

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
                .onChange(of: experiment.canEdit) {
                    if !experiment.canEdit { experiment.previewPart = nil }
                }
        }
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func canvas(in viewport: CGSize) -> some View {
        let projection = camera.projection(in: viewport)
        let preview = experiment.previewPart
        let selected = selectedPart
        return Canvas { context, size in
            drawGrid(context, size: size, projection: projection)
            for i in 0..<experiment.simulation.bodyCount {
                drawBody(i, context: context, projection: projection, preview: preview)
            }
            drawConnections(context, projection: projection, preview: preview)
            drawGauges(context, projection: projection, preview: preview)
            if experiment.canEdit, !experiment.placingGauge, let part = selected,
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
            if !experiment.canEdit {
                context.draw(Text(field.legend).font(.caption2).foregroundStyle(assemblyInk.opacity(0.86)),
                             at: CGPoint(x: size.width - 19, y: y), anchor: .trailing)
            }
        }
        .accessibilityLabel("Assembly workspace")
        .accessibilityHint("Scroll vertically or pinch to zoom. Drag the background or Option-scroll to pan.")
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
                if let index = experiment.selectedIndex {
                    camera = AssemblyCamera(fitting: [index], in: size, experiment: experiment)
                }
            }
            .disabled(experiment.selectedIndex == nil)
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
            beginDrag(at: location, projection: projection)
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

    private func beginDrag(at location: CGPoint, projection: AssemblyProjection) {
        cancelDrag()
        dragStart = location
        if experiment.placingGauge {
            drag = .gauge
        } else if experiment.canEdit, let part = selectedPart, handlesAreVisible(for: part, projection: projection),
                  let handle = Handle.allCases.first(where: {
                      let position = handlePosition($0, part: part, projection: projection)
                      return hypot(position.x - location.x, position.y - location.y) <= 11
                  }) {
            drag = .body(part, handle)
        } else if let id = part(at: projection.world(location)) {
            experiment.select(id)
            if experiment.canEdit, let part = selectedPart {
                drag = .body(part, nil)
            } else {
                drag = .pan(camera)
            }
        } else {
            drag = .pan(camera)
        }
    }

    private func updateDrag(at location: CGPoint, projection: AssemblyProjection) {
        let translation = CGSize(width: location.x - dragStart.x, height: location.y - dragStart.y)
        switch drag {
        case .pan(let start):
            camera.center = start.center - projection.worldDelta(translation)
        case .body(let original, let handle) where experiment.canEdit:
            var part = original
            switch handle {
            case nil:
                let center = part.center + projection.worldDelta(translation)
                part.center = Point(min(1, max(-1, center.x)), min(1, max(-1, center.y)))
            case .rotate:
                let initial = projection.world(dragStart) - part.center
                let current = projection.world(location) - part.center
                guard hypot(current.x, current.y) * projection.scale >= 5 else { return }
                let radians = atan2(current.y, current.x) - atan2(initial.y, initial.x)
                part.angle = (original.angle + radians * 180 / .pi).remainder(dividingBy: 360)
            case .resize:
                let delta = rotated(projection.worldDelta(translation), by: -part.angle)
                let size = part.size + 2 * delta
                part.size = Point(min(0.30, max(0.025, size.x)), min(0.30, max(0.025, size.y)))
                experiment.fitWall(of: &part)
            }
            experiment.previewPart = part
        default:
            break
        }
    }

    private func endDrag(at location: CGPoint, projection: AssemblyProjection) {
        defer { cancelDrag() }
        let distance = hypot(location.x - dragStart.x, location.y - dragStart.y)
        if case .gauge = drag, distance < 4, experiment.placingGauge {
            let point = projection.world(location)
            if let id = part(at: point) { experiment.addGauge(body: id, at: point) }
        } else if case .body(_, let handle) = drag, distance >= 2, experiment.canEdit {
            updateDrag(at: location, projection: projection)
            if let part = experiment.previewPart {
                let action = handle == .rotate ? "Rotate Body" : handle == .resize ? "Resize Body" : "Move Body"
                experiment.updatePart(part.id, action: action) { $0 = part }
            }
        }
    }

    private func cancelDrag() {
        drag = nil
        experiment.previewPart = nil
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
        if case .body(_, .some) = drag { return true }
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
        let step = scaleBarMillimetres(at: projection.scale) / 1_000
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

    private func drawBody(_ i: Int, context: GraphicsContext, projection: AssemblyProjection, preview: AssemblyPart?) {
        let part = experiment.scene.parts[i]
        let body = experiment.simulation.body(i)
        let positions = body.position.map { previewPosition($0, relativeTo: part, preview: preview) }
        let nodes = positions.map(projection.screen)
        let values = experiment.canEdit ? [] : field.values(i, in: experiment.simulation)
        let color = assemblyColor(i)
        var buckets = Array(repeating: Path(), count: 13)
        for (index, triangle) in body.mesh.elements.enumerated() {
            let value = values.isEmpty ? 0 : values[index]
            let level = min(1, abs(value) / field.scale)
            let step = Int((level * 6).rounded())
            let slot = value < 0 ? 6 - step : 6 + step
            buckets[slot].move(to: nodes[triangle.a])
            buckets[slot].addLine(to: nodes[triangle.b])
            buckets[slot].addLine(to: nodes[triangle.c])
            buckets[slot].closeSubpath()
        }
        for (i, path) in buckets.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(color.opacity(0.25)))
            if i != 6 {
                let diverging = field == .strain || field == .pressure
                let shade = field == .damage ? crackColor : (diverging && i > 6 ? assemblyMint : assemblyAmber)
                context.fill(path, with: .color(shade.opacity(Double(abs(i - 6)) / 6 * 0.9)))
            }
            if showMesh { context.stroke(path, with: .color(assemblyInk.opacity(0.17)), lineWidth: 0.45) }
        }
        let outline = Path { p in
            for edge in body.mesh.boundary {
                p.move(to: nodes[edge.a])
                p.addLine(to: nodes[edge.b])
            }
        }
        let active = experiment.simulation.activeContacts.contains { $0.x == i || $0.y == i }
        let selected = experiment.selectedPart == part.id
        context.stroke(outline, with: .color(active ? .white : color), lineWidth: selected ? 2.3 : 1.3)
        for line in body.mesh.interfaceLines {
            guard let first = line.first else { continue }
            let bond = Path { path in
                path.move(to: nodes[first])
                for node in line.dropFirst() { path.addLine(to: nodes[node]) }
            }
            context.stroke(bond, with: .color(assemblyInk.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
        }
        let cracks = experiment.simulation.crackFaces(i)
        for crack in cracks where crack.damage == 1 || field == .damage || field == .separation {
            let ratio = min(1, crack.separation / field.scale)
            let shade = field == .separation ? Color(red: 0.6 + 0.4 * ratio, green: 0.8 - 0.44 * ratio, blue: 0.2) : crackColor
            let opacity = field == .separation ? 0.4 + 0.6 * ratio : 0.25 + 0.75 * crack.damage
            let faces = Path { p in
                for edge in [crack.first, crack.second] {
                    p.move(to: nodes[edge.a])
                    p.addLine(to: nodes[edge.b])
                }
            }
            context.stroke(faces, with: .color(shade.opacity(opacity)), lineWidth: crack.damage == 1 ? 2.5 : 1.2)
        }
        let center = previewPosition(body.centerOfMass, relativeTo: part, preview: preview)
        let bottom = positions.map(\.y).min()!
        let top = positions.map(\.y).max()!
        let interior = experiment.scene.parts.enumerated().contains { j, other in
            other.shape == .enclosure && j != i
                && abs(experiment.simulation.body(j).centerOfMass.x - center.x) < other.size.x * 0.38
                && abs(experiment.simulation.body(j).centerOfMass.y - center.y) < other.size.y * 0.38
        }
        let topLabel = i.isMultiple(of: 2) && !(selected && experiment.canEdit)
        var labelPosition = projection.screen(Point(center.x, interior ? center.y : topLabel ? top : bottom))
        if !interior { labelPosition.y += topLabel ? -14 : 14 }
        let label = Text(part.name).font(.caption.weight(.semibold)).foregroundStyle(color)
        context.draw(label, at: labelPosition)
    }

    private func drawConnections(_ context: GraphicsContext, projection: AssemblyProjection, preview: AssemblyPart?) {
        let scene = experiment.scene
        for link in experiment.simulation.linkReadings {
            let connection = scene.connections[link.connection]
            let selected = experiment.selectedConnection == connection.id
            let first = scene.parts.first { $0.id == connection.first }
            let second = scene.parts.first { $0.id == connection.second }
            let a = projection.screen(first.map { previewPosition(link.start, relativeTo: $0, preview: preview) } ?? link.start)
            let b = projection.screen(second.map { previewPosition(link.end, relativeTo: $0, preview: preview) } ?? link.end)
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
        for i in experiment.scene.parts.indices.reversed() {
            let body = experiment.simulation.body(i)
            for triangle in body.mesh.elements {
                let a = body.position[triangle.a], b = body.position[triangle.b], c = body.position[triangle.c]
                func side(_ start: Point, _ end: Point) -> Double {
                    let edge = end - start, offset = point - start
                    return edge.x * offset.y - edge.y * offset.x
                }
                if min(side(a, b), side(b, c), side(c, a)) >= -1e-12 { return experiment.scene.parts[i].id }
            }
        }
        return nil
    }

    private func drawGauges(_ context: GraphicsContext, projection: AssemblyProjection, preview: AssemblyPart?) {
        for (index, gauge) in experiment.gauges.enumerated() {
            let position = experiment.simulation.gaugePosition(index)
            let part = experiment.scene.parts.first { $0.id == gauge.body }
            let at = projection.screen(part.map { previewPosition(position, relativeTo: $0, preview: preview) } ?? position)
            let dot = Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8))
            context.fill(dot, with: .color(.black))
            context.stroke(dot, with: .color(.white), lineWidth: 1.5)
            context.draw(Text(gauge.name).font(.caption2.monospaced()).foregroundStyle(.white),
                         at: CGPoint(x: at.x + 7, y: at.y - 7), anchor: .bottomLeading)
        }
    }
}

private struct AssemblyCanvasInput: NSViewRepresentable {
    let handle: (NSEvent, CGPoint) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.toolTip = "Scroll vertically or pinch to zoom. Drag the background or Option-scroll to pan."
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
