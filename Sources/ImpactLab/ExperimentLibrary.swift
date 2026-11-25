import ImpactPhysics
import SwiftUI

struct ExperimentLibrary: View {
    let load: (AssemblyScene, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AssemblyExperimentPreset = .inclinedPlate
    @State private var boundary = AssemblyExperimentPreset.inclinedPlate.defaultBoundary
    @State private var resolution = AssemblyExperimentPreset.inclinedPlate.defaultResolution

    /// A ready-made showcase when one is selected; nil shows the controlled-experiment presets.
    @State private var showcase: ShowcasePreset? = .notchedAcrylicBeam

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Experiment library").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ready-made showcases").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    showcases
                    Text("Controlled experiments").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    presets
                }
                .frame(width: 215)
                if let showcase { showcaseDetail(showcase) } else { presetDetail }
            }
        }
        .padding(21)
        .frame(width: 780)
    }

    @ViewBuilder private func showcaseDetail(_ preset: ShowcasePreset) -> some View {
        let built = Result { try preset.scene() }
        VStack(alignment: .leading, spacing: 10) {
            Text(preset.rawValue).font(.title3.weight(.semibold))
            Text(preset.description).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch built {
            case .success(let scene):
                ExperimentSchematic(scene: scene)
                    .frame(height: 218)
                    .accessibilityLabel("Initial geometry and loading")
            case .failure(let error):
                Text("This showcase could not be built: \(String(describing: error))").font(.caption).foregroundStyle(.red)
            }
            Text(preset.limitations).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Press Calculate after loading. Everything you see is computed by the solver; you can edit any value in the workshop.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("Loading replaces the current assembly.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Load showcase") { if case .success(let scene) = built { load(scene, preset.rawValue) } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled((try? built.get()) == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetDetail: some View {
        let draft = selection.scene(boundary: boundary, resolution: resolution)
        return VStack(alignment: .leading, spacing: 10) {
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
            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("Loading replaces the current assembly.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Load experiment") { load(draft, selection.rawValue) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showcases: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ShowcasePreset.allCases) { preset in
                listButton(preset.rawValue, icon: preset.icon, selected: showcase == preset) { showcase = preset }
            }
        }
        .padding(5)
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func listButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(selected ? assemblyMint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AssemblyExperimentPreset.allCases) { preset in
                listButton(preset.rawValue, icon: preset.icon, selected: showcase == nil && selection == preset) {
                    showcase = nil
                    selection = preset
                    boundary = preset.defaultBoundary
                    resolution = preset.defaultResolution
                }
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
                for hole in holes(part) {
                    outline.addLines(hole.map(screen))
                    outline.closeSubpath()
                }
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

    /// The drawn shape: an outline body's polygon, an ellipse for a round body, else the rectangle.
    private func corners(_ part: AssemblyPart, halfSize: Point) -> [Point] {
        if part.shape == .outline, let shape = part.outline {
            return local(shape.outer, shape, part).map { world($0, part) }
        }
        if part.shape == .round {
            return (0..<32).map { i in
                let t = Double(i) / 32 * 2 * .pi
                return world(Point(halfSize.x * cos(t), halfSize.y * sin(t)), part)
            }
        }
        return [Point(-halfSize.x, -halfSize.y), Point(halfSize.x, -halfSize.y),
         Point(halfSize.x, halfSize.y), Point(-halfSize.x, halfSize.y)].map { world($0, part) }
    }

    private func holes(_ part: AssemblyPart) -> [[Point]] {
        guard part.shape == .outline, let shape = part.outline else { return [] }
        return shape.holes.map { local($0, shape, part).map { world($0, part) } }
    }

    /// Outline points re-centred on their box and stretched to the body's size, as the mesher places them.
    private func local(_ ring: [Point], _ shape: BodyOutline, _ part: AssemblyPart) -> [Point] {
        let (lo, hi) = shape.bounds
        let mid = (lo + hi) / 2, span = hi - lo
        return ring.map { p in
            Point(span.x > 0 ? (p.x - mid.x) * part.size.x / span.x : 0, span.y > 0 ? (p.y - mid.y) * part.size.y / span.y : 0)
        }
    }

    private func world(_ point: Point, _ part: AssemblyPart) -> Point {
        let angle = part.angle * .pi / 180
        return part.center + Point(cos(angle) * point.x - sin(angle) * point.y,
                                   sin(angle) * point.x + cos(angle) * point.y)
    }
}
