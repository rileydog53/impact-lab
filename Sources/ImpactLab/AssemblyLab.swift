import AppKit
import ImpactPhysics
import SwiftUI
import UniformTypeIdentifiers

struct AssemblyLab: View {
    @State private var experiment = AssemblyExperiment()
    @State private var plastic = false
    @State private var compare = false
    @State private var signal = 0
    @State private var confirmClear = false
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    AssemblyCanvas(experiment: experiment, plastic: plastic)
                        .frame(minHeight: 230, maxHeight: .infinity)
                    indicators
                    trace
                    status
                }
                AssemblyEditor(experiment: experiment).frame(width: 315)
            }
        }
        .padding(20)
        .background(Color(red: 0.055, green: 0.085, blue: 0.116))
        .foregroundStyle(assemblyInk)
        .onReceive(timer) { _ in experiment.tick() }
        .onDisappear { experiment.pause() }
        .task { await startup() }
        .sheet(isPresented: $compare) {
            if let reference = experiment.reference {
                ComparisonView(reference: reference, current: experiment.current)
            }
        }
        .alert("Assembly", isPresented: Binding(get: { experiment.error != nil }, set: { if !$0 { experiment.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(experiment.error ?? "")
        }
        .confirmationDialog("Replace this assembly?", isPresented: $confirmClear) {
            Button("New blank assembly", role: .destructive) {
                do { try experiment.configure(AssemblyScene()) }
                catch { experiment.error = error.localizedDescription }
            }
            Button("Load enclosure example") {
                do {
                    let scene = AssemblyScene.enclosureExample()
                    try experiment.configure(scene)
                    if let monitor = scene.monitor { experiment.select(monitor) }
                } catch { experiment.error = error.localizedDescription }
            }
        } message: {
            Text("Save your current setup first if you want to reopen it.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assembly laboratory").font(.system(size: 29, weight: .semibold))
                Text("\(experiment.scene.parts.count) bodies · \(experiment.scene.connections.count) connections")
                    .font(.subheadline).foregroundStyle(assemblyMint)
            }
            Spacer()
            Button("New", systemImage: "doc.badge.plus") {
                experiment.pause()
                if experiment.scene.parts.isEmpty { return }
                confirmClear = true
            }
            Button("Open", systemImage: "folder") { open() }
            Button("Save", systemImage: "square.and.arrow.down") { save() }
                .disabled(experiment.scene.parts.isEmpty)
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            Button(experiment.running ? "Pause" : "Run", systemImage: experiment.running ? "pause.fill" : "play.fill") {
                experiment.toggle()
            }
            .buttonStyle(.borderedProminent).tint(assemblyMint).foregroundStyle(.black)
            .disabled(!experiment.running && !experiment.canRun)
            .keyboardShortcut(.space, modifiers: [])
            Button("+1 ms") { experiment.advance(to: experiment.simulation.time + 0.001) }
                .disabled(experiment.running || !experiment.canRun)
            Button("Reset", systemImage: "arrow.counterclockwise") { experiment.reset() }
                .labelStyle(.iconOnly).help("Reset the assembly to its initial state")
            Toggle("Slow", isOn: Binding(get: { experiment.slow }, set: { experiment.slow = $0 }))
                .toggleStyle(.checkbox).help("Play at one fifth of normal playback speed")
            Spacer()
            Button("Pin", systemImage: "pin") { experiment.pin() }
                .disabled(experiment.samples.count < 2)
            Button("Compare", systemImage: "chart.xyaxis.line") { experiment.pause(); compare = true }
                .disabled(experiment.reference == nil || experiment.samples.count < 2)
            Text(String(format: "%.2f ms", experiment.simulation.time * 1000))
                .font(.system(.body, design: .monospaced)).frame(minWidth: 84, alignment: .trailing)
        }
        .font(.callout)
    }

    private var indicators: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = experiment.simulation.initialIssue ?? experiment.simulation.failure {
                Label(reason, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(assemblyAmber)
            } else {
                HStack {
                    Picker("Field", selection: $plastic) {
                        Text("Axial strain").tag(false)
                        Text("Plastic strain").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 192)
                    Spacer()
                    if let pair = experiment.simulation.firstContactTimes.min(by: { $0.value < $1.value }) {
                        let names = experiment.scene.parts
                        Text("First contact · \(names[pair.key.x].name) / \(names[pair.key.y].name) · \(pair.value * 1000, specifier: "%.2f") ms")
                            .font(.caption).monospacedDigit().lineLimit(1)
                    } else {
                        Text("Drag a body to move it at the start of a run.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !experiment.scene.parts.isEmpty { readout }
        }
    }

    private var readout: some View {
        let s = experiment.simulation
        let e = s.energies
        let motion = experiment.relativeMotion
        let error = s.initialEnergy > 0 ? 100 * (e.total / s.initialEnergy - 1) : 0
        let maxForce = s.linkReadings.map { abs($0.force) }.max() ?? 0
        let broken = s.linkReadings.filter { $0.damage >= 1 }.count
        return DisclosureGroup {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    metric("Elastic", e.elastic, "J/m")
                    metric("Contact", e.contact, "J/m")
                    metric("Hardening", e.hardening, "J/m")
                    metric("Plastic", e.plastic, "J/m")
                }
                GridRow {
                    metric("Fracture", e.fracture, "J/m")
                    metric("Max link load", maxForce, "N/m")
                    metric("Peak overlap", s.peakRelativePenetration * 100, "%")
                    metric("Energy error", error, "%")
                }
                GridRow {
                    metric("Momentum X", s.momentum.x, "N·s/m")
                    metric("Momentum Y", s.momentum.y, "N·s/m")
                    metric("Angular momentum", s.angularMomentum, "N·m·s/m")
                    metric("Timestep", s.dt * 1e6, "µs")
                }
            }.padding(.top, 8)
            let contacts = s.firstContactTimes.sorted { $0.value < $1.value }
            if !contacts.isEmpty {
                let names = experiment.scene.parts
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("First contact by pair").foregroundStyle(.secondary)
                        ForEach(contacts, id: \.key) { pair, time in
                            Text("\(names[pair.x].name) / \(names[pair.y].name) · \(time * 1000, specifier: "%.2f") ms")
                                .monospacedDigit()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: min(77, 18 * Double(contacts.count + 1))).font(.caption)
            }
        } label: {
            HStack(spacing: 12) {
                metric("Relative X / Y", String(format: "%+.2f / %+.2f mm", 1000 * motion.x, 1000 * motion.y))
                metric("Kinetic", e.kinetic, "J/m")
                metric("Connections", e.connection, "J/m")
                metric("Failed links", String(broken))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ name: String, _ value: Double, _ unit: String) -> some View {
        metric(name, String(format: "%.3f", value) + (unit == "%" ? "" : " ") + unit)
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit()).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trace: some View {
        let samples = experiment.samples
        let duration = experiment.scene.duration
        let field: KeyPath<TraceSample, Double> = signal == 0 ? \.values.x : (signal == 1 ? \.values.y : \.connectionEnergy)
        let unit = signal == 0 ? "mm" : "J/m"
        let color = signal == 0 ? assemblyMint : assemblyAmber
        return VStack(spacing: 5) {
            HStack {
                Picker("Trace", selection: $signal) {
                    Text("Relative X").tag(0)
                    Text("Body kinetic").tag(1)
                    Text("Link energy").tag(2)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
                Spacer()
                Text(signal == 2 ? "All connections" : "\(experiment.monitoredName) · \(experiment.relativeName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Canvas { context, size in
                let values = samples.map { $0[keyPath: field] }
                let low = min(0, values.min() ?? 0)
                let high = max(signal == 0 ? 1 : 0.1, values.max() ?? 0)
                let inset = 8.0
                let left = 59.0, right = size.width - 15
                let height = size.height - 25
                func y(_ value: Double) -> Double { inset + (high - value) / (high - low) * height }
                for value in [low, high] {
                    let row = y(value)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: left, y: row))
                        p.addLine(to: CGPoint(x: right, y: row))
                    }, with: .color(assemblyInk.opacity(0.16)))
                    context.draw(Text(String(format: "%.2f %@", value, unit)).font(.caption2.monospaced()),
                                 at: CGPoint(x: left - 6, y: row), anchor: .trailing)
                }
                let path = Path { p in
                    for (index, sample) in samples.enumerated() {
                        let point = CGPoint(x: left + sample.time / duration * (right - left), y: y(sample[keyPath: field]))
                        if index == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.6)
                context.draw(Text(String(format: "%.0f ms", 1000 * duration)).font(.caption2.monospaced()),
                             at: CGPoint(x: right, y: size.height - 5), anchor: .bottomTrailing)
            }.frame(height: 78)
                .accessibilityLabel("Sampled assembly measurements over time")
        }
        .padding(8)
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func open() {
        experiment.pause()
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.json]
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        do { try experiment.configure(AssemblyScene.open(url)) }
        catch { experiment.error = error.localizedDescription }
    }

    private func save() {
        experiment.pause()
        let dialog = NSSavePanel()
        dialog.allowedContentTypes = [.json]
        dialog.nameFieldStringValue = "Assembly.impact-assembly.json"
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        do { try experiment.scene.save(to: url) }
        catch { experiment.error = error.localizedDescription }
    }

    private func startup() async {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--assembly-inspect"), args.indices.contains(index + 2) {
            do {
                let scene = try AssemblyScene.open(URL(fileURLWithPath: args[index + 1]))
                try experiment.configure(scene)
                if let id = scene.monitor { experiment.select(id) }
                if let milliseconds = Double(args[index + 2]), milliseconds.isFinite, milliseconds >= 0 {
                    experiment.advance(to: milliseconds / 1000)
                }
                NSApplication.shared.activate(ignoringOtherApps: true)
            } catch { experiment.error = error.localizedDescription }
        } else if let index = args.firstIndex(of: "--assembly-smoke"), args.indices.contains(index + 1) {
            await smoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if experiment.selectedPart == nil, let id = experiment.scene.monitor {
            experiment.select(id)
        }
    }

    private func smoke(report: URL) async {
        try? await Task.sleep(for: .milliseconds(400))
        var result: [String] = []
        do {
            let visible = NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" }
            result.append("native window=\(visible)")
            let scene = AssemblyScene.enclosureExample()
            try experiment.configure(AssemblyScene())
            var ids: [UUID: UUID] = [:]
            for part in scene.parts {
                if let id = experiment.add(part.shape) {
                    ids[part.id] = id
                    experiment.updatePart(id) {
                        $0 = part
                        $0.id = id
                    }
                }
            }
            for link in scene.connections {
                let a = ids[link.first]!, b = ids[link.second]!
                if let generated = experiment.addConnection(first: a, second: b) {
                    experiment.updateConnection(generated) {
                        $0 = link
                        $0.id = generated
                        $0.first = a
                        $0.second = b
                    }
                }
            }
            experiment.edit {
                $0.monitor = ids[scene.monitor!]
                $0.relativeTo = ids[scene.relativeTo!]
                $0.duration = scene.duration
            }
            result.append("built from blank=\(experiment.canRun && experiment.scene.parts.count == 4 && experiment.scene.connections.count == 2)")
            let url = report.deletingPathExtension().appendingPathExtension("impact-assembly.json")
            try experiment.scene.save(to: url)

            experiment.toggle()
            for _ in 0..<40 where experiment.simulation.time < 0.023 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            experiment.pause()
            result.append("timer advanced to contact=\(experiment.simulation.time >= 0.023 && !experiment.simulation.firstContactTimes.isEmpty)")
            let paused = experiment.simulation.time
            try? await Task.sleep(for: .milliseconds(100))
            result.append("paused=\(paused == experiment.simulation.time)")
            experiment.advance(to: paused + 0.001)
            result.append("millisecond step=\(experiment.simulation.time - paused >= 0.000999999)")
            while experiment.advance() {}
            let trace = experiment.samples
            let success = experiment.finished && experiment.simulation.energies.fracture > 0
                && experiment.simulation.firstContactTimes[SIMD2(0, 1)] != nil
            result.append("enclosure impact and cavity contact=\(success)")
            experiment.pin()

            try experiment.configure(AssemblyScene.open(url))
            while experiment.advance() {}
            result.append("saved trace replay=\(trace == experiment.samples)")
            let mount = experiment.scene.connections.first!.id
            experiment.updateConnection(mount) { $0.stiffness *= 1.6 }
            while experiment.advance() {}
            let matches = SceneTrace.matching(trace, experiment.samples)
            result.append("edited stiffness changes response=\(matches.contains { abs($0.current.x - $0.reference.x) > 1 })")
            compare = true
            try? await Task.sleep(for: .milliseconds(400))
            result.append("comparison sheet=\(NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true })")
            compare = false
            try? await Task.sleep(for: .milliseconds(300))

            try experiment.configure(AssemblyScene())
            let a = experiment.add(.block)!, b = experiment.add(.block)!, c = experiment.add(.block)!
            experiment.updatePart(a) { $0.center = Point(-0.09, 0.022); $0.angle = -8; $0.velocity = Point(1, -0.05) }
            experiment.updatePart(b) { $0.center = .zero }
            experiment.updatePart(c) { $0.center = Point(0.115, -0.016); $0.material.density = 1300 }
            experiment.addConnection(first: b, second: c)
            experiment.edit { $0.monitor = c; $0.relativeTo = b }
            while experiment.advance() {}
            result.append("different three-body build=\(experiment.finished && experiment.simulation.firstContactTimes[SIMD2(0, 1)] != nil && experiment.simulation.kineticEnergy(2) > 0.005)")
        } catch {
            result.append("smoke=false \(error.localizedDescription)")
        }
        try? result.joined(separator: "\n").appending("\n").write(to: report, atomically: true, encoding: .utf8)
        exit(result.contains { $0.contains("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
    }
}
