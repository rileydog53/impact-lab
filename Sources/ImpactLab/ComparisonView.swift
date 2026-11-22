import ImpactPhysics
import SwiftUI

struct ComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cursor: Double
    let reference: SceneTrace
    let current: SceneTrace
    let samples: [SceneTrace.Match]
    private var preset: Preset { current.preset }

    init(reference: SceneTrace, current: SceneTrace) {
        self.reference = reference
        self.current = current
        samples = current.matching(reference)
        _cursor = State(initialValue: Double(max(0, samples.count - 1)))
    }

    private var series: [(name: String, unit: String, value: KeyPath<Point, Double>, color: Color)] {
        switch preset {
        case .bar, .bondedBar: [("Axial strain", "%", \.x, .mint)]
        case .block: [("Orientation", "°", \.x, .mint)]
        case .ring: [("Horizontal diameter", "mm", \.x, .mint), ("Vertical diameter", "mm", \.y, .orange)]
        case .twoBars: [("Left bar", "m/s", \.x, .mint), ("Right bar", "m/s", \.y, .orange)]
        case .puckStrip: [("Puck", "m/s", \.x, .mint), ("Strip", "m/s", \.y, .orange)]
        case .tensionCoupon:
            [("Length change", "mm", \.x, .mint), ("Mean plastic strain", "%", \.y, .orange)]
        case .layeredSeam:
            [("Opening", "mm", \.x, .mint), ("Dissipated fracture energy", "J/m²", \.y, .orange)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Compare runs").font(.title2.bold())
                    Text(preset.rawValue).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if samples.count > 1 {
                let selected = samples[Int(cursor)]
                HStack(spacing: 18) {
                    Label("\(reference.seamResponse?.rawValue ?? reference.couponResponse?.rawValue ?? "Reference") · dashed",
                          systemImage: "line.diagonal")
                    Label("\(current.seamResponse?.rawValue ?? current.couponResponse?.rawValue ?? "Current") · solid",
                          systemImage: "line.horizontal")
                }
                .font(.caption).foregroundStyle(.secondary)
                if preset == .tensionCoupon {
                    Text("Length change (mm)").font(.caption).foregroundStyle(.secondary)
                } else if preset == .layeredSeam {
                    Text("Mean opening (mm)").font(.caption).foregroundStyle(.secondary)
                }
                chart.frame(height: 190)
                HStack {
                    Text("Simulated time").foregroundStyle(.secondary)
                    Slider(value: $cursor, in: 0...Double(samples.count - 1), step: 1) {
                        Text("Simulated time")
                    }
                    Text("\(selected.time * 1000, specifier: "%.2f") ms").monospacedDigit()
                        .frame(width: 88, alignment: .trailing)
                }
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Signal")
                        Text("Reference")
                        Text("Current")
                        Text("Change")
                    }
                    .font(.subheadline.weight(.medium))
                    ForEach(series.indices, id: \.self) { index in
                        let signal = series[index]
                        let reference = selected.reference[keyPath: signal.value]
                        let current = selected.current[keyPath: signal.value]
                        GridRow {
                            Label(signal.name, systemImage: "circle.fill")
                                .foregroundStyle(signal.color)
                            reading(reference, unit: signal.unit)
                            reading(current, unit: signal.unit)
                            reading(current - reference, unit: signal.unit)
                        }
                    }
                    if let referenceLength = reference.residualLength, let currentLength = current.residualLength {
                        GridRow {
                            Text("Residual length")
                            reading(1000 * referenceLength, unit: "mm")
                            reading(1000 * currentLength, unit: "mm")
                            reading(1000 * (currentLength - referenceLength), unit: "mm")
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 570)
    }

    private func reading(_ value: Double, unit: String) -> some View {
        Text(String(format: "%.4f", value) + (unit == "%" || unit == "°" ? "" : " ") + unit)
            .monospacedDigit()
            .gridColumnAlignment(.trailing)
    }

    private var chart: some View {
        Canvas { context, size in
            let signals = preset == .tensionCoupon || preset == .layeredSeam ? Array(series.prefix(1)) : series
            let time = samples.last!.time
            var low = Double.infinity
            var high = -Double.infinity
            for sample in samples {
                for signal in signals {
                    low = min(low, sample.reference[keyPath: signal.value], sample.current[keyPath: signal.value])
                    high = max(high, sample.reference[keyPath: signal.value], sample.current[keyPath: signal.value])
                }
            }
            let pad = max(1e-6, (high - low) * 0.07)
            let range = high - low + 2 * pad
            let left = 52.0, right = size.width - 10
            let top = 12.0, bottom = size.height - 23
            func x(_ value: Double) -> Double { left + value / time * (right - left) }
            func y(_ value: Double) -> Double { bottom - (value - low + pad) / range * (bottom - top) }
            for value in [low, (low + high) / 2, high] {
                let height = y(value)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: left, y: height))
                    p.addLine(to: CGPoint(x: right, y: height))
                }, with: .color(.secondary.opacity(0.25)))
                context.draw(Text(String(format: "%.3g", value)).font(.caption2.monospaced()),
                             at: CGPoint(x: left - 8, y: height), anchor: .trailing)
            }
            for signal in signals {
                for isReference in [true, false] {
                    let path = Path { p in
                        for (i, sample) in samples.enumerated() {
                            let value = (isReference ? sample.reference : sample.current)[keyPath: signal.value]
                            let point = CGPoint(x: x(sample.time), y: y(value))
                            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                        }
                    }
                    context.stroke(path, with: .color(signal.color),
                                   style: StrokeStyle(lineWidth: 1.6, dash: isReference ? [4, 4] : []))
                }
            }
            let position = x(samples[Int(cursor)].time)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: position, y: top))
                p.addLine(to: CGPoint(x: position, y: bottom))
            }, with: .color(.primary.opacity(0.5)))
            context.draw(Text("0 ms").font(.caption2.monospaced()), at: CGPoint(x: left, y: size.height - 8))
            context.draw(Text(String(format: "%.1f ms", 1000 * time)).font(.caption2.monospaced()),
                         at: CGPoint(x: right, y: size.height - 8), anchor: .trailing)
        }
        .accessibilityLabel("Reference and current traces aligned by simulated time")
    }
}
