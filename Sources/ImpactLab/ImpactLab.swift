import AppKit
import ImpactPhysics
import SwiftUI

private let ink = Color(red: 0.82, green: 0.88, blue: 0.92)
private let mint = Color(red: 0.42, green: 0.88, blue: 0.78)
private let amber = Color(red: 1, green: 0.64, blue: 0.38)
private let labBackground = Color(red: 0.06, green: 0.09, blue: 0.12)
private let panel = Color(red: 0.09, green: 0.13, blue: 0.17)

@MainActor @Observable final class Experiment {
    var stiffness = 1.0
    var speed = 0.4
    var density = 1000.0
    var poisson = 0.0
    var running = false
    private(set) var simulation = Simulation()
    private(set) var trace: [Point] = [.zero]
    private var lastTick: Double?
    private var budget = 0.0
    private var lastSample = 0.0

    func reset() {
        running = false
        simulation = Simulation(material: Material(young: stiffness * 1e6, density: density,
                                                   poisson: poisson), speed: speed)
        trace = [.zero]
        lastTick = nil
        lastSample = 0
        budget = 0
    }

    func toggle() {
        guard simulation.failure == nil else { return }
        running.toggle()
        lastTick = nil
        budget = 0
    }

    func tick(now: Double = ProcessInfo.processInfo.systemUptime) {
        guard running else { return }
        defer { lastTick = now }
        guard let lastTick else { return }
        budget += min(0.05, max(0, now - lastTick)) * 0.012
        let deadline = ProcessInfo.processInfo.systemUptime + 0.008
        while budget >= simulation.dt {
            guard advance() else { return }
            budget -= simulation.dt
            if ProcessInfo.processInfo.systemUptime > deadline {
                budget = min(budget, simulation.dt)
                break
            }
        }
    }

    @discardableResult func advance() -> Bool {
        guard simulation.step() else {
            running = false
            return false
        }
        if simulation.time - lastSample >= 0.00016 {
            trace.append(Point(simulation.time, simulation.probeStrain * 100))
            lastSample = simulation.time
            if trace.count > 1000 { trace.removeFirst(250) }
        }
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
                        Text("Bar impact").font(.subheadline).foregroundStyle(mint)
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
                    Text("Axial strain at probe").font(.headline)
                    Spacer()
                    Text("0.50 m from impact face").foregroundStyle(.secondary)
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
                .disabled(experiment.simulation.failure != nil)
                Button("Step", systemImage: "forward.frame") { experiment.advance() }
                    .disabled(experiment.running || experiment.simulation.failure != nil)
                    .help("Advance one physical timestep")
                }
                Button("Reset", systemImage: "arrow.counterclockwise") { experiment.reset() }
                Divider()
                readings
                if let failure = experiment.simulation.failure {
                    Text(failure).foregroundStyle(amber)
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
            Slider(value: value, in: range, step: step) { Text(title) }
                .tint(mint)
        }
        .onChange(of: value.wrappedValue) { _, _ in experiment.reset() }
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
            let scale = min((size.width - 65) / 1.15, (size.height - 60) / 0.55)
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
            for (i, e) in mesh.elements.enumerated() {
                let strain = simulation.strain[i]
                let intensity = min(1, sqrt(abs(strain) / 0.014))
                let path = Path { p in
                    p.move(to: nodes[e.a])
                    p.addLine(to: nodes[e.b])
                    p.addLine(to: nodes[e.c])
                    p.closeSubpath()
                }
                context.fill(path, with: .color(Color(red: 0.18, green: 0.33, blue: 0.42)))
                context.fill(path, with: .color((strain < 0 ? amber : mint).opacity(intensity)))
            }
            var outline = Path()
            for edge in mesh.boundary {
                outline.move(to: nodes[edge.a])
                outline.addLine(to: nodes[edge.b])
            }
            context.stroke(outline, with: .color(ink), lineWidth: 1.4)
            let probe = project(Point(-0.5, 0)).x
            context.stroke(Path { p in
                p.move(to: CGPoint(x: probe, y: 40))
                p.addLine(to: CGPoint(x: probe, y: size.height - 35))
            }, with: .color(mint), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            context.draw(Text("PROBE").font(.caption2.monospaced()).foregroundStyle(mint),
                         at: CGPoint(x: probe, y: 25))
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
            let start = trace.first?.x ?? 0
            let end = max(start + 0.06, trace.last?.x ?? 0)
            let peak = max(0.1, (trace.map { abs($0.y) }.max() ?? 0) * 1.12)
            let left = 59.0, right = size.width - 18
            let middle = (size.height - 17) / 2
            for fraction in [-1.0, 0, 1] {
                let y = middle - fraction * (middle - 12)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: left, y: y))
                    p.addLine(to: CGPoint(x: right, y: y))
                }, with: .color(ink.opacity(0.18)))
                let label = String(format: "%+.2f%%", fraction * peak)
                context.draw(Text(label).font(.caption2.monospaced()).foregroundStyle(ink),
                             at: CGPoint(x: left - 6, y: y), anchor: .trailing)
            }
            for (t, x) in [(start, left), (end, right)] {
                context.draw(Text(String(format: "%.0f ms", t * 1000)).font(.caption2.monospaced())
                    .foregroundStyle(ink), at: CGPoint(x: x, y: size.height - 9))
            }
            let path = Path { p in
                for (i, sample) in trace.enumerated() {
                    let x = left + (right - left) * (sample.x - start) / (end - start)
                    let y = middle - (middle - 12) * sample.y / peak
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            context.stroke(path, with: .color(mint), lineWidth: 1.8)
        }
        .accessibilityLabel("Axial strain versus simulated time")
    }

    private func smokeCheck() async {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--smoke"), args.indices.contains(flag + 1) else { return }
        try? await Task.sleep(for: .milliseconds(250))
        let windowVisible = NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" }
        experiment.toggle()
        try? await Task.sleep(for: .milliseconds(300))
        experiment.toggle()
        let pausedTime = experiment.simulation.time
        try? await Task.sleep(for: .milliseconds(100))
        let paused = pausedTime > 0 && experiment.simulation.time == pausedTime
        let step = experiment.advance()
            && abs(experiment.simulation.time - pausedTime - experiment.simulation.dt) < 1e-12
        experiment.speed = 0.6
        experiment.density = 1500
        experiment.poisson = 0.2
        experiment.stiffness = 4
        experiment.reset()
        let reset = experiment.simulation.time == 0 && experiment.trace == [.zero]
            && experiment.simulation.body.material.young == 4e6
            && experiment.simulation.body.velocity[0].x == 0.6
            && experiment.simulation.body.material.density == 1500
            && experiment.simulation.body.material.poisson == 0.2
            && experiment.simulation.wallImpulse == 0
        try? "window=\(windowVisible) run/pause=\(paused) single-step=\(step) edit/reset=\(reset)\n"
            .write(toFile: args[flag + 1], atomically: true, encoding: .utf8)
        NSApplication.shared.terminate(nil)
    }
}
