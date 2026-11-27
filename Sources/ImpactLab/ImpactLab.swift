import AppKit
import ImpactPhysics
import SwiftUI
import UniformTypeIdentifiers

private let ink = Color(red: 0.82, green: 0.88, blue: 0.92)
private let mint = Color(red: 0.42, green: 0.88, blue: 0.78)
private let sky = Color(red: 0.58, green: 0.78, blue: 1)
private let amber = Color(red: 1, green: 0.64, blue: 0.38)
private let labBackground = Color(red: 0.06, green: 0.09, blue: 0.12)
private let panel = Color(red: 0.09, green: 0.13, blue: 0.17)

private extension Preset {
    var pairLabels: (first: String, second: String)? {
        switch self {
        case .twoBars: ("Left bar", "Right bar")
        case .puckStrip: ("Puck", "Strip")
        case .layeredSeam: ("Left layer", "Right layer")
        case .layeredImpact, .offAxisImpact: ("Striker", "Facing layer")
        default: nil
        }
    }
}

@MainActor @Observable final class Experiment {
    static let initialPreset = Preset.offAxisImpact
    private var run = try! SceneRun(.standard(initialPreset))
    private var drafts: [Preset: SceneConfiguration] = [:]
    private(set) var reference: SceneTrace?
    private(set) var running = false
    var fileError: String?
    var slowerPlayback = false
    private var lastTick: Double?
    private var budget = 0.0

    var configuration: SceneConfiguration { run.configuration }
    var preset: Preset { configuration.preset }
    var simulation: Simulation { run.simulation }
    var trace: [TraceSample] { run.samples }
    var currentTrace: SceneTrace { run.trace }
    var residualLength: Double? { run.residualLength }
    var gaugeLength: Double? { run.gaugeLength }
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

    func setMaterialResponse(_ response: CouponResponse) {
        var draft = configuration
        guard let current = draft.impactPlasticity?.response ?? draft.tension?.response, current != response else { return }
        draft.impactPlasticity?.response = response
        draft.tension?.response = response
        edit(draft)
    }

    func setSeamResponse(_ response: SeamResponse) {
        var draft = configuration
        guard draft.seam?.response != response else { return }
        draft.seam?.response = response
        edit(draft)
    }

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
        budget += min(0.05, max(0, now - lastTick)) * playbackRate * (slowerPlayback ? 0.25 : 1)
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
        case .tensionCoupon: 0.105
        case .materialImpact: 0.026
        case .layeredSeam: 0.065
        case .offAxisImpact, .layeredImpact: 0.016
        }
    }

    func advance(to time: Double) {
        pause()
        while simulation.time < time && advance() {}
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

@main enum ImpactLab {
    @MainActor static func main() {
        // Cocoa treats a bare file path on the command line as "open this document"; this app has no document
        // handler, so with `--assembly-inspect <file> ...` that suppressed the window. Launch flags are not documents.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
        if #available(macOS 15.0, *) {
            PresentedLaboratory.main()
        } else {
            Laboratory.main()
        }
    }
}

@available(macOS 15.0, *)
private struct PresentedLaboratory: App {
    var body: some Scene {
        LaboratoryWindow().defaultLaunchBehavior(.presented)
        CreditsWindow().defaultLaunchBehavior(.suppressed)
    }
}

private struct Laboratory: App {
    var body: some Scene {
        LaboratoryWindow()
        CreditsWindow()
    }
}

