import Foundation
import ImpactPhysics

/// Raw-field VTK export for the headless runner: `ImpactCheck run SCENE.json --out DIR --vtk`.
///
/// Writes into DIR:
///   fields.pvd               ParaView time index (one DataSet per recorded frame, timestep in seconds)
///   vtk/frame_00000.vtu ...  one VTK XML unstructured grid per recorded frame, every body in one piece
///
/// Only values the solver calculated are written, exactly as recorded in the replay frames, with full
/// round-trip precision. Nothing is smoothed, averaged to nodes or interpolated. Nothing here touches the solver.
///
/// Point data (one value per mesh node, metres and seconds):
///   displacement_m        current position minus the same node's position in the first recorded frame (t = 0).
///                         Nodes split by a crack keep the reference point of the node they came from, so they
///                         are matched to that node's starting position.
///   velocity_m_per_s      nodal velocity
/// Cell data (one value per triangle, as calculated for that element):
///   von_mises_stress_Pa, mean_pressure_Pa (positive in compression), max_principal_stress_Pa,
///   min_principal_stress_Pa   Cauchy stress invariants, plane strain (the out-of-plane stress is included)
///   equivalent_plastic_strain_dimensionless   accumulated J2 plastic strain; 0 for a body with no plasticity
///   damage_dimensionless      cohesive damage progress (0 to 1) of the element's most damaged crack face;
///                             0 for a body with no fracture model
///   body_index                which body the triangle belongs to (scene part order, from 0); a label, not physics
/// Points are written with z = 0. The model is 2-D plane strain; stresses are per unit area as usual.
///
/// Not exported because the solver does not record them per element on this branch: the full stress tensor
/// components (only the invariants above are kept in replay frames) and a plastic-work density.
enum VTKExport {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Returns the written file names relative to `out`, for the manifest.
    static func write(_ replay: AssemblyReplay, to out: URL) throws -> [String] {
        guard let first = replay.frames.first else { throw Failure(message: "VTK export: no recorded frames") }
        let folder = out.appendingPathComponent("vtk")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Starting position of every node, keyed by its reference point (exact bit pattern).
        let start: [[ReferenceKey: Point]] = first.bodies.map { b in
            var map: [ReferenceKey: Point] = [:]
            for (i, r) in b.body.mesh.reference.enumerated() where map[ReferenceKey(r)] == nil {
                map[ReferenceKey(r)] = b.body.position[i]
            }
            return map
        }

        var written: [String] = []
        var collection: [(time: Double, file: String)] = []
        for (index, frame) in replay.frames.enumerated() {
            let name = String(format: "vtk/frame_%05d.vtu", index)
            try vtu(frame, start: start).write(to: out.appendingPathComponent(name), atomically: true, encoding: .utf8)
            written.append(name)
            collection.append((frame.time, name))
        }
        var pvd = "<?xml version=\"1.0\"?>\n"
        pvd += "<VTKFile type=\"Collection\" version=\"0.1\" byte_order=\"LittleEndian\">\n<Collection>\n"
        for item in collection {
            pvd += "<DataSet timestep=\"\(item.time)\" group=\"\" part=\"0\" file=\"\(item.file)\"/>\n"
        }
        pvd += "</Collection>\n</VTKFile>\n"
        try pvd.write(to: out.appendingPathComponent("fields.pvd"), atomically: true, encoding: .utf8)
        return ["fields.pvd"] + written
    }

    private struct ReferenceKey: Hashable {
        let x, y: UInt64
        init(_ p: Point) { x = p.x.bitPattern; y = p.y.bitPattern }
    }

    private static func number(_ v: Double, _ field: String, time: Double) throws -> String {
        guard v.isFinite else { throw Failure(message: "VTK export: non-finite \(field) at t = \(time) s") }
        return "\(v)"
    }

