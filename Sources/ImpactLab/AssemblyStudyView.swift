import AppKit
import Charts
import ImpactPhysics
import SwiftUI
import UniformTypeIdentifiers

struct AssemblyStudyView: View {
    private enum Mode: String, CaseIterable {
        case current = "Single run"
        case mesh = "Mesh refinement"
        case timestep = "Timestep halving"
    }

    let scene: AssemblyScene
    var smokeResult: ((Result<AssemblyStudy, Error>) -> Void)?
    @State private var bodyID: UUID?
    @State private var mode: Mode = .current
    @State private var coarse = AssemblyScene.Resolution.fine
    @State private var middle = AssemblyScene.Resolution.extraFine
    @State private var fine = AssemblyScene.Resolution.x4
    @State private var result: AssemblyStudy?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var caseProgress: [String: AssemblyStudyProgress] = [:]
    @State private var started: AssemblyProcessSample?
    @State private var process: AssemblyProcessSample?
    @State private var processCPU: Double?
    @State private var cancelling = false
    @State private var signal: StudySignal = .energy(.residual)
    @State private var cursor: Double?
    @Environment(\.dismiss) private var dismiss

    private var sampleSpacing: String {
        let interval = scene.sampleInterval
        return interval >= 0.001 ? String(format: "%.3g ms", interval * 1e3) : String(format: "%.3g µs", interval * 1e6)
    }

