import ImpactPhysics
import SwiftUI

let assemblyInk = Color(red: 0.85, green: 0.91, blue: 0.95)
let assemblyMint = Color(red: 0.43, green: 0.89, blue: 0.77)
let assemblyAmber = Color(red: 1, green: 0.67, blue: 0.39)
let assemblyPanel = Color(red: 0.085, green: 0.125, blue: 0.17)

func assemblyColor(_ index: Int) -> Color {
    let palette = [assemblyMint, assemblyAmber, Color(red: 0.55, green: 0.75, blue: 1),
                   Color(red: 0.83, green: 0.67, blue: 0.98),
                   .pink, .green, .cyan, .yellow]
    return palette[index % palette.count]
}

private struct AssemblyProjection {
    let center: Point
    let viewport: CGSize
    let scale: Double

    @MainActor init(_ size: CGSize, experiment: AssemblyExperiment) {
        viewport = size
        var lower = Point(-0.19, -0.09)
        var upper = Point(0.13, 0.09)
        for index in 0..<experiment.simulation.bodyCount {
            for point in experiment.simulation.body(index).position {
                lower = Point(min(lower.x, point.x), min(lower.y, point.y))
                upper = Point(max(upper.x, point.x), max(upper.y, point.y))
            }
        }
        center = (upper + lower) / 2
        let span = upper - lower
        scale = max(1, min((size.width - 66) / span.x, (size.height - 80) / span.y))
    }

    func screen(_ p: Point) -> CGPoint {
        CGPoint(x: viewport.width / 2 + (p.x - center.x) * scale,
                y: viewport.height / 2 - (p.y - center.y) * scale)
    }

    func world(_ p: CGPoint) -> Point {
        center + Point((p.x - viewport.width / 2) / scale, (viewport.height / 2 - p.y) / scale)
    }
}

struct AssemblyCanvas: View {
    let experiment: AssemblyExperiment
    let plastic: Bool
    @State private var dragOrigin: Point?
    @State private var dragTarget: UUID?
    @State private var dragDelta: Point = .zero

    var body: some View {
        GeometryReader { geometry in
            let projection = AssemblyProjection(geometry.size, experiment: experiment)
            Canvas { context, size in
                drawGrid(context, size: size, projection: projection)
                for i in 0..<experiment.simulation.bodyCount {
                    drawBody(i, context: context, projection: projection)
                }
                drawConnections(context, projection: projection)
                let y = size.height - 22
                let x = 22.0
                let end = x + projection.scale * 0.025
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: y - 4))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: end, y: y))
                    p.addLine(to: CGPoint(x: end, y: y - 4))
                }, with: .color(assemblyInk.opacity(0.6)))
                context.draw(Text("25 mm").font(.caption2.monospaced()), at: CGPoint(x: x, y: y - 7), anchor: .bottomLeading)
                let legend = plastic ? "Plastic strain · 0–8%" : "Amber fill · compression     Mint fill · tension"
                context.draw(Text(legend).font(.caption2).foregroundStyle(assemblyInk.opacity(0.73)),
                             at: CGPoint(x: size.width - 19, y: y), anchor: .trailing)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                if dragOrigin == nil {
                    let point = projection.world(event.startLocation)
                    dragOrigin = point
                    dragTarget = part(at: point)
                    if let dragTarget { experiment.select(dragTarget) }
                }
                if experiment.simulation.time == 0, let origin = dragOrigin, dragTarget != nil {
                    dragDelta = projection.world(event.location) - origin
                }
            }.onEnded { _ in
                if let dragTarget, experiment.simulation.time == 0, dragDelta != .zero {
                    let delta = dragDelta
                    experiment.updatePart(dragTarget) { part in
                        let proposed = part.center + delta
                        part.center = Point(min(1, max(-1, proposed.x)), min(1, max(-1, proposed.y)))
                    }
                }
                dragOrigin = nil
                dragTarget = nil
                dragDelta = .zero
            })
        }
        .accessibilityLabel("Assembly workspace. Select bodies in the sidebar to edit exact positions.")
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func drawGrid(_ context: GraphicsContext, size: CGSize, projection: AssemblyProjection) {
        let low = projection.world(CGPoint(x: 12, y: size.height - 39))
        let high = projection.world(CGPoint(x: size.width - 12, y: 18))
        let step = 0.025
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

    private func offset(_ id: UUID) -> Point { dragTarget == id ? dragDelta : .zero }

    private func drawBody(_ i: Int, context: GraphicsContext, projection: AssemblyProjection) {
        let part = experiment.scene.parts[i]
        let body = experiment.simulation.body(i)
        let shift = offset(part.id)
        let nodes = body.position.map { projection.screen($0 + shift) }
        let strains = plastic ? experiment.simulation.plasticStrain(i) : experiment.simulation.strain(i)
        let color = assemblyColor(i)
        var buckets = Array(repeating: Path(), count: 13)
        for (index, triangle) in body.mesh.elements.enumerated() {
            let strain = strains.isEmpty ? 0 : strains[index]
            let step = Int((min(1, sqrt(abs(strain) / 0.08)) * 6).rounded())
            let slot = strain < 0 ? 6 - step : 6 + step
            buckets[slot].move(to: nodes[triangle.a])
            buckets[slot].addLine(to: nodes[triangle.b])
            buckets[slot].addLine(to: nodes[triangle.c])
            buckets[slot].closeSubpath()
        }
        for (i, path) in buckets.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(color.opacity(0.25)))
            if i != 6 {
                context.fill(path, with: .color((plastic || i < 6 ? assemblyAmber : assemblyMint)
                    .opacity(Double(abs(i - 6)) / 6 * 0.88)))
            }
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
        let center = body.centerOfMass + shift
        let bottom = body.position.map(\.y).min()! + shift.y
        let top = body.position.map(\.y).max()! + shift.y
        let interior = experiment.scene.parts.enumerated().contains { j, other in
            other.shape == .enclosure && j != i
                && abs(experiment.simulation.body(j).centerOfMass.x - center.x) < other.size.x * 0.38
                && abs(experiment.simulation.body(j).centerOfMass.y - center.y) < other.size.y * 0.38
        }
        let y = interior ? center.y : (i.isMultiple(of: 2) ? top + 0.010 : bottom - 0.010)
        let label = Text(part.name).font(.caption.weight(.semibold)).foregroundStyle(color)
        context.draw(label, at: projection.screen(Point(center.x, y)))
    }

    private func drawConnections(_ context: GraphicsContext, projection: AssemblyProjection) {
        let scene = experiment.scene
        for link in experiment.simulation.linkReadings {
            let connection = scene.connections[link.connection]
            let selected = experiment.selectedConnection == connection.id
            let a = projection.screen(link.start + offset(connection.first))
            let b = projection.screen(link.end + offset(connection.second))
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
            var inside = false
            for edge in body.mesh.boundary {
                let a = body.position[edge.a], b = body.position[edge.b]
                if (a.y > point.y) != (b.y > point.y),
                   point.x < a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y) {
                    inside.toggle()
                }
            }
            if inside { return experiment.scene.parts[i].id }
        }
        return nil
    }
}
