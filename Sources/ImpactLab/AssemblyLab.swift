import AppKit
import ImpactPhysics
import SwiftUI
import UniformTypeIdentifiers

struct AssemblyLab: View {
    @State private var experiment = AssemblyExperiment()
    @State private var field = AssemblyField.strain
    @State private var showMesh = false
    @State private var showPieces = false
    @State private var compare = false
    @State private var signal = 0
    @State private var confirmClear = false
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    AssemblyCanvas(experiment: experiment, field: field, showMesh: showMesh)
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
            Button("Load bending fracture example") {
                do {
                    let scene = AssemblyScene.bendingFractureExample()
                    try experiment.configure(scene)
                    if let monitor = scene.monitor { experiment.select(monitor) }
                    field = .damage
                    signal = 3
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
            Button("New / Examples", systemImage: "doc.badge.plus") {
                experiment.pause()
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
            Button("Refine", systemImage: "square.grid.3x3") { experiment.refine() }
                .help("Pin this run and rerun at the next finer mesh resolution")
                .disabled(!experiment.canRefine)
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
                    Picker("Field", selection: $field) {
                        ForEach(AssemblyField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 166)
                    Toggle("Mesh", isOn: $showMesh).toggleStyle(.checkbox)
                    Spacer()
                    if let index = experiment.selectedIndex, field == .stress || field == .plastic {
                        let peak = field.values(index, in: experiment.simulation).max() ?? 0
                        Text(field == .stress
                             ? String(format: "Selected body · %.2f kPa peak", peak / 1000)
                             : String(format: "Selected body · %.2f%% peak", peak * 100))
                            .font(.caption).monospacedDigit()
                    } else if let pair = experiment.simulation.firstContactTimes.min(by: { $0.value < $1.value }) {
                        let names = experiment.scene.parts
                        Text("First contact · \(names[pair.key.x].name) / \(names[pair.key.y].name) · \(pair.value * 1000, specifier: "%.2f") ms")
                            .font(.caption).monospacedDigit().lineLimit(1)
                    } else {
                        Text("Drag a body to move it at the start of a run.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !experiment.scene.parts.isEmpty { readout }
            if let index = experiment.selectedIndex, let reading = experiment.simulation.fractureReading(index) {
                fractureReadout(index, reading)
            }
        }
    }

    private func fractureReadout(_ index: Int, _ reading: MaterialFractureReading) -> some View {
        let first = experiment.simulation.fragmentContacts.first {
            $0.onExposedFace && ($0.parts.x == index || $0.parts.y == index)
        }
        return DisclosureGroup(isExpanded: $showPieces) {
            let events = experiment.simulation.fragmentContacts.filter {
                $0.onExposedFace && ($0.parts.x == index || $0.parts.y == index)
            }
            let pieces = experiment.simulation.materialPieces(index)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    GridRow {
                        Text("Piece")
                        Text("Mass (kg/m)")
                        Text("Center X / Y (mm)")
                        Text("VX / VY (m/s)")
                    }.foregroundStyle(.secondary)
                    ForEach(pieces) { piece in
                        GridRow {
                            Text("#\(piece.id + 1)")
                            Text(piece.mass, format: .number.precision(.fractionLength(3)))
                            Text(String(format: "%+.1f / %+.1f", 1000 * piece.center.x, 1000 * piece.center.y))
                            Text(String(format: "%+.3f / %+.3f", piece.velocity.x, piece.velocity.y))
                        }
                    }
                    ForEach(events.indices, id: \.self) { i in
                        let event = events[i]
                        let names = experiment.scene.parts
                        let a = names[event.parts.x].name, b = names[event.parts.y].name
                        Text("New face · \(a) #\(event.pieces.x + 1) / \(b) #\(event.pieces.y + 1) · \(event.time * 1000, specifier: "%.2f") ms")
                            .gridCellColumns(4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).font(.caption2.monospacedDigit())
            }.frame(height: min(88, 16 * Double(1 + pieces.count + events.count))).padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                metric("Pieces", String(reading.pieces))
                metric("Broken / damaged edges", "\(reading.failedEdges) / \(reading.damagedEdges)")
                metric("Crack length", reading.crackLength * 1000, "mm")
                metric("Face separation", reading.separation * 1000, "mm")
                metric("Material fracture", reading.dissipation, "J/m")
                if let first { metric("New-face contact", first.time * 1000, "ms") }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 8))
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
                    metric("Stored cohesive", e.cohesive, "J/m")
                    metric("Max link load", maxForce, "N/m")
                    metric("Peak overlap", s.peakRelativePenetration * 100, "%")
                }
                GridRow {
                    metric("Momentum X", s.momentum.x, "N·s/m")
                    metric("Momentum Y", s.momentum.y, "N·s/m")
                    metric("Angular momentum", s.angularMomentum, "N·m·s/m")
                    metric("Energy error", error, "%")
                }
            }.padding(.top, 8)
            let contacts = s.firstContactTimes.sorted { $0.value < $1.value }
            if !contacts.isEmpty {
                let names = experiment.scene.parts
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("First contact by pair").foregroundStyle(.secondary)
                        ForEach(contacts, id: \.key) { pair, time in
                            let label = pair.x == pair.y ? "\(names[pair.x].name) fragments" : "\(names[pair.x].name) / \(names[pair.y].name)"
                            Text("\(label) · \(time * 1000, specifier: "%.2f") ms")
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
        let traceSignals: [(String, String, KeyPath<TraceSample, Double>)] = [
            ("Relative X", "mm", \.values.x), ("Body kinetic", "J/m", \.values.y),
            ("Link energy", "J/m", \.connectionEnergy), ("Material fracture", "J/m", \.materialFracture),
            ("Crack length", "mm", \.crackLength), ("Face separation", "mm", \.crackSeparation),
            ("Sampled peak stress", "kPa", \.peakStress)
        ]
        let (_, unit, field) = traceSignals[signal]
        let color = signal == 0 ? assemblyMint : assemblyAmber
        return VStack(spacing: 5) {
            HStack {
                Picker("Trace", selection: $signal) {
                    ForEach(traceSignals.indices, id: \.self) { Text(traceSignals[$0].0).tag($0) }
                }.labelsHidden().frame(width: 166)
                Spacer()
                Text(signal == 2 ? "All connections" : (signal == 0 ? "\(experiment.monitoredName) · \(experiment.relativeName)" : experiment.monitoredName))
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
                if scene.parts.contains(where: { $0.fracture != nil }) {
                    field = .damage
                    signal = 3
                }
                if args.indices.contains(index + 3), let requested = AssemblyField(rawValue: args[index + 3]) { field = requested }
                if let milliseconds = Double(args[index + 2]), milliseconds.isFinite, milliseconds >= 0 {
                    experiment.advance(to: milliseconds / 1000)
                }
                NSApplication.shared.activate(ignoringOtherApps: true)
            } catch { experiment.error = error.localizedDescription }
        } else if let index = args.firstIndex(of: "--assembly-smoke"), args.indices.contains(index + 1) {
            await smoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--fracture-smoke"), args.indices.contains(index + 1) {
            await fractureSmoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if experiment.selectedPart == nil, let id = experiment.scene.monitor {
            experiment.select(id)
        }
    }

    private func fractureSmoke(report: URL) async {
        var result: [String] = []
        do {
            let example = AssemblyScene.bendingFractureExample()
            try experiment.configure(AssemblyScene())
            for part in example.parts {
                guard let id = experiment.add(part.shape) else { throw CocoaError(.validationMissingMandatoryProperty) }
                experiment.updatePart(id) {
                    $0 = part
                    $0.id = id
                }
            }
            let specimen = experiment.scene.parts[0].id
            let striker = experiment.scene.parts[1].id
            experiment.edit {
                $0.duration = example.duration
                $0.monitor = specimen
            }
            experiment.select(specimen)
            field = .damage
            signal = 3
            showMesh = true
            result.append("built from blank=\(experiment.canRun && experiment.scene.parts.count == 5 && experiment.scene.connections.isEmpty)")
            let sceneURL = report.deletingPathExtension().appendingPathExtension("impact-assembly.json")
            try experiment.scene.save(to: sceneURL)
            experiment.advance(to: experiment.scene.duration)
            let base = experiment.samples
            result.append("detached and receiver hit a new face=\(experiment.finished && experiment.simulation.materialPieces(0).count > 1 && experiment.simulation.fragmentContacts.contains { $0.parts == SIMD2(0, 4) && $0.onExposedFace })")
            experiment.pin()
            try experiment.configure(AssemblyScene.open(sceneURL))
            experiment.advance(to: experiment.scene.duration)
            result.append("saved scene replay=\(base == experiment.samples)")
            experiment.updatePart(striker) { $0.center.x = 0.023 }
            let shiftedURL = report.deletingPathExtension().appendingPathExtension("shifted.impact-assembly.json")
            try experiment.scene.save(to: shiftedURL)
            experiment.advance(to: experiment.scene.duration)
            result.append("moved striker changes fracture trace=\(experiment.finished && base.map(\.materialFracture) != experiment.samples.map(\.materialFracture))")

            try experiment.configure(AssemblyScene.open(sceneURL))
            experiment.advance(to: experiment.scene.duration)
            experiment.refine()
            result.append("refine pinned and remeshed=\(experiment.reference?.samples == base && experiment.scene.resolution == .fine && experiment.running)")
            experiment.advance(to: experiment.scene.duration)
            let matched = SceneTrace.matching(base, experiment.samples)
            result.append("refinement aligned fracture output=\(experiment.finished && matched.count == base.count && matched.contains { $0.referenceSample.crackLength != $0.currentSample.crackLength })")
            compare = true
            try? await Task.sleep(for: .milliseconds(450))
            result.append("native window=\(NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" })")
            result.append("comparison sheet=\(NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true })")
        } catch {
            result.append("error=\(error.localizedDescription)")
        }
        try? (result.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
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
