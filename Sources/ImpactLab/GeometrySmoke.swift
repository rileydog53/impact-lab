import Foundation
import ImpactGeometry
import ImpactPhysics
import simd

/// App-model checks and screenshot poses for the geometry editor (`--geometry-smoke REPORT`,
/// `--geometry-pose NAME`). They drive the same AssemblyExperiment methods the buttons and canvas call.
@MainActor enum GeometrySmoke {
    static func run(_ experiment: AssemblyExperiment) -> [String] {
        var checks: [String] = []
        func check(_ name: String, _ ok: Bool) { checks.append("\(name)=\(ok)") }
        experiment.error = nil
        try? experiment.load(AssemblyScene(), title: "Geometry smoke")
        // 1. Every outline primitive inserts, meshes and can run.
        for primitive in OutlinePrimitive.allCases { experiment.insertOutline(primitive) }
        check("primitives inserted", experiment.scene.parts.count == OutlinePrimitive.allCases.count && experiment.error == nil)
        check("primitives meshed", (0..<experiment.simulation.bodyCount).allSatisfy { experiment.simulation.body($0).mesh.elements.count > 10 })
        check("no structural overlap", experiment.simulation.initialIssue == nil)
        // 2. Draw an outline by clicking points; closing it creates a body.
        experiment.beginOutlineDrawing()
        for p in [Point(-0.05, 0.20), Point(0.05, 0.20), Point(0.07, 0.26), Point(-0.03, 0.27)] { experiment.addDraftPoint(p) }
        check("draft closable", experiment.draftIssues.isEmpty)
        experiment.finishOutlineDrawing()
        let drawn = experiment.scene.parts.last!
        check("drawn body created", drawn.shape == .outline && experiment.outlineDraft == nil && abs(drawn.outline!.region.area - 0.0066) < 1e-6)
        // 3. A bow-tie is refused with a reason and creates nothing.
        let before = experiment.scene.parts.count
        experiment.beginOutlineDrawing()
        for p in [Point(0.2, 0.2), Point(0.3, 0.3), Point(0.3, 0.2), Point(0.2, 0.3)] { experiment.addDraftPoint(p) }
        check("bow-tie explained", experiment.draftIssues.contains { $0.contains("crosses") })
        checks.append("  (bow-tie reason: \(experiment.draftIssues.joined(separator: " ")))")
        experiment.finishOutlineDrawing()
        experiment.cancelOutlineDrawing()
        check("bow-tie not added", experiment.scene.parts.count == before)
        // 4. Moving one point keeps every other point where it was in the world.
        let world = drawn.outline!.outer.map { experiment.world($0, in: drawn) }
        var region = drawn.outline!.region
        region.outer[2] = experiment.local(Point(0.09, 0.29), in: drawn)
        experiment.reshape(drawn.id, to: region, action: "Move Outline Point")
        let moved = experiment.scene.parts.first { $0.id == drawn.id }!
        let after = moved.outline!.outer.map { experiment.world($0, in: moved) }
        check("point move keeps others", zip(world, after).enumerated().allSatisfy { i, pair in
            i == 2 ? simd_distance(pair.1, Point(0.09, 0.29)) < 1e-12 : simd_distance(pair.0, pair.1) < 1e-12 })
        // 5. Cut a round hole and a notch out of a plate; join a tab onto it.
        try? experiment.load(AssemblyScene(), title: "Geometry smoke")
        let plate = experiment.insertOutline(.plate)!
        var hole = AssemblyPart("Cutter", shape: .round, center: Point(0.01, 0.0), size: Point(0.012, 0.012))
        hole.center = experiment.scene.parts[0].center + Point(0.01, 0)
        experiment.edit("Add Cutter") { $0.parts.append(hole) }
        experiment.selectParts([plate, hole.id], primary: plate)
        check("pair recognised", experiment.booleanPair?.target.id == plate && experiment.booleanPair?.tool.id == hole.id)
        experiment.cut(target: plate, tool: hole.id)
        var cutPlate = experiment.scene.parts.first { $0.id == plate }!
        check("cut makes a hole", experiment.scene.parts.count == 1 && cutPlate.outline?.holes.count == 1)
        let expected = 0.100 * 0.030 - (48 / 2 * sin(2 * .pi / 48)) * 0.006 * 0.006
        check("cut area exact", abs(cutPlate.outline!.region.area - expected) < 2e-9)
        var notch = AssemblyPart("Notch tool", shape: .outline, size: Point(0.01, 0.01))
        notch = notch.reshaped(to: PolygonRegion(outer: [Point(-0.006, -0.02), Point(0.006, -0.02), Point(0, -0.007)]))
        notch.center += cutPlate.center + Point(-0.025, 0)
        experiment.edit("Add Notch Tool") { $0.parts.append(notch) }
        experiment.cut(target: plate, tool: notch.id)
        cutPlate = experiment.scene.parts.first { $0.id == plate }!
        check("notch cut", cutPlate.outline!.outer.count == 7 && experiment.scene.parts.count == 1)
        var tab = AssemblyPart("Tab", size: Point(0.02, 0.03))
        tab.center = cutPlate.center + Point(0.03, 0.025)
        experiment.edit("Add Tab") { $0.parts.append(tab) }
        experiment.join(target: plate, with: tab.id)
        cutPlate = experiment.scene.parts.first { $0.id == plate }!
        check("join merges", experiment.scene.parts.count == 1 && cutPlate.outline!.region.area > 0.0031)
        // 6. Separate bodies are not joined; a cut through the middle gives two pieces.
        var far = AssemblyPart("Far", size: Point(0.02, 0.02))
        far.center = cutPlate.center + Point(0, 0.2)
        experiment.edit("Add Far") { $0.parts.append(far) }
        experiment.error = nil
        experiment.join(target: plate, with: far.id)
        check("separate bodies refused", experiment.scene.parts.count == 2 && (experiment.error ?? "").contains("do not overlap"))
        experiment.edit("Remove Far") { $0.removePart(far.id) }
        var bar = AssemblyPart("Splitter", size: Point(0.004, 0.08))
        bar.center = cutPlate.center + Point(-0.005, 0)
        experiment.edit("Add Splitter") { $0.parts.append(bar) }
        experiment.cut(target: plate, tool: bar.id)
        check("split gives two bodies", experiment.scene.parts.count == 2 && experiment.scene.parts.allSatisfy { $0.shape == .outline })
        // 7. Convert legacy shapes; fracture is switched off; undo restores the structured body.
        try? experiment.load(AssemblyScene.bendingFractureExample(), title: "Convert")
        let beam = experiment.scene.parts.first { $0.fracture != nil }!
        experiment.convertToOutline(beam.id)
        let converted = experiment.scene.parts.first { $0.id == beam.id }!
        check("convert", converted.shape == .outline && converted.fracture == nil && converted.notch == nil)
        experiment.undo()
        check("undo convert", experiment.scene.parts.first { $0.id == beam.id } == beam)
        // 8. Mesh size changes the mesh; a huge request is refused with a clear reason.
        try? experiment.load(AssemblyScene(), title: "Mesh size")
        let id = experiment.insertOutline(.holedPlate)!
        let coarse = experiment.simulation.body(0).mesh.elements.count
        experiment.setMeshSize(id, 0.004)
        let fine = experiment.simulation.body(0).mesh.elements.count
        check("mesh size refines", fine > 3 * coarse)
        experiment.error = nil
        experiment.setMeshSize(id, 0.00005)
        check("huge mesh refused", experiment.scene.parts[0].outline?.meshSize == 0.004 && (experiment.error ?? "").contains("triangles"))
        check("advisories present", !experiment.scene.advisories(for: experiment.scene.parts[0]).isEmpty)
        // 9. More than the earlier 8 bodies is accepted, with an advisory note.
        for _ in 0..<9 { experiment.insertOutline(.disc) }
        check("ten bodies accepted", experiment.scene.parts.count == 10 && !experiment.scene.sceneAdvisories.isEmpty)
        experiment.error = nil
        return checks
    }

