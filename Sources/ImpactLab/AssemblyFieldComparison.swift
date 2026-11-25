import Charts
import ImpactPhysics
import SwiftUI

struct AssemblyFieldComparison: View {
    let reference: AssemblyComparison
    let current: AssemblyComparison
    let first: AssemblyReplay
    let second: AssemblyReplay
    @State var field: AssemblyField
    @State private var range = AssemblyFieldRange.standard
    @State private var time: Double
    @State private var histories = false
    @State private var curves = false
    @Environment(\.dismiss) private var dismiss

    init(reference: AssemblyComparison, current: AssemblyComparison,
         first: AssemblyReplay, second: AssemblyReplay, field: AssemblyField) {
        self.reference = reference
        self.current = current
        self.first = first
        self.second = second
        _field = State(initialValue: field)
        _time = State(initialValue: min(first.frames.last!.time, second.frames.last!.time))
    }

    private var horizon: Double { min(first.frames.last!.time, second.frames.last!.time) }

    var body: some View {
        let ref = first.frames[first.index(at: time)], now = second.frames[second.index(at: time)]
        let hasMetal = (reference.scene.parts + current.scene.parts).contains { $0.material.provenance != nil }
        let limit = max(field.limit(for: range, frame: ref, metal: hasMetal),
                        field.limit(for: range, frame: now, metal: hasMetal))
        let bounds = ViewBounds(ref, now)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Compare Recorded Runs").font(.title2.weight(.semibold))
                Spacer()
                if !hardeningCurves.isEmpty { Button("Flow Curves…") { curves = true } }
                Button("Trace Comparison…") { histories = true }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 12) {
                Picker("Field", selection: $field) {
                    ForEach(AssemblyField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.fixedSize()
                Picker("Color range", selection: $range) {
                    ForEach(AssemblyFieldRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize().disabled(field == .damage)
                Spacer()
                AssemblyFieldLegend(field: field, limit: limit)
            }
            HStack(alignment: .top, spacing: 12) {
                panel("Reference", comparison: reference, frame: ref, bounds: bounds, limit: limit)
                panel("Current", comparison: current, frame: now, bounds: bounds, limit: limit)
            }
            Slider(value: $time, in: 0...max(horizon, 1e-12)) { Text("Comparison time") }
                .accessibilityValue(replayTime(time))
            HStack {
                Text("Requested time \(replayTime(time))")
                Spacer()
                Text("\(AssemblyField.layerLabel(smooth: false)) · Shared spatial scale · True geometry · Nearest recorded frames")
            }.font(.caption).foregroundStyle(.secondary)
            Text(field.definition).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 850)
        .sheet(isPresented: $histories) { ComparisonView(reference: reference, current: current) }
        .sheet(isPresented: $curves) { flowCurves }
    }

    private struct FlowCurve: Identifiable {
        let id, name: String
        let points: [HardeningPoint]
    }

    private var hardeningCurves: [FlowCurve] {
        [("Reference", reference.scene), ("Current", current.scene)].compactMap { title, scene in
            guard let part = monitored(scene), part.plasticity.response == .elastoplastic,
                  let table = part.plasticity.table else { return nil }
            return FlowCurve(id: title, name: part.material.provenance?.name ?? part.name, points: table.points)
        }
    }

    private var flowCurves: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tabulated J2 Flow Curves").font(.title2.weight(.semibold))
            Chart(hardeningCurves) { curve in
                ForEach(Array(curve.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Equivalent plastic strain", 100 * point.strain),
                             y: .value("Kirchhoff flow stress", point.stress / 1e6),
                             series: .value("Run", curve.id))
                        .foregroundStyle(by: .value("Run", curve.id))
                    PointMark(x: .value("Equivalent plastic strain", 100 * point.strain),
                              y: .value("Kirchhoff flow stress", point.stress / 1e6))
                        .foregroundStyle(by: .value("Run", curve.id))
                }
            }.chartXAxisLabel("Equivalent plastic strain (%)").chartYAxisLabel("Kirchhoff flow stress (MPa)")
                .frame(height: 250)
            ForEach(hardeningCurves) { curve in Text("\(curve.id) · \(curve.name)") }
            Text("The solver interpolates between the displayed points and holds flow stress constant after the final point. The built-in post-yield curves are illustrative.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Done") { curves = false }.keyboardShortcut(.defaultAction)
        }.padding(20).frame(width: 630)
    }

