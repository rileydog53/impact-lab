import AppKit
import ImpactPhysics
import SwiftUI

private let ink = Color(red: 0.82, green: 0.88, blue: 0.92)
private let mint = Color(red: 0.42, green: 0.88, blue: 0.78)
private let amber = Color(red: 1, green: 0.64, blue: 0.38)
private let labBackground = Color(red: 0.06, green: 0.09, blue: 0.12)
private let panel = Color(red: 0.09, green: 0.13, blue: 0.17)

struct TraceSample: Equatable {
    let time: Double
    let values: Point
}

@MainActor @Observable final class Experiment {
    private(set) var preset = Preset.bar
    var stiffness = 1.0
    var speed = 0.4
    var density = 1000.0
    var poisson = 0.0
    var running = false
    private(set) var simulation = Simulation()
    private(set) var trace = [TraceSample(time: 0, values: .zero)]
    private var lastTick: Double?
    private var budget = 0.0
    private var lastSample = 0.0

    func select(_ newPreset: Preset) {
        preset = newPreset
        reset()
    }

    func reset() {
        running = false
        let material = Material(young: stiffness * 1e6, density: density, poisson: poisson)
        simulation = preset.makeSimulation(material: material, speed: speed)
        trace = [TraceSample(time: 0, values: traceValues)]
        lastTick = nil
        lastSample = 0
        budget = 0
    }

    func toggle() {
        guard simulation.failure == nil, !finished else { return }
        running.toggle()
        lastTick = nil
        budget = 0
    }

    func tick(now: Double = ProcessInfo.processInfo.systemUptime) {
        guard running else { return }
        defer { lastTick = now }
        guard let lastTick else { return }
        budget += min(0.05, max(0, now - lastTick)) * playbackRate
        let deadline = ProcessInfo.processInfo.systemUptime + 0.008
        while budget >= simulation.dt {
            guard advance() else { return }
            budget -= simulation.dt
            if finished { return }
            if ProcessInfo.processInfo.systemUptime > deadline {
                budget = min(budget, simulation.dt)
                break
            }
        }
    }

    private var playbackRate: Double { preset == .bar ? 0.020 : 0.045 }

    var horizon: Double {
        let duration = preset == .bar ? 0.062 : 0.26
        return simulation.gap / speed + duration * Material().waveSpeed / simulation.body.material.waveSpeed
    }

    var finished: Bool { simulation.time >= horizon }

    private var traceValues: Point {
        switch preset {
        case .bar: Point(simulation.probeStrain * 100, 0)
        case .ring: simulation.body.diameters * 1000
        }
    }

    @discardableResult func advance() -> Bool {
        guard !finished, simulation.step() else {
            running = false
            return false
        }
        if simulation.time - lastSample >= horizon / 600 || finished || !running {
            trace.append(TraceSample(time: simulation.time, values: traceValues))
            lastSample = simulation.time
            if trace.count > 1400 { trace.remove(at: 1) }
        }
        if finished { running = false }
        return true
    }
}