    /// Scenes and states for window screenshots of the editor.
    static func pose(_ name: String, _ experiment: AssemblyExperiment) {
        var scene = AssemblyScene()
        scene.gravity = AssemblyScene.standardGravity
        scene.duration = 0.05
        try? experiment.load(scene, title: "Geometry editor")
        let bracket = experiment.insertOutline(.bracket)!
        experiment.updatePart(bracket) { $0.center = Point(-0.13, -0.02) }
        let plate = experiment.insertOutline(.holedPlate)!
        experiment.updatePart(plate) { $0.center = Point(0.03, -0.034) }
        // A V-notch cut out of the plate's top edge with a drawn triangle.
        var tool = AssemblyPart("Tool", shape: .outline, size: Point(0.01, 0.01))
        tool = tool.reshaped(to: PolygonRegion(outer: [Point(0.012, -0.002), Point(0.028, -0.002), Point(0.02, -0.018)]))
        tool.center += Point(0.03, 0.0)
        experiment.edit("Add Tool") { $0.parts.append(tool) }
        experiment.cut(target: plate, tool: tool.id)
        let wedge = experiment.insertOutline(.wedge)!
        experiment.updatePart(wedge) { $0.center = Point(0.15, -0.045) }
        let hexagon = experiment.insertOutline(.hexagon)!
        experiment.updatePart(hexagon) { $0.center = Point(0.03, 0.05); $0.velocity = Point(0, -2) }
        var bench = AssemblyPart("Bench", center: Point(0, -0.075), size: Point(0.42, 0.02))
        bench.support = .fixed
        AssemblyMaterialProfile.stiff.apply(to: &bench)
        experiment.edit("Add Bench") { $0.parts.append(bench) }
        experiment.error = nil
        switch name {
        case "points":
            experiment.beginPointEditing(bracket)
        case "draw":
            experiment.beginOutlineDrawing()
            for p in [Point(0.10, 0.03), Point(0.17, 0.02), Point(0.19, 0.08), Point(0.13, 0.10)] { experiment.addDraftPoint(p) }
        case "inspector":
            experiment.select(plate)
        default:
            experiment.select(plate)
        }
    }
}
