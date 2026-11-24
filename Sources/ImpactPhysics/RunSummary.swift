import Foundation

extension AssemblyReplay {
    /// Short plain-text description of a run for pasting into a chat: scene and
    /// material parameters, then the state at the chosen frame and at the end.
    public func textSummary(scene: AssemblyScene, frameIndex: Int) -> String {
        guard let last = frames.last, frames.indices.contains(frameIndex) else { return "No run recorded." }
        func g(_ v: Double) -> String { String(format: "%.4g", v) }
        var lines = ["Impact Lab run summary",
                     "Duration \(g(scene.duration * 1000)) ms, mesh \(scene.resolution.rawValue), \(scene.parts.count) bodies"]
        for part in scene.parts {
            var text = "• \(part.name): \(part.shape.rawValue) \(g(part.size.x * 1000))×\(g(part.size.y * 1000)) mm, "
                + "v (\(g(part.velocity.x)), \(g(part.velocity.y))) m/s, E \(g(part.material.young / 1e9)) GPa, "
                + "ρ \(g(part.material.density)) kg/m³, ν \(g(part.material.poisson))"
            if let name = part.material.provenance?.name { text += " [\(name)]" }
            text += part.plasticity.response == .elastoplastic ? ", plastic (J2)" : ", elastic"
            if let f = part.fracture {
                text += ", fracture strength \(g(f.resolvedStrength(young: part.material.young) / 1e6)) MPa, energy \(g(f.energy)) J/m²"
            }
            lines.append(text)
        }
        func state(_ title: String, _ frame: AssemblyReplayFrame) -> String {
            let percent = last.time > 0 ? 100 * frame.time / last.time : 0
            let e = frame.energies
            var parts = ["\(title): t = \(g(frame.time * 1000)) ms (\(String(format: "%.0f", percent))% of run)",
                         "kinetic \(g(e.kinetic)), elastic \(g(e.elastic)), plastic \(g(e.plastic)), fracture \(g(e.fracture)) J/m",
                         "peak overlap \(g(frame.peakRelativePenetration * 100))%"]
            let plastic = frame.bodies.flatMap(\.plasticStrain).max() ?? 0
            let damage = frame.bodies.flatMap(\.damage).max() ?? 0
            let pieces = frame.bodies.reduce(0) { $0 + $1.pieces.count }
            parts.append("max plastic strain \(g(plastic * 100))%, max damage \(g(damage)), pieces \(pieces)")
            return parts.joined(separator: "; ")
        }
        lines.append(state("Shown frame", frames[frameIndex]))
        if frameIndex != frames.count - 1 { lines.append(state("Final", last)) }
        if !events.isEmpty { lines.append("Events: " + events.map { "\($0.label) \(g($0.time * 1000)) ms" }.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}