@main struct ImpactLab: App {
    var body: some Scene {
        WindowGroup("Impact Lab") {
            LabView()
                .frame(minWidth: 860, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1050, height: 660)
    }
}

struct LabView: View {
    @State private var experiment = Experiment()
    private let refresh = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Impact Lab").font(.system(size: 31, weight: .semibold))
                        Text(experiment.preset.rawValue).font(.subheadline).foregroundStyle(mint)
                    }
                    Spacer()
                    Text(experiment.simulation.time * 1000, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit().font(.system(size: 25, weight: .medium, design: .monospaced))
                    Text("ms").foregroundStyle(.secondary)
                }
                impactCanvas
                    .frame(minHeight: 230, maxHeight: .infinity)
                    .background(panel, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    if experiment.preset == .bar {
                        Text("Axial strain at probe").font(.headline)
                        Spacer()
                        Text("0.50 m from impact face").foregroundStyle(.secondary)
                    } else {
                        Text("Ring diameters").font(.headline)
                        Spacer()
                        Text("Horizontal").foregroundStyle(mint)
                        Text("Vertical").foregroundStyle(amber)
                    }
                }
                traceCanvas
                    .frame(height: 125)
                    .background(panel, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Experiment").font(.title3.bold())
                    Picker("Preset", selection: Binding(get: { experiment.preset }, set: { newPreset in experiment.select(newPreset) })) {
                        ForEach(Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    control("Young’s modulus", unit: "MPa", value: $experiment.stiffness, range: 0.5...4, step: 0.05)
                    control("Impact speed", unit: "m/s", value: $experiment.speed, range: 0.1...1, step: 0.05)
                    control("Density", unit: "kg/m³", value: $experiment.density, range: 500...2500, step: 50, digits: 0)
                    control("Poisson ratio", unit: "", value: $experiment.poisson, range: 0...0.35, step: 0.01)
                    HStack {
                        Button(experiment.running ? "Pause" : "Run", systemImage: experiment.running ? "pause.fill" : "play.fill") {
                            experiment.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(mint)
                        .foregroundStyle(labBackground)
                        .keyboardShortcut(.space, modifiers: [])
                        .disabled(experiment.simulation.failure != nil || experiment.finished)
                        Button("Step", systemImage: "forward.frame") { experiment.advance() }
                            .disabled(experiment.running || experiment.simulation.failure != nil || experiment.finished)
                            .help("Advance one physical timestep")
                    }
                    Button("Reset", systemImage: "arrow.counterclockwise") { experiment.reset() }
                    Divider()
                    readings
                    if let failure = experiment.simulation.failure {
                        Text(failure).foregroundStyle(amber)
                    } else if experiment.finished {
                        Text("Run complete").foregroundStyle(mint).font(.caption)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(amber).frame(width: 8, height: 8)
                        Text("Compression")
                        Circle().fill(mint).frame(width: 8, height: 8)
                        Text("Tension")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .frame(width: 252)
            .background(panel)
        }
        .foregroundStyle(ink)
        .background(labBackground)
        .onReceive(refresh) { _ in experiment.tick() }
        .task { await smokeCheck() }
    }

    private func control(_ title: String, unit: String, value: Binding<Double>,
                         range: ClosedRange<Double>, step: Double, digits: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(digits))) +
                 (unit.isEmpty ? "" : " " + unit))
                .font(.system(.callout, design: .monospaced)).foregroundStyle(mint)
            Slider(value: Binding(get: { value.wrappedValue }, set: {
                value.wrappedValue = $0
                experiment.reset()
            }), in: range, step: step) { Text(title) }
                .tint(mint)
        }
    }

    private var readings: some View {
        let simulation = experiment.simulation
        let d = simulation.diagnostics
        return VStack(alignment: .leading, spacing: 5) {
            Text("Diagnostics").font(.headline).padding(.bottom, 3)
            reading("Timestep", simulation.dt * 1e6, "µs", "%.2f")
            reading("Peak penetration", simulation.peakPenetration * 1000, "mm", "%.3f")
            reading("Wall impulse", simulation.wallImpulse, "N·s/m", "%.3f")
            reading("Kinetic energy", d.kinetic, "J/m", "%.3f")
            reading("Elastic energy", d.elastic, "J/m", "%.3f")
            reading("Contact energy", d.contact, "J/m", "%.3f")
            reading("Energy imbalance", 100 * d.relativeEnergyError, "%", "%+.3f")
        }
    }

    private func reading(_ name: String, _ value: Double, _ unit: String, _ format: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(String(format: format, value) + " " + unit).monospacedDigit()
        }
        .font(.caption)
    }

    private var impactCanvas: some View {
        Canvas { context, size in
            let sceneWidth = experiment.preset == .bar ? 1.15 : 0.70
            let scale = min((size.width - 65) / sceneWidth, (size.height - 60) / 0.52)
            let wall = size.width - 32
            let middle = size.height / 2
            func project(_ p: Point) -> CGPoint {
                CGPoint(x: wall + scale * p.x, y: middle - scale * p.y)
            }
            let simulation = experiment.simulation
            let nodes = simulation.body.position.map(project)
            let mesh = simulation.body.mesh
            var grid = Path()
            for i in 0...10 {
                let x = wall - Double(i) * scale / 10
                grid.move(to: CGPoint(x: x, y: 25))
                grid.addLine(to: CGPoint(x: x, y: size.height - 28))
            }
            context.stroke(grid, with: .color(ink.opacity(0.09)))
            let levels = 10
            var patches = Array(repeating: Path(), count: levels * 2 + 1)
            for (i, e) in mesh.elements.enumerated() {
                let strain = simulation.strain[i]
                let intensity = min(1, sqrt(abs(strain) / 0.014))
                let offset = Int((intensity * Double(levels)).rounded())
                let bucket = levels + (strain < 0 ? -offset : offset)
                patches[bucket].move(to: nodes[e.a])
                patches[bucket].addLine(to: nodes[e.b])
                patches[bucket].addLine(to: nodes[e.c])
                patches[bucket].closeSubpath()
            }
            let neutral = Color(red: 0.18, green: 0.33, blue: 0.42)
            for (i, patch) in patches.enumerated() where !patch.isEmpty {
                let intensity = Double(abs(i - levels)) / Double(levels)
                context.fill(patch, with: .color(neutral))
                context.fill(patch, with: .color((i < levels ? amber : mint).opacity(intensity)))
            }
            var outline = Path()
            for edge in mesh.boundary {
                outline.move(to: nodes[edge.a])
                outline.addLine(to: nodes[edge.b])
            }
            context.stroke(outline, with: .color(ink), lineWidth: 1.4)
            if experiment.preset == .bar {
                let probe = project(simulation.body.probePosition ?? Point(-0.5, 0)).x
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: probe, y: 40))
                    p.addLine(to: CGPoint(x: probe, y: size.height - 35))
                }, with: .color(mint), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                context.draw(Text("PROBE").font(.caption2.monospaced()).foregroundStyle(mint),
                             at: CGPoint(x: probe, y: 25))
            }
            context.stroke(Path { p in
                p.move(to: CGPoint(x: wall, y: 29))
                p.addLine(to: CGPoint(x: wall, y: size.height - 24))
            }, with: .color(ink), lineWidth: 3)
            context.draw(Text("WALL").font(.caption2.monospaced()).foregroundStyle(ink),
                         at: CGPoint(x: wall - 22, y: size.height - 15))
        }
        .accessibilityLabel("Deforming specimen and fixed wall")
    }

    private var traceCanvas: some View {
        Canvas { context, size in
            let trace = experiment.trace
            let end = experiment.horizon
            let ring = experiment.preset == .ring
            let center = ring ? 400.0 : 0.0
            var peak = ring ? 1.0 : 0.1
            for sample in trace {
                peak = max(peak, abs(sample.values.x - center) * 1.12)
                if ring { peak = max(peak, abs(sample.values.y - center) * 1.12) }
            }
            let left = 67.0, right = size.width - 29
            let middle = (size.height - 17) / 2
            for fraction in [-1.0, 0, 1] {
                let y = middle - fraction * (middle - 12)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: left, y: y))
                    p.addLine(to: CGPoint(x: right, y: y))
                }, with: .color(ink.opacity(0.18)))
                let value = center + fraction * peak
                let label = ring ? String(format: "%.1f mm", value) : String(format: "%+.2f%%", value)
                context.draw(Text(label).font(.caption2.monospaced()).foregroundStyle(ink),
                             at: CGPoint(x: left - 6, y: y), anchor: .trailing)
            }
            for (t, x) in [(0.0, left), (end, right)] {
                context.draw(Text(String(format: "%.0f ms", t * 1000)).font(.caption2.monospaced())
                    .foregroundStyle(ink), at: CGPoint(x: x, y: size.height - 9))
            }
            func line(_ values: KeyPath<Point, Double>) -> Path {
                Path { p in
                    for (i, sample) in trace.enumerated() {
                        let x = left + (right - left) * sample.time / end
                        let y = middle - (middle - 12) * (sample.values[keyPath: values] - center) / peak
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
            }
            context.stroke(line(\.x), with: .color(mint), lineWidth: 1.8)
            if ring { context.stroke(line(\.y), with: .color(amber), lineWidth: 1.8) }
        }
        .accessibilityLabel(experiment.preset == .bar ? "Axial strain versus time" : "Diameters versus time")
    }

    private func smokeCheck() async {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--smoke"), args.indices.contains(flag + 1) else { return }
        try? await Task.sleep(for: .milliseconds(250))
        let windowVisible = NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" }
        var results = ["window=\(windowVisible)"]
        for preset in Preset.allCases {
            experiment.speed = 0.4
            experiment.stiffness = 1
            experiment.density = 1000
            experiment.poisson = 0
            experiment.select(preset)
            experiment.toggle()
            let start = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(for: .milliseconds(1000))
            let playbackRate = experiment.simulation.time / (ProcessInfo.processInfo.systemUptime - start)
            experiment.toggle()
            let pausedTime = experiment.simulation.time
            try? await Task.sleep(for: .milliseconds(100))
            let paused = pausedTime > 0 && experiment.simulation.time == pausedTime
            let step = experiment.advance()
                && abs(experiment.simulation.time - pausedTime - experiment.simulation.dt) < 1e-12
            let traceAdvanced = experiment.trace.count > 2
                && experiment.trace.contains { $0.values != experiment.trace[0].values }
            experiment.speed = 0.6
            experiment.density = 1500
            experiment.poisson = 0.2
            experiment.stiffness = 4
            experiment.reset()
            let reset = experiment.simulation.time == 0 && experiment.trace.count == 1
                && experiment.simulation.body.material.young == 4e6
                && experiment.simulation.body.velocity[0].x == 0.6
                && experiment.simulation.body.material.density == 1500
                && experiment.simulation.body.material.poisson == 0.2
                && experiment.simulation.wallImpulse == 0
            results.append(String(format: "%@: run/pause=%@ single-step=%@ inspect=%@ edit/reset=%@ playback=%.3f sim s/wall s",
                                  preset.rawValue, paused.description, step.description,
                                  traceAdvanced.description, reset.description, playbackRate))
        }
        try? (results.joined(separator: "\n") + "\n").write(
            toFile: args[flag + 1], atomically: true, encoding: .utf8)
        NSApplication.shared.terminate(nil)
    }
}
