import AppKit
import ImpactPhysics
import SwiftUI
import UniformTypeIdentifiers

struct AssemblyLab: View {
    @State private var experiment = AssemblyExperiment()
    @State private var field = AssemblyField.strain
    @State private var showMesh = false
    @State private var smoothFields = true
    @State private var exportMessage: String?
    @State private var showInitial = false
    @State private var showVelocity = false
    @State private var range = AssemblyFieldRange.standard
    @State private var measurements = false
    @State private var definition = false
    @State private var showMeshReport = false
    @State private var showPieces = false
    @State private var compare = false
    @State private var sceneGuide = false
    @State private var study = false
    @State private var library = false
    @State private var studySmokeResult: Result<AssemblyStudy, Error>?
    @State private var signal = 0
    @State private var replacement: Replacement?
    @State private var confirmReplacement = false
    @State private var scenarioLibrary = false
    @State private var scenario: ScenarioSession?
    @State private var pendingScenario: (session: ScenarioSession, calculate: Bool)?
    @State private var scenarioToken: UUID?
    @State private var scenarioResults = false
    @State private var confirmScenario = false
    @State private var confirmLongRun: RunCostEstimate?

    private struct Replacement {
        let scene: AssemblyScene
        let title: String
        var url: URL? = nil
        var field = AssemblyField.stress
        var signal = 0
    }
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    AssemblyCanvas(experiment: experiment, field: field, showMesh: showMesh, smooth: smoothFields,
                                   showInitial: showInitial, showVelocity: showVelocity, limit: fieldLimit)
                        .frame(minHeight: experiment.frame == nil ? 230 : 170, maxHeight: .infinity)
                    indicators
                    trace
                    if experiment.frames.count > 1 { timeline }
                    if experiment.clip != nil || experiment.slowing || experiment.slowNote != nil { slowMotionBanner }
                    if scenario != nil { scenarioBanner }
                    AssemblyComputationStatus(experiment: experiment)
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
                let current = experiment.current
                if let first = reference.replay, let second = current.replay {
                    AssemblyFieldComparison(reference: reference, current: current, first: first, second: second, field: field)
                } else {
                    ComparisonView(reference: reference, current: current)
                }
            }
        }
        .sheet(isPresented: $showMeshReport) { meshReport }
        .sheet(isPresented: $sceneGuide) { SceneFormatGuide() }
        .sheet(isPresented: $measurements) {
            ReplayMeasurements(scene: experiment.scene, frames: experiment.frames,
                               events: experiment.replay?.timeline ?? [], time: experiment.displayTime)
        }
        .sheet(isPresented: $study) {
            studyView
        }
        .sheet(isPresented: $scenarioLibrary, onDismiss: beginPendingScenario) {
            ScenarioLibraryView { chosen, settings, calculate in
                pendingScenario = (ScenarioSession(scenario: chosen, settings: settings), calculate)
                scenarioLibrary = false
            }
        }
        .sheet(isPresented: $scenarioResults) {
            if let scenario {
                ScenarioResultsView(session: scenario, first: experiment.reference, second: experiment.current) {
                    scenarioResults = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        compare = true
                    }
                }
            }
        }
        .confirmationDialog(longRunTitle, isPresented: Binding(get: { confirmLongRun != nil }, set: { if !$0 { confirmLongRun = nil } }),
                            titleVisibility: .visible, presenting: confirmLongRun) { _ in
            Button("Calculate Anyway") { confirmLongRun = nil; experiment.calculate() }
            Button("Cancel", role: .cancel) { confirmLongRun = nil }
        } message: { estimate in
            Text(longRunMessage(estimate))
        }
        .confirmationDialog("Replace the unsaved assembly?", isPresented: $confirmScenario) {
            Button("Discard Changes and Continue", role: .destructive) { startScenario() }
            Button("Cancel", role: .cancel) { pendingScenario = nil }
        }
        .sheet(isPresented: $library, onDismiss: applyPendingReplacement) {
            ExperimentLibrary { scene, name in
                replacement = Replacement(scene: scene, title: name)
                library = false
            }
        }
        .alert("Assembly", isPresented: Binding(get: { experiment.error != nil }, set: { if !$0 { experiment.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(experiment.error ?? "")
        }
        .confirmationDialog("Replace the unsaved assembly?", isPresented: $confirmReplacement) {
            Button("Save and Continue") {
                if save() { applyReplacement(refreshFile: true) }
                else { replacement = nil }
            }
            Button("Discard Changes", role: .destructive) { applyReplacement() }
            Button("Cancel", role: .cancel) { replacement = nil }
        }
    }

    // MARK: Run cost

    private func requestCalculate() {
        let estimate = experiment.estimate
        if estimate.seconds > RuntimeWarnings.thresholds.confirm { confirmLongRun = estimate }
        else { experiment.calculate() }
    }

    private var longRunTitle: String {
        guard let estimate = confirmLongRun else { return "" }
        return estimate.seconds > RuntimeWarnings.thresholds.long
            ? "Long run: \(RunCostEstimate.duration(estimate.seconds)) estimated"
            : "This run is estimated at \(RunCostEstimate.duration(estimate.seconds))"
    }

    private func longRunMessage(_ estimate: RunCostEstimate) -> String {
        var text = "\(Int(estimate.steps).formatted()) steps for \(replayTime(experiment.scene.duration - experiment.simulation.time)) of simulated time. "
            + experiment.simulation.timestep.explanation + "\n\n" + estimate.laneNote + "\n\n" + estimate.uncertainty
        if estimate.seconds > RuntimeWarnings.thresholds.long {
            text += "\n\nThis is longer than your long-run threshold. To shorten it without weakening any safeguard: shorten the duration, use a coarser mesh, or turn off Material fracture on stiff bodies. You can cancel at any time and keep the partial result."
        }
        return text
    }

    @ViewBuilder
    private var estimateNote: some View {
        let estimate = experiment.estimate
        if estimate.seconds > RuntimeWarnings.thresholds.show {
            Text("Estimated \(RunCostEstimate.duration(estimate.seconds)), roughly ×2 either way")
                .foregroundStyle(estimate.seconds > RuntimeWarnings.thresholds.confirm ? assemblyAmber : .secondary)
                .help(experiment.simulation.timestep.explanation + " " + estimate.laneNote + " " + estimate.uncertainty)
        }
    }

    private var studyView: some View {
        var view = AssemblyStudyView(scene: experiment.scene, selectedBody: experiment.selectedPart)
        if CommandLine.arguments.contains("--study-smoke") {
            view.smokeResult = { studySmokeResult = $0 }
        }
        return view
    }

    // MARK: Scenarios

    private var scenarioBanner: some View {
        let session = scenario!
        let state: String = switch session.stage {
        case .first: "Calculating case A (1 of 2)…"
        case .second: "Case A pinned. Calculating case B (2 of 2)…"
        case .finished: experiment.reference == nil ? "Case A is no longer pinned." : "Case A pinned. Showing case B. Edit and rerun B to compare variations."
        case .stopped(let reason): reason
        }
        return HStack(spacing: 8) {
            Label("Scenario · \(session.scenario.rawValue)", systemImage: session.scenario.icon)
                .font(.callout.weight(.semibold)).foregroundStyle(assemblyMint)
            Text(state).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Results", systemImage: "tablecells") { experiment.pause(); scenarioResults = true }
                .disabled(experiment.solving || experiment.reference?.replay == nil || experiment.replay == nil)
            Button("End Scenario", systemImage: "xmark") {
                scenarioToken = nil
                scenario = nil
            }.labelStyle(.iconOnly).help("Stop tracking this scenario. The current assembly stays loaded.")
        }
        .controlSize(.small)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(assemblyMint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func beginPendingScenario() {
        guard pendingScenario != nil else { return }
        experiment.pause()
        if experiment.isDirty { confirmScenario = true } else { startScenario() }
    }

    private func startScenario() {
        guard let pending = pendingScenario else { return }
        pendingScenario = nil
        let token = UUID()
        scenarioToken = token
        Task { await runScenario(pending.session, calculate: pending.calculate, token: token) }
    }

    @discardableResult
    private func runScenario(_ chosen: ScenarioSession, calculate: Bool, token: UUID) async -> Bool {
        var session = chosen
        scenario = calculate ? session : nil
        field = switch session.scenario {
        case .elasticContrast, .bondedLayers: .pressure
        case .elasticVersusYielding, .strainHardening: .plastic
        case .interfaceFailure: .damage
        }
        func finish(_ index: Int) async -> Bool {
            experiment.calculate()
            while experiment.solving { try? await Task.sleep(for: .milliseconds(50)) }
            guard scenarioToken == token else { return false }
            guard experiment.finished else {
                session.stage = .stopped("Case \(index == 0 ? "A" : "B") stopped before the end. Resume it or start the scenario again.")
                scenario = session
                return false
            }
            return true
        }
        do {
            try experiment.load(session.scenario.scene(session.settings, case: 0), title: session.title(case: 0))
            guard calculate else { return true }
            guard await finish(0) else { return false }
            experiment.pin()
            session.stage = .second
            scenario = session
            try experiment.load(session.scenario.scene(session.settings, case: 1), title: session.title(case: 1))
            guard await finish(1) else { return false }
            session.stage = .finished
            scenario = session
            scenarioResults = true
            return true
        } catch {
            experiment.error = error.localizedDescription
            scenario = nil
            return false
        }
    }

    private func scenarioSmoke(report: URL) async {
        var checks: [String] = []
        try? await Task.sleep(for: .milliseconds(400))
        scenarioLibrary = true
        for _ in 0..<20 where !NSApplication.shared.windows.contains(where: { $0.attachedSheet?.isVisible == true }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        checks.append("native scenario library=\(NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true })")
        scenarioLibrary = false
        try? await Task.sleep(for: .milliseconds(400))
        for chosen in LabScenario.allCases {
            let token = UUID()
            scenarioToken = token
            let started = ProcessInfo.processInfo.systemUptime
            let ran = await runScenario(ScenarioSession(scenario: chosen, settings: chosen.defaultSettings), calculate: true, token: token)
            let report = experiment.reference.flatMap { a in
                a.replay.flatMap { ra in experiment.replay.flatMap { rb in
                    chosen.report(.init(scene: a.scene, replay: ra), .init(scene: experiment.scene, replay: rb))
                } }
            }
            checks.append(String(format: "%@ ran both cases and measured=%@ (%.1f s)", chosen.rawValue,
                                 String(ran && report != nil && scenario?.stage == .finished), ProcessInfo.processInfo.systemUptime - started))
            if let report { checks.append("  " + report.finding) }
            for _ in 0..<20 where !NSApplication.shared.windows.contains(where: { $0.attachedSheet?.isVisible == true }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            checks.append("  results sheet=\(scenarioResults && NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true })")
            scenarioResults = false
            try? await Task.sleep(for: .milliseconds(400))
        }
        // Edit case B of the last scenario and rerun it against the pinned case A.
        let pinned = experiment.reference?.samples
        experiment.reset()
        let striker = experiment.scene.parts[1].id
        experiment.updatePart(striker) { $0.velocity.y = -1.9 }
        experiment.calculate()
        while experiment.solving { try? await Task.sleep(for: .milliseconds(50)) }
        let edited = experiment.reference.flatMap { a in
            a.replay.flatMap { ra in experiment.replay.flatMap { rb in
                LabScenario.interfaceFailure.report(.init(scene: a.scene, replay: ra), .init(scene: experiment.scene, replay: rb))
            } }
        }
        checks.append("edited case B rerun against pinned A=\(experiment.finished && experiment.reference?.samples == pinned && edited != nil && experiment.scene.parts[1].velocity.y == -1.9)")
        if let edited { checks.append("  " + edited.finding) }
        do {
            try (checks.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        } catch { exit(EXIT_FAILURE) }
        exit(checks.contains { $0.contains("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
    }

    private func applyPendingReplacement() {
        guard replacement != nil else { return }
        experiment.pause()
        if experiment.isDirty {
            confirmReplacement = true
        } else {
            applyReplacement()
        }
    }

    private func applyReplacement(refreshFile: Bool = false) {
        guard let next = replacement else { return }
        replacement = nil
        do {
            let scene = if refreshFile, let url = next.url { try AssemblyScene.open(url) } else { next.scene }
            try experiment.load(scene, title: next.title, url: next.url)
            field = next.field
            signal = next.signal
        } catch { experiment.error = error.localizedDescription }
    }

    private func loadPreset(_ scene: AssemblyScene, title: String) {
        replacement = Replacement(scene: scene, title: title)
        applyPendingReplacement()
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(experiment.title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                    .help(experiment.fileURL?.path ?? experiment.title)
                HStack(spacing: 8) {
                    Text(experiment.canEdit ? "Edit assembly" : "Inspect run")
                        .foregroundStyle(assemblyMint)
                    if experiment.isDirty {
                        Label("Unsaved changes", systemImage: "circle.fill").foregroundStyle(assemblyAmber)
                    }
                }.font(.caption)
            }
            Spacer(minLength: 8)
            Button("Study", systemImage: "chart.line.uptrend.xyaxis") {
                experiment.pause()
                experiment.placingGauge = false
                experiment.linkPlacement = nil
                study = true
            }
            .disabled(experiment.scene.parts.isEmpty || experiment.simulation.initialIssue != nil)
            Button("Experiments", systemImage: "books.vertical") {
                experiment.pause()
                experiment.placingGauge = false
                experiment.linkPlacement = nil
                library = true
            }
            // The Scenarios button is hidden (2026-11-26): its solver tests use the simplified soft material, which
            // Joseph asked not to see. They still run in the automatic checks and the app's scenario smoke test.
            .disabled(experiment.solving)
            Menu("New / Examples", systemImage: "doc.badge.plus") {
                Button("Blank Assembly") { loadPreset(AssemblyScene(), title: "Untitled assembly") }
                Section("Ready-made showcases (real materials)") {
                    ForEach(ShowcasePreset.allCases) { preset in
                        Button(preset.rawValue) {
                            do {
                                replacement = Replacement(scene: try preset.scene(), title: preset.rawValue)
                                applyPendingReplacement()
                            } catch { experiment.error = error.localizedDescription }
                        }
                        .help(preset.description)
                    }
                }
                Button("Metal Impact Example") {
                    replacement = Replacement(scene: .metalImpactExample(), title: "Metal impact example",
                                              field: .plastic, signal: 7)
                    applyPendingReplacement()
                }
                Section("Layered examples (laminates)") {
                    ForEach(LayeredExample.allCases, id: \.self) { example in
                        Button(example.rawValue) {
                            do {
                                replacement = Replacement(scene: try example.scene(), title: example.rawValue, field: .damage)
                                applyPendingReplacement()
                            } catch { experiment.error = error.localizedDescription }
                        }
                        .help(example.description)
                    }
                }
            }.fixedSize()
            Button("Open", systemImage: "folder") { open() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Save", systemImage: "square.and.arrow.down") { save() }
                .keyboardShortcut("s", modifiers: .command)
            Menu {
                Button("Save As…") { save(asNewFile: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Import Scene JSON…") { open() }
                Button("Export Scene JSON Copy…") { exportCopy() }
                Button("Reload from Disk") { reloadFromDisk() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(experiment.fileURL == nil)
                Button("Scene JSON Format…") { sceneGuide = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More file actions")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var metalScale: Bool {
        experiment.scene.parts.contains {
            $0.material.provenance != nil || $0.bondedLayer?.material.provenance != nil
                || $0.bondedLayer?.third?.material.provenance != nil
        }
    }

    private var fieldLimit: Double { field.limit(for: range, frame: experiment.frame, metal: metalScale) }

    private var timeline: some View {
        HStack(spacing: 7) {
            Button("Restart Replay", systemImage: "backward.end.fill") { experiment.seek(to: experiment.playbackStart) }
                .labelStyle(.iconOnly)
            Button("Previous Frame", systemImage: "backward.frame.fill") { experiment.stepFrame(by: -1) }
                .labelStyle(.iconOnly).disabled(experiment.frameIndex == 0)
            Slider(value: Binding(get: { experiment.displayTime }, set: { experiment.seek(to: $0) }),
                   in: experiment.playbackStart...max(experiment.playbackStart + 1e-12, experiment.playbackDuration)) { Text("Replay time") }
                .accessibilityValue(replayTime(experiment.displayTime))
            Button("Next Frame", systemImage: "forward.frame.fill") { experiment.stepFrame(by: 1) }
                .labelStyle(.iconOnly).disabled(experiment.frameIndex == experiment.playbackFrames.count - 1)
            Text(replayTime(experiment.displayTime)).font(.caption.monospacedDigit()).fixedSize()
            Menu("Events") {
                ForEach(experiment.replay?.timeline ?? []) { event in
                    Button("\(event.label) · \(replayTime(event.time))") { experiment.seek(to: event.time) }
                }
            }.fixedSize().disabled(experiment.replay?.timeline.isEmpty != false)
            if experiment.clip != nil {
                Button("Whole Run", systemImage: "arrow.uturn.backward") { experiment.exitClip() }
                    .help("Return to the whole recorded run at this moment")
            } else {
                Menu("Slow Down Here") {
                    ForEach(slowSpans, id: \.self) { span in
                        Button("Recalculate \(replayTime(span)) around this moment") { experiment.slowDown(span: span) }
                    }
                }
                .fixedSize().disabled(!experiment.canSlowDown)
                .help("Recalculate a short stretch around the shown moment from a saved checkpoint, keeping far more solver steps, and play it slowly. Every frame is calculated; nothing is interpolated.")
            }
            Button("Copy Summary", systemImage: "doc.on.clipboard") {
                guard let replay = experiment.replay else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(replay.textSummary(scene: experiment.scene, frameIndex: experiment.frameIndex), forType: .string)
            }
            .labelStyle(.iconOnly)
            .help("Copy a text summary of this run at the frame shown, to paste into chat")
            .disabled(experiment.replay == nil || experiment.clip != nil)
        }
        .controlSize(.small)
        .disabled(experiment.solving)
    }

    /// Stretches offered by Slow Down Here, as fractions of the run's length.
    private var slowSpans: [Double] {
        let duration = experiment.scene.duration
        return [duration / 100, duration / 40, duration / 15]
    }

    private var slowMotionBanner: some View {
        HStack(spacing: 8) {
            if experiment.slowing {
                ProgressView().controlSize(.small)
                Text("Recalculating this stretch from a saved checkpoint…").foregroundStyle(.secondary)
                Button("Cancel") { experiment.cancelSlowDown() }
            } else if let clip = experiment.clip {
                Text("Calculated").bold().foregroundStyle(assemblyMint)
                Text("Slowed down: \(replayTime(clip.end - clip.start)) recalculated, "
                     + (clip.stride == 1 ? "every solver step" : "every \(clip.stride) solver steps")
                     + " · \(clip.frames.count) frames")
                if clip.isExact {
                    Text("Matches the original run at all \(clip.shared) shared frames").foregroundStyle(assemblyMint)
                        .help("Frames this clip shares with the whole run were compared bit for bit.")
                } else if clip.shared == 0 {
                    Text("No shared frames to compare with the original run").foregroundStyle(.secondary)
                } else {
                    Text("Differs from the original run at \(clip.shared - clip.reproduced) of \(clip.shared) shared frames")
                        .foregroundStyle(assemblyAmber)
                        .help("The recalculation did not reproduce the original run exactly. Treat this clip with caution and report it.")
                }
            } else if let note = experiment.slowNote {
                Text(note).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
    }

    private var status: some View {
        HStack(spacing: 8) {
            if experiment.solving {
                if experiment.computation == nil { ProgressView("Starting calculation…").controlSize(.small) }
            } else if experiment.frames.count > 1 {
                Button(experiment.running ? "Pause" : "Play", systemImage: experiment.running ? "pause.fill" : "play.fill") {
                    experiment.toggle()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                Picker("Replay speed", selection: Binding(get: { experiment.playbackSpeed }, set: { experiment.playbackSpeed = $0 })) {
                    ForEach([0.25, 0.5, 1, 2, 4], id: \.self) { Text("\($0.formatted())×").tag($0) }
                }.labelsHidden().fixedSize()
                .help("At 1×, replay takes five seconds to show the recorded interval.")
                if experiment.canRun { Button("Resume Calculation", action: requestCalculate) }
                Button("Edit a Copy", systemImage: "square.and.pencil", action: experiment.editCopy)
                    .disabled(experiment.samples.count < 2)
                    .help("Keep this result as the comparison reference and return to editing a copy of its setup. Nothing is lost.")
            } else {
                Button("Calculate", systemImage: "play.fill", action: requestCalculate)
                    .buttonStyle(.borderedProminent)
                    .disabled(!experiment.canRun)
                    .keyboardShortcut(.space, modifiers: [])
                if experiment.canRun { estimateNote }
            }
            Button("Reset Run", systemImage: "arrow.counterclockwise", action: experiment.reset)
                .labelStyle(.iconOnly)
                .disabled(experiment.canEdit || experiment.solving)
                .help("Return to the authored assembly and clear this run. Completed runs stay in the run history.")
            Spacer()
            Button("Measurements", systemImage: "chart.xyaxis.line") { experiment.pause(); measurements = true }
                .disabled(experiment.frames.count < 2 || experiment.solving)
            Button("Pin", systemImage: "pin", action: experiment.pin)
                .disabled(experiment.samples.count < 2 || experiment.solving)
            Menu("History") {
                ForEach(Array(experiment.history.enumerated()).reversed(), id: \.offset) { index, entry in
                    Button("Use \(entry.label) as reference · \(entry.details)") { experiment.useAsReference(index) }
                }
                if experiment.history.isEmpty { Text("Completed runs appear here.") }
            }
            .fixedSize()
            .help("Completed runs this session (up to \(AssemblyExperiment.historyLimit)). Choose one to compare against.")
            Button("Compare") { experiment.pause(); compare = true }
                .disabled(experiment.reference == nil || experiment.samples.count < 2 || experiment.solving)
                .help(experiment.reference.map { "Compare against \($0.label.isEmpty ? "the pinned run" : $0.label)" } ?? "Pin a run or use Edit a Copy first")
            Button("Refine", systemImage: "square.grid.3x3", action: experiment.refine)
                .labelStyle(.iconOnly)
                .help("Pin this run and refine bodies that use the assembly mesh")
                .disabled(!experiment.canRefine || experiment.solving)
        }
        .font(.callout).controlSize(.small)
    }

    private var indicators: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if experiment.canEdit {
                    Picker("Snap", selection: Binding(get: { experiment.gridStep }, set: { experiment.gridStep = $0 })) {
                        Text("Off").tag(0.0)
                        Text("1 mm").tag(0.001)
                        Text("5 mm").tag(0.005)
                        Text("10 mm").tag(0.010)
                    }
                    .fixedSize()
                    .help("Snap dragged body centers to a world-coordinate grid")
                } else if experiment.frame != nil {
                    Picker("Result field", selection: $field) {
                        ForEach(AssemblyField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                    Picker("Color range", selection: $range) {
                        ForEach(AssemblyFieldRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize().disabled(field == .damage)
                    Menu("Overlays") {
                        Toggle("Initial geometry", isOn: $showInitial)
                        Toggle("Body velocity", isOn: $showVelocity)
                            .help("Arrows indicate center-of-mass velocity direction. Length uses a compressed display scale.")
                    }.fixedSize()
                }
                Toggle("Smooth", isOn: $smoothFields).toggleStyle(.checkbox)
                    .help("On: interpolated display of the calculated field (superconvergent patch recovery of per-element values). Off: raw per-element colors. The calculation is identical either way.")
                Toggle("Show mesh", isOn: $showMesh).toggleStyle(.checkbox)
                    .help("Draw the actual simulation mesh. Amber outlines indicate thin reference triangles.")
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("Results for ParaView (.pvd + .vtu)…") {
                        exportMessage = ResultsExportActions.exportParaView(frames: experiment.frames, suggestedName: experiment.title)
                    }
                    Button("Current frame as PNG…") {
                        exportMessage = ResultsExportActions.savePNG(frame: experiment.frame, field: field, limit: fieldLimit, title: experiment.title)
                    }
                }.fixedSize().disabled(experiment.frames.isEmpty)
                .help("Write the calculated results to files. Values are exactly what the solver recorded.")
                .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
                    Button("OK") { exportMessage = nil }
                } message: { Text(exportMessage ?? "") }
                if experiment.canEdit {
                    Button("Mesh Report", systemImage: "square.grid.3x3") {
                        showMesh = true
                        showMeshReport = true
                    }
                    .disabled(experiment.scene.parts.isEmpty)
                    .help("Check triangle counts and shape quality for the starting assembly")
                    if experiment.linkPlacement != nil {
                        Button("Cancel Link", role: .cancel) { experiment.linkPlacement = nil }
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Button(experiment.placingGauge ? "Cancel gauge" : "Place gauge", systemImage: "scope") {
                            experiment.placingGauge.toggle()
                        }
                        .disabled(!experiment.canEdit || experiment.scene.parts.isEmpty || experiment.gauges.count >= AssemblyGauge.limit)
                    }
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            if let placement = experiment.linkPlacement {
                let source = placement.first.flatMap { anchor in experiment.scene.parts.first { $0.id == anchor.body }?.name }
                let instruction = if let source {
                    placement.needsOtherBody
                        ? "Choose a different body for the second anchor. First anchor is on \(source)."
                        : "Click material on a second body. First anchor is on \(source)."
                } else {
                    "Click material on the first body to place an anchor."
                }
                Label(instruction, systemImage: "scope").font(.caption).foregroundStyle(assemblyMint)
            } else if experiment.placingGauge {
                Text("Click inside a body to place a material gauge.").font(.caption).foregroundStyle(assemblyMint)
            }
            if let reason = experiment.simulation.initialIssue ?? experiment.simulation.failure {
                Label(reason, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(assemblyAmber)
            } else if let note = experiment.initialMotionNote {
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(assemblyAmber)
            }
            if let frame = experiment.frame {
                playbackIndicator(frame)
            }
            if !experiment.scene.parts.isEmpty { readout }
            if let index = experiment.selectedIndex,
               let reading = experiment.frame?.bodies[index].fracture ?? experiment.simulation.fractureReading(index) {
                fractureReadout(index, reading)
            }
        }
    }

    @ViewBuilder private func playbackIndicator(_ frame: AssemblyReplayFrame) -> some View {
        HStack(spacing: 9) {
            if smoothFields { SmoothFieldLegend(field: field, limit: fieldLimit) }
            else { AssemblyFieldLegend(field: field, limit: fieldLimit) }
            Text(AssemblyField.layerLabel(smooth: smoothFields)).bold()
                .foregroundStyle(smoothFields ? assemblyAmber : assemblyMint)
                .help(smoothFields ? "Element values from the solver, interpolated for a continuous look. The smoothing adds no solver resolution."
                                   : "Element values exactly as the solver recorded them.")
            Text(field.provenance).foregroundStyle(.secondary)
            if field != .separation, frame.bodies.contains(where: { field.values($0).isEmpty }) {
                Text(field == .plastic || field == .plasticWork ? "Elastic bodies have no plastic history, so they keep their own color."
                                       : "Bodies with no \(field.rawValue.lowercased()) data keep their own color.")
                    .foregroundStyle(.secondary)
                    .help("A body that stays elastic records zero plastic strain, so the plastic-strain scale does not apply to it.")
            }
            Button("Field definition", systemImage: "info.circle") { definition = true }
                .labelStyle(.iconOnly).help(field.definition)
                .popover(isPresented: $definition) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(field.rawValue).font(.headline)
                        Text(field.definition)
                        Text("Geometry and local values are from the selected recorded frame. Element colors are constant within each triangle. The legend clips values beyond its end colors.").foregroundStyle(.secondary)
                    }.font(.callout).padding(14).frame(width: 310)
                }
        }.font(.caption)
        if let index = experiment.selectedIndex {
            let state = frame.bodies[index]
            let values = field == .separation ? state.cracks.map(\.separation) : field.values(state)
            let reading = if let element = experiment.probeElement, experiment.probeBody == index, values.indices.contains(element), field != .separation {
                "Element \(element + 1) · \(field.display(values[element], limit: fieldLimit))"
            } else if let high = values.max() {
                field.signed ? "\(field.display(values.min() ?? 0, limit: fieldLimit)) to \(field.display(high, limit: fieldLimit))"
                    : "Peak \(field.display(high, limit: fieldLimit))"
            } else {
                field == .separation ? "No inserted faces" : "Field unavailable on this body"
            }
            Text("\(experiment.scene.parts[index].name) · \(reading)")
                .font(.caption.monospacedDigit()).lineLimit(1)
                .help("Click a triangle in the viewer to follow its recorded element value.")
        }
        let active = frame.contacts.filter { $0.force > 0 }
        let contactLabel = active.max(by: { $0.force < $1.force }).map {
            let title = replayPairName($0.pair, scene: experiment.scene)
            return "Active contact · \(title) · \($0.force.formatted(.number.precision(.significantDigits(1...4)))) N/m"
        } ?? "No active contact in this frame"
        Text(contactLabel).font(.caption.monospacedDigit()).lineLimit(1)
            .help("White outlines show bodies in active contact. A dot marks the largest recorded boundary-contact contribution when available.")
        if experiment.scene.parts.contains(where: { $0.bondedLayer != nil || $0.fracture != nil }) {
            Text("Dashed gray · permanent bond    Dashed red · cohesive interface    Solid faces · failed interface")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var meshReport: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assembly mesh").font(.title2.weight(.semibold))
            Text("\(experiment.elementCount) triangles · \(experiment.simulation.dt * 1e6, specifier: "%.2f") µs timestep")
                .font(.callout).monospacedDigit()
            if let issue = experiment.simulation.initialIssue {
                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(assemblyAmber)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Body")
                    Text("Triangles")
                    Text("Lowest quality")
                    Text("Thin triangles")
                }.fontWeight(.semibold)
                ForEach(experiment.displayIndices, id: \.self) { index in
                    let quality = experiment.meshQuality[index]
                    GridRow {
                        Text(experiment.scene.parts[index].name)
                        Text(quality.triangleCount.formatted())
                        Text(quality.minimum, format: .number.precision(.fractionLength(2)))
                        Text(quality.thinTriangles.count.formatted())
                            .foregroundStyle(quality.thinTriangles.isEmpty ? assemblyInk : assemblyAmber)
                    }
                }
            }.font(.callout).monospacedDigit()
            Text("An equilateral triangle scores 1. Thin triangles below 0.20 are marked amber. Geometry changes regenerate the mesh. Use the body’s Mesh settings to change its refinement.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { showMeshReport = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(18).frame(minWidth: 530)
    }

    private func fractureReadout(_ index: Int, _ reading: MaterialFractureReading) -> some View {
        let first = (experiment.frame?.fragments ?? []).first {
            $0.onExposedFace && ($0.parts.x == index || $0.parts.y == index)
        }
        return DisclosureGroup(isExpanded: $showPieces) {
            let events = (experiment.frame?.fragments ?? []).filter { $0.parts.x == index || $0.parts.y == index }
            let pieces = experiment.frame?.bodies[index].pieces ?? experiment.simulation.materialPieces(index)
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
                        let label = event.onExposedFace ? "New face" : "Contact"
                        Text("\(label) · \(a) #\(event.pieces.x + 1) / \(b) #\(event.pieces.y + 1) · \(event.time * 1000, specifier: "%.2f") ms · \(event.normalImpulse, specifier: "%.3f") N·s/m")
                            .gridCellColumns(4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).font(.caption2.monospacedDigit())
            }.frame(height: min(88, 16 * Double(1 + pieces.count + events.count))).padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                metric("Pieces", String(reading.pieces))
                metric("Broken / inserted edges", "\(reading.failedEdges) / \(reading.insertedEdges)")
                metric("Crack length", reading.crackLength * 1000, "mm")
                metric("Face separation", reading.separation * 1000, "mm")
                metric("Material fracture", reading.dissipation, "J/m")
                if let first = first?.firstExposedTime { metric("New-face contact", first * 1000, "ms") }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 8))
    }

    private var readout: some View {
        let s = experiment.simulation
        let frame = experiment.frame
        let e = frame?.energies ?? s.energies
        let motion = experiment.relativeMotion
        let error = s.initialEnergy > 0 ? 100 * (e.total / s.initialEnergy - 1) : 0
        let maxForce = experiment.displayedLinks.map { abs($0.force) }.max() ?? 0
        let broken = experiment.displayedLinks.filter { $0.damage >= 1 }.count
        return DisclosureGroup {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    metric("Elastic", e.elastic, "J/m")
                    metric("Contact", e.contact, "J/m")
                    metric("Stored hardening", e.hardening, "J/m")
                    metric("Modelled plastic dissipation", e.plastic, "J/m")
                }
                GridRow {
                    metric("Fracture", e.fracture, "J/m")
                    metric("Stored cohesive", e.cohesive, "J/m")
                    metric("Max link load", maxForce, "N/m")
                    metric("Peak overlap", overlapText(relative: frame?.peakRelativePenetration ?? 0,
                                                       depth: frame?.peakPenetrationDepth ?? 0))
                }
                GridRow {
                    metric("Momentum X", (frame?.momentum ?? s.momentum).x, "N·s/m")
                    metric("Momentum Y", (frame?.momentum ?? s.momentum).y, "N·s/m")
                    metric("Angular momentum", frame?.angularMomentum ?? s.angularMomentum, "N·m·s/m")
                    metric("Energy error", error, "%")
                }
                if experiment.scene.bulkViscosity != nil {
                    GridRow {
                        metric("Bulk viscosity (numerical)", e.viscous, "J/m")
                        metric("Peak viscous damping", 100 * s.peakViscousDamping, "% critical")
                    }
                }
            }.padding(.top, 8)
            MeasurementHonesty.energyFootnote.padding(.top, 4)
            let contacts = s.firstContactTimes.filter { $0.value <= experiment.displayTime }.sorted { $0.value < $1.value }
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

    /// Overlap as a share of the local edge and as an absolute depth.
    private func overlapText(relative: Double, depth: Double) -> String {
        let absolute = depth < 1e-3 ? String(format: "%.3g µm", depth * 1e6) : String(format: "%.3g mm", depth * 1e3)
        return String(format: "%.3f%% · ", relative * 100) + absolute
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
        let duration = max(experiment.scene.duration, experiment.playbackDuration)
        let traceSignals: [(String, String, KeyPath<TraceSample, Double>)] = [
            ("Relative X", "mm", \.values.x), ("Body kinetic", "J/m", \.values.y),
            ("Link energy", "J/m", \.connectionEnergy), ("Material fracture", "J/m", \.materialFracture),
            ("Crack length", "mm", \.crackLength), ("Face separation", "mm", \.crackSeparation),
            ("Sampled peak stress", "kPa", \.peakStress), ("Modelled plastic dissipation", "J/m", \.plasticDissipation)
        ]
        let (_, unit, field) = traceSignals[signal]
        let color = signal == 0 ? assemblyMint : assemblyAmber
        return VStack(spacing: 5) {
            HStack {
                Picker("Trace", selection: $signal) {
                    ForEach(traceSignals.indices, id: \.self) { Text(traceSignals[$0].0).tag($0) }
                }.labelsHidden().frame(width: 166)
                Spacer()
                Text(signal == 2 ? "All connections" : (signal == 7 ? "All bodies" : (signal == 0 ? "\(experiment.monitoredName) · \(experiment.relativeName)" : experiment.monitoredName)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Canvas { context, size in
                let values = samples.map { $0[keyPath: field] }
                let low = min(0, values.min() ?? 0)
                let high = max(signal == 0 ? 1 : 0.1, values.max() ?? 0)
                let inset = 8.0
                let left = 92.0, right = size.width - 15
                let height = size.height - 25
                func y(_ value: Double) -> Double { inset + (high - value) / (high - low) * height }
                for value in [low, high] {
                    let row = y(value)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: left, y: row))
                        p.addLine(to: CGPoint(x: right, y: row))
                    }, with: .color(assemblyInk.opacity(0.16)))
                    context.draw(Text(String(format: "%.5g %@", value, unit)).font(.caption2.monospaced()),
                                 at: CGPoint(x: left - 6, y: row), anchor: .trailing)
                }
                let path = Path { p in
                    for (index, sample) in samples.enumerated() {
                        let point = CGPoint(x: left + sample.time / duration * (right - left), y: y(sample[keyPath: field]))
                        if index == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.6)
                for event in experiment.replay?.timeline ?? [] {
                    let x = left + event.time / duration * (right - left)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: inset)); p.addLine(to: CGPoint(x: x, y: inset + 6))
                    }, with: .color(assemblyMint))
                }
                if experiment.frame != nil {
                    let x = left + experiment.displayTime / duration * (right - left)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: inset)); p.addLine(to: CGPoint(x: x, y: inset + height))
                    }, with: .color(assemblyInk.opacity(0.65)))
                }
                context.draw(Text(replayTime(duration)).font(.caption2.monospaced()),
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
        guard let url = ExperimentDirectory.run(dialog, fallback: experiment.fileURL) else { return }
        do {
            replacement = Replacement(scene: try AssemblyScene.open(url), title: AssemblyExperiment.fileTitle(url), url: url)
            applyPendingReplacement()
        } catch { experiment.error = error.localizedDescription }
    }

    /// Writes the current scene for external tools without changing which file is open.
    private func exportCopy() {
        experiment.pause()
        let dialog = NSSavePanel()
        dialog.allowedContentTypes = [.json]
        dialog.nameFieldStringValue = "\(experiment.title) export.json"
        guard let url = ExperimentDirectory.run(dialog, fallback: experiment.fileURL) else { return }
        do { try experiment.scene.save(to: url) } catch { experiment.error = error.localizedDescription }
    }

    /// Re-reads the open file, for example after an external script rewrote it.
    private func reloadFromDisk() {
        guard let url = experiment.fileURL else { return }
        experiment.pause()
        do {
            replacement = Replacement(scene: try AssemblyScene.open(url), title: AssemblyExperiment.fileTitle(url), url: url)
            applyPendingReplacement()
        } catch { experiment.error = error.localizedDescription }
    }

    @discardableResult private func save(asNewFile: Bool = false) -> Bool {
        experiment.pause()
        let url: URL
        if let existing = experiment.fileURL, !asNewFile {
            url = existing
        } else {
            let dialog = NSSavePanel()
            dialog.allowedContentTypes = [.json]
            dialog.nameFieldStringValue = "\(experiment.title).impact-assembly.json"
            guard let destination = ExperimentDirectory.run(dialog, fallback: experiment.fileURL) else { return false }
            url = destination
        }
        do {
            try experiment.save(to: url)
            return true
        } catch {
            experiment.error = error.localizedDescription
            return false
        }
    }

    private func startup() async {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--assembly-inspect"), args.indices.contains(index + 2) {
            do {
                let scene = try AssemblyScene.open(URL(fileURLWithPath: args[index + 1]))
                let url = URL(fileURLWithPath: args[index + 1])
                try experiment.load(scene, title: AssemblyExperiment.fileTitle(url), url: url)
                if scene.parts.contains(where: { $0.fracture != nil }) {
                    field = .damage
                    signal = 3
                }
                if args.indices.contains(index + 3), let requested = AssemblyField.allCases.first(where: { $0.rawValue == args[index + 3] || "\($0)" == args[index + 3] }) { field = requested }
                if let milliseconds = Double(args[index + 2]), milliseconds.isFinite, milliseconds >= 0 {
                    experiment.advance(to: milliseconds / 1000)
                }
                NSApplication.shared.activate(ignoringOtherApps: true)
            } catch { experiment.error = error.localizedDescription }
        } else if let index = args.firstIndex(of: "--assembly-smoke"), args.indices.contains(index + 1) {
            await smoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--fracture-smoke"), args.indices.contains(index + 1) {
            await fractureSmoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--study-smoke"), args.indices.contains(index + 1) {
            await studySmoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--scenario-smoke"), args.indices.contains(index + 1) {
            await scenarioSmoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--library-smoke"), args.indices.contains(index + 1) {
            await librarySmoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--workbench-smoke"), args.indices.contains(index + 1) {
            await workbenchSmoke(report: URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--geometry-smoke"), args.indices.contains(index + 1) {
            let checks = GeometrySmoke.run(experiment)
            try? (checks.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: args[index + 1]), atomically: true, encoding: .utf8)
            exit(checks.contains { $0.hasSuffix("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
        } else if let index = args.firstIndex(of: "--geometry-pose"), args.indices.contains(index + 1) {
            GeometrySmoke.pose(args[index + 1], experiment)
            showMesh = args.contains("--show-mesh")
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.title == "Impact Lab" }),
               let screen = window.screen?.visibleFrame {
                window.setFrame(screen.insetBy(dx: 8, dy: 8), display: true)
            }
            if args.contains("--calculate") {
                experiment.calculate()
                for _ in 0..<600 where experiment.solving { try? await Task.sleep(for: .milliseconds(100)) }
                field = .stress
            }
        } else if experiment.selectedPart == nil, let id = experiment.scene.monitor {
            experiment.select(id)
        }
    }

    /// Exercises the integration-branch workflow through the real app model: lab example,
    /// supports and gravity, run-cost warnings, edit a copy, run history and preload.
    private func workbenchSmoke(report: URL) async {
        var checks: [String] = []
        func waitForRun() async {
            for _ in 0..<1200 where experiment.solving { try? await Task.sleep(for: .milliseconds(100)) }
        }
        do {
            let visible = NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" }
            checks.append("native window=\(visible)")
            loadPreset(try LabExample.hanging_springs.scene(), title: LabExample.hanging_springs.rawValue)
            checks.append("lab example loads=\(experiment.canRun && experiment.scene.gravity != nil && experiment.scene.parts[0].support == .fixed)")
            checks.append("timestep explained=\(experiment.simulation.timestep.explanation.hasPrefix("Timestep"))")
            let defaults = UserDefaults.standard
            let saved = RuntimeWarnings.thresholds
            defaults.set(0.0, forKey: RuntimeWarnings.confirmKey)
            requestCalculate()
            checks.append("confirmation asked above threshold=\(confirmLongRun != nil && !experiment.solving)")
            confirmLongRun = nil
            defaults.set(saved.confirm, forKey: RuntimeWarnings.confirmKey)
            requestCalculate()
            await waitForRun()
            let first = experiment.samples
            checks.append("first run completed=\(experiment.finished && experiment.simulation.failure == nil && experiment.history.count == 1)")
            let reaction = experiment.simulation.supportReaction(0)
            checks.append("ceiling reaction finite and upward=\(reaction.y > 0 && reaction.y.isFinite)")
            experiment.editCopy()
            checks.append("edit a copy keeps the result=\(experiment.canEdit && experiment.reference?.samples == first && experiment.reference?.label == "Run 1")")
            let unloaded = experiment.scene.connections[0].id
            experiment.updateConnection(unloaded, action: "Set Preload") { $0.preload = 0.0078453 }
            experiment.updateConnection(unloaded, action: "Move Link Anchor") { $0.secondAnchor = Point(0.25, 1) }
            checks.append("preload and anchor edit=\(experiment.scene.connections[0].preload == 0.0078453 && experiment.scene.connections[0].secondAnchor.x == 0.25 && experiment.canRun)")
            requestCalculate()
            await waitForRun()
            checks.append("second run completed=\(experiment.finished && experiment.history.count == 2 && experiment.reference?.samples == first)")
            experiment.useAsReference(1)
            checks.append("history selects reference=\(experiment.reference?.label == "Run 2")")
            checks.append("rate calibrated=\(RuntimeWarnings.measuredRate != nil)")
            experiment.reset()
            experiment.undo()
            checks.append("undo after reset=\(experiment.scene.connections[0].secondAnchor.x != 0.25 || experiment.scene.connections[0].preload == 0.0078453)")
        } catch { checks.append("error=false \(error.localizedDescription)") }
        try? (checks.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        exit(checks.contains { $0.contains("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
    }

    private func librarySmoke(report: URL) async {
        library = true
        for _ in 0..<20 where !NSApplication.shared.windows.contains(where: { $0.attachedSheet?.isVisible == true }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        var checks = ["native library=\(NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true })"]
        let scene = AssemblyExperimentPreset.bondedComposite.scene(boundary: .supports, resolution: .fine)
        library = false
        loadPreset(scene, title: AssemblyExperimentPreset.bondedComposite.rawValue)
        checks.append("loaded preset=\(experiment.canRun && experiment.selectedPart == scene.monitor && experiment.scene == scene)")
        checks.append("supports and gauges visible in model=\(experiment.scene.parts.count == 4 && experiment.gauges.count == 3)")
        let specimen = scene.parts[1].id
        experiment.updatePart(specimen) { part in
            part.size.x = 0.052
            part.bondedLayer?.third?.material = AssemblyMaterialProfile.stiff.material
        }
        let mesh = experiment.simulation.body(1).mesh
        let edited = experiment.canRun && experiment.scene.parts[1].size.x == 0.052
            && experiment.scene.parts[1].bondedLayer?.third?.material == AssemblyMaterialProfile.stiff.material
            && mesh.interfaceLines.count == 2
        checks.append("edited thickness and material=\(edited)")
        experiment.advance(to: 0.026)
        let measured = experiment.simulation.failure == nil && !experiment.simulation.firstContactTimes.isEmpty
            && experiment.simulation.gaugeReading(0).pressure.isFinite
        checks.append("forces and material gauges=\(measured)")
        do {
            try (checks.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        } catch {
            exit(EXIT_FAILURE)
        }
        exit(checks.contains { $0.contains("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
    }

    private func studySmoke(report: URL) async {
        var checks: [String] = []
        do {
            try experiment.configure(AssemblyScene())
            let part = experiment.add(.block)!
            experiment.updatePart(part) {
                $0.notch = AssemblyPart.Notch()
                $0.refinement = .x5
            }
            checks.append("notch and mesh override=\(experiment.scene.parts[0].notch != nil && experiment.elementCount > 1_000)")
            let gauge = experiment.addGauge(body: part, at: Point(0.002, 0.003))
            checks.append("authored gauge=\(gauge != nil && experiment.gauges.count == 1)")
            let setting = AssemblyScene.bondedWaveExample()
            let sceneURL = report.deletingPathExtension().appendingPathExtension("json")
            try experiment.configure(setting)
            try experiment.scene.save(to: sceneURL)
            try experiment.configure(AssemblyScene.open(sceneURL))
            experiment.select(setting.parts[1].id)
            field = .pressure
            checks.append("saved and reopened bonded setup=\(experiment.scene == setting && experiment.gauges.count == 2)")
            study = true
            for _ in 0..<300 where studySmokeResult == nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            checks.append("native window=\(NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" })")
            checks.append("native study sheet=\(NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true })")
            if let outcome = studySmokeResult {
                let outcome = try outcome.get()
                checks.append("rendered study=\(outcome.cases.count == 3 && outcome.cases.allSatisfy { $0.failure == nil })")
                let url = report.deletingPathExtension().appendingPathExtension("csv")
                try outcome.exportCSV(to: url)
                checks.append("exported CSV=\(FileManager.default.fileExists(atPath: url.path))")
            } else {
                checks.append("rendered study=false")
            }
        } catch {
            checks.append("smoke=false \(error.localizedDescription)")
        }
        do {
            try (checks.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        } catch {
            exit(EXIT_FAILURE)
        }
        exit(checks.contains { $0.contains("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
    }

    private func fractureSmoke(report: URL) async {
        var result: [String] = []
        // Watchdog: the smoke used to wait forever when a step hung. It now always ends, with a failure after 10 minutes.
        Task.detached {
            try? await Task.sleep(for: .seconds(600))
            try? "timed out after 600 s=false\n".write(to: report, atomically: true, encoding: .utf8)
            exit(EXIT_FAILURE)
        }
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
            result.append("finished with dynamically inserted faces=\(experiment.finished && (experiment.simulation.fractureReading(0)?.insertedEdges ?? 0) > 0)")
            result.append("detached pieces=\(experiment.simulation.materialPieces(0).count)")
            // Since the 0.8 contact repair the standard-mesh crack path misses the receiver (docs/PHASE_0_8.md, the
            // "two pieces, miss" outcome); the new-face hit is checked on the extra-fine mesh at the end of this smoke.
            result.append("standard run misses the receiver, as recorded=\(!experiment.simulation.fragmentContacts.contains { $0.parts == SIMD2(0, 4) })")
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
            result.append("refine pinned and remeshed=\(experiment.reference?.samples == base && experiment.scene.resolution == .fine && experiment.solving)")
            while experiment.solving { try await Task.sleep(for: .milliseconds(25)) }
            let matched = SceneTrace.matching(base, experiment.samples)
            result.append("refinement aligned fracture output=\(experiment.finished && matched.count == base.count && matched.contains { $0.referenceSample.crackLength != $0.currentSample.crackLength })")
            NSApplication.shared.activate(ignoringOtherApps: true)
            compare = true
            for _ in 0..<20 where !NSApplication.shared.windows.contains(where: { $0.attachedSheet?.isVisible == true }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            result.append("native window=\(NSApplication.shared.windows.contains { $0.isVisible && $0.title == "Impact Lab" })")
            result.append("comparison sheet=\(NSApplication.shared.windows.contains { $0.attachedSheet?.isVisible == true })")
            compare = false
            var contactScene = try AssemblyScene.open(sceneURL)
            // Pause-on-contact uses a resolution whose production fracture
            // trajectory reaches the receiver on a new face (about 63 ms).
            contactScene.meshResolution = .extraFine
            contactScene.parts[0].fracture?.meshPattern = .aligned
            try experiment.configure(contactScene)
            experiment.select(specimen)
            showPieces = true
            experiment.advance(to: 0.070)
            result.append("paused after observed receiver contact=\(!experiment.running && experiment.simulation.fragmentContacts.contains { $0.parts == SIMD2(0, 4) && $0.onExposedFace && $0.normalImpulse > 0 })")
        } catch {
            result.append("error=\(error.localizedDescription)")
        }
        try? (result.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        exit(result.contains { $0.hasSuffix("=false") || $0.hasPrefix("error=") } ? EXIT_FAILURE : EXIT_SUCCESS)
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

            experiment.advance(to: experiment.scene.duration)
            let finishedTime = experiment.simulation.time
            experiment.seek(to: 0.023)
            experiment.toggle()
            try? await Task.sleep(for: .milliseconds(100))
            experiment.pause()
            let paused = experiment.displayTime
            try? await Task.sleep(for: .milliseconds(100))
            result.append("timer advanced replay without solving=\(paused >= 0.023 && experiment.simulation.time == finishedTime)")
            result.append("paused=\(paused == experiment.displayTime)")
            experiment.stepFrame(by: 1)
            result.append("recorded frame step=\(experiment.displayTime > paused)")
            let trace = experiment.samples
            let success = experiment.finished && experiment.simulation.energies.fracture > 0
                && experiment.simulation.firstContactTimes[SIMD2(0, 1)] != nil
            result.append("enclosure impact and cavity contact=\(success)")
            experiment.pin()

            try experiment.configure(AssemblyScene.open(url))
            experiment.advance(to: experiment.scene.duration)
            result.append("saved trace replay=\(trace == experiment.samples)")
            let mount = experiment.scene.connections.first!.id
            experiment.updateConnection(mount) { $0.stiffness *= 1.6 }
            experiment.advance(to: experiment.scene.duration)
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
            experiment.advance(to: experiment.scene.duration)
            result.append("different three-body build=\(experiment.finished && experiment.simulation.firstContactTimes[SIMD2(0, 1)] != nil && experiment.simulation.kineticEnergy(2) > 0.005)")
        } catch {
            result.append("smoke=false \(error.localizedDescription)")
        }
        try? result.joined(separator: "\n").appending("\n").write(to: report, atomically: true, encoding: .utf8)
        exit(result.contains { $0.contains("=false") } ? EXIT_FAILURE : EXIT_SUCCESS)
    }
}
