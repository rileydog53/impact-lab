import ImpactPhysics
import simd
import SwiftUI

/// "What was simulated", beside the replay (Joseph, 2026-11-26, items 25 and 33): which body is which colour,
/// which real material each body and each glued layer is, whether it could crack or peel, how fast it started,
/// and the run settings. Everything here is read from the experiment's own settings, not from the result.
struct AssemblyRunSummary: View {
    let experiment: AssemblyExperiment
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(experiment.scene.parts.enumerated()), id: \.element.id) { index, part in
                    bodyRow(index, part)
                }
                Text(runLine)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("How to read the picture: each body's outline is drawn in its colour above, and pieces that break off keep that colour. Inside a body, dashed lines are glue lines. Red lines are cracks: solid once fully broken, dashed while weakening.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Text(experiment.canEdit ? "What will be simulated" : "What was simulated")
                .font(.callout.weight(.semibold))
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var runLine: String {
        let scene = experiment.scene
        var parts = ["Mesh \(scene.resolution.label)", "run length \(AssemblyEditor.milliseconds(scene.duration))"]
        parts.append((scene.gravity ?? 0) > 0 ? "gravity \(String(format: "%.3g", scene.gravity!)) m/s²" : "no gravity")
        parts.append(scene.bulkViscosity == nil ? "no shock smoothing"
                     : "shock smoothing \(String(format: "%.3g", scene.bulkViscosity!.linear)) / \(String(format: "%.3g", scene.bulkViscosity!.quadratic))")
        parts.append("\(scene.connections.count) link\(scene.connections.count == 1 ? "" : "s") between bodies")
        return parts.joined(separator: " · ") + ". No friction, no heating, flat (2-D)."
    }

    private func bodyRow(_ index: Int, _ part: AssemblyPart) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2).stroke(assemblyColor(index), lineWidth: 2)
                .frame(width: 12, height: 12).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(part.name).font(.caption.weight(.semibold)).foregroundStyle(assemblyColor(index))
                ForEach(Array(layers(part).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Text(motion(part)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func layers(_ part: AssemblyPart) -> [String] {
        let cracking = part.fracture != nil
        guard let layer = part.bondedLayer else {
            return ["\(name(part.material, plastic: part.plasticity.response == .elastoplastic)) · \(crackWords(part))"]
        }
        var lines = ["Left layer: \(name(part.material, plastic: part.plasticity.response == .elastoplastic)) · \(cracking ? "can crack" : "cannot crack")"]
        lines.append("Glue line at \(Int((layer.interfaceFraction * 100).rounded()))% of the width: \(glueWords(layer.bond, cracking: cracking, young: min(part.material.young, layer.material.young)))")
        lines.append("\(layer.third == nil ? "Right" : "Middle") layer: \(name(layer.material, plastic: layer.plasticity?.response == .elastoplastic)) · \(cracking && layer.fracture != nil ? "can crack" : "cannot crack")")
        if let third = layer.third {
            lines.append("Glue line at \(Int((third.interfaceFraction * 100).rounded()))% of the width: \(glueWords(third.bond, cracking: cracking, young: min(layer.material.young, third.material.young)))")
            lines.append("Right layer: \(name(third.material, plastic: third.plasticity?.response == .elastoplastic)) · \(cracking && third.fracture != nil ? "can crack" : "cannot crack")")
        }
        return lines
    }

    private func name(_ material: ImpactPhysics.Material, plastic: Bool) -> String {
        let label: String
        if let provenance = material.provenance {
            let library = MaterialProfile.libraryProfile(for: provenance)
            label = provenance.isCustom
                ? "your version of \(library?.plainName ?? provenance.name)"
                : (library?.plainName ?? provenance.name) + " (Library, sourced)"
        } else {
            label = "numbers set in this experiment (stiffness \((material.young / 1e9).formatted(.number.precision(.significantDigits(1...4)))) GPa)"
        }
        return label + (plastic ? ", bends for good" : ", springs back")
    }

    private func crackWords(_ part: AssemblyPart) -> String {
        if part.fractureUnavailableReason != nil { return "cannot crack (\(part.fractureStatus.tag))" }
        return part.fracture == nil ? "cracking off" : "can crack"
    }

    private func glueWords(_ bond: MaterialFractureSettings?, cracking: Bool, young: Double) -> String {
        guard cracking, let bond else { return "holds forever" }
        return String(format: "can let go at %.3g MPa, peel resistance %.3g J/m²", bond.resolvedStrength(young: young) / 1e6, bond.energy)
    }

    private func motion(_ part: AssemblyPart) -> String {
        if part.support == .fixed { return "Fixed support: never moves" }
        let speed = simd_length(part.velocity)
        let held = part.support == nil ? "" : " · one edge clamped"
        return (speed > 0 ? String(format: "Starts at %.3g m/s", speed) : "Starts at rest") + held
    }
}
