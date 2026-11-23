import ImpactPhysics
import SwiftUI

/// The scenario chosen in the library, waiting to run or being measured.
struct ScenarioSession {
    let scenario: LabScenario
    let settings: LabScenario.Settings
    var stage = Stage.first

    enum Stage: Equatable {
        case first, second, finished
        case stopped(String)
    }

    func title(case index: Int) -> String {
        "\(scenario.rawValue) · \(index == 0 ? "A" : "B")"
    }
}

struct ScenarioLibraryView: View {
    let start: (LabScenario, LabScenario.Settings, _ calculate: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection = LabScenario.elasticContrast
    @State private var settings = LabScenario.elasticContrast.defaultSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Scenario library").font(.title2.weight(.semibold))
                Spacer()
                Text("Each scenario runs case A, pins it, then runs case B and compares them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                list.frame(width: 215)
                detail.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Running replaces the current assembly. Both cases stay editable afterwards.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open Case A Only") { start(selection, settings, false) }
                Button("Run A and B") { start(selection, settings, true) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(21)
        .frame(width: 900)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(LabScenario.allCases) { scenario in
                Button {
                    selection = scenario
                    settings = scenario.defaultSettings
                } label: {
                    Label(scenario.rawValue, systemImage: scenario.icon)
                        .font(.callout.weight(selection == scenario ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9).padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(selection == scenario ? assemblyMint.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == scenario ? .isSelected : [])
            }
            Divider().padding(.vertical, 4)
            Label("Brittle versus ductile", systemImage: "lock")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .help(brittleVersusDuctileNote)
            Text("Not yet available. Hover for why.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 9)
        }
        .padding(5)
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selection.rawValue).font(.title3.weight(.semibold))
                Spacer()
                Label(selection.evidence.rawValue, systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(assemblyMint)
            }
            Text(selection.question).font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Text(selection.procedure).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                caseColumn(0)
                caseColumn(1)
            }
            if let label = selection.sharedLabel {
                Picker(label, selection: $settings.shared) {
                    ForEach(selection.sharedOptions.indices, id: \.self) { Text(selection.sharedOptions[$0]).tag($0) }
                }
            }
            HStack {
                Text(selection == .interfaceFailure ? "Striker speed (downward)" : "Striker speed")
                Slider(value: $settings.speed, in: selection.speedRange, step: selection.speedStep)
                Text(String(format: selection.speedStep < 0.1 ? "%.2f m/s" : "%.0f m/s", settings.speed))
                    .font(.callout.monospacedDigit()).frame(width: 70, alignment: .trailing)
            }
            Text("Limitations: " + selection.limitations)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caseColumn(_ index: Int) -> some View {
        let options = index == 0 ? selection.firstOptions : selection.secondOptions
        let binding = index == 0 ? $settings.first : $settings.second
        return VStack(alignment: .leading, spacing: 6) {
            Text(index == 0 ? "Case A" : "Case B").font(.caption.weight(.semibold)).foregroundStyle(assemblyMint)
            if options.count > 1 {
                Picker(index == 0 ? "Case A" : "Case B", selection: binding) {
                    ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
                }.labelsHidden()
            } else {
                Text(options[0]).font(.callout).frame(height: 22, alignment: .leading)
            }
            ExperimentSchematic(scene: selection.scene(settings, case: index),
                                labelsOutside: selection.scene(settings, case: index).parts.count <= 2)
                .frame(height: 150)
                .accessibilityLabel("Case \(index == 0 ? "A" : "B") geometry and striker motion")
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScenarioResultsView: View {
    let session: ScenarioSession
    let first: AssemblyComparison?
    let second: AssemblyComparison
    let compareFields: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var report: LabScenario.Report? {
        guard let first, let a = first.replay, let b = second.replay else { return nil }
        return session.scenario.report(.init(scene: first.scene, replay: a), .init(scene: second.scene, replay: b))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.scenario.rawValue + " · results").font(.title2.weight(.semibold))
            Text(session.scenario.question).font(.callout).foregroundStyle(.secondary)
            if let report {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                    GridRow {
                        Text("Measurement")
                        Text("A · " + caseName(first?.scene, 0))
                        Text("B · " + caseName(second.scene, 1))
                        Text("Prediction")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(assemblyMint)
                    Divider().gridCellColumns(4)
                    ForEach(report.rows) { row in
                        GridRow {
                            Text(row.label)
                            Text(row.first).monospacedDigit()
                            Text(row.second).monospacedDigit()
                            Text(row.prediction ?? "—").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .padding(12)
                .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 9))
                Label(report.finding, systemImage: "lightbulb")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Both cases must finish calculating before this scenario can be measured. If you edited the geometry, the automatic measurement may no longer apply.")
                    .font(.callout).foregroundStyle(assemblyAmber)
            }
            Text("Evidence: " + session.scenario.evidence.rawValue + ". " + session.scenario.limitations)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("To try a variation, press Reset Run, edit case B in the inspector and press Calculate. Case A stays pinned, and these results update.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Spacer()
                Button("Compare Fields") { compareFields() }.disabled(first?.replay == nil || second.replay == nil)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(21)
        .frame(width: 820)
    }

    private func caseName(_ scene: AssemblyScene?, _ index: Int) -> String {
        guard let scene else { return "not run" }
        switch session.scenario {
        case .elasticContrast: return scene.parts.last?.material.provenance?.name ?? "edited"
        case .strainHardening, .elasticVersusYielding:
            let part = scene.parts[0]
            let name = part.material.provenance?.name ?? "edited"
            return part.plasticity.response == .elastoplastic ? name : name + " (elastic)"
        default: return session.scenario.caseLabel(session.settings, case: index)
        }
    }
}
