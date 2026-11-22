import Foundation
import ImpactPhysics
import simd

// Independent audit probe: where and when cohesive faces are inserted in the
// compliant-pad notched bend.
func fractureMapProbe(_ orientation: String, refinement: Int, dt: Double, duration: Double, strikerX: Double? = nil, quiet: Bool = false, production: Bool = false) throws {
    var scene = AssemblyScene.bendingFractureExample()
    let mesh = MaterialFractureSettings.MeshPattern.allCases.first { $0.rawValue.lowercased() == orientation }!
    scene.parts[0].fracture?.meshPattern = mesh
    scene.duration = duration
    if let strikerX { scene.parts[1].center.x = strikerX }
    let pad: StrikerPad? = production ? nil : StrikerPad(thickness: 0.004, modulus: 250_000, samples: 64)
    if let pad { scene.parts[1].center.y += pad.thickness }
    var s = try AssemblySimulation(scene, refinement: refinement, stepLimit: dt, notchDepth: production ? 0 : 0.005, strikerPad: pad)
    let strength = scene.parts[0].material.young * scene.parts[0].fracture!.strengthFraction
    var seen = 0
    var printed = 0
    var crossing: Double?
    while s.step() {
        if crossing == nil {
            let q = s.body(0).mesh.reference
            if s.crackFaces(0).contains(where: { $0.damage == 1 && abs((q[$0.first.a] + q[$0.first.b]).x / 2) < 0.004 && (q[$0.first.a] + q[$0.first.b]).y / 2 > 0.0025 }) { crossing = s.time }
        }
        let faces = s.crackFaces(0)
        if faces.count > seen {
            let p = s.body(0).mesh.reference
            for f in faces[seen...] where printed < (quiet ? 0 : 40) {
                let m = (p[f.first.a] + p[f.first.b]) / 2
                let d = p[f.first.b] - p[f.first.a]
                print(String(format: "t=%.3f ms  mid (%.1f, %.1f) mm  dir (%.2f, %.2f)  seed n/s %.2f %.2f", s.time * 1000, m.x * 1000, m.y * 1000,
                             d.x / simd_length(d), d.y / simd_length(d), f.seed.x / strength, f.seed.y / strength))
                printed += 1
            }
            seen = faces.count
        }
    }
    let p = s.body(0).mesh.reference
    var bins: [String: (n: Int, w: Double)] = [:]
    let g = scene.parts[0].fracture!.energy
    for f in s.crackFaces(0) where f.damage > 0 {
        let m = (p[f.first.a] + p[f.first.b]) / 2
        let key = String(format: "x%+04.0f y%+03.0f", (m.x * 1000 / 10).rounded(.down) * 10, (m.y * 1000 / 7).rounded(.down) * 7)
        let w = g * simd_distance(p[f.first.a], p[f.first.b]) * f.damage
        bins[key, default: (0, 0)].n += 1
        bins[key, default: (0, 0)].w += w
    }
    // Notch-connected advance: highest y among fully failed faces whose
    // midpoints lie within 4 mm of the notch axis.
    let ligament = s.crackFaces(0).filter { $0.damage == 1 }.map { (p[$0.first.a] + p[$0.first.b]) / 2 }.filter { abs($0.x) < 0.004 }.map(\.y).max() ?? -1
    print(String(format: "Highest spent face within 4 mm of axis: y = %.1f mm", ligament * 1000))
    var near = 0.0, far = 0.0
    for f in s.crackFaces(0) where f.damage > 0 {
        let m = (p[f.first.a] + p[f.first.b]) / 2
        let w = g * simd_distance(p[f.first.a], p[f.first.b]) * f.damage
        if abs(m.x) < 0.006 { near += w } else { far += w }
    }
    var kinds: [String: Double] = [:]
    for f in s.crackFaces(0) where f.damage > 0 {
        let a = p[f.first.a], b = p[f.first.b], m = (a + b) / 2
        guard abs(m.x) < 0.006 else { continue }
        let d = simd_normalize(b - a)
        let kind = abs(d.y) > 0.95 ? "vertical" : abs(d.x) > 0.95 ? "horizontal" : "inclined"
        kinds[kind + (f.damage == 1 ? " spent" : " partial"), default: 0] += g * simd_distance(a, b) * f.damage
    }
    print(kinds.keys.sorted().map { String(format: "%@ %.4f", $0, kinds[$0]!) }.joined(separator: ", "))
    print(String(format: "Work within 6 mm of notch axis %.5f J/m, elsewhere %.5f J/m", near, far))
    for key in bins.keys.sorted() where !quiet { print(String(format: "%@  faces %3d  work %.4f J/m", key, bins[key]!.n, bins[key]!.w)) }
    print(String(format: "Notch crack past y = 2.5 mm at %.3f ms", (crossing ?? .nan) * 1000))
    print(String(format: "Total work %.5f J/m, faces %d, stopped %@", s.fractureReading(0)!.dissipation, s.crackFaces(0).count, s.failure ?? "no"))
}