private struct LaboratoryWindow: Scene {
    var body: some Scene {
        WindowGroup("Impact Lab") {
            LaboratoryTabs()
                .frame(minWidth: 940, minHeight: 660)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { ImpactLabCommands() }
    }
}

private struct CreditsWindow: Scene {
    var body: some Scene {
        Window("Credits and Licences", id: "credits") {
            CreditsView().preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}

private struct LaboratoryTabs: View {
    @State private var mode = CommandLine.arguments.contains("--smoke") || CommandLine.arguments.contains("--inspect-ms") ? 1 : 0

    var body: some View {
        TabView(selection: $mode) {
            AssemblyLab()
                .tabItem { Label("Assembly", systemImage: "square.3.layers.3d") }.tag(0)
            LabView()
                .tabItem { Label("Verified presets", systemImage: "waveform.path") }.tag(1)
        }
    }
}

struct LabView: View {
    @State private var experiment = Experiment()
    @State private var showComparison = false
    @State private var showPlasticStrain = false
    @State private var showFractureEnergy = false
    private var isCoupon: Bool { experiment.preset == .tensionCoupon }
    private var layeredImpact: Bool { experiment.configuration.hasImpactedLayers }
    private var offAxis: Bool { experiment.preset == .offAxisImpact }
    @State private var showReceiverVelocity = false
    private var isSeam: Bool { experiment.configuration.seam != nil }
    private var showsMaterialResponse: Bool { isCoupon || experiment.configuration.impactPlasticity != nil }
    private var showingPlastic: Bool { showsMaterialResponse && showPlasticStrain }
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
                    if showsMaterialResponse {
                        Picker("Color field", selection: $showPlasticStrain) {
                            Text("Axial strain").tag(false)
                            Text("Plastic strain").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 205)
                    }
                    Text(experiment.simulation.time * 1000, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit().font(.system(size: 25, weight: .medium, design: .monospaced))
                    Text("ms").foregroundStyle(.secondary)
                }
                impactCanvas
                    .frame(minHeight: 230, maxHeight: .infinity)
                    .background(panel, in: RoundedRectangle(cornerRadius: 12))
                if offAxis { eventReadings }
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
                    case .tensionCoupon, .materialImpact:
                        Text("Length change").font(.headline)
                        Spacer()
                        if let length = experiment.residualLength {
                            let change = 1000 * (length - experiment.configuration.first.width)
                            Text(String(format: "Residual %.2f mm (%+.2f mm)", 1000 * length, abs(change) < 0.005 ? 0 : change))
                                .foregroundStyle(mint).monospacedDigit()
                                .help("Mean end-to-end length over the final six wave transits after unloading")
                        } else if let length = experiment.gaugeLength {
                            Text("Length \(1000 * length, specifier: "%.2f") mm")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    case .offAxisImpact:
                        Picker("Motion trace", selection: $showReceiverVelocity) {
                            Text("Backing angle").tag(false)
                            Text("Receiver velocity X").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 275)
                        Spacer()
                        let signal = experiment.trace.last?.values ?? .zero
                        Text(showReceiverVelocity ? String(format: "%+.3f m/s", signal.y)
                             : String(format: "%+.1f°", signal.x))
                        .foregroundStyle(showReceiverVelocity ? amber : mint).monospacedDigit()
                    case .layeredSeam, .layeredImpact:
                        Picker("Seam trace", selection: $showFractureEnergy) {
                            Text("Mean opening").tag(false)
                            Text("Fracture energy").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 245)
                        Spacer()
                        if let seam = experiment.simulation.seamReadings {
                            Text(showFractureEnergy
                                 ? String(format: "%.2f J/m²", seam.dissipatedPerArea)
                                 : String(format: "%+.3f mm", 1000 * seam.opening))
                                .foregroundStyle(mint).monospacedDigit()
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
                    if layeredImpact {
                        Text(offAxis ? "Four deformable bodies · Free motion in X and Y" : "Collinear impact · Lateral guides")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if showsMaterialResponse {
                        Picker(layeredImpact ? "Striker and facing" : "Material response", selection: Binding(
                            get: { experiment.configuration.impactPlasticity?.response ?? experiment.configuration.tension?.response ?? .elastoplastic },
                            set: { experiment.setMaterialResponse($0) }
                        )) {
                            ForEach(CouponResponse.allCases, id: \.self) { response in
                                Text(response.rawValue).tag(response)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if isSeam {
                        Picker("Bond response", selection: Binding(
                            get: { experiment.configuration.seam?.response ?? .separating },
                            set: { experiment.setSeamResponse($0) }
                        )) {
                            ForEach(SeamResponse.allCases, id: \.self) { response in
                                Text(response.rawValue).tag(response)
                            }
                        }
                        .pickerStyle(.segmented)
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
                        if offAxis {
                            Button("+1 ms") { experiment.advance(to: experiment.simulation.time + 0.001) }
                                .disabled(experiment.running || experiment.simulation.failure != nil || experiment.finished)
                                .help("Advance at least one simulated millisecond, ending at the next solver step")
                        }
                        Button("Reset", systemImage: "arrow.counterclockwise") { experiment.reset() }
                            .labelStyle(.iconOnly)
                            .help("Reset to the configured initial state")
                    }
                    if offAxis {
                        Toggle("Quarter-speed playback", isOn: Binding(get: { experiment.slowerPlayback },
                                                                        set: { experiment.slowerPlayback = $0 }))
                            .font(.callout)
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
                        Text("Reference · \(reference.seamResponse?.rawValue ?? reference.materialResponse?.rawValue ?? reference.preset.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    SceneEditor(experiment: experiment)
                    Divider()
                    readings
                    if let failure = experiment.simulation.failure {
                        Text(failure).foregroundStyle(amber)
                    } else if experiment.finished {
                        Text(experiment.residualLength != nil ? "Unloaded · Run complete" : "Run complete")
                            .foregroundStyle(mint).font(.caption)
                        if showsMaterialResponse && !layeredImpact && experiment.residualLength == nil {
                            Text("Residual length requires a full unloading window.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Calculated").bold().help("Element values exactly as the solver recorded them.")
                        Circle().fill(amber).frame(width: 8, height: 8)
                        if showingPlastic {
                            Text("Accumulated plastic strain · 0–8%")
                        } else {
                            Text("Compression")
                            Circle().fill(mint).frame(width: 8, height: 8)
                            Text("Tension")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if experiment.preset == .puckStrip {
                        Text("Puck strain along impact · Strip strain along length")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(22)
            }
            .frame(width: offAxis ? 316 : 286)
            .background(panel)
        }
        .foregroundStyle(ink)
        .background(labBackground)
        .onReceive(refresh) { _ in experiment.tick() }
        .task { await inspectOnLaunch(); await smokeCheck() }
        .sheet(isPresented: $showComparison) {
            if let reference = experiment.reference {
                ComparisonView(reference: reference, current: experiment.currentTrace)
            }
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
        guard let url = ExperimentDirectory.run(panel) else { return }
        do { try experiment.open(url) }
        catch { experiment.fileError = error.localizedDescription }
    }

    private func saveScene() {
        experiment.pause()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = experiment.preset.rawValue + ".impact.json"
        guard let url = ExperimentDirectory.run(panel) else { return }
        do { try experiment.save(to: url) }
        catch { experiment.fileError = error.localizedDescription }
    }

    private var eventReadings: some View {
        let events = experiment.simulation.impactEvents
        return HStack(spacing: 8) {
            eventReading("Striker contact", time: events?.strike, color: mint)
            eventReading("Full bond failure", time: events?.failure, color: amber)
            eventReading("Backing hits receiver", time: events?.receiver, color: sky)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Measured event times")
    }

    private func eventReading(_ name: String, time: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(ink)
            Text(time.map { String(format: "%.2f ms", 1000 * $0) } ?? "Pending")
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(time == nil ? Color.secondary : color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private var readings: some View {
        let simulation = experiment.simulation
        let d = simulation.diagnostics
        return VStack(alignment: .leading, spacing: 5) {
            Text("Diagnostics").font(.headline).padding(.bottom, 3)
            reading("Timestep", simulation.dt * 1e6, "µs", "%.2f")
            if isCoupon {
                reading("Applied end stress", simulation.appliedTraction / 1000, "kPa", "%.2f")
                reading("Applied work", d.appliedWork, "J/m", "%.3f")
            }
            if showsMaterialResponse {
                reading(layeredImpact ? "Striker mean plastic strain" : "Mean plastic strain",
                        simulation.meanPlasticStrain * 100, "%", "%.3f")
                if layeredImpact {
                    reading("Facing mean plastic strain", simulation.facingMeanPlasticStrain * 100, "%", "%.3f")
                }
                reading("Peak plastic strain", simulation.peakPlasticStrain * 100, "%", "%.3f")
                reading("Peak |σzz|", d.peakOutOfPlaneStress / 1000, "kPa", "%.2f")
                reading("Modelled plastic dissipation", d.plasticDissipation, "J/m", "%.3f")
                reading("Stored hardening", d.hardening, "J/m", "%.3f")
            }
            if let seam = simulation.seamReadings {
                reading(offAxis ? "Sum of link tension" : "Seam force", seam.force, "N/m", "%+.2f")
                reading("Fully separated", 100 * seam.separatedFraction, "%", "%.1f")
                reading("Dissipated / area", seam.dissipatedPerArea, "J/m²", "%.3f")
                reading("Fracture energy Gc", seam.criticalEnergy, "J/m²", "%.3f")
                reading("Stored bond energy", d.bondEnergy, "J/m", "%.3f")
                if layeredImpact {
                    reading("Peak penetration", simulation.peakPenetration * 1000, "mm", "%.3f")
                    reading("Total momentum x", d.momentum.x, "N·s/m", "%+.5f")
                    if offAxis {
                        reading("Total momentum y", d.momentum.y, "N·s/m", "%+.5f")
                        reading("Total angular momentum", d.angularMomentum, "N·m·s/m", "%+.5f")
                        reading("Peak overlap / edge", 100 * simulation.peakRelativePenetration, "%", "%.2f")
                        reading("Backing velocity y", simulation.thirdBody!.centerVelocity.y, "m/s", "%+.3f")
                        reading("Receiver velocity y", simulation.receiverBody!.centerVelocity.y, "m/s", "%+.3f")
                        reading("Mean link extension", seam.opening * 1000, "mm", "%.2f")
                    }
                    if experiment.configuration.backstopX != nil {
                        reading("Backstop impulse", simulation.wallImpulse, "N·s/m", "%.3f")
                    }
                    reading("Total contact energy", d.contact, "J/m", "%.3f")
                    reading("Fracture dissipation", d.fractureDissipation, "J/m", "%.3f")
                } else {
                    reading("Closure contact energy", d.contact, "J/m", "%.3f")
                    reading("Grip work", d.appliedWork, "J/m", "%.3f")
                }
            } else if !isCoupon {
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
                reading("Contact energy", d.contact, "J/m", "%.3f")
            }
            reading("Kinetic energy", d.kinetic, "J/m", "%.3f")
            reading("Elastic energy", d.elastic, "J/m", "%.3f")
            reading(isCoupon || (isSeam && !layeredImpact) ? "Work balance error" : "Energy imbalance", 100 * d.relativeEnergyError, "%", "%+.3f")
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
            let third = simulation.thirdBody
            let receiver = simulation.receiverBody
            let puckStrip = experiment.preset == .puckStrip
            let scene = experiment.configuration
            let coupon = scene.tension != nil
            let free = second != nil || scene.isBonded || coupon
            let initialWidth = experiment.preset == .bar ? 1.15 : (scene.impactPlasticity != nil ? 0.52 : 0.70)
            let primary = simulation.body.position
            let farthestLeft = min(primary.map(\.x).min() ?? 0, second?.position.map(\.x).min() ?? .infinity,
                                   third?.position.map(\.x).min() ?? .infinity, receiver?.position.map(\.x).min() ?? .infinity)
            let farthestRight = max(primary.map(\.x).max() ?? 0, second?.position.map(\.x).max() ?? -.infinity,
                                    third?.position.map(\.x).max() ?? -.infinity, receiver?.position.map(\.x).max() ?? -.infinity, scene.backstopX ?? -.infinity)
            let farthestVertical = max(primary.map { abs($0.y - scene.centerY) }.max() ?? 0,
                                       second?.position.map { abs($0.y - scene.centerY) }.max() ?? 0,
                                       third?.position.map { abs($0.y - scene.centerY) }.max() ?? 0,
                                       receiver?.position.map { abs($0.y - scene.centerY) }.max() ?? 0)
            let sceneCenter = offAxis ? 0.088 : (layeredImpact ? 0.060
                : scene.targetX + (coupon || isSeam ? 0 : (puckStrip ? -0.045 : (scene.isBonded ? -0.10 : 0.054))))
            let minimumHalfWidth = offAxis ? 0.201 : (layeredImpact ? 0.164 : (isSeam ? 0.13 : (coupon ? 0.24 : (puckStrip ? 0.16 : (scene.isBonded ? 0.99 : 0.63)))))
            let sceneWidth = free ? 2 * max(minimumHalfWidth, sceneCenter - farthestLeft, farthestRight - sceneCenter)
                : max(initialWidth, -farthestLeft + 0.1)
            let sceneHeight = max(offAxis ? 0.19 : (coupon || isSeam ? 0.17 : 0.52),
                                  2 * farthestVertical + (puckStrip ? 0.12 : 0.08))
            let scale = min((size.width - 65) / sceneWidth, (size.height - 60) / sceneHeight)
            let wall = size.width - 32
            let origin = free ? size.width / 2 - sceneCenter * scale : wall
            let middle = size.height / 2
            func project(_ p: Point) -> CGPoint {
                CGPoint(x: origin + scale * p.x, y: middle - scale * (p.y - scene.centerY))
            }
            var grid = Path()
            let gridsPerMetre = puckStrip || coupon || isSeam ? 20.0 : 10.0
            let firstGrid = !free ? -Int(sceneWidth * gridsPerMetre)
                : Int(ceil((sceneCenter - sceneWidth / 2) * gridsPerMetre))
            let lastGrid = !free ? 0 : Int(floor((sceneCenter + sceneWidth / 2) * gridsPerMetre))
            for i in firstGrid...lastGrid {
                let x = project(Point(Double(i) / gridsPerMetre, 0)).x
                grid.move(to: CGPoint(x: x, y: 25))
                grid.addLine(to: CGPoint(x: x, y: size.height - 28))
            }
            if offAxis {
                for j in -2...2 {
                    let y = project(Point(0, scene.centerY + Double(j) * 0.025)).y
                    grid.move(to: CGPoint(x: 24, y: y))
                    grid.addLine(to: CGPoint(x: size.width - 24, y: y))
                }
            }
            context.stroke(grid, with: .color(ink.opacity(0.09)))
            let levels = 10
            let strainScale = showsMaterialResponse ? 0.08 : (scene.isBonded ? 0.0015 : 0.014)
            var patches = Array(repeating: Path(), count: levels * 2 + 1)
            var outlines: [(Path, Color)] = []
            func drawMesh(_ body: ImpactPhysics.Body, strain: [Double], edgeColor: Color = ink) {
                let nodes = body.position.map(project)
                for (i, e) in body.mesh.elements.enumerated() {
                    let value = strain.isEmpty ? 0 : strain[i]
                    let intensity = min(1, sqrt(abs(value) / strainScale))
                    let offset = Int((intensity * Double(levels)).rounded())
                    let bucket = levels + (value < 0 ? -offset : offset)
                    patches[bucket].move(to: nodes[e.a])
                    patches[bucket].addLine(to: nodes[e.b])
                    patches[bucket].addLine(to: nodes[e.c])
                    patches[bucket].closeSubpath()
                }
                let outline = Path { path in
                    for edge in body.mesh.boundary {
                        path.move(to: nodes[edge.a])
                        path.addLine(to: nodes[edge.b])
                    }
                }
                outlines.append((outline, edgeColor))
            }
            drawMesh(simulation.body, strain: showingPlastic ? simulation.plasticStrain : simulation.strain,
                     edgeColor: offAxis ? mint : ink)
            if let second, let strain = simulation.secondStrain {
                drawMesh(second, strain: layeredImpact && showingPlastic ? simulation.secondPlasticStrain : strain,
                         edgeColor: offAxis ? amber : ink)
            }
            if let third, let strain = simulation.thirdStrain {
                drawMesh(third, strain: showingPlastic ? [] : strain)
            }
            if let receiver, let strain = simulation.receiverStrain {
                drawMesh(receiver, strain: showingPlastic ? [] : strain, edgeColor: simulation.receiverInContact ? mint : sky)
            }
            let neutral = Color(red: 0.18, green: 0.33, blue: 0.42)
            for (i, patch) in patches.enumerated() where !patch.isEmpty {
                let intensity = Double(abs(i - levels)) / Double(levels)
                context.fill(patch, with: .color(neutral))
                let color = showingPlastic || i < levels ? amber : mint
                context.fill(patch, with: .color(color.opacity(intensity)))
            }
            for (outline, edgeColor) in outlines {
                context.stroke(outline, with: .color(edgeColor), lineWidth: 1.4)
            }
            if let receiver, let third {
                for (body, color) in [(third, ink), (receiver, sky)] {
                    let center = body.centerOfMass
                    let angle = body.orientation
                    let axis = 0.016 * Point(cos(angle), sin(angle))
                    context.stroke(Path { p in
                        p.move(to: project(center - axis))
                        p.addLine(to: project(center + axis))
                    }, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                    let dot = project(center)
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 2, y: dot.y - 2, width: 4, height: 4)), with: .color(color))
                }
            }
            if scene.impactPlasticity == nil, let station = simulation.body.probePosition {
                let probe = project(station).x
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: probe, y: 40))
                    p.addLine(to: CGPoint(x: probe, y: size.height - 35))
                }, with: .color(mint), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                context.draw(Text("PROBE").font(.caption2.monospaced()).foregroundStyle(mint),
                             at: CGPoint(x: probe, y: 25))
            }
            if offAxis {
                let x = 24.0
                let y = size.height - 23
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: y - 3))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + 0.025 * scale, y: y))
                    p.addLine(to: CGPoint(x: x + 0.025 * scale, y: y - 3))
                }, with: .color(ink.opacity(0.65)))
                context.draw(Text("25 mm").font(.caption2.monospaced()).foregroundStyle(ink),
                             at: CGPoint(x: x, y: y - 7), anchor: .bottomLeading)
                let legend = "Calculated · " + (showingPlastic ? "Plastic strain · 0–8%" : "Amber: compression     Mint: tension")
                context.draw(Text(legend).font(.caption2).foregroundStyle(ink.opacity(0.8)),
                             at: CGPoint(x: size.width - 24, y: y), anchor: .trailing)
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
                func drawLabel(_ body: ImpactPhysics.Body, _ label: String, _ color: Color, below: Bool = false) {
                    let vertical = body.position.map(\.y)
                    let labelY = below ? (vertical.min() ?? 0) - 0.016 : (vertical.max() ?? 0) + 0.017
                    let labelPosition = project(Point(body.centerOfMass.x, labelY))
                    context.draw(Text(label.uppercased()).font(.caption2.monospaced()).foregroundStyle(color),
                                 at: labelPosition)
                }
                drawLabel(simulation.body, labels.first, mint)
                drawLabel(second, labels.second, amber, below: offAxis)
                if let third { drawLabel(third, "Backing layer", ink) }
                if let receiver { drawLabel(receiver, "Receiver", sky, below: true) }
                if let stop = scene.backstopX {
                    let x = project(Point(stop, scene.centerY)).x
                    let color = simulation.backstopInContact ? amber : ink
                    context.stroke(Path { path in
                        path.move(to: CGPoint(x: x, y: 29))
                        path.addLine(to: CGPoint(x: x, y: size.height - 24))
                    }, with: .color(color), lineWidth: 3)
                    context.draw(Text("STOP").font(.caption2.monospaced()).foregroundStyle(color),
                                 at: CGPoint(x: x + 6, y: size.height - 15), anchor: .trailing)
                }
                if let faces = simulation.seamFaces, let readings = simulation.seamReadings {
                    let damage = simulation.seamDamage
                    for face in [faces.left, faces.right] {
                        for i in face.indices.dropFirst() {
                            let localDamage = (damage[i - 1] + damage[i]) / 2
                            let segment = Path { path in
                                path.move(to: project(face[i - 1]))
                                path.addLine(to: project(face[i]))
                            }
                            context.stroke(segment, with: .color(mint.opacity(1 - localDamage)), lineWidth: 2.5)
                            if localDamage > 0 {
                                context.stroke(segment, with: .color(amber.opacity(localDamage)), lineWidth: 2.5)
                            }
                        }
                    }
                    let separated = readings.separatedFraction > 1 - 1e-12
                    let closure = simulation.seamInCompression
                    if !offAxis {
                        let caption = separated ? (closure ? "FAILED SEAM IN CONTACT" : "SEAM FAILED")
                            : (closure ? "SEAM IN COMPRESSION" : (readings.dissipated > 0 ? "SEAM SOFTENING" : "SEAM"))
                        context.draw(Text(caption).font(.caption2.monospaced())
                            .foregroundStyle(separated || closure || readings.dissipated > 0 ? amber : mint),
                                     at: project(Point((faces.left[0].x + faces.right[0].x) / 2,
                                                       min(faces.left[0].y, faces.right[0].y) - 0.018)))
                    }
                }
            } else if let tension = scene.tension {
                let ratio = simulation.appliedTraction / (tension.peakFraction * scene.first.material.young)
                if ratio > 0.02 {
                    for (edge, direction) in [(farthestLeft, -1.0), (farthestRight, 1.0)] {
                        let p = project(Point(edge, scene.centerY))
                        let start = p.x + direction * 8
                        let tip = start + direction * (13 + 32 * ratio)
                        context.stroke(Path { arrow in
                            arrow.move(to: CGPoint(x: start, y: p.y))
                            arrow.addLine(to: CGPoint(x: tip, y: p.y))
                            arrow.move(to: CGPoint(x: tip - direction * 7, y: p.y - 4))
                            arrow.addLine(to: CGPoint(x: tip, y: p.y))
                            arrow.addLine(to: CGPoint(x: tip - direction * 7, y: p.y + 4))
                        }, with: .color(ink.opacity(0.7)), lineWidth: 1.4)
                    }
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
        .accessibilityLabel(offAxis ? "Free striker, facing, backing and receiver"
                            : layeredImpact ? "Deforming striker, facing, and backing layers"
                            : experiment.preset.pairLabels.map { "Deforming \($0.first.lowercased()) and \($0.second.lowercased())" }
                            ?? (isCoupon ? "Tension coupon" : (experiment.configuration.isBonded
                                ? "Bonded bar and strain probe" : "Deforming specimen and fixed wall")))
    }

    private var traceCanvas: some View {
        Canvas { context, size in
            let trace = experiment.trace
            let end = max(experiment.horizon, trace.last?.time ?? 0)
            let ring = experiment.preset == .ring
            let block = experiment.preset == .block
            let bonded = experiment.preset == .bondedBar
            let lengthTrace = showsMaterialResponse
            let velocityTrace = experiment.configuration.isPair
            let seamEnergy = isSeam && !offAxis && showFractureEnergy
            let signal: KeyPath<Point, Double> = (offAxis ? showReceiverVelocity : seamEnergy) ? \.y : \.x
            let initial = trace.first?.values.x ?? 0
            let initialTargetSpeed = trace.first?.values.y ?? 0
            let fractureScale = experiment.simulation.seamReadings?.criticalEnergy ?? 1
            let center = offAxis ? 0 : seamEnergy ? fractureScale / 2 : (velocityTrace ? (initial + initialTargetSpeed) / 2 : initial)
            var peak = offAxis ? (showReceiverVelocity ? 0.1 : 5) : velocityTrace ? abs(initial - initialTargetSpeed) * 0.5
                : (seamEnergy ? fractureScale / 2 : (lengthTrace || isSeam ? 4 : (ring || block ? 1.0 : (bonded ? 0.01 : 0.1))))
            for sample in trace {
                let padding = velocityTrace || seamEnergy ? 1.0 : 1.12
                peak = max(peak, abs(sample.values[keyPath: signal] - center) * padding)
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
                if offAxis { label = String(format: showReceiverVelocity ? "%.2f m/s" : "%.0f°", value) }
                else if seamEnergy { label = String(format: "%.1f J/m²", value) }
                else if isSeam || ring || lengthTrace { label = String(format: "%.1f mm", value) }
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
            context.stroke(line(signal), with: .color((offAxis ? showReceiverVelocity : seamEnergy) ? amber : mint), lineWidth: 1.8)
            if ring || velocityTrace { context.stroke(line(\.y), with: .color(amber), lineWidth: 1.8) }
            if let events = experiment.simulation.impactEvents {
                for (time, label) in [(events.strike, "STRIKE"), (events.failure, "FAILS"),
                                      (events.backstop, "STOP"), (offAxis ? nil : events.reclosure, "RECLOSES"),
                                      (events.receiver, "RECEIVER")] {
                    guard let time else { continue }
                    let x = left + (right - left) * time / end
                    context.stroke(Path { path in
                        path.move(to: CGPoint(x: x, y: 22))
                        path.addLine(to: CGPoint(x: x, y: size.height - 18))
                    }, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    context.draw(Text(label).font(.caption2.monospaced()).foregroundStyle(ink),
                                 at: CGPoint(x: x, y: 12))
                }
            }
            if let release = experiment.simulation.loadReleaseTime {
                let x = left + (right - left) * release / end
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: 22))
                    p.addLine(to: CGPoint(x: x, y: size.height - 18))
                }, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                context.draw(Text("LOAD OFF").font(.caption2.monospaced()).foregroundStyle(ink),
                             at: CGPoint(x: x, y: 12))
            }
            if let phase = experiment.simulation.seamFirstOpeningTime {
                for (time, label) in [(phase, "CLOSE"), (2 * phase, "REOPEN")] {
                    let x = left + (right - left) * time / end
                    context.stroke(Path { path in
                        path.move(to: CGPoint(x: x, y: 22))
                        path.addLine(to: CGPoint(x: x, y: size.height - 18))
                    }, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    context.draw(Text(label).font(.caption2.monospaced()).foregroundStyle(ink),
                                 at: CGPoint(x: x, y: 12))
                }
            }
        }
        .accessibilityLabel("Time trace for " + experiment.preset.rawValue)
    }

    private func inspectOnLaunch() async {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--inspect-ms"), args.indices.contains(flag + 1),
              let milliseconds = Double(args[flag + 1]), milliseconds.isFinite, milliseconds >= 0 else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        experiment.advance(to: milliseconds / 1000)
    }

    private func smokeCheck() async {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--smoke"), args.indices.contains(flag + 1) else { return }
        try? await Task.sleep(for: .milliseconds(250))
        let windowVisible = NSApplication.shared.windows.contains { $0.isVisible && $0.title.hasPrefix("Impact Lab") }
        var results = ["window=\(windowVisible)", "opens on off-axis impact=\(experiment.preset == .offAxisImpact)"]
        for preset in Preset.allCases {
            experiment.select(preset)
            let isPair = experiment.configuration.isPair
            let isCoupon = preset == .tensionCoupon
            let isMaterialImpact = preset == .materialImpact
            let isSeam = preset == .layeredSeam
            let selected = experiment.preset == preset && experiment.simulation.time == 0
            let s = experiment.simulation
            let topology = [s.body, s.secondBody, s.thirdBody, s.receiverBody]
                .compactMap { $0 }.reduce(0) { $0 + $1.mesh.elements.count }
            experiment.toggle()
            let start = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(for: .milliseconds(isPair ? 1300 : 1400))
            if isSeam, let firstOpening = experiment.simulation.seamFirstOpeningTime {
                // Observe actual timer-driven progress before pausing the guided cycle.
                for _ in 0..<50 where experiment.running && experiment.simulation.time < firstOpening {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let playbackRate = experiment.simulation.time / (ProcessInfo.processInfo.systemUptime - start)
            experiment.pause()
            let pausedTime = experiment.simulation.time
            try? await Task.sleep(for: .milliseconds(100))
            let paused = pausedTime > 0 && experiment.simulation.time == pausedTime
            let step = experiment.advance()
                && abs(experiment.simulation.time - pausedTime - experiment.simulation.dt) < 1e-12
            let inspected: Bool
            switch preset {
            case .bondedBar: inspected = experiment.simulation.body.mesh.interfaceNodes.count == 5
            case .tensionCoupon: inspected = experiment.simulation.appliedTraction > 0
                && experiment.simulation.gaugeLength != nil
            case .offAxisImpact: inspected = experiment.simulation.impactEvents?.failure != nil
                && experiment.simulation.peakPlasticStrain > 0 && experiment.simulation.receiverBody != nil
            case .layeredImpact: inspected = experiment.simulation.impactEvents?.failure != nil
                && experiment.simulation.peakPlasticStrain > 0 && experiment.simulation.thirdBody != nil
            case .layeredSeam: inspected = experiment.simulation.seamFaces != nil
                && (experiment.simulation.seamReadings?.dissipated ?? 0) > 0
            default: inspected = experiment.simulation.peakPenetration > 0 && (isPair || experiment.simulation.wallImpulse > 0)
            }
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
            } else if isCoupon || isMaterialImpact {
                experiment.toggle()
                for _ in 0..<75 where experiment.running {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let residual = (experiment.residualLength ?? 0) - experiment.configuration.first.width
                let unloaded = experiment.finished && experiment.simulation.appliedTraction == 0
                    && experiment.simulation.failure == nil && (isCoupon ? residual > 0.001 : residual < -0.001)
                let field = experiment.simulation.plasticStrain.contains { $0 > 0 }
                results.append("\(preset.rawValue) playback: unloaded permanent set=\(unloaded) plastic field=\(field)")
            } else if preset == .offAxisImpact {
                let before = experiment.simulation.time
                experiment.advance(to: before + 0.001)
                let delta = experiment.simulation.time - before
                let coarseStep = delta >= 0.001 && delta < 0.001 + experiment.simulation.dt
                experiment.toggle()
                for _ in 0..<180 where experiment.running {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let events = experiment.simulation.impactEvents
                let secondary = (events?.receiver ?? -1) > (events?.failure ?? .infinity)
                let complete = experiment.finished && experiment.simulation.failure == nil
                showPlasticStrain = true
                try? await Task.sleep(for: .milliseconds(100))
                let fields = showingPlastic && experiment.simulation.peakPlasticStrain > 0
                    && experiment.simulation.seamDamage.allSatisfy { $0 == 1 }
                showPlasticStrain = false
                showReceiverVelocity = true
                try? await Task.sleep(for: .milliseconds(100))
                let motionTrace = (experiment.trace.last?.values.y ?? 0) > 0.1
                showReceiverVelocity = false
                results.append("Off-axis playback: millisecond step=\(coarseStep) finished=\(complete) failed backing hit receiver=\(secondary) plastic and damage fields=\(fields) receiver trace=\(motionTrace)")
            } else if preset == .layeredImpact {
                showPlasticStrain = true
                experiment.toggle()
                for _ in 0..<90 where experiment.running {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let events = experiment.simulation.impactEvents
                let fields = experiment.simulation.plasticStrain.contains { $0 > 0 }
                    && experiment.simulation.secondPlasticStrain.contains { $0 > 0 }
                    && experiment.simulation.seamDamage.allSatisfy { $0 == 1 }
                results.append("Layered impact playback: finished=\(experiment.finished) backstop hit=\(events?.backstop != nil) failed seam reclosed=\(events?.reclosure != nil) plastic and damage fields=\(fields)")
                showPlasticStrain = false
            } else if isSeam {
                experiment.toggle()
                for _ in 0..<110 where experiment.running {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let sim = experiment.simulation
                let seam = sim.seamReadings!
                let broken = experiment.finished && seam.separatedFraction > 1 - 1e-12
                    && abs(seam.dissipatedPerArea - seam.criticalEnergy) < 1e-8
                let reclosed = sim.peakPenetration > 0 && seam.opening > 0 && abs(seam.force) < 1e-8
                results.append("Layered seam playback: full separation=\(broken) compressive reclosure and free reopening=\(reclosed)")
            }
            var edited = experiment.configuration
            if !isCoupon && !isSeam { edited.speed = preset == .bondedBar ? 0.07 : (preset == .offAxisImpact ? 1.10 : 0.6) }
            edited.first.material = Material(young: 4e6, density: 1500, poisson: 0.2)
            edited.first.width *= 1.05
            edited.second?.material = Material(young: 2e6)
            edited.third?.material = Material(young: 3e6)
            edited.offAxis?.strikerAngle = -14
            edited.offAxis?.receiverAngle = 14
            edited.offAxis?.receiver.material = Material(young: 1.6e6)
            edited.mirrored = preset == .block
            experiment.edit(edited)
            let resetSecond = !(isPair || isSeam || preset == .layeredImpact) || experiment.simulation.secondBody?.material == edited.second?.material
            let reset = experiment.simulation.time == 0 && experiment.trace.count == 1
                && experiment.configuration == edited
                && experiment.simulation.body.material == edited.first.material
                && experiment.simulation.wallImpulse == 0
                && resetSecond
                && experiment.simulation.thirdBody?.material == edited.third?.material
                && experiment.simulation.receiverBody?.material == edited.offAxis?.receiver.material
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
        try? await Task.sleep(for: .milliseconds(300))
        for preset in [Preset.materialImpact, .tensionCoupon] {
            do {
                let url = URL(fileURLWithPath: args[flag + 1]).deletingLastPathComponent()
                    .appendingPathComponent(UUID().uuidString + ".impact.json")
                defer { try? FileManager.default.removeItem(at: url) }
                var elastic = SceneConfiguration.standard(preset)
                elastic.impactPlasticity?.response = .elastic
                elastic.tension?.response = .elastic
                try experiment.configure(elastic)
                while experiment.advance() {}
                let recovered = abs((experiment.residualLength ?? 0) - elastic.first.width) < 0.00005
                experiment.pinReference()
                experiment.setMaterialResponse(.elastoplastic)
                let plastic = experiment.configuration
                try experiment.save(to: url)
                try experiment.open(url)
                let restored = experiment.configuration == plastic
                    && experiment.currentTrace.materialResponse == .elastoplastic
                while experiment.advance() {}
                let comparison = experiment.comparison()
                let matched = comparison.count == experiment.trace.count
                    && (comparison.last?.reference.y ?? .infinity) == 0 && (comparison.last?.current.y ?? 0) > 0
                let set = (experiment.residualLength ?? 0) - plastic.first.width
                let plasticSet = preset == .tensionCoupon ? set > 0.001 : set < -0.001
                showPlasticStrain = true
                try? await Task.sleep(for: .milliseconds(150))
                showComparison = true
                try? await Task.sleep(for: .milliseconds(450))
                let sheet = NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true }
                showComparison = false
                results.append("\(preset.rawValue) comparison: elastic recovery=\(recovered) plastic set=\(plasticSet) save/reopen=\(restored) matched times=\(matched) comparison sheet=\(sheet)")
            } catch {
                results.append("\(preset.rawValue) comparison: save/reopen=false error=\(error.localizedDescription)")
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        try? await Task.sleep(for: .milliseconds(300))
        for preset in [Preset.layeredSeam, .layeredImpact] {
            do {
                let url = URL(fileURLWithPath: args[flag + 1]).deletingLastPathComponent()
                    .appendingPathComponent(UUID().uuidString + ".impact.json")
                defer { try? FileManager.default.removeItem(at: url) }
                var intact = SceneConfiguration.standard(preset)
                intact.seam?.response = .intact
                try experiment.configure(intact)
                while experiment.advance() {}
                let intactCarriesTension = experiment.trace.contains { $0.values.x > 0.01 }
                    && experiment.simulation.seamReadings?.dissipated == 0
                experiment.pinReference()
                experiment.setSeamResponse(.separating)
                let separating = experiment.configuration
                try experiment.save(to: url)
                while experiment.advance() {}
                let firstTrace = experiment.trace
                try experiment.open(url)
                let restored = experiment.configuration == separating
                while experiment.advance() {}
                let comparison = experiment.comparison()
                let matched = comparison.count == experiment.trace.count && comparison.count > 100
                    && comparison.last?.reference.y == 0 && (comparison.last?.current.y ?? 0) > 0
                let replay = experiment.finished && firstTrace == experiment.trace
                showFractureEnergy = true
                try? await Task.sleep(for: .milliseconds(150))
                showComparison = true
                try? await Task.sleep(for: .milliseconds(450))
                let sheet = NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true }
                showComparison = false
                results.append("\(preset.rawValue) comparison: intact tension=\(intactCarriesTension) save/reopen=\(restored) identical replay=\(replay) matched times=\(matched) comparison sheet=\(sheet)")
            } catch {
                results.append("\(preset.rawValue) comparison: save/reopen=false error=\(error.localizedDescription)")
            }
        }
        do {
            let url = URL(fileURLWithPath: args[flag + 1]).deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".impact.json")
            defer { try? FileManager.default.removeItem(at: url) }
            let standard = SceneConfiguration.standard(.offAxisImpact)
            try experiment.configure(standard)
            while experiment.advance() {}
            experiment.pinReference()
            var edited = standard
            edited.offAxis?.receiverGap = 0.032
            edited.offAxis?.receiverAngle = 3
            edited.offAxis?.duration = 0.12
            try experiment.configure(edited)
            try experiment.save(to: url)
            while experiment.advance() {}
            let firstTrace = experiment.trace
            let receiverTime = experiment.simulation.impactEvents?.receiver ?? 0
            try experiment.open(url)
            let restored = experiment.configuration == edited
            while experiment.advance() {}
            let replay = experiment.finished && experiment.trace == firstTrace
            let matched = experiment.comparison().contains { abs($0.current.y - $0.reference.y) > 0.1 }
            showComparison = true
            try? await Task.sleep(for: .milliseconds(450))
            let sheet = NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true }
            showComparison = false
            results.append("Off-axis comparison: save/reopen=\(restored) identical replay=\(replay) different matched-time velocities=\(matched) moved receiver hit later=\(receiverTime > 0.038) comparison sheet=\(sheet)")
        } catch {
            results.append("Off-axis comparison: save/reopen=false error=\(error.localizedDescription)")
        }
        do {
            try (results.joined(separator: "\n") + "\n").write(
                toFile: args[flag + 1], atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("Smoke report write failed: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
        // This dedicated process can exit even if a comparison sheet is still being dismissed.
        exit(results.contains { $0.contains("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
    }
}
