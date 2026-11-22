import AppKit
import ImpactPhysics
import SwiftUI
import UniformTypeIdentifiers

private let ink = Color(red: 0.82, green: 0.88, blue: 0.92)
private let mint = Color(red: 0.42, green: 0.88, blue: 0.78)
private let amber = Color(red: 1, green: 0.64, blue: 0.38)
private let labBackground = Color(red: 0.06, green: 0.09, blue: 0.12)
private let panel = Color(red: 0.09, green: 0.13, blue: 0.17)

private extension Preset {
    var pairLabels: (first: String, second: String)? {
        switch self {
        case .twoBars: ("Left bar", "Right bar")
        case .puckStrip: ("Puck", "Strip")
        default: nil
        }
    }
}

@MainActor @Observable final class Experiment {
    static let initialPreset = Preset.twoBars
    private var run = try! SceneRun(.standard(initialPreset))
    private var drafts: [Preset: SceneConfiguration] = [:]
    private(set) var reference: SceneTrace?
    private(set) var running = false
    var fileError: String?
    private var lastTick: Double?
    private var budget = 0.0

    var configuration: SceneConfiguration { run.configuration }
    var preset: Preset { configuration.preset }
    var simulation: Simulation { run.simulation }
    var trace: [TraceSample] { run.samples }
    var horizon: Double { run.horizon }
    var finished: Bool { run.finished }
    var angle: Double { simulation.body.orientation * 180 / .pi }
    var canCompare: Bool { reference?.preset == preset && trace.count > 1 }

    func configure(_ configuration: SceneConfiguration) throws {
        let next = try SceneRun(configuration)
        running = false
        run = next
        drafts[configuration.preset] = configuration
        lastTick = nil
        budget = 0
    }

    func edit(_ draft: SceneConfiguration) {
        do { try configure(draft) }
        catch { fileError = error.localizedDescription }
    }

    func select(_ preset: Preset) {
        edit(drafts[preset] ?? .standard(preset))
    }

    func reset() { edit(configuration) }

    func save(to url: URL) throws {
        try configuration.save(to: url)
    }

    func open(_ url: URL) throws {
        try configure(SceneConfiguration.open(url))
    }

    func pinReference() {
        pause()
        reference = run.trace
    }

    func comparison() -> [SceneTrace.Match] {
        guard let reference else { return [] }
        return run.trace.matching(reference)
    }