    private func panel(_ title: String, comparison: AssemblyComparison, frame: AssemblyReplayFrame,
                       bounds: ViewBounds, limit: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title).font(.headline); Spacer(); Text(replayTime(frame.time)).monospacedDigit() }
            Text(comparison.details).lineLimit(2).foregroundStyle(.secondary)
            if let part = monitored(comparison.scene) {
                let material = part.material
                Text("E \(material.young / 1e9, specifier: "%.4g") GPa · ρ \(material.density, specifier: "%.5g") kg/m³")
                if let yield = part.plasticity.table?.points.first?.stress, part.plasticity.response == .elastoplastic {
                    Text("Initial flow \(yield / 1e6, specifier: "%.4g") MPa")
                }
            }
            miniature(frame, bounds: bounds, limit: limit)
                .frame(height: 205)
                .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel("\(title) computed geometry at \(replayTime(frame.time))")
            Text("Kinetic \(frame.energies.kinetic, specifier: "%.5g") J/m · Recoverable \(frame.recoverableEnergy, specifier: "%.5g") J/m")
            Text("Modelled plastic dissipation \(frame.energies.plastic, specifier: "%.5g") J/m · Fracture \(frame.energies.fracture, specifier: "%.5g") J/m")
            if let p = monitored(comparison.scene), let i = comparison.scene.parts.firstIndex(where: { $0.id == p.id }) {
                let body = frame.bodies[i]
                let values = field == .separation ? body.cracks.map(\.separation) : field.values(body)
                if let high = values.max() {
                    let low = values.min() ?? 0
                    Text(field.signed ? "Specimen \(field.display(low, limit: limit)) to \(field.display(high, limit: limit))"
                         : "Specimen peak \(field.display(high, limit: limit))")
                } else { Text("Specimen field unavailable").foregroundStyle(.secondary) }
            }
        }
        .font(.callout.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func monitored(_ scene: AssemblyScene) -> AssemblyPart? {
        scene.parts.first(where: { $0.id == scene.monitor }) ?? scene.parts.first
    }

    private func miniature(_ frame: AssemblyReplayFrame, bounds: ViewBounds, limit: Double) -> some View {
        Canvas { context, size in
            let factor = min((size.width - 30) / bounds.span.x, (size.height - 32) / bounds.span.y)
            func project(_ point: Point) -> CGPoint {
                let relative = (point - bounds.center) * factor
                return CGPoint(x: size.width / 2 + relative.x, y: size.height / 2 - relative.y)
            }
            for (index, state) in frame.bodies.enumerated() {
                let body = state.body
                let points = body.position.map(project)
                let values = field.values(state)
                var buckets = Array(repeating: Path(), count: 13)
                for (i, t) in body.mesh.elements.enumerated() {
                    let bin = values.isEmpty ? 6 : 6 + field.bin(values[i], limit: limit)
                    buckets[bin].move(to: points[t.a]); buckets[bin].addLine(to: points[t.b])
                    buckets[bin].addLine(to: points[t.c]); buckets[bin].closeSubpath()
                }
                for (i, path) in buckets.enumerated() where !path.isEmpty {
                    context.fill(path, with: .color(values.isEmpty ? assemblyColor(index).opacity(0.20) : field.shade(i - 6)))
                }
                context.stroke(edgePath(body.mesh.boundary, nodes: points), with: .color(assemblyColor(index)), lineWidth: 1)
                for line in body.mesh.interfaceLines {
                    let edges = zip(line, line.dropFirst()).map { ImpactPhysics.Edge($0, $1) }
                    context.stroke(edgePath(edges, nodes: points), with: .color(assemblyInk), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                for face in state.cracks {
                    let color = field == .separation ? field.shade(field.bin(face.separation, limit: limit)) : .red
                    context.stroke(edgePath([face.first, face.second], nodes: points), with: .color(color),
                                   style: StrokeStyle(lineWidth: 1.3, dash: face.failed ? [] : [3, 2]))
                }
            }
        }
    }

    private struct ViewBounds {
        let center, span: Point
        init(_ a: AssemblyReplayFrame, _ b: AssemblyReplayFrame) {
            var low = Point(repeating: .infinity), high = Point(repeating: -.infinity)
            for state in a.bodies + b.bodies {
                for p in state.body.position {
                    low = Point(min(low.x, p.x), min(low.y, p.y))
                    high = Point(max(high.x, p.x), max(high.y, p.y))
                }
            }
            center = low.x.isFinite ? (low + high) / 2 : .zero
            span = Point(max(1e-3, high.x - low.x), max(1e-3, high.y - low.y))
        }
    }
}
