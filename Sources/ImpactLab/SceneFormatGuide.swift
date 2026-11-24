import AppKit
import ImpactPhysics
import SwiftUI

/// A short in-app reference for writing scene files. The full schema is in
/// docs/SCENE_FORMAT.md and docs/scene-format.schema.json.
struct SceneFormatGuide: View {
    @Environment(\.dismiss) private var dismiss

    static let example = """
    {
      "duration": 0.001,
      "meshResolution": "fine",
      "parts": [
        { "name": "Plate", "size": [0.11, 0.025],
          "material": "aluminum-6061-t6" },
        { "name": "Ball", "shape": "round", "size": [0.03, 0.03],
          "center": [0.072, 0], "velocity": [-40, 0],
          "material": { "profile": "structural-steel-a36", "elasticOnly": true } }
      ],
      "monitor": "Plate"
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scene JSON format").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Write a scene in any editor or script, then use Open or Import Scene JSON. Everything you leave out takes the workshop default. Save and Export write the complete form, which opens again unchanged.")
                    Text("Units: metres, seconds, m/s, pascals, kg/m³ and degrees. Positions are body centres; x points right and y points up.")
                        .foregroundStyle(.secondary)
                    Text(Self.example)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 8))
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                        row("Scene", "parts, connections, gauges, duration (0.0001–2 s), gravity (m/s², downward), meshResolution (standard, fine, extraFine, x4–x7), monitor, relativeTo, groups")
                        row("Body", "name, shape (block, enclosure, round), size [w, h] 0.025–0.30 m, center, angle, velocity [vx, vy] ±150 m/s, wall, refinement, material, plasticity, fracture, notch, bondedLayer, support (fixed, clampLeft, clampRight, clampBottom, clampTop)")
                        row("Layers", "bondedLayer { interfaceFraction, material, plasticity, fracture, bond, third { … } }: each layer can yield and crack, and bond is a weaker cohesive interface with the layer before it")
                        row("Material", "a profile id, { \"profile\": id, \"elasticOnly\": true }, or { young, density, poisson }")
                        row("Profiles", MaterialProfile.references.map(\.id).joined(separator: ", "))
                        row("Connections", "first, second (body names), kind (spring, breakable), stiffness, criticalExtension, span, anchors, preload (m, springs only)")
                        row("Gauges", "name, body, location [x, y] in metres or body fractions with usesBodyFractions")
                    }
                    .font(.callout)
                    Text("Not available in the solver, and reported as an error if present: pinned points and partial constraints, applied loads other than gravity, friction, initial spin, temperature or rate effects, and a user-set timestep. Unknown or misspelled settings are also reported rather than ignored.")
                        .foregroundStyle(assemblyAmber)
                    Text("Full reference and examples: docs/SCENE_FORMAT.md, docs/scene-examples and docs/lab-examples in the Impact Lab project folder.")
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Copy Example") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.example, forType: .string)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 640, height: 600)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title).font(.callout.weight(.semibold))
            Text(detail).fixedSize(horizontal: false, vertical: true)
        }
    }
}