    func pause() {
        if running { toggle() }
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

    private var playbackRate: Double {
        switch preset {
        case .bar, .bondedBar: 0.020
        case .ring, .block: 0.045
        case .twoBars: 0.065
        case .puckStrip: 0.075
        }
    }

    @discardableResult func advance() -> Bool {
        guard run.step() else {
            running = false
            return false
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
    @State private var showComparison = false
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
                        Text("\(experiment.configuration.first.width / 2, specifier: "%.2f") m from impact face")
                            .foregroundStyle(.secondary)
                    case .bondedBar:
                        Text("Axial strain at probe").font(.headline)
                        Spacer()
                        Text("Incident and reflected pulses").foregroundStyle(.secondary)
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
                    case .twoBars, .puckStrip:
                        Text("Center-of-mass velocity").font(.headline)
                        Spacer()
                        if let labels = experiment.preset.pairLabels {
                            Text(labels.first).foregroundStyle(mint)
                            Text(labels.second).foregroundStyle(amber)
                        }
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
                    HStack {
                        Button("Open…", systemImage: "folder", action: openScene)
                        Button("Save…", systemImage: "square.and.arrow.down", action: saveScene)
                    }
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
                        Button("Reset", systemImage: "arrow.counterclockwise") { experiment.reset() }
                            .labelStyle(.iconOnly)
                            .help("Reset to the configured initial state")
                    }
                    HStack {
                        Button("Pin reference", systemImage: "pin") { experiment.pinReference() }
                            .disabled(experiment.trace.count < 2)
                        Button("Compare", systemImage: "chart.xyaxis.line") {
                            experiment.pause()
                            showComparison = true
                        }
                        .disabled(!experiment.canCompare)
                    }
                    if let reference = experiment.reference {
                        Text("Reference · \(reference.preset.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    SceneEditor(experiment: experiment)
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
                    if experiment.preset == .puckStrip {
                        Text("Puck strain along impact · Strip strain along length")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(22)
            }
            .frame(width: 286)
            .background(panel)
        }
        .foregroundStyle(ink)
        .background(labBackground)
        .onReceive(refresh) { _ in experiment.tick() }
        .task { await smokeCheck() }
        .sheet(isPresented: $showComparison) {
            ComparisonView(preset: experiment.preset, samples: experiment.comparison())
        }
        .alert("Scene File", isPresented: Binding(get: { experiment.fileError != nil },
                                                  set: { if !$0 { experiment.fileError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(experiment.fileError ?? "")
        }
    }

    private func openScene() {
        experiment.pause()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try experiment.open(url) }
        catch { experiment.fileError = error.localizedDescription }
    }

    private func saveScene() {
        experiment.pause()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = experiment.preset.rawValue + ".impact.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try experiment.save(to: url) }
        catch { experiment.fileError = error.localizedDescription }
    }

    private var readings: some View {
        let simulation = experiment.simulation
        let d = simulation.diagnostics
        return VStack(alignment: .leading, spacing: 5) {
            Text("Diagnostics").font(.headline).padding(.bottom, 3)
            reading("Timestep", simulation.dt * 1e6, "µs", "%.2f")
            if !experiment.configuration.isBonded {
                reading("Peak penetration", simulation.peakPenetration * 1000, "mm", "%.3f")
            }
            if experiment.preset == .puckStrip {
                reading("Peak overlap / edge", simulation.peakRelativePenetration * 100, "%", "%.2f")
            }
            if simulation.secondBody == nil && !experiment.configuration.isBonded {
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
            let puckStrip = experiment.preset == .puckStrip
            let scene = experiment.configuration
            let free = second != nil || scene.isBonded
            let initialWidth = experiment.preset == .bar ? 1.15 : 0.70
            let primary = simulation.body.position
            let farthestLeft = min(primary.map(\.x).min() ?? 0, second?.position.map(\.x).min() ?? .infinity)
            let farthestRight = max(primary.map(\.x).max() ?? 0, second?.position.map(\.x).max() ?? -.infinity)
            let farthestVertical = max(primary.map { abs($0.y - scene.centerY) }.max() ?? 0,
                                       second?.position.map { abs($0.y - scene.centerY) }.max() ?? 0)
            let sceneCenter = scene.targetX + (puckStrip ? -0.045 : (scene.isBonded ? -0.10 : 0.054))
            let minimumHalfWidth = puckStrip ? 0.16 : (scene.isBonded ? 0.99 : 0.63)
            let sceneWidth = free ? 2 * max(minimumHalfWidth, sceneCenter - farthestLeft, farthestRight - sceneCenter)
                : max(initialWidth, -farthestLeft + 0.1)
            let sceneHeight = max(0.52, 2 * farthestVertical + (puckStrip ? 0.12 : 0.08))
            let scale = min((size.width - 65) / sceneWidth, (size.height - 60) / sceneHeight)
            let wall = size.width - 32
            let origin = free ? size.width / 2 - sceneCenter * scale : wall
            let middle = size.height / 2
            func project(_ p: Point) -> CGPoint {
                CGPoint(x: origin + scale * p.x, y: middle - scale * (p.y - scene.centerY))
            }
            var grid = Path()
            let gridsPerMetre = puckStrip ? 20.0 : 10.0
            let firstGrid = !free ? -Int(sceneWidth * gridsPerMetre)
                : Int(ceil((sceneCenter - sceneWidth / 2) * gridsPerMetre))
            let lastGrid = !free ? 0 : Int(floor((sceneCenter + sceneWidth / 2) * gridsPerMetre))
            for i in firstGrid...lastGrid {
                let x = project(Point(Double(i) / gridsPerMetre, 0)).x
                grid.move(to: CGPoint(x: x, y: 25))
                grid.addLine(to: CGPoint(x: x, y: size.height - 28))
            }
            context.stroke(grid, with: .color(ink.opacity(0.09)))
            let levels = 10
            let strainScale = scene.isBonded ? 0.0015 : 0.014
            var patches = Array(repeating: Path(), count: levels * 2 + 1)
            var outline = Path()
            func drawMesh(_ body: ImpactPhysics.Body, strain: [Double]) {
                let nodes = body.position.map(project)
                for (i, e) in body.mesh.elements.enumerated() {
                    let value = strain[i]
                    let intensity = min(1, sqrt(abs(value) / strainScale))
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
            if let station = simulation.body.probePosition {
                let probe = project(station).x
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
            if let second, let labels = experiment.preset.pairLabels {
                for (body, label, color) in [(simulation.body, labels.first, mint), (second, labels.second, amber)] {
                    let top = body.position.map(\.y).max() ?? 0
                    let labelPosition = project(Point(body.centerOfMass.x, top + 0.026))
                    context.draw(Text(label.uppercased()).font(.caption2.monospaced()).foregroundStyle(color),
                                 at: labelPosition)
                }
            } else if scene.isBonded {
                let bond = simulation.body.mesh.interfaceNodes.map { project(primary[$0]) }
                if let bottom = bond.first, let top = bond.last {
                    context.stroke(Path { p in
                        p.move(to: bottom)
                        for point in bond.dropFirst() { p.addLine(to: point) }
                    }, with: .color(amber), style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                    context.draw(Text("BOND").font(.caption2.monospaced()).foregroundStyle(amber),
                                 at: CGPoint(x: top.x, y: top.y - 15))
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
        .accessibilityLabel(experiment.preset.pairLabels.map { "Deforming \($0.first.lowercased()) and \($0.second.lowercased())" }
                            ?? (experiment.configuration.isBonded ? "Bonded bar and strain probe" : "Deforming specimen and fixed wall"))
    }

    private var traceCanvas: some View {
        Canvas { context, size in
            let trace = experiment.trace
            let end = max(experiment.horizon, trace.last?.time ?? 0)
            let ring = experiment.preset == .ring
            let block = experiment.preset == .block
            let bonded = experiment.preset == .bondedBar
            let velocityTrace = experiment.preset.pairLabels != nil
            let initial = trace.first?.values.x ?? 0
            let initialTargetSpeed = trace.first?.values.y ?? 0
            let center = velocityTrace ? (initial + initialTargetSpeed) / 2 : initial
            var peak = velocityTrace ? abs(initial - initialTargetSpeed) * 0.5
                : (ring || block ? 1.0 : (bonded ? 0.01 : 0.1))
            for sample in trace {
                let padding = velocityTrace ? 1.0 : 1.12
                peak = max(peak, abs(sample.values.x - center) * padding)
                if ring || velocityTrace { peak = max(peak, abs(sample.values.y - center) * padding) }
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
                else if velocityTrace { label = String(format: "%.2f m/s", value) }
                else { label = String(format: bonded ? "%+.3f%%" : "%+.2f%%", value) }
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
            if ring || velocityTrace { context.stroke(line(\.y), with: .color(amber), lineWidth: 1.8) }
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
            let isPair = preset.pairLabels != nil
            experiment.select(preset)
            let selected = experiment.preset == preset && experiment.simulation.time == 0
            let topology = experiment.simulation.body.mesh.elements.count
                + (experiment.simulation.secondBody?.mesh.elements.count ?? 0)
            experiment.toggle()
            let start = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(for: .milliseconds(isPair ? 1300 : 1400))
            let playbackRate = experiment.simulation.time / (ProcessInfo.processInfo.systemUptime - start)
            experiment.toggle()
            let pausedTime = experiment.simulation.time
            try? await Task.sleep(for: .milliseconds(100))
            let paused = pausedTime > 0 && experiment.simulation.time == pausedTime
            let step = experiment.advance()
                && abs(experiment.simulation.time - pausedTime - experiment.simulation.dt) < 1e-12
            let inspected = preset == .bondedBar
                ? experiment.simulation.body.mesh.interfaceNodes.count == 5
                : experiment.simulation.peakPenetration > 0 && (isPair || experiment.simulation.wallImpulse > 0)
            let traceAdvanced = experiment.trace.count > 2 && inspected
                && experiment.trace.contains { abs($0.values.x - experiment.trace[0].values.x) > 1e-3 }
                && experiment.simulation.diagnostics.relativeEnergyError.isFinite
            if isPair {
                experiment.toggle()
                for _ in 0..<50 where experiment.running {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let final = experiment.simulation
                let clearance = final.secondBody.map { final.body.boundaryClearance(to: $0) } ?? 0
                let separated = experiment.finished && experiment.simulation.failure == nil
                    && clearance > 0.001 && final.diagnostics.contact == 0
                if preset == .twoBars {
                    let exchanged = abs(experiment.trace.last?.values.x ?? .infinity) < 0.008
                        && abs((experiment.trace.last?.values.y ?? .infinity) - 0.4) < 0.008
                    results.append("Two-bar playback: complete separation=\(separated) velocity exchange=\(exchanged)")
                } else {
                    let puckStrain = final.strain.contains { abs($0) > 0.0001 }
                    let stripStrain = final.secondStrain?.contains { abs($0) > 0.0001 } ?? false
                    let deformation = puckStrain && stripStrain
                    let overlap = final.peakRelativePenetration > 0 && final.peakRelativePenetration < 0.1
                    results.append("Puck and strip playback: complete separation=\(separated) both deform=\(deformation) bounded overlap=\(overlap)")
                }
            }
            var edited = experiment.configuration
            edited.speed = preset == .bondedBar ? 0.07 : 0.6
            edited.first.material = Material(young: 4e6, density: 1500, poisson: 0.2)
            edited.first.width *= 1.05
            edited.second?.material = Material(young: 2e6)
            edited.mirrored = preset == .block
            experiment.edit(edited)
            let resetSecond = !isPair || experiment.simulation.secondBody?.material == edited.second?.material
            let reset = experiment.simulation.time == 0 && experiment.trace.count == 1
                && experiment.configuration == edited
                && experiment.simulation.body.material == edited.first.material
                && experiment.simulation.wallImpulse == 0
                && resetSecond
                && (!edited.mirrored || abs(experiment.angle + 18) < 1e-9)
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
        do {
            let url = URL(fileURLWithPath: args[flag + 1]).deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".impact.json")
            defer { try? FileManager.default.removeItem(at: url) }
            let baseline = SceneConfiguration.standard(.puckStrip)
            try experiment.configure(baseline)
            while experiment.advance() {}
            let reference = experiment.trace
            experiment.pinReference()
            var edited = baseline
            edited.first.width = 0.146
            edited.second?.material.young = 1.5e6
            edited.second?.height = 0.41
            edited.gap = 0.01
            edited.puckOffsetY = 0.05
            edited.targetVelocityX = -0.02
            edited.speed = 0.5
            try experiment.configure(edited)
            try experiment.save(to: url)
            while experiment.advance() {}
            let before = experiment.trace
            try experiment.configure(baseline)
            try experiment.open(url)
            let restored = experiment.configuration == edited
            while experiment.advance() {}
            let replay = experiment.finished && experiment.trace == before
            let matches = experiment.comparison()
            let aligned = experiment.canCompare && before != reference && matches.count > 100 && matches.enumerated().allSatisfy {
                $0.element.time == before[$0.offset].time && $0.element.time == reference[$0.offset].time
            }
            showComparison = true
            try? await Task.sleep(for: .milliseconds(450))
            let sheet = NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true }
            showComparison = false
            results.append("Puck and strip scene: save/reopen=\(restored) identical replay=\(replay) matched times=\(aligned) comparison sheet=\(sheet)")
        } catch {
            results.append("Puck and strip scene: save/reopen=false error=\(error.localizedDescription)")
        }
        try? (results.joined(separator: "\n") + "\n").write(
            toFile: args[flag + 1], atomically: true, encoding: .utf8)
        NSApplication.shared.terminate(nil)
    }
}
