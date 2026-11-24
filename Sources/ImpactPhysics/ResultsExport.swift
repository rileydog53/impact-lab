import Foundation
import simd

// Solver-neutral results export to the VTK XML formats that ParaView opens.
//
// Format facts (checked against Kitware's vtkCellType.h: VTK_TRIANGLE = 5; ASCII DataArrays are
// allowed in .vtu; a .pvd "Collection" file lists one .vtu per time step, see the check gate which
// reads the files back with the real VTK readers). No library is linked: this writes plain text.
// The exporter knows nothing about FEM: any method (FEM, MPM background cells, ...) that can fill
// `ExportGrid` can use it. Values are written exactly as calculated; nothing is smoothed here except
// the clearly named "*_nodal_average" point arrays.

public struct ExportGrid: Sendable {
    public var time: Double
    /// Metres, 2D; written with z = 0.
    public var points: [Point]
    /// Triangle point indices (VTK cell type 5).
    public var triangles: [SIMD3<Int>]
    public var pointScalars: [(name: String, values: [Double])] = []
    public var pointVectors: [(name: String, values: [Point])] = []
    public var cellScalars: [(name: String, values: [Double])] = []

    public init(time: Double, points: [Point], triangles: [SIMD3<Int>]) {
        self.time = time
        self.points = points
        self.triangles = triangles
    }
}

public enum ResultsExport {
    public static func vtu(_ grid: ExportGrid) -> String {
        func num(_ v: Double) -> String { v.isFinite ? "\(v)" : "0" }
        func array(_ type: String, _ name: String, components: Int = 1, _ body: String) -> String {
            "<DataArray type=\"\(type)\" Name=\"\(name)\" NumberOfComponents=\"\(components)\" format=\"ascii\">\n\(body)\n</DataArray>\n"
        }
        var x = "<?xml version=\"1.0\"?>\n"
        x += "<VTKFile type=\"UnstructuredGrid\" version=\"0.1\" byte_order=\"LittleEndian\">\n<UnstructuredGrid>\n"
        x += "<FieldData>\n<DataArray type=\"Float64\" Name=\"TimeValue\" NumberOfTuples=\"1\" format=\"ascii\">\(num(grid.time))</DataArray>\n</FieldData>\n"
        x += "<Piece NumberOfPoints=\"\(grid.points.count)\" NumberOfCells=\"\(grid.triangles.count)\">\n<PointData>\n"
        for s in grid.pointScalars { x += array("Float64", s.name, s.values.map(num).joined(separator: " ")) }
        for v in grid.pointVectors {
            x += array("Float64", v.name, components: 3, v.values.map { "\(num($0.x)) \(num($0.y)) 0" }.joined(separator: "\n"))
        }
        x += "</PointData>\n<CellData>\n"
        for s in grid.cellScalars { x += array("Float64", s.name, s.values.map(num).joined(separator: " ")) }
        x += "</CellData>\n<Points>\n"
        x += array("Float64", "Points", components: 3, grid.points.map { "\(num($0.x)) \(num($0.y)) 0" }.joined(separator: "\n"))
        x += "</Points>\n<Cells>\n"
        x += array("Int64", "connectivity", grid.triangles.map { "\($0.x) \($0.y) \($0.z)" }.joined(separator: "\n"))
        x += array("Int64", "offsets", grid.triangles.indices.map { "\(($0 + 1) * 3)" }.joined(separator: " "))
        x += array("UInt8", "types", Array(repeating: "5", count: grid.triangles.count).joined(separator: " "))
        x += "</Cells>\n</Piece>\n</UnstructuredGrid>\n</VTKFile>\n"
        return x
    }

    /// ParaView time-series collection. `files` pairs a time with a file name relative to the .pvd.
    public static func pvd(_ files: [(time: Double, file: String)]) -> String {
        var x = "<?xml version=\"1.0\"?>\n<VTKFile type=\"Collection\" version=\"0.1\" byte_order=\"LittleEndian\">\n<Collection>\n"
        for f in files { x += "<DataSet timestep=\"\(f.time)\" group=\"\" part=\"0\" file=\"\(f.file)\"/>\n" }
        return x + "</Collection>\n</VTKFile>\n"
    }

