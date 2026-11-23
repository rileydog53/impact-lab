import Foundation
import ImpactPhysics
import simd

func experimentLibraryCheck() async throws {
    for preset in AssemblyExperimentPreset.allCases {
        for boundary in AssemblyExperimentPreset.Boundary.allCases {
            let scene = preset.scene(boundary: boundary)
            let study: AssemblyStudy
            do {
                study = try await AssemblyStudy.run(scene, variation: .current)
            } catch {
                require(false, "\(preset.rawValue) / \(boundary.rawValue) invalid: \(error.localizedDescription)")
                return
            }
            let result = study.cases[0]
            let peakEnergyError = result.samples.map { abs($0.residual) }.max()! / result.samples[0].energy.total
            let contacts = zip(study.pairs, result.contacts).compactMap { pair, contact in
                contact.firstTime.map { "\(pair.name) \(String(format: "%.2f", 1000 * $0)) ms" }
            }
            print(String(format: "%@ / %@: %d triangles, %.2f s, %.4f%% sampled energy error, %.3f%% overlap. %@",
                         preset.rawValue, boundary.rawValue, result.triangles, result.wallTime,
                         peakEnergyError * 100, result.peakPenetration * 100, contacts.joined(separator: ", ")))
            require(result.failure == nil && result.samples.last!.time >= scene.duration, result.failure ?? "Preset completes")
            require(peakEnergyError < 0.005 && result.peakPenetration < 0.06, "Preset energy or overlap outside preview bounds")
            require(result.contacts[0].firstTime != nil && result.contacts[0].impulse > 0, "Striker loads first specimen")
            require(result.samples.contains { $0.gauges.contains { abs($0.pressure) > 1 } }, "Gauges register a stress wave")
            if boundary == .supports {
                let last = scene.parts.count - 1
                require(zip(study.pairs, result.contacts).contains { pair, contact in
                    pair.bodies.x == last - 2 && pair.bodies.y >= last - 1 && contact.impulse > 0
                }, "Preset loads a deformable support")
            }
            if preset == .separatedPlates || preset == .angledPanels {
                let second = zip(study.pairs, result.contacts).first { $0.0.bodies == SIMD2(1, 2) }!.1
                require((second.firstTime ?? 0) > result.contacts[0].firstTime! && second.impulse > 0,
                        "First plate transfers load to the receiver after initial contact")
            }
        }
    }

    var composite = AssemblyExperimentPreset.bondedComposite.scene()
    var simulation = try AssemblySimulation(composite)
    let coupon = simulation.body(1)
    let layer = composite.parts[1].bondedLayer!
    let positions = [layer.interfaceFraction, layer.third!.interfaceFraction]
    require(coupon.mesh.interfaceLines.count == 2, "The coupon carries both material interfaces")
    for (fraction, line) in zip(positions, coupon.mesh.interfaceLines) {
        let x = coupon.mesh.reference[line[0]].x
        require(abs(x - (fraction - 0.5) * composite.parts[1].size.x) < 1e-12, "Interface lies on the entered coordinate")
        for node in line {
            let sides = coupon.mesh.elements.compactMap { triangle -> Double? in
                let indices = [triangle.a, triangle.b, triangle.c]
                guard indices.contains(node) else { return nil }
                return indices.reduce(0) { $0 + coupon.mesh.reference[$1].x } / 3
            }
            require(sides.contains { $0 < x } && sides.contains { $0 > x },
                    "Elements on both sides use each shared interface node")
        }
    }
    let initialMomentum = simulation.momentum
    while simulation.step() {}
    require(simulation.failure == nil && simd_distance(simulation.momentum, initialMomentum) < 1e-10,
            "The freely moving composite conserves total momentum")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("composite.json")
    try composite.save(to: file)
    let reopened = try AssemblyScene.open(file)
    require(reopened == composite, "Save/reopen preserves a third material and proportional gauges")
    composite.parts[1].size.x *= 0.75
    let resized = try AssemblySimulation(composite)
    require(abs(resized.gaugePosition(0).y - 0.5 * 0.76 * composite.parts[1].size.x) < 1e-12,
            "Proportional gauge follows a thickness edit")

    var plates = AssemblyExperimentPreset.separatedPlates.scene()
    plates.duration = 0.020
    let refinement = try await AssemblyStudy.run(plates, variation: .mesh(body: nil, levels: [.fine, .extraFine]))
    let impulses = refinement.cases.map { $0.contacts[0].impulse }
    require(refinement.cases.allSatisfy { $0.failure == nil } && impulses[0] > 0 && impulses[1] > 0, "Refined plate cases produce measurable impulses")
    let relativeChange = abs(impulses[1] / impulses[0] - 1)
    print(String(format: "Separated plates 0–20 ms striker impulse: ×2 %.6f, ×3 %.6f N·s/m, change %.2f%% at %.3f µs",
                 impulses[0], impulses[1], relativeChange * 100, refinement.cases[0].dt * 1e6))
    require(relativeChange < 0.05, "Early striker impulse is within 5% over the checked refinements")

    var panels = AssemblyExperimentPreset.angledPanels.scene()
    let baseline = try await AssemblyStudy.run(panels, variation: .current)
    let frontAngle = panels.parts[1].angle
    panels.parts[2].angle = 4
    let adjusted = try await AssemblyStudy.run(panels, variation: .current)
    let pair = adjusted.pairs.firstIndex { $0.bodies == SIMD2(1, 2) }!
    let before = baseline.cases[0].contacts[pair].firstTime ?? 0
    let after = adjusted.cases[0].contacts[pair].firstTime ?? 0
    require(adjusted.cases[0].failure == nil && panels.parts[1].angle == frontAngle
            && min(before, after) > 0 && abs(after - before) > 0.0002,
            "Changing the rear panel's angle independently shifts contact timing")
    print(String(format: "Rear panel angle 9°→4° shifts inter-panel contact %.2f→%.2f ms", before * 1000, after * 1000))
    print("Experiment library checks passed")
}