    private static func vtu(_ frame: AssemblyReplayFrame, start: [[ReferenceKey: Point]]) throws -> String {
        let t = frame.time
        var points: [String] = [], displacement: [String] = [], velocity: [String] = []
        var connectivity: [String] = [], offsets: [String] = []
        var vonMises: [String] = [], pressure: [String] = [], maxPrincipal: [String] = [], minPrincipal: [String] = []
        var plastic: [String] = [], damage: [String] = [], bodyIndex: [String] = []
        var cellCount = 0

        for (index, b) in frame.bodies.enumerated() {
            let base = points.count
            let mesh = b.body.mesh
            let elements = mesh.elements.count
            guard index < start.count else { throw Failure(message: "VTK export: body \(index) missing from the first frame") }
            for (i, p) in b.body.position.enumerated() {
                guard let p0 = start[index][ReferenceKey(mesh.reference[i])] else {
                    throw Failure(message: "VTK export: node \(i) of body \(index) has no starting position at t = \(t) s")
                }
                let v = b.body.velocity[i]
                let px = try number(p.x, "position", time: t), py = try number(p.y, "position", time: t)
                let ux = try number(p.x - p0.x, "displacement", time: t), uy = try number(p.y - p0.y, "displacement", time: t)
                let vx = try number(v.x, "velocity", time: t), vy = try number(v.y, "velocity", time: t)
                points.append("\(px) \(py) 0")
                displacement.append("\(ux) \(uy) 0")
                velocity.append("\(vx) \(vy) 0")
            }
            for e in mesh.elements {
                connectivity.append("\(e.a + base) \(e.b + base) \(e.c + base)")
                cellCount += 1
                offsets.append("\(cellCount * 3)")
            }
            guard b.stress.count == elements else {
                throw Failure(message: "VTK export: body \(index) has \(b.stress.count) stress values for \(elements) elements")
            }
            for s in b.stress {
                vonMises.append(try number(s.equivalent, "von Mises stress", time: t))
                pressure.append(try number(s.pressure, "pressure", time: t))
                maxPrincipal.append(try number(s.maximumPrincipal, "max principal stress", time: t))
                minPrincipal.append(try number(s.minimumPrincipal, "min principal stress", time: t))
            }
            // An empty array means the body has no plasticity (or no fracture) model, so the value is zero by
            // construction, the same convention as the gauge readings. Any other length mismatch is an error.
            func column(_ values: [Double], _ field: String) throws -> [String] {
                guard values.isEmpty || values.count == elements else {
                    throw Failure(message: "VTK export: body \(index) has \(values.count) \(field) values for \(elements) elements")
                }
                if values.isEmpty { return Array(repeating: "0", count: elements) }
                return try values.map { try number($0, field, time: t) }
            }
            plastic += try column(b.plasticStrain, "plastic strain")
            damage += try column(b.damage, "damage")
            bodyIndex += Array(repeating: String(index), count: elements)
        }

        func array(_ type: String, _ name: String, components: Int = 1, _ values: [String]) -> String {
            "<DataArray type=\"\(type)\" Name=\"\(name)\" NumberOfComponents=\"\(components)\" format=\"ascii\">\n"
                + values.joined(separator: "\n") + "\n</DataArray>\n"
        }
        var x = "<?xml version=\"1.0\"?>\n"
        x += "<!-- Impact Lab raw fields. SI units in every name. 2-D plane strain, z = 0. Calculated values only, not smoothed. -->\n"
        x += "<VTKFile type=\"UnstructuredGrid\" version=\"0.1\" byte_order=\"LittleEndian\">\n<UnstructuredGrid>\n"
        x += "<FieldData>\n<DataArray type=\"Float64\" Name=\"TimeValue\" NumberOfTuples=\"1\" format=\"ascii\">\(t)</DataArray>\n</FieldData>\n"
        x += "<Piece NumberOfPoints=\"\(points.count)\" NumberOfCells=\"\(cellCount)\">\n"
        x += "<PointData Vectors=\"displacement_m\">\n"
        x += array("Float64", "displacement_m", components: 3, displacement)
        x += array("Float64", "velocity_m_per_s", components: 3, velocity)
        x += "</PointData>\n<CellData Scalars=\"von_mises_stress_Pa\">\n"
        x += array("Float64", "von_mises_stress_Pa", vonMises)
        x += array("Float64", "mean_pressure_Pa", pressure)
        x += array("Float64", "max_principal_stress_Pa", maxPrincipal)
        x += array("Float64", "min_principal_stress_Pa", minPrincipal)
        x += array("Float64", "equivalent_plastic_strain_dimensionless", plastic)
        x += array("Float64", "damage_dimensionless", damage)
        x += array("Int32", "body_index", bodyIndex)
        x += "</CellData>\n<Points>\n"
        x += array("Float64", "position_m", components: 3, points)
        x += "</Points>\n<Cells>\n"
        x += array("Int64", "connectivity", connectivity)
        x += array("Int64", "offsets", offsets)
        x += array("UInt8", "types", Array(repeating: "5", count: cellCount))
        x += "</Cells>\n</Piece>\n</UnstructuredGrid>\n</VTKFile>\n"
        return x
    }
}
