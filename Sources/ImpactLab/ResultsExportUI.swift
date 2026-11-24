import AppKit
import ImpactPhysics
import SwiftUI

/// File exports of calculated results. These write what the solver recorded; the PNG is the smooth
/// display of the chosen field and says so in its caption.
@MainActor enum ResultsExportActions {
    static func exportParaView(frames: [AssemblyReplayFrame], suggestedName: String) -> String? {
        guard !frames.isEmpty else { return "Nothing to export yet. Run the experiment first." }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder. A .pvd file and one .vtu file per time step are written; open the .pvd in ParaView."
        guard let base = ExperimentDirectory.run(panel, remember: { $0 }) else { return nil }
        let cleaned = String(suggestedName.map { "/:\\".contains($0) ? "-" : $0 })
        let name = cleaned.isEmpty ? "impactlab-results" : cleaned
        do {
            let url = try ResultsExport.write(frames: frames, to: base.appendingPathComponent(name), name: name)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return "Wrote \(url.lastPathComponent) and its time steps. Open the .pvd in ParaView."
        } catch { return "Export failed: \(error.localizedDescription)" }
    }

    static func savePNG(frame: AssemblyReplayFrame?, field: AssemblyField, limit: Double, title: String) -> String? {
        guard let frame, field != .separation else { return "Pick a frame and a per-element field first." }
        let (unit, scale): (String, Double) = {
            switch field {
            case .stress, .maximum, .minimum, .pressure: limit >= 1e6 ? ("MPa", 1e-6) : ("kPa", 1e-3)
            case .strain, .plastic: ("%", 100)
            case .speed: ("m/s", 1)
            default: ("", 1)
            }
        }()
        guard let data = FieldSnapshot.png(frame: frame, title: "\(title): \(field.rawValue), t = \(String(format: "%.3g", frame.time * 1000)) ms",
                                           unit: unit, unitScale: scale, signed: field.signed, limit: limit,
                                           value: { field.values($0) }) else { return "Could not render the image." }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String("\(title) \(field.rawValue).png".map { "/:".contains($0) ? "-" : $0 })
        panel.allowedContentTypes = [.png]
        guard let url = ExperimentDirectory.run(panel) else { return nil }
        do { try data.write(to: url); return "Saved \(url.lastPathComponent)." }
        catch { return "Save failed: \(error.localizedDescription)" }
    }
}
