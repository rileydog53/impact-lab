import AppKit
import Charts
import ImpactPhysics
import SwiftUI
import UniformTypeIdentifiers

func replayTime(_ seconds: Double) -> String {
    seconds < 0.001 ? String(format: "%.2f µs", seconds * 1e6) : String(format: "%.3f ms", seconds * 1e3)
}

func replayPairName(_ pair: SIMD2<Int>, scene: AssemblyScene) -> String {
    let first = scene.parts[pair.x].name
    return pair.x == pair.y ? "\(first) fragments" : "\(first) / \(scene.parts[pair.y].name)"
}

struct ReplayMeasurements: View {
    private enum Group: String, CaseIterable {
        case energy = "Energy"
        case balance = "Conservation"
        case gauge = "Gauge"
        case contact = "Contact pair"
        case link = "Connection"
    }

    private struct Signal: Identifiable {
        let name, unit: String
        let color: Color
        let value: (AssemblyReplayFrame) -> Double
        var id: String { name }
    }

    let scene: AssemblyScene
    let frames: [AssemblyReplayFrame]
    let events: [AssemblyReplayEvent]
    let time: Double
    @State private var group = Group.energy
    @State private var picked = ""
    @State private var gauge = 0
    @State private var pair = 0
    @State private var link = 0
    @State private var index = 0
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var pairs: [SIMD2<Int>] {
        Set(frames.last?.contacts.map(\.pair) ?? []).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    private var signals: [Signal] {
        switch group {
        case .energy:
            [Signal(name: "Kinetic", unit: "J/m", color: .mint, value: { $0.energies.kinetic }),
             Signal(name: "Recoverable", unit: "J/m", color: .blue, value: \.recoverableEnergy),
             Signal(name: "Dissipated", unit: "J/m", color: .orange, value: \.dissipatedEnergy),
             Signal(name: "Plastic dissipation", unit: "J/m", color: .pink, value: { $0.energies.plastic }),
             Signal(name: "Fracture dissipation", unit: "J/m", color: .red, value: { $0.energies.fracture }),
             Signal(name: "Elastic", unit: "J/m", color: .green, value: { $0.energies.elastic }),
             Signal(name: "Isotropic hardening", unit: "J/m", color: .purple, value: { $0.energies.hardening }),
             Signal(name: "Penalty contact", unit: "J/m", color: .gray, value: { $0.energies.contact }),
             Signal(name: "Stored connection / cohesive", unit: "J/m", color: .yellow,
                    value: { $0.energies.connection + $0.energies.cohesive })]
        case .balance:
            [Signal(name: "Energy residual", unit: "J/m", color: .orange, value: { $0.energies.total - (frames.first?.energies.total ?? 0) }),
             Signal(name: "Momentum change X", unit: "N·s/m", color: .mint, value: { $0.momentum.x - (frames.first?.momentum.x ?? 0) }),
             Signal(name: "Momentum change Y", unit: "N·s/m", color: .blue, value: { $0.momentum.y - (frames.first?.momentum.y ?? 0) }),
             Signal(name: "Angular momentum change", unit: "N·m·s/m", color: .purple,
                    value: { $0.angularMomentum - (frames.first?.angularMomentum ?? 0) })]
        case .gauge:
            [Signal(name: "Displacement X", unit: "mm", color: .mint, value: { 1000 * ($0.gauges[gauge].position.x - frames[0].gauges[gauge].position.x) }),
             Signal(name: "Displacement Y", unit: "mm", color: .blue, value: { 1000 * ($0.gauges[gauge].position.y - frames[0].gauges[gauge].position.y) }),
             Signal(name: "Velocity X", unit: "m/s", color: .indigo, value: { $0.gauges[gauge].velocity.x }),
             Signal(name: "Velocity Y", unit: "m/s", color: .cyan, value: { $0.gauges[gauge].velocity.y }),
             Signal(name: "Von Mises stress", unit: "MPa", color: .orange, value: { $0.gauges[gauge].equivalentStress / 1e6 }),
             Signal(name: "Mean pressure", unit: "MPa", color: .purple, value: { $0.gauges[gauge].pressure / 1e6 }),
             Signal(name: "Axial strain", unit: "%", color: .pink, value: { 100 * $0.gauges[gauge].strain }),
             Signal(name: "Plastic strain", unit: "%", color: .red, value: { 100 * $0.gauges[gauge].plasticStrain }),
             Signal(name: "Adjacent face damage", unit: "0–1", color: .yellow, value: { $0.gauges[gauge].damage })]
        case .contact:
            [Signal(name: "Normal load (sum)", unit: "N/m", color: .orange, value: { $0.contacts.first { $0.pair == pairs[pair] }?.force ?? 0 }),
             Signal(name: "Normal impulse (sum)", unit: "N·s/m", color: .mint, value: { $0.contacts.first { $0.pair == pairs[pair] }?.impulse ?? 0 })]
        case .link:
            [Signal(name: "Signed force", unit: "N/m", color: .orange, value: { readings($0).reduce(0) { $0 + $1.force } }),
             Signal(name: "Stored energy", unit: "J/m", color: .mint, value: { readings($0).reduce(0) { $0 + $1.storedEnergy } }),
             Signal(name: "Fracture dissipation", unit: "J/m", color: .red, value: { readings($0).reduce(0) { $0 + $1.fractureDissipation } })]
        }
    }

    private func readings(_ frame: AssemblyReplayFrame) -> [AssemblyLinkReading] { frame.links.filter { $0.connection == link } }
    private var current: Signal? { signals.first(where: { $0.id == picked }) ?? signals.first }
    private var groups: [Group] {
        [.energy, .balance] + ((scene.gauges ?? []).isEmpty ? [] : [.gauge])
            + (pairs.isEmpty ? [] : [.contact]) + (scene.connections.isEmpty ? [] : [.link])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recorded Measurements").font(.title2.weight(.semibold))
                Spacer()
                Button("Export CSV…", action: export)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                Picker("History", selection: $group) {
                    ForEach(groups, id: \.self) { Text($0.rawValue).tag($0) }
                }.fixedSize()
                if group == .gauge {
                    Picker("Gauge", selection: $gauge) {
                        ForEach(Array((scene.gauges ?? []).enumerated()), id: \.offset) { Text($1.name).tag($0) }
                    }.fixedSize()
                }
                if group == .contact {
                    Picker("Pair", selection: $pair) {
                        ForEach(pairs.indices, id: \.self) { Text(replayPairName(pairs[$0], scene: scene)).tag($0) }
                    }.fixedSize()
                }
                if group == .link {
                    Picker("Link", selection: $link) {
                        ForEach(scene.connections.indices, id: \.self) { Text("Connection \($0 + 1)").tag($0) }
                    }.fixedSize()
                }
                Picker("Signal", selection: Binding(get: { current?.id ?? "" }, set: { picked = $0 })) {
                    ForEach(signals) { Text($0.name).tag($0.id) }
                }.fixedSize()
            }
            if let signal = current {
                let frame = frames[index]
                let timeUnit = (frames.last?.time ?? 0) < 0.001 ? "µs" : "ms"
                let factor = timeUnit == "µs" ? 1e6 : 1e3
                Chart {
                    ForEach(frames.indices, id: \.self) { i in
                        LineMark(x: .value("Time", frames[i].time * factor), y: .value(signal.name, signal.value(frames[i])))
                            .foregroundStyle(signal.color)
                    }
                    ForEach(events) { event in
                        RuleMark(x: .value("Event", event.time * factor))
                            .foregroundStyle(assemblyMint.opacity(0.40)).lineStyle(StrokeStyle(dash: [3, 3]))
                    }
                    RuleMark(x: .value("Selected frame", frame.time * factor)).foregroundStyle(assemblyInk)
                    PointMark(x: .value("Time", frame.time * factor), y: .value(signal.name, signal.value(frame)))
                        .foregroundStyle(signal.color)
                }
                .chartXAxisLabel("Simulated time (\(timeUnit))")
                .chartYAxisLabel("\(signal.name) (\(signal.unit))")
                .frame(height: 250)
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0) }),
                       in: 0...Double(max(1, frames.count - 1)), step: 1) { Text("Measurement frame") }
                Text("\(replayTime(frame.time)) · \(signal.name) \(signal.value(frame), specifier: "%.6g") \(signal.unit)")
                    .font(.callout.monospacedDigit())
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(minWidth: 740, minHeight: 460)
        .onAppear { index = frames.indices.min(by: { abs(frames[$0].time - time) < abs(frames[$1].time - time) }) ?? 0 }
        .alert("CSV export", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var note: String {
        switch group {
        case .energy: "Recoverable energy includes elastic, hardening, contact, link and cohesive storage. Dissipated energy is plastic plus fracture. Lines connect recorded values."
        case .balance: "Changes are measured against frame zero. The closed assembly has zero external work. Dashed lines mark recorded events."
        case .gauge: "The gauge follows its reference triangle. Position and velocity use the gauge’s material weights. Stress, strain and damage are element values."
        case .contact: "The load sums compressive contributions at the active contacts. Impulse integrates that scalar load over solver steps."
        case .link: "Positive force is tension. For a band connection the force and energies sum across its attachment points."
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Impact Lab Measurements.csv"
        guard let url = ExperimentDirectory.run(panel) else { return }
        let fields = signals
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let subject = switch group {
        case .gauge: (scene.gauges ?? [])[gauge].name
        case .contact: replayPairName(pairs[pair], scene: scene)
        case .link: "Connection \(link + 1)"
        default: "Assembly"
        }
        let header = ["time_s", "subject"] + fields.map { quoted("\($0.name) [\($0.unit)]") } + ["events"]
        let rows = frames.map { frame in
            [String(frame.time), quoted(subject)] + fields.map { String($0.value(frame)) }
                + [quoted(events.filter { $0.time == frame.time }.map(\.label).joined(separator: " | "))]
        }
        let csv = ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        do { try csv.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
}
