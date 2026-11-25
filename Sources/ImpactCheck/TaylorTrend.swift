import Foundation
import ImpactPhysics
import simd

// Layered target plan, step 8 part 2: Taylor-style trend check, plane strain. Not comparable with round-bar Taylor
// test results (docs/step8-design.md, Part 3; Joseph's decision 2026-11-25: trend only, no 25% band).
//
// A flat slab, 25.4 mm long and 7.62 mm thick (the design's sizes), hits a rigid wall end-on and mushrooms. Speeds stay
// at or below the app's 150 m/s cap. Criteria fixed before the first run (2026-11-25):
//  1. Every run reaches its end (no rejected step, no inverted element).
//  2. For each material and mesh, the final length falls strictly as the speed rises.
// Reported, not gated: the 1D estimate Lf/L0 = exp(−ρ v² / (2Y)) [recall: Taylor 1948; Wilkins and Guinan 1973], with
// Y the initial yield and with the flow stress at 12% strain (the end of the profile's curve), and x4 against x6.

private func taylorScene(profile: String, speed: Double, resolution: String) throws -> AssemblyScene {
    let text = #"""
    { "duration": 0.0003, "meshResolution": "\#(resolution)",
      "parts": [
        { "name": "Slab", "size": [0.0254, 0.00762], "center": [0.0129, 0], "velocity": [-\#(speed), 0],
          "material": { "profile": "\#(profile)" } },
        { "name": "Rigid wall", "size": [0.02, 0.06], "center": [-0.01, 0], "support": "fixed",
          "material": { "profile": "structural-steel-a36", "elasticOnly": true } } ] }
    """#
    return try AssemblyScene.document(Data(text.utf8))
}

func taylorTrendCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Taylor-style trend check, plane strain. Not comparable with round-bar Taylor test results. Numerical verification of a trend only.")
    let cases: [(name: String, id: String, profile: MaterialProfile, speeds: [Double])] = [
        ("Annealed copper", "copper-c11000-annealed", .copperC110, [100, 130, 146]),
        ("6061-T6 aluminium", "aluminum-6061-t6", .aluminum6061, [100, 125, 150]),
    ]
    for item in cases {
        let rho = item.profile.material.density
        let initialYield = item.profile.hardening.points.first!.stress, lateYield = item.profile.hardening.points.last!.stress
        var lengths: [String: [Double]] = [:]
        for resolution in ["x4", "x6"] {
            for speed in item.speeds {
                let scene = try taylorScene(profile: item.id, speed: speed, resolution: resolution)
                var sim = try AssemblySimulation(scene)
                require(sim.initialIssue == nil, sim.initialIssue ?? "")
                let started = Date()
                while sim.time < scene.duration - 1e-15 {
                    require(sim.step(), "\(item.name) \(speed) m/s \(resolution): \(sim.failure ?? "step rejected") at \(sim.time)")
                }
                let xs = sim.body(0).position.map(\.x), ys = sim.body(0).position.map(\.y)
                let length = xs.max()! - xs.min()!, width = ys.max()! - ys.min()!
                let ratio = length / 0.0254
                func estimate(_ y: Double) -> Double { exp(-rho * speed * speed / (2 * y)) }
                lengths[resolution, default: []].append(length)
                print(String(format: "  %@ %.0f m/s, %@: final length %.2f mm (Lf/L0 %.3f), widest %.2f mm (start 7.62); 1D estimate %.3f with initial yield (%+.0f%%), %.3f with 12%%-strain flow stress (%+.0f%%); still moving at %.1f m/s; %.0f s",
                             item.name, speed, resolution, 1000 * length, ratio, 1000 * width,
                             estimate(initialYield), 100 * (ratio / estimate(initialYield) - 1),
                             estimate(lateYield), 100 * (ratio / estimate(lateYield) - 1),
                             sim.body(0).centerVelocity.x, Date().timeIntervalSince(started)))
            }
            let l = lengths[resolution]!
            require(zip(l, l.dropFirst()).allSatisfy { $1 < $0 }, "\(item.name) \(resolution): final length does not fall steadily with speed")
        }
        let gaps = zip(lengths["x4"]!, lengths["x6"]!).map { abs($1 / $0 - 1) }
        print(String(format: "  %@: x6 against x4 final length within %.2f%%", item.name, 100 * gaps.max()!))
    }
    print("Taylor trend check passed.")
}
