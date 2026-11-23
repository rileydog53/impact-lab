import ImpactPhysics
import SwiftUI

struct ExperimentLibrary: View {
    let load: (AssemblyScene, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AssemblyExperimentPreset = .inclinedPlate
    @State private var boundary = AssemblyExperimentPreset.inclinedPlate.defaultBoundary
    @State private var resolution = AssemblyExperimentPreset.inclinedPlate.defaultResolution

    var body: some View {
        let draft = selection.scene(boundary: boundary, resolution: resolution)
        VStack(alignment: .leading, spacing: 16) {
            Text("Experiment library").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 16) {
                presets
                    .frame(width: 195)
                VStack(alignment: .leading, spacing: 10) {
                    Text(selection.rawValue).font(.title3.weight(.semibold))
                    Text(selection.description).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ExperimentSchematic(scene: draft)
                        .frame(height: 218)
                        .accessibilityLabel("Initial geometry and striker motion")
                    Picker("Boundary", selection: $boundary) {
                        ForEach(AssemblyExperimentPreset.Boundary.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Picker("Assembly mesh", selection: $resolution) {
                        ForEach(AssemblyScene.Resolution.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text(boundary == .supports
                         ? "Support bodies deform and move when loaded."
                         : "Bodies move freely and interact through contact.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Use coarse meshes to preview the setup. Check the readings in a mesh and timestep study before drawing quantitative conclusions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Loading replaces the current assembly.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Load experiment") { load(draft, selection.rawValue) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(21)
        .frame(width: 740)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AssemblyExperimentPreset.allCases) { preset in
                Button {
                    selection = preset
                    boundary = preset.defaultBoundary
                    resolution = preset.defaultResolution
                } label: {
                    Label(preset.rawValue, systemImage: preset.icon)
                        .font(.callout.weight(selection == preset ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9).padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(selection == preset ? assemblyMint.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == preset ? .isSelected : [])
            }
        }
        .padding(5)
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension AssemblyExperimentPreset {
    var description: String {
        switch self {
        case .inclinedPlate: "Trace how tilt changes bending and the sequence of support loads."
        case .separatedPlates: "Measure the delay and impulse as the moving front plate reaches a separate receiver."
        case .bondedComposite: "Follow a pulse through three elastic layers and two shared-node bonds."
        case .hollowSandwich: "Compare motion at the front and rear faces of a panel joined by side walls."
        case .angledPanels: "Set each panel’s angle independently and compare its force and motion history."
        }
    }

    var icon: String {
        switch self {
        case .inclinedPlate: "angle"
        case .separatedPlates: "rectangle.split.1x2"
        case .bondedComposite: "square.3.layers.3d"
        case .hollowSandwich: "rectangle.inset.filled"
        case .angledPanels: "rotate.right"
        }
    }
}

struct ExperimentSchematic: View {
    let scene: AssemblyScene
    /// Alternates labels below and above bodies so touching bodies stay legible.
    var labelsOutside = false

    var body: some View {
        Canvas { context, size in
            let outlines = scene.parts.map { corners($0, halfSize: $0.size / 2) }
            let points = outlines.flatMap { $0 }
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxY = (points.map(\.y).max() ?? 0) + 0.026
            let margin = labelsOutside ? 60.0 : 32.0
            let scale = min((size.width - 70) / max(0.02, maxX - minX), (size.height - margin) / max(0.02, maxY - minY))
            func screen(_ point: Point) -> CGPoint {
                CGPoint(x: size.width / 2 + (point.x - (minX + maxX) / 2) * scale,
                        y: size.height / 2 - (point.y - (minY + maxY) / 2) * scale)
            }
            for (index, part) in scene.parts.enumerated() {
                let color = assemblyColor(index)
                var outline = Path()
                outline.addLines(outlines[index].map(screen))
                outline.closeSubpath()
                if part.shape == .enclosure {
                    outline.addLines(corners(part, halfSize: part.size / 2 - Point(repeating: part.wall)).map(screen))
                    outline.closeSubpath()
                }
                context.fill(outline, with: .color(color.opacity(0.2)), style: FillStyle(eoFill: true))
                context.stroke(outline, with: .color(color), lineWidth: 1.5)
                if let layer = part.bondedLayer {
                    let interfaces = [layer.interfaceFraction, layer.third?.interfaceFraction].compactMap { $0 }
                    for position in interfaces {
                        let x = (position - 0.5) * part.size.x
                        let line = Path { path in
                            path.move(to: screen(world(Point(x, -part.size.y / 2), part)))
                            path.addLine(to: screen(world(Point(x, part.size.y / 2), part)))
                        }
                        context.stroke(line, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }
                }
                let text = Text(part.name).font(.caption2.weight(.medium)).foregroundStyle(color)
                if labelsOutside {
                    let ys = outlines[index].map { screen($0).y }
                    let below = index.isMultiple(of: 2)
                    let anchor = screen(part.center)
                    context.draw(text, at: CGPoint(x: anchor.x, y: below ? ys.max()! + 9 : ys.min()! - 9))
                } else {
                    context.draw(text, at: screen(part.center))
                }
                let speed = (part.velocity.x * part.velocity.x + part.velocity.y * part.velocity.y).squareRoot()
                if speed > 0 {
                    // Screen y points down, so the arrow flips the vertical component.
                    let d = CGPoint(x: part.velocity.x / speed, y: -part.velocity.y / speed)
                    let reach = abs(d.x) * part.size.x / 2 + abs(d.y) * part.size.y / 2 + 0.003
                    let tip = screen(part.center + Point(d.x * reach, -d.y * reach))
                    let n = CGPoint(x: -d.y, y: d.x)
                    let arrow = Path { path in
                        path.move(to: CGPoint(x: tip.x - 18 * d.x, y: tip.y - 18 * d.y))
                        path.addLine(to: tip)
                        path.move(to: CGPoint(x: tip.x - 5 * d.x + 4 * n.x, y: tip.y - 5 * d.y + 4 * n.y))
                        path.addLine(to: tip)
                        path.addLine(to: CGPoint(x: tip.x - 5 * d.x - 4 * n.x, y: tip.y - 5 * d.y - 4 * n.y))
                    }
                    context.stroke(arrow, with: .color(color), lineWidth: 1.5)
                }
            }
        }
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 9))
    }

    private func corners(_ part: AssemblyPart, halfSize: Point) -> [Point] {
        [Point(-halfSize.x, -halfSize.y), Point(halfSize.x, -halfSize.y),
         Point(halfSize.x, halfSize.y), Point(-halfSize.x, halfSize.y)].map { world($0, part) }
    }

    private func world(_ point: Point, _ part: AssemblyPart) -> Point {
        let angle = part.angle * .pi / 180
        return part.center + Point(cos(angle) * point.x - sin(angle) * point.y,
                                   sin(angle) * point.x + cos(angle) * point.y)
    }
}
