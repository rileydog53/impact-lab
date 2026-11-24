import CoreGraphics
import Foundation
import ImageIO
import ImpactPhysics
import UniformTypeIdentifiers

// Gate for the smooth-field display layer (display only; no solver code is touched).
// NUMERICAL VERIFICATION of the recovery and colour maps. It does not validate any physical result.

func smoothFieldCheck(snapshot: String?) throws {
    print("Smooth field display check (numerical verification of display code only)")

    // 1. A uniform field is reproduced exactly; recovered corners never leave the solver's own range.
    let pts: [Point] = [Point(0, 0), Point(1, 0), Point(2, 0), Point(0, 1), Point(1, 1), Point(2, 1)]
    let tris: [SIMD3<Int>] = [SIMD3(0, 1, 4), SIMD3(0, 4, 3), SIMD3(1, 2, 5), SIMD3(1, 5, 4)]
    let uniform = ScalarFieldOnTriangles(points: pts, triangles: tris, values: [3, 3, 3, 3]).recoveredCorners()
    require(uniform.allSatisfy { $0 == SIMD3(3, 3, 3) }, "Uniform field not reproduced")
    let mixed = ScalarFieldOnTriangles(points: pts, triangles: tris, values: [-5, 2, 9, 4]).recoveredCorners()
    require(mixed.allSatisfy { $0.min() >= -5 && $0.max() <= 9 }, "Recovery overshoots the element range")
    print("  uniform field exact, recovered corners within [-5, 9] for elements in [-5, 9]: ok")

    // 2. A discontinuity label keeps a jump sharp; without it the jump is averaged across.
    let jump = [1.0, 1, 10, 10]
    let sharp = ScalarFieldOnTriangles(points: pts, triangles: tris, values: jump, groups: [0, 0, 1, 1]).recoveredCorners()
    require(sharp[0] == SIMD3(1, 1, 1) && sharp[3] == SIMD3(10, 10, 10), "Group split smeared a jump")
    let smeared = ScalarFieldOnTriangles(points: pts, triangles: tris, values: jump).recoveredCorners()
    require(smeared[0].y > 1 && smeared[0].y < 10, "Ungrouped nodes should average across")
    print("  discontinuity groups keep a material jump sharp: ok")

    // 3. Colour maps: lightness monotone for the sequential map; diverging is symmetric about 0 in lightness order.
    var previous = -1.0
    for i in 0...100 {
        let l = FieldColormap.sequential.luminance(Double(i) / 100)
        require(l >= previous - 1e-9, "Sequential luminance not monotone at \(i)")
        previous = l
    }
    let center = FieldColormap.diverging.luminance(0.5)
    require(center > FieldColormap.diverging.luminance(0.1) && center > FieldColormap.diverging.luminance(0.9)
            && FieldColormap.diverging.color(0.5).x > 0.95, "Diverging map should be lightest at zero")
    require(FieldColormap.position(of: 5, limit: 10, signed: true) == 0.75
            && FieldColormap.position(of: 5, limit: 10, signed: false) == 0.5
            && FieldColormap.position(of: -50, limit: 10, signed: true) == 0, "Value to color position wrong")
    print("  viridis lightness monotone; RdBu lightest at zero; clamping correct: ok")

    // 4. Real solver output: copper impact. The display adapter must not change any solver value.
    var run = try AssemblyRun(AssemblyScene.metalImpactExample())
    var replay = AssemblyReplay(run)
    while run.step() { replay.record(run) }
    replay.finish(run)
    require(run.finished && run.simulation.failure == nil, "Run failed")
    func peakStress(_ f: AssemblyReplayFrame) -> Double {
        var peak = 0.0
        for b in f.bodies { for st in b.stress { peak = max(peak, st.equivalent) } }
        return peak
    }
    var frame = replay.frames[0]
    for f in replay.frames where peakStress(f) > peakStress(frame) { frame = f }
    var images: [(String, CGImage)] = []
    let limit = peakStress(frame)
    for (label, smooth) in [("per element", false), ("smooth", true)] {
        var cells: [(positions: [Point], triangles: [SIMD3<Int>], corners: [SIMD3<Double>])] = []
        for b in frame.bodies {
            let values: [Double] = b.stress.map { $0.equivalent }
            let before = values
            let field = b.body.scalarField(elementValues: values)
            let corners = smooth ? field.recoveredCorners() : values.map { SIMD3($0, $0, $0) }
            require(values == before, "Adapter mutated solver values")
            var peak = -Double.infinity, low = Double.infinity
            for c in corners { peak = max(peak, c.max()); low = min(low, c.min()) }
            require(peak <= values.max()! + 1e-6 * limit && low >= values.min()! - 1e-6 * limit, "Overshoot on real field")
            cells.append((b.body.position, field.triangles, corners))
        }
        var all: [Point] = []
        for c in cells { all += c.positions }
        let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!, minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!
        let scale = 900.0 / (maxX - minX)
        let width = Int(900), height = Int((maxY - minY) * scale) + 2
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }
        ctx.setFillColor(CGColor(red: 0.085, green: 0.125, blue: 0.17, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for cell in cells {
            let positions = cell.positions, triangles = cell.triangles, corners = cell.corners
            let screen = positions.map { CGPoint(x: ($0.x - minX) * scale, y: (maxY - $0.y) * scale) }
            if let out = FieldRaster.render(screen: screen, triangles: triangles, corners: corners,
                                            limit: limit, signed: false, scale: 1) {
                ctx.draw(out.image, in: CGRect(x: out.rect.minX, y: CGFloat(height) - out.rect.maxY,
                                               width: out.rect.width, height: out.rect.height))
            }
        }
        images.append((label, ctx.makeImage()!))
    }
    print("  copper impact peak-stress frame: adapter leaves solver values untouched, no overshoot: ok")
    if let snapshot {
        let size = (images[0].1.width, images[0].1.height)
        guard let ctx = CGContext(data: nil, width: size.0, height: size.1 * 2 + 4, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }
        ctx.draw(images[1].1, in: CGRect(x: 0, y: size.1 + 4, width: size.0, height: size.1))
        ctx.draw(images[0].1, in: CGRect(x: 0, y: 0, width: size.0, height: size.1))
        let url = URL(fileURLWithPath: snapshot)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        require(CGImageDestinationFinalize(dest), "PNG write failed")
        print("  wrote \(snapshot): top = smooth (interpolated display), bottom = per-element, same data and colour map, von Mises 0 to \(String(format: "%.0f", limit / 1e6)) MPa")
    }
}

/// Export gate: writes a real run to .vtu/.pvd, re-reads the text and checks structure and values.
/// Independent read-back with the real VTK readers is done separately (see docs/smooth-field-visualization.md).
func resultsExportCheck(directory: String) throws {
    print("Results export check (.vtu/.pvd and PNG; numerical verification of export code only)")
    var run = try AssemblyRun(AssemblyScene.metalImpactExample())
    var replay = AssemblyReplay(run)
    while run.step() { replay.record(run) }
    replay.finish(run)
    require(run.finished && run.simulation.failure == nil, "Run failed")
    let dir = URL(fileURLWithPath: directory)
    let pvd = try ResultsExport.write(frames: replay.frames, to: dir, name: "copper-impact", maxFrames: 12)
    let pvdText = try String(contentsOf: pvd, encoding: .utf8)
    let files = pvdText.components(separatedBy: "file=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
    require(files.count >= 2 && files.count <= 12, "Unexpected number of time steps \(files.count)")
    print("  \(pvd.lastPathComponent): \(files.count) time steps")
    for (i, file) in files.enumerated() {
        let doc = try XMLDocument(contentsOf: dir.appendingPathComponent(file), options: [])
        func nodes(_ path: String) -> [XMLNode] { (try? doc.nodes(forXPath: path)) ?? [] }
        func numbers(_ path: String) -> [Double] {
            (nodes(path).first?.stringValue ?? "").split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Double($0) }
        }
        let piece = nodes("//Piece")[0] as! XMLElement
        let np = Int(piece.attribute(forName: "NumberOfPoints")!.stringValue!)!
        let nc = Int(piece.attribute(forName: "NumberOfCells")!.stringValue!)!
        require(numbers("//Points/DataArray").count == 3 * np, "Point count mismatch in \(file)")
        let conn = numbers("//Cells/DataArray[@Name='connectivity']")
        let offsets = numbers("//Cells/DataArray[@Name='offsets']")
        let types = numbers("//Cells/DataArray[@Name='types']")
        require(conn.count == 3 * nc && offsets.count == nc && types.count == nc, "Cell array sizes wrong in \(file)")
        require(types.allSatisfy { $0 == 5 } && offsets.last == Double(3 * nc) && conn.allSatisfy { $0 >= 0 && Int($0) < np },
                "Bad cell types, offsets or connectivity in \(file)")
        for array in nodes("//CellData/DataArray") {
            let name = (array as! XMLElement).attribute(forName: "Name")!.stringValue!
            require(numbers("//CellData/DataArray[@Name='\(name)']").count == nc, "Cell array \(name) wrong length")
        }
        for array in nodes("//PointData/DataArray") {
            let e = array as! XMLElement
            let name = e.attribute(forName: "Name")!.stringValue!
            let comps = Int(e.attribute(forName: "NumberOfComponents")!.stringValue!)!
            require(numbers("//PointData/DataArray[@Name='\(name)']").count == comps * np, "Point array \(name) wrong length")
        }
        if i == files.count - 1 {
            // Exported cell values must equal the solver's values exactly (Swift prints doubles round-trip exact).
            let last = replay.frames.last!
            let expected = last.bodies.flatMap { $0.stress.map(\.equivalent) }
            require(numbers("//CellData/DataArray[@Name='von_mises_stress_Pa']") == expected, "Exported von Mises differs from solver values")
            require(numbers("//FieldData/DataArray").first == last.time, "Exported time differs")
        }
    }
    print("  structure, cell type 5, offsets, array lengths, and exact solver values in last frame: ok")
    let frame = replay.frames.max { a, b in
        a.bodies.reduce(0.0) { max($0, $1.stress.map(\.equivalent).max() ?? 0) }
            < b.bodies.reduce(0.0) { max($0, $1.stress.map(\.equivalent).max() ?? 0) }
    }!
    let png = FieldSnapshot.png(frame: frame, title: "Copper impact, von Mises stress at t = \(String(format: "%.3g", frame.time * 1000)) ms",
                                unit: "MPa", unitScale: 1e-6, signed: false) { $0.stress.map(\.equivalent) }
    require(png != nil && png!.count > 5000 && png!.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]), "PNG snapshot failed")
    try png!.write(to: dir.appendingPathComponent("copper-impact-von-mises.png"))
    print("  PNG snapshot with color bar and caption written: ok")
}
