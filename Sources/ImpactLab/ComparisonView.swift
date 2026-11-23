import ImpactPhysics
import SwiftUI

struct ComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cursor: Double
    @State private var selectedSignal = 0
    private let title: String
    private let referenceDetails, currentDetails: String
    private let referenceResidual, currentResidual: Double?
    private let preset: Preset?
    private let samples: [SceneTrace.Match]
    private let tracksFracture: Bool

    init(reference: SceneTrace, current: SceneTrace) {
        title = current.preset.rawValue
        preset = current.preset
        tracksFracture = false
        referenceDetails = Self.details(reference)
        currentDetails = Self.details(current)
        referenceResidual = reference.residualLength
        currentResidual = current.residualLength
        samples = current.matching(reference)
        _cursor = State(initialValue: Double(max(0, samples.count - 1)))
    }

    init(reference: AssemblyComparison, current: AssemblyComparison) {
        title = "Assembly laboratory"
        preset = nil
        tracksFracture = reference.tracksFracture || current.tracksFracture
        referenceDetails = reference.details
        currentDetails = current.details
        referenceResidual = nil
        currentResidual = nil
        samples = SceneTrace.matching(reference.samples, current.samples)
        _cursor = State(initialValue: Double(max(0, samples.count - 1)))
        _selectedSignal = State(initialValue: tracksFracture ? 3
            : (samples.last.map { $0.referenceSample.plasticDissipation > 0 || $0.currentSample.plasticDissipation > 0 } == true ? 3 : 0))
    }

    private typealias Signal = (name: String, unit: String, value: KeyPath<TraceSample, Double>, color: Color)
    private var series: [Signal] {
        guard let preset else {
            let motion: [Signal] = [("Relative X", "mm", \.values.x, .mint), ("Body kinetic energy", "J/m", \.values.y, .orange),
                    ("Stored connection energy", "J/m", \.connectionEnergy, .yellow)]
            guard tracksFracture else {
                return motion + [("Plastic dissipation", "J/m", \.plasticDissipation, .pink),
                                 ("Sampled peak stress", "kPa", \.peakStress, .cyan)]
            }
            return motion + [("Material fracture dissipation", "J/m", \.materialFracture, .pink),
                             ("Crack length", "mm", \.crackLength, .red),
                             ("Face separation", "mm", \.crackSeparation, .purple),
                             ("Sampled peak stress", "kPa", \.peakStress, .cyan)]
        }
        return switch preset {
        case .bar, .bondedBar: [("Axial strain", "%", \.values.x, .mint)]
        case .block: [("Orientation", "°", \.values.x, .mint)]
        case .ring: [("Horizontal diameter", "mm", \.values.x, .mint), ("Vertical diameter", "mm", \.values.y, .orange)]
        case .twoBars: [("Left bar", "m/s", \.values.x, .mint), ("Right bar", "m/s", \.values.y, .orange)]
        case .puckStrip: [("Puck", "m/s", \.values.x, .mint), ("Strip", "m/s", \.values.y, .orange)]
        case .tensionCoupon, .materialImpact:
            [("Length change", "mm", \.values.x, .mint), ("Mean plastic strain", "%", \.values.y, .orange)]
        case .layeredSeam:
            [("Mean opening", "mm", \.values.x, .mint), ("Fracture dissipation", "J/m²", \.values.y, .orange)]
        case .offAxisImpact:
            [("Backing angle", "°", \.values.x, .mint), ("Receiver velocity X", "m/s", \.values.y, .orange),
             ("Plastic dissipation", "J/m", \.plasticDissipation, .yellow)]
        case .layeredImpact:
            [("Mean opening", "mm", \.values.x, .mint), ("Fracture dissipation", "J/m²", \.values.y, .orange),
             ("Plastic dissipation", "J/m", \.plasticDissipation, .yellow)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Compare runs").font(.title2.bold())
                    Text(title).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if samples.count > 1 {
                let selected = samples[Int(cursor)]
                HStack(spacing: 18) {
                    runLegend("Reference", details: referenceDetails, symbol: "line.diagonal")
                    runLegend("Current", details: currentDetails, symbol: "line.horizontal")
                }
                .font(.caption).foregroundStyle(.secondary)
                if choosesSignal {
                    Picker("Comparison signal", selection: $selectedSignal) {
                        ForEach(series.indices, id: \.self) { index in
                            let signal = series[index]
                            Text("\(signal.name) (\(signal.unit))").tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                }
                chart.frame(height: 190)
                HStack {
                    Text("Simulated time").foregroundStyle(.secondary)
                    Slider(value: $cursor, in: 0...Double(samples.count - 1), step: 1) {
                        Text("Simulated time")
                    }
                    .labelsHidden()
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
                        let reference = selected.referenceSample[keyPath: signal.value]
                        let current = selected.currentSample[keyPath: signal.value]
                        GridRow {
                            Label(signal.name, systemImage: "circle.fill")
                                .foregroundStyle(signal.color)
                            reading(reference, unit: signal.unit)
                            reading(current, unit: signal.unit)
                            reading(current - reference, unit: signal.unit)
                        }
                    }
                    if let referenceLength = referenceResidual, let currentLength = currentResidual {
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

    private var choosesSignal: Bool {
        switch preset {
        case nil, .tensionCoupon, .materialImpact, .layeredSeam, .layeredImpact, .offAxisImpact: true
        default: false
        }
    }

    private static func details(_ trace: SceneTrace) -> String {
        let stop = trace.preset == .layeredImpact ? (trace.hasBackstop ? "Backstop" : "Free specimen") : nil
        return [trace.seamResponse?.rawValue, trace.materialResponse?.rawValue, stop].compactMap { $0 }.joined(separator: " · ")
    }

    private func runLegend(_ title: String, details: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
            if !details.isEmpty { Text(details) }
        }
    }

    private func reading(_ value: Double, unit: String) -> some View {
        Text(String(format: "%.4f", value) + (unit == "%" || unit == "°" ? "" : " ") + unit)
            .monospacedDigit()
            .gridColumnAlignment(.trailing)
    }

    private var chart: some View {
        Canvas { context, size in
            let signals = choosesSignal ? [series[selectedSignal]] : series
            let time = samples.last!.time
            var low = Double.infinity
            var high = -Double.infinity
            for sample in samples {
                for signal in signals {
                    low = min(low, sample.referenceSample[keyPath: signal.value], sample.currentSample[keyPath: signal.value])
                    high = max(high, sample.referenceSample[keyPath: signal.value], sample.currentSample[keyPath: signal.value])
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
                            let value = (isReference ? sample.referenceSample : sample.currentSample)[keyPath: signal.value]
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
