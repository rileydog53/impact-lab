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
    private(set) var preset = Preset.twoBars
    var stiffness = 1.0
    var speed = 0.4
    var density = 1000.0
    var poisson = 0.0
    private(set) var running = false
    private(set) var mirrored = false
    private(set) var simulation = Preset.twoBars.makeSimulation()
    private(set) var trace: [TraceSample] = []
    private var lastTick: Double?
    private var budget = 0.0
    private var lastSample = 0.0

    init() {
        trace = [TraceSample(time: 0, values: traceValues)]
    }

    func select(_ newPreset: Preset) {
        preset = newPreset
        reset()
    }

    func mirror(_ enabled: Bool) {
        mirrored = enabled
        reset()
    }

    func reset() {
        running = false
        let material = Material(young: stiffness * 1e6, density: density, poisson: poisson)
        simulation = preset.makeSimulation(material: material, speed: speed, mirrored: mirrored)
        trace = [TraceSample(time: 0, values: traceValues)]
        lastTick = nil
        lastSample = 0
        budget = 0
    }

    func toggle() {
        guard simulation.failure == nil, !finished else { return }
        running.toggle()
        if !running && simulation.time > lastSample { recordSample() }
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

    private var playbackRate: Double {
        switch preset {
        case .bar: 0.020
        case .ring, .block: 0.045
        case .twoBars: 0.065
        }
    }

    var horizon: Double {
        let duration: Double
        switch preset {
        case .bar: duration = 0.062
        case .ring: duration = 0.26
        case .block: duration = 0.17
        case .twoBars: duration = 0.070
        }
        let travel = simulation.gap / speed
        return (preset == .twoBars ? 2 * travel : travel)
            + duration * Material().waveSpeed / simulation.body.material.waveSpeed
    }

    var finished: Bool { simulation.time >= horizon }

    private var traceValues: Point {
        switch preset {
        case .bar: Point(simulation.probeStrain * 100, 0)
        case .ring: simulation.body.diameters * 1000
        case .block: Point(angle, 0)
        case .twoBars: Point(simulation.body.centerVelocity.x, simulation.secondBody!.centerVelocity.x)
        }
    }

    var angle: Double { simulation.body.orientation * 180 / .pi }

    private func recordSample() {
        trace.append(TraceSample(time: simulation.time, values: traceValues))
        lastSample = simulation.time
        if trace.count > 1400 { trace.remove(at: 1) }
    }

    @discardableResult func advance() -> Bool {
        guard !finished, simulation.step() else {
            running = false
            return false
        }
        if simulation.time - lastSample >= horizon / 600 || finished || !running {
            recordSample()
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
                    switch experiment.preset {
                    case .bar:
                        Text("Axial strain at probe").font(.headline)
                        Spacer()
                        Text("0.50 m from impact face").foregroundStyle(.secondary)
                    case .ring:
                        Text("Ring diameters").font(.headline)
                        Spacer()
                        Text("Horizontal").foregroundStyle(mint)
                        Text("Vertical").foregroundStyle(amber)
                    case .block:
                        Text("Block orientation").font(.headline)
                        Spacer()
                        Text(String(format: "%+.2f°", experiment.angle))
                            .monospacedDigit().foregroundStyle(mint)
                    case .twoBars:
                        Text("Center-of-mass velocity").font(.headline)
                        Spacer()
                        Text("Left bar").foregroundStyle(mint)
                        Text("Right bar").foregroundStyle(amber)
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
                    if experiment.preset == .block {
                        Toggle("Mirror tilt", isOn: Binding(get: { experiment.mirrored },
                                                          set: { experiment.mirror($0) }))
                    }
                    control("Young’s modulus", unit: "MPa", value: $experiment.stiffness, range: 0.5...4, step: 0.05)
                    control(experiment.preset == .twoBars ? "Left bar’s initial speed" : "Impact speed",
                            unit: "m/s", value: $experiment.speed, range: 0.1...1, step: 0.05)
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
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 5)
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(digits))) +
                     (unit.isEmpty ? "" : " " + unit))
                    .font(.system(.callout, design: .monospaced)).foregroundStyle(mint)
            }
            Slider(value: Binding(get: { value.wrappedValue }, set: {
                value.wrappedValue = $0
                experiment.reset()
            }), in: range, step: step) { Text(title) }
                .labelsHidden()
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
            if simulation.secondBody == nil {
                reading("Wall impulse", simulation.wallImpulse, "N·s/m", "%.3f")
            } else {
                reading("Total momentum x", d.momentum.x, "N·s/m", "%+.5f")
                reading("Total momentum y", d.momentum.y, "N·s/m", "%+.2e")
                reading("Angular momentum", d.angularMomentum, "N·m·s/m", "%+.2e")
            }
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
            Text(String(format: format, value) + (unit == "%" ? "" : " ") + unit).monospacedDigit()
        }
        .font(.caption)
    }

    private var impactCanvas: some View {
        Canvas { context, size in
            let simulation = experiment.simulation
            let second = simulation.secondBody
            let initialWidth = experiment.preset == .bar ? 1.15 : 0.70
            let farthestLeft = simulation.body.position.map(\.x).min() ?? 0
            let farthestRight = second?.position.map(\.x).max() ?? 0
            let farthestVertical = max(simulation.body.position.map { abs($0.y) }.max() ?? 0,
                                       second?.position.map { abs($0.y) }.max() ?? 0)
            let sceneCenter = second == nil ? 0 : 0.06
            let sceneWidth = second == nil ? max(initialWidth, -farthestLeft + 0.1)
                : 2 * max(0.63, sceneCenter - farthestLeft, farthestRight - sceneCenter)
            let sceneHeight = max(0.52, 2 * farthestVertical + 0.08)
            let scale = min((size.width - 65) / sceneWidth, (size.height - 60) / sceneHeight)
            let wall = size.width - 32
            let origin = second == nil ? wall : size.width / 2 - sceneCenter * scale
            let middle = size.height / 2
            func project(_ p: Point) -> CGPoint {
                CGPoint(x: origin + scale * p.x, y: middle - scale * p.y)
            }
            var grid = Path()
            let firstGrid = second == nil ? -Int(sceneWidth * 10) : Int(ceil((sceneCenter - sceneWidth / 2) * 10))
            let lastGrid = second == nil ? 0 : Int(floor((sceneCenter + sceneWidth / 2) * 10))
            for i in firstGrid...lastGrid {
                let x = project(Point(Double(i) / 10, 0)).x
                grid.move(to: CGPoint(x: x, y: 25))
                grid.addLine(to: CGPoint(x: x, y: size.height - 28))
            }
            context.stroke(grid, with: .color(ink.opacity(0.09)))
            let levels = 10
            var patches = Array(repeating: Path(), count: levels * 2 + 1)
            var outline = Path()
            func drawMesh(_ body: ImpactPhysics.Body, strain: [Double]) {
                let nodes = body.position.map(project)
                for (i, e) in body.mesh.elements.enumerated() {
                    let value = strain[i]
                    let intensity = min(1, sqrt(abs(value) / 0.014))
                    let offset = Int((intensity * Double(levels)).rounded())
                    let bucket = levels + (value < 0 ? -offset : offset)
                    patches[bucket].move(to: nodes[e.a])
                    patches[bucket].addLine(to: nodes[e.b])
                    patches[bucket].addLine(to: nodes[e.c])
                    patches[bucket].closeSubpath()
                }
                for edge in body.mesh.boundary {
                    outline.move(to: nodes[edge.a])
                    outline.addLine(to: nodes[edge.b])
                }
            }
            drawMesh(simulation.body, strain: simulation.strain)
            if let second, let strain = simulation.secondStrain { drawMesh(second, strain: strain) }
            let neutral = Color(red: 0.18, green: 0.33, blue: 0.42)
            for (i, patch) in patches.enumerated() where !patch.isEmpty {
                let intensity = Double(abs(i - levels)) / Double(levels)
                context.fill(patch, with: .color(neutral))
                context.fill(patch, with: .color((i < levels ? amber : mint).opacity(intensity)))
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
            if experiment.preset == .block {
                let center = simulation.body.centerOfMass
                let angle = simulation.body.orientation
                let halfAxis = 0.12 * Point(cos(angle), sin(angle))
                context.stroke(Path { p in
                    p.move(to: project(center - halfAxis))
                    p.addLine(to: project(center + halfAxis))
                }, with: .color(mint), style: StrokeStyle(lineWidth: 1.6, dash: [6, 4]))
                let c = project(center)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                             with: .color(mint))
            }
            if let second {
                for (body, label, color) in [(simulation.body, "LEFT BAR", mint), (second, "RIGHT BAR", amber)] {
                    let center = project(body.centerOfMass)
                    context.draw(Text(label).font(.caption2.monospaced()).foregroundStyle(color),
                                 at: CGPoint(x: center.x, y: center.y - 0.08 * scale))
                }
            } else {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: wall, y: 29))
                    p.addLine(to: CGPoint(x: wall, y: size.height - 24))
                }, with: .color(ink), lineWidth: 3)
                context.draw(Text("WALL").font(.caption2.monospaced()).foregroundStyle(ink),
                             at: CGPoint(x: wall - 22, y: size.height - 15))
            }
        }
        .accessibilityLabel(experiment.preset == .twoBars ? "Two deforming bars" : "Deforming specimen and fixed wall")
    }

    private var traceCanvas: some View {
        Canvas { context, size in
            let trace = experiment.trace
            let end = max(experiment.horizon, trace.last?.time ?? 0)
            let ring = experiment.preset == .ring
            let block = experiment.preset == .block
            let twoBars = experiment.preset == .twoBars
            let initial = trace.first?.values.x ?? 0
            let center = twoBars ? initial / 2 : initial
            var peak = twoBars ? initial * 0.5 : (ring || block ? 1.0 : 0.1)
            for sample in trace {
                let padding = twoBars ? 1.0 : 1.12
                peak = max(peak, abs(sample.values.x - center) * padding)
                if ring || twoBars { peak = max(peak, abs(sample.values.y - center) * padding) }
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
                let label: String
                if ring { label = String(format: "%.1f mm", value) }
                else if block { label = String(format: "%+.1f°", value) }
                else if twoBars { label = String(format: "%.2f m/s", value) }
                else { label = String(format: "%+.2f%%", value) }
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
            if ring || twoBars { context.stroke(line(\.y), with: .color(amber), lineWidth: 1.8) }
        }
        .accessibilityLabel("Time trace for " + experiment.preset.rawValue)
    }

    private func smokeCheck() async {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--smoke"), args.indices.contains(flag + 1) else { return }
        try? await Task.sleep(for: .milliseconds(250))
        let windowVisible = NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" }
        var results = ["window=\(windowVisible)", "opens on two bars=\(experiment.preset == .twoBars)"]
        for preset in Preset.allCases {
            experiment.speed = 0.4
            experiment.stiffness = 1
            experiment.density = 1000
            experiment.poisson = 0
            experiment.select(preset)
            let selected = experiment.preset == preset && experiment.simulation.time == 0
            let topology = experiment.simulation.body.mesh.elements.count
                + (experiment.simulation.secondBody?.mesh.elements.count ?? 0)
            experiment.toggle()
            let start = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(for: .milliseconds(preset == .twoBars ? 1300 : 1400))
            let playbackRate = experiment.simulation.time / (ProcessInfo.processInfo.systemUptime - start)
            experiment.toggle()
            let pausedTime = experiment.simulation.time
            try? await Task.sleep(for: .milliseconds(100))
            let paused = pausedTime > 0 && experiment.simulation.time == pausedTime
            let step = experiment.advance()
                && abs(experiment.simulation.time - pausedTime - experiment.simulation.dt) < 1e-12
            let impactObserved = preset == .twoBars || experiment.simulation.wallImpulse > 0
            let traceAdvanced = experiment.trace.count > 2 && impactObserved
                && experiment.trace.contains { abs($0.values.x - experiment.trace[0].values.x) > 1e-3 }
                && experiment.simulation.peakPenetration > 0
                && experiment.simulation.diagnostics.relativeEnergyError.isFinite
            if preset == .twoBars {
                experiment.toggle()
                for _ in 0..<50 where experiment.running {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let final = experiment.simulation
                let clearance = (final.secondBody?.position.map(\.x).min() ?? 0)
                    - (final.body.position.map(\.x).max() ?? 0)
                let separated = experiment.finished && experiment.simulation.failure == nil
                    && clearance > 0.005 && final.diagnostics.contact == 0
                let exchanged = abs(experiment.trace.last?.values.x ?? .infinity) < 0.008
                    && abs((experiment.trace.last?.values.y ?? .infinity) - 0.4) < 0.008
                results.append("Two-bar playback: complete separation=\(separated) velocity exchange=\(exchanged)")
            }
            let updateTilt = preset == .block
            experiment.speed = 0.6
            experiment.density = 1500
            experiment.poisson = 0.2
            experiment.stiffness = 4
            if updateTilt { experiment.mirror(true) }
            else { experiment.reset() }
            let resetSecond = preset != .twoBars || (
                experiment.simulation.secondBody?.material.young == 4e6
                    && experiment.simulation.secondBody?.velocity[0] == .zero
                    && experiment.simulation.peakPenetration == 0
            )
            let reset = experiment.simulation.time == 0 && experiment.trace.count == 1
                && experiment.simulation.body.material.young == 4e6
                && experiment.simulation.body.velocity[0].x == 0.6
                && experiment.simulation.body.material.density == 1500
                && experiment.simulation.body.material.poisson == 0.2
                && experiment.simulation.wallImpulse == 0
                && resetSecond
                && (!updateTilt || abs(experiment.angle + 18) < 1e-9)
            experiment.toggle()
            try? await Task.sleep(for: .milliseconds(400))
            experiment.toggle()
            let editedRun = experiment.simulation.time > 0 && experiment.simulation.failure == nil
            experiment.reset()
            results.append(String(format: "%@ (%d triangles): select=%@ run/pause=%@ single-step=%@ inspect=%@ edit/reset=%@ edited run=%@ playback=%.3f sim s/wall s",
                                  preset.rawValue, topology, selected.description, paused.description,
                                  step.description, traceAdvanced.description, reset.description,
                                  editedRun.description, playbackRate))
        }
        try? (results.joined(separator: "\n") + "\n").write(
            toFile: args[flag + 1], atomically: true, encoding: .utf8)
        NSApplication.shared.terminate(nil)
    }
}