    init(scene: AssemblyScene, selectedBody: UUID?) {
        self.scene = scene
        _bodyID = State(initialValue: selectedBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Assembly study").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            controls
            if let result {
                ScrollView { results(result) }
            } else if task != nil {
                studyProgress
            } else {
                    Text("Run this setup from its initial state to measure gauges, contacts, and the energy ledger.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 165)
            }
            if let error { Text(error).foregroundStyle(assemblyAmber).font(.callout) }
        }
        .padding(20)
        .frame(width: 810, height: result == nil ? 360 : 635, alignment: .topLeading)
        .onDisappear { task?.cancel() }
        .task {
            if smokeResult != nil && task == nil && result == nil {
                mode = .mesh
                start()
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Picker("Study", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(maxWidth: 250)
                if mode == .mesh {
                    Picker("Refine", selection: $bodyID) {
                        Text("All bodies").tag(nil as UUID?)
                        ForEach(scene.parts) { Text($0.name).tag(Optional($0.id)) }
                    }.frame(maxWidth: 290)
                }
                Spacer()
                if let task {
                    Button(cancelling ? "Cancelling…" : "Cancel Study") {
                        cancelling = true
                        task.cancel()
                    }.disabled(cancelling)
                }
                Button("Run study") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(task != nil || (mode == .mesh && !(coarse.rawValue < middle.rawValue && middle.rawValue < fine.rawValue)))
            }
            if mode == .mesh {
                HStack {
                    level("Coarse", $coarse)
                    level("Middle", $middle)
                    level("Fine", $fine)
                }.disabled(task != nil)
                Text("All three runs use the smallest stable timestep of the three cases. When you refine one body, the other bodies keep their mesh settings.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if mode == .timestep {
                Text("Run the same mesh at its nominal, half, and quarter timestep.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func level(_ label: String, _ selection: Binding<AssemblyScene.Resolution>) -> some View {
        Picker(label, selection: selection) {
            ForEach(AssemblyScene.Resolution.allCases, id: \.self) { Text("×\($0.rawValue)").tag($0) }
        }
    }

    private var studyProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            if caseProgress.isEmpty {
                ProgressView("Preparing study meshes").controlSize(.small)
            }
            ForEach(caseProgress.values.sorted(by: { $0.id.localizedStandardCompare($1.id) == .orderedAscending })) { item in
                HStack {
                    Text(item.id).frame(width: 130, alignment: .leading)
                    ProgressView(value: item.fraction).accessibilityLabel(item.id)
                    Text(item.finished ? "Complete" : "\(replayTime(item.time)) / \(replayTime(item.duration))")
                        .frame(width: 175, alignment: .trailing)
                    Text("\(item.steps.formatted()) steps").frame(width: 100, alignment: .trailing)
                }
            }
            if let started, let process {
                let cpu = processCPU.map { String(format: "%.0f%%", $0) } ?? "—"
                let ram = process.resident.map { String(format: "%.1f MiB", Double($0) / 1_048_576) } ?? "—"
                Text("\(process.time - started.time, specifier: "%.2f") s elapsed · App CPU \(cpu) · App RAM \(ram)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout.monospacedDigit())
        .frame(maxWidth: .infinity, minHeight: 165, alignment: .leading)
    }

    private func start() {
        let variation: AssemblyStudyVariation = switch mode {
        case .current: .current
        case .mesh: .mesh(body: bodyID, levels: [coarse, middle, fine])
        case .timestep: .timestep
        }
        result = nil
        error = nil
        cursor = nil
        signal = .energy(.residual)
        caseProgress.removeAll()
        let initial = AssemblyProcessSample()
        started = initial
        process = initial
        processCPU = nil
        cancelling = false
        let (updates, continuation) = AsyncStream.makeStream(of: AssemblyStudyProgress.self)
        task = Task {
            defer { task = nil; cancelling = false }
            async let resultTask: AssemblyStudy = {
                defer { continuation.finish() }
                return try await AssemblyStudy.run(scene, variation: variation, progress: { continuation.yield($0) })
            }()
            for await item in updates {
                caseProgress[item.id] = item
                if let process, ProcessInfo.processInfo.systemUptime - process.time >= 0.25 {
                    let next = AssemblyProcessSample()
                    processCPU = next.utilization(since: process)
                    self.process = next
                }
            }
            do { result = try await resultTask }
            catch is CancellationError {}
            catch {
                self.error = error.localizedDescription
                smokeResult?(.failure(error))
            }
        }
    }

    private func results(_ study: AssemblyStudy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Signal", selection: $signal) {
                    Section("Energy ledger") {
                        ForEach(StudyEnergy.allCases, id: \.self) { Text($0.rawValue).tag(StudySignal.energy($0)) }
                    }
                    ForEach(Array((scene.gauges ?? []).enumerated()), id: \.offset) { i, gauge in
                        Section(gauge.name) {
                            ForEach(StudyGauge.allCases, id: \.self) { quantity in
                                Text("\(gauge.name) · \(quantity.rawValue)").tag(StudySignal.gauge(i, quantity))
                            }
                        }
                    }
                    ForEach(Array(study.pairs.enumerated()), id: \.offset) { i, pair in
                        Section(pair.name) {
                            Text("\(pair.name) · Scalar normal load").tag(StudySignal.load(i))
                            Text("\(pair.name) · Scalar normal impulse").tag(StudySignal.impulse(i))
                        }
                    }
                    ForEach(scene.parts.indices.filter { scene.parts[$0].fracture != nil }, id: \.self) { i in
                        Section(scene.parts[i].name) {
                            Text("\(scene.parts[i].name) · Crack length").tag(StudySignal.crack(i))
                            Text("\(scene.parts[i].name) · Piece count").tag(StudySignal.pieces(i))
                        }
                    }
                }.frame(maxWidth: 440)
                Spacer()
                Button("Export CSV…", systemImage: "square.and.arrow.down") { export(study) }
            }
            chart(study).onAppear { smokeResult?(.success(study)) }
            Text("Samples are accepted solver states, about \(sampleSpacing) apart. Lines connect samples. Contact peaks and scalar normal impulses use every accepted step.")
                .font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Case")
                    Text("Triangles")
                    Text("Step (µs)")
                    Text("Compute (s)")
                    Text("Peak sampled |ΔE|")
                    Text(cursor == nil ? "Final sample" : "Nearest sample")
                }.foregroundStyle(.secondary)
                ForEach(study.cases, id: \.label) { item in
                    caseRow(item)
                }
            }.font(.caption.monospacedDigit())
            if let index = signal.contactIndex {
                ForEach(study.cases, id: \.label) { item in
                    let pair = item.contacts[index]
                    let onset = pair.firstTime.map { String(format: "%.3f ms", $0 * 1000) } ?? "—"
                    Text("\(item.label) · First contact \(onset) · Impulse \(pair.impulse, specifier: "%.4g") N·s/m · \(pulseSummary(pair.pulses))")
                        .font(.caption.monospacedDigit())
                    Text("\(item.label) · Raw step peak \(pair.peak, specifier: "%.4g") N/m (numerical diagnostic, depends on penalty and mesh) · Overlap \(item.peakPenetration * 100, specifier: "%.3f")% of edge, \(item.peakPenetrationDepth * 1e6, specifier: "%.3g") µm")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(pulseNote(study, index))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let index = signal.fractureIndex {
                ForEach(study.cases, id: \.label) { item in
                    let onset = item.firstInsertions[index].map { String(format: "%.3f ms", $0 * 1000) } ?? "—"
                    Text("\(item.label) · First insertion \(onset)")
                        .font(.caption.monospacedDigit())
                }
            }
            Text("Study wall time \(study.wallTime, specifier: "%.2f") s")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func chart(_ study: AssemblyStudy) -> some View {
        Chart {
            ForEach(study.cases, id: \.label) { item in
                ForEach(item.samples, id: \.time) { sample in
                    LineMark(x: .value("Time", sample.time * 1000), y: .value("Reading", signal.value(sample)))
                        .foregroundStyle(by: .value("Case", item.label))
                }
            }
            if let cursor {
                RuleMark(x: .value("Time", cursor)).foregroundStyle(.secondary)
            }
        }
        .chartXAxisLabel("Simulated time (ms)")
        .chartYAxisLabel(signal.unit)
        .chartXSelection(value: $cursor)
        .frame(height: 245)
    }

    @ViewBuilder private func caseRow(_ item: AssemblyStudyCase) -> some View {
        let initial = item.samples[0].energy.total
        let peak = item.samples.reduce(0.0) { max($0, abs($1.residual)) }
        let sample = cursor.map { time in item.samples.min { abs($0.time * 1000 - time) < abs($1.time * 1000 - time) }! }
            ?? item.samples.last!
        GridRow {
            Text(item.label)
            Text(item.triangles.formatted())
            Text(item.dt * 1e6, format: .number.precision(.fractionLength(3)))
            Text(item.wallTime, format: .number.precision(.fractionLength(2)))
            Text(initial > 0 ? String(format: "%.3f%%", 100 * peak / initial) : String(format: "%.3g J/m", peak))
            Text(String(format: "%.4g %@ at %.2f ms", signal.value(sample), signal.unit, sample.time * 1000))
        }
        if let issue = item.failure {
            GridRow { Text(issue).foregroundStyle(assemblyAmber).gridCellColumns(6) }
        }
    }

    private func export(_ study: AssemblyStudy) {
        let dialog = NSSavePanel()
        dialog.allowedContentTypes = [.commaSeparatedText]
        dialog.nameFieldStringValue = "Impact Lab Study.csv"
        guard let url = ExperimentDirectory.run(dialog) else { return }
        do {
            try study.exportCSV(to: url)
            let pulses = url.deletingPathExtension().lastPathComponent + " pulses.csv"
            try study.exportPulseCSV(to: url.deletingLastPathComponent().appendingPathComponent(pulses))
        } catch { self.error = error.localizedDescription }
    }

    private func pulseSummary(_ report: ContactPulseReport?) -> String {
        guard let report, let first = report.pulses.first else { return "No contact pulses" }
        let window = report.settings.windows.count > 1 ? report.settings.windows[1] : report.settings.windows.first ?? 0
        let windowed = first.windowPeaks.count > 1 ? first.windowPeaks[1] : first.windowPeaks.first ?? 0
        return String(format: "%d pulse%@ · first pulse %.4g N·s/m over %.3g ms, mean %.4g N/m, %@ average peak %.4g N/m",
                      report.pulses.count, report.pulses.count == 1 ? "" : "s", first.impulse, first.duration * 1000,
                      first.meanForce, timeText(window), windowed)
    }

    private func pulseNote(_ study: AssemblyStudy, _ index: Int) -> String {
        let s = study.pulseSettings[index]
        return "The load sums positive normal contributions; its integral is the scalar contact impulse. "
            + "Pulses: loaded spans closer than \(timeText(s.mergeGap)) are merged, and touches under "
            + String(format: "%.0f%%", s.minorFraction * 100) + " of the largest pulse are counted as minor. "
            + "Averaging windows \(s.windows.map(timeText).joined(separator: ", ")) are common to every case, "
            + "chosen from an element wave-transit time of \(timeText(study.transitTimes[index])) (an empirical guideline)."
    }

    private func timeText(_ seconds: Double) -> String {
        seconds < 1e-3 ? String(format: "%.3g µs", seconds * 1e6) : String(format: "%.3g ms", seconds * 1e3)
    }
}

private enum StudyEnergy: String, CaseIterable {
    case residual = "Energy residual", kinetic = "Kinetic", elastic = "Elastic", contact = "Penalty contact"
    case connection = "Stored connection", cohesive = "Stored cohesive", hardening = "Stored hardening"
    case plastic = "Modelled plastic dissipation", fracture = "Fracture dissipation", viscous = "Bulk viscosity (numerical)"
    case total = "Total accounted energy"

    func value(_ sample: AssemblyStudySample) -> Double {
        switch self {
        case .residual: sample.residual
        case .kinetic: sample.energy.kinetic
        case .elastic: sample.energy.elastic
        case .contact: sample.energy.contact
        case .connection: sample.energy.connection
        case .cohesive: sample.energy.cohesive
        case .hardening: sample.energy.hardening
        case .plastic: sample.energy.plastic
        case .fracture: sample.energy.fracture
        case .viscous: sample.energy.viscous
        case .total: sample.energy.total
        }
    }
}

private enum StudyGauge: String, CaseIterable {
    case x = "X position", y = "Y position", vx = "X velocity", vy = "Y velocity"
    case strain = "Axial Green strain", pressure = "Mean pressure", mises = "Von Mises stress"
    case plastic = "Equivalent plastic strain", damage = "Adjacent-face damage"

    var unit: String {
        switch self {
        case .x, .y: "mm"
        case .vx, .vy: "m/s"
        case .pressure, .mises: "kPa"
        case .strain, .plastic: "%"
        case .damage: "0–1"
        }
    }

    func value(_ gauge: AssemblyGaugeReading) -> Double {
        switch self {
        case .x: gauge.position.x * 1000
        case .y: gauge.position.y * 1000
        case .vx: gauge.velocity.x
        case .vy: gauge.velocity.y
        case .strain: gauge.strain * 100
        case .pressure: gauge.pressure / 1000
        case .mises: gauge.equivalentStress / 1000
        case .plastic: gauge.plasticStrain * 100
        case .damage: gauge.damage
        }
    }
}

private enum StudySignal: Hashable {
    case energy(StudyEnergy), gauge(Int, StudyGauge), load(Int), impulse(Int), crack(Int), pieces(Int)

    var unit: String {
        switch self {
        case .energy: "J/m"
        case .gauge(_, let quantity): quantity.unit
        case .load: "N/m"
        case .impulse: "N·s/m"
        case .crack: "mm"
        case .pieces: "pieces"
        }
    }

    var contactIndex: Int? {
        switch self {
        case .load(let i), .impulse(let i): i
        default: nil
        }
    }

    var fractureIndex: Int? {
        switch self {
        case .crack(let i), .pieces(let i): i
        default: nil
        }
    }

    func value(_ sample: AssemblyStudySample) -> Double {
        switch self {
        case .energy(let term): term.value(sample)
        case .gauge(let i, let quantity): quantity.value(sample.gauges[i])
        case .load(let i): sample.normalLoads[i]
        case .impulse(let i): sample.normalImpulses[i]
        case .crack(let i): (sample.fractures[i]?.crackLength ?? 0) * 1000
        case .pieces(let i): Double(sample.fractures[i]?.pieces ?? 0)
        }
    }
}