    /// One merged grid per frame: every body in one piece, with a `body` cell array to tell them apart.
    /// Cell arrays are the raw per-element solver values (Pa, dimensionless, m/s). Point arrays: displacement
    /// and velocity (as calculated) plus area-weighted nodal averages of the same fields for smooth contours.
    public static func grid(_ frame: AssemblyReplayFrame) -> ExportGrid {
        var g = ExportGrid(time: frame.time, points: [], triangles: [])
        var body: [Double] = [], vm: [Double] = [], pmax: [Double] = [], pmin: [Double] = [], pressure: [Double] = []
        var strain: [Double] = [], plastic: [Double] = [], damage: [Double] = [], speed: [Double] = []
        var nodalVM: [Double] = [], nodalPlastic: [Double] = [], nodalStrain: [Double] = []
        var displacement: [Point] = [], velocity: [Point] = []
        for (index, b) in frame.bodies.enumerated() {
            let offset = g.points.count
            let mesh = b.body.mesh
            g.points += b.body.position
            for t in mesh.elements { g.triangles.append(SIMD3(t.a + offset, t.b + offset, t.c + offset)) }
            body += Array(repeating: Double(index), count: mesh.elements.count)
            // Elastic bodies record no plastic or damage field; export zeros so every array has one value per cell.
            func fit(_ values: [Double]) -> [Double] { values.count == mesh.elements.count ? values : Array(repeating: 0, count: mesh.elements.count) }
            let eq = b.stress.map(\.equivalent)
            vm += eq; pmax += b.stress.map(\.maximumPrincipal); pmin += b.stress.map(\.minimumPrincipal)
            pressure += b.stress.map(\.pressure); strain += fit(b.strain); plastic += fit(b.plasticStrain); damage += fit(b.damage)
            let v = b.body.velocity
            speed += mesh.elements.map { simd_length_squared((v[$0.a] + v[$0.b] + v[$0.c]) / 3).squareRoot() }
            func nodal(_ values: [Double]) -> [Double] {
                guard values.count == mesh.elements.count, !values.isEmpty else { return Array(repeating: 0, count: b.body.position.count) }
                let field = ScalarFieldOnTriangles(points: b.body.position, triangles: mesh.elements.map { SIMD3($0.a, $0.b, $0.c) }, values: values)
                return field.nodalAverage()
            }
            nodalVM += nodal(eq); nodalPlastic += nodal(fit(b.plasticStrain)); nodalStrain += nodal(fit(b.strain))
            displacement += zip(b.body.position, mesh.reference).map { $0 - $1 }
            velocity += v
        }
        g.cellScalars = [("body", body), ("von_mises_stress_Pa", vm), ("max_principal_stress_Pa", pmax),
                         ("min_principal_stress_Pa", pmin), ("mean_pressure_Pa", pressure),
                         ("axial_strain", strain), ("plastic_strain", plastic),
                         ("interface_damage", damage), ("element_speed_m_per_s", speed)]
        g.pointScalars = [("von_mises_stress_Pa_nodal_average", nodalVM),
                          ("plastic_strain_nodal_average", nodalPlastic),
                          ("axial_strain_nodal_average", nodalStrain)]
        g.pointVectors = [("displacement_m", displacement), ("velocity_m_per_s", velocity)]
        return g
    }

    /// Writes `name.pvd` plus `name_0000.vtu`, ... into `directory`. At most `maxFrames` frames, evenly spread
    /// and always including the first and last. Returns the .pvd URL.
    @discardableResult
    public static func write(frames: [AssemblyReplayFrame], to directory: URL, name: String, maxFrames: Int = 60) throws -> URL {
        precondition(!frames.isEmpty)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let count = min(frames.count, max(2, maxFrames))
        let picks = count == 1 ? [0] : (0..<count).map { Int((Double($0) * Double(frames.count - 1) / Double(count - 1)).rounded()) }
        var list: [(time: Double, file: String)] = []
        for (i, f) in picks.enumerated() {
            let file = String(format: "%@_%04d.vtu", name, i)
            try vtu(grid(frames[f])).write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
            list.append((frames[f].time, file))
        }
        let url = directory.appendingPathComponent(name + ".pvd")
        try pvd(list).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

public extension ScalarFieldOnTriangles {
    /// Area-weighted average at each point over every triangle touching it (all groups together).
    func nodalAverage() -> [Double] {
        var sum = [Double](repeating: 0, count: points.count), weight = sum
        for (i, t) in triangles.enumerated() {
            let u = points[t.y] - points[t.x], v = points[t.z] - points[t.x]
            let area = abs(u.x * v.y - u.y * v.x) / 2
            for n in [t.x, t.y, t.z] { sum[n] += area * values[i]; weight[n] += area }
        }
        return zip(sum, weight).map { $1 > 0 ? $0 / $1 : 0 }
    }
}
