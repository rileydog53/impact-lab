import Foundation
import ImpactGeometry
import ImpactPhysics

// Verification gates for the general-geometry mesher prototype.
//
//   swift run -c release MeshCheck [--svg DIR]
//
// Everything here is numerical verification: the mesher does what it claims,
// and its meshes satisfy the existing FEM element's own consistency tests.
// None of it is physical validation against experiments.
// Nothing in the app or production solver uses this code.

setvbuf(stdout, nil, _IONBF, 0)
var failures: [String] = []
@MainActor func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message); print("  FAIL: \(message)") }
}

let arguments = CommandLine.arguments
let svgDirectory = arguments.firstIndex(of: "--svg").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }

// MARK: - Cases

struct Case {
    let name: String
    let region: PolygonRegion
    let h: Double
    /// False when the shape has corners sharper than 60°, where Ruppert's angle bound need not hold.
    let cleanAngles: Bool
    let svg: Bool
}

func circle(_ diameter: Double, at center: GeoPoint, sides: Int = 32) -> [GeoPoint] {
    Array(Shapes.ellipse(width: diameter, height: diameter, sides: sides, center: center).reversed())
}

let mm = 0.001
let cases: [Case] = [
    Case(name: "Block 60 × 30 mm", region: PolygonRegion(outer: Shapes.rectangle(width: 60 * mm, height: 30 * mm)),
         h: 3 * mm, cleanAngles: true, svg: false),
    Case(name: "Enclosure 100 × 80 mm, 12 mm wall (one hole)", region: Shapes.enclosure(width: 100 * mm, height: 80 * mm, wall: 12 * mm),
         h: 4 * mm, cleanAngles: true, svg: false),
    Case(name: "Legacy V-notch as ordinary polygon (60 × 36 mm)", region: Shapes.notchedBlock(width: 60 * mm, height: 36 * mm),
         h: 3 * mm, cleanAngles: false, svg: true),
    Case(name: "Round body, 64-sided, 50 mm", region: PolygonRegion(outer: Shapes.ellipse(width: 50 * mm, height: 50 * mm, sides: 64)),
         h: 3 * mm, cleanAngles: true, svg: false),
    Case(name: "L-bracket 80 × 60 mm, 15 mm legs", region: PolygonRegion(outer: [
        GeoPoint(0, 0), GeoPoint(80 * mm, 0), GeoPoint(80 * mm, 15 * mm), GeoPoint(15 * mm, 15 * mm),
        GeoPoint(15 * mm, 60 * mm), GeoPoint(0, 60 * mm)]), h: 3 * mm, cleanAngles: true, svg: false),
    Case(name: "Plate 120 × 60 mm with a round hole and a slot", region: PolygonRegion(
        outer: Shapes.rectangle(width: 120 * mm, height: 60 * mm),
        holes: [circle(20 * mm, at: GeoPoint(-30 * mm, 0)), Shapes.rectangle(width: 30 * mm, height: 6 * mm, center: GeoPoint(25 * mm, 10 * mm))]),
         h: 4 * mm, cleanAngles: true, svg: true),
    Case(name: "Sharp slit, 8° tip (crack-like notch)", region: PolygonRegion(outer: [
        GeoPoint(-30 * mm, -15 * mm), GeoPoint(-2.1 * mm, -15 * mm), GeoPoint(0, 0), GeoPoint(2.1 * mm, -15 * mm),
        GeoPoint(30 * mm, -15 * mm), GeoPoint(30 * mm, 15 * mm), GeoPoint(-30 * mm, 15 * mm)]),
         h: 3 * mm, cleanAngles: false, svg: true),
    Case(name: "Wedge shim with a 10° tip", region: PolygonRegion(outer: [
        GeoPoint(0, 0), GeoPoint(60 * mm, 0), GeoPoint(60 * mm, 60 * mm * tan(10 * Double.pi / 180))]),
         h: 2 * mm, cleanAngles: false, svg: true),
    Case(name: "Thin strip 5 × 1 mm (below the old 25 mm minimum)", region: PolygonRegion(outer: Shapes.rectangle(width: 5 * mm, height: 1 * mm)),
         h: 0.25 * mm, cleanAngles: true, svg: false),
    Case(name: "Bench 1000 × 20 mm (above the old 300 mm maximum)", region: PolygonRegion(outer: Shapes.rectangle(width: 1, height: 20 * mm)),
         h: 5 * mm, cleanAngles: true, svg: false),
    Case(name: "Layered block 80 × 30 mm, two bonded interfaces", region: Shapes.layeredBlock(width: 80 * mm, height: 30 * mm, interfaces: [0.35, 0.7]),
         h: 3 * mm, cleanAngles: true, svg: true),
]

func fingerprint(_ mesh: TriangleMesh) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    func mix(_ value: UInt64) { hash = (hash ^ value) &* 0x100000001b3 }
    for p in mesh.points { mix(p.x.bitPattern); mix(p.y.bitPattern) }
    for t in mesh.triangles { mix(UInt64(t.x)); mix(UInt64(t.y)); mix(UInt64(t.z)) }
    return String(format: "%016llx", hash)
}

func writeSVG(_ mesh: TriangleMesh, title: String, to path: String) {
    let lo = mesh.points.reduce(mesh.points[0]) { pointwiseMin($0, $1) }
    let hi = mesh.points.reduce(mesh.points[0]) { pointwiseMax($0, $1) }
    let span = max(hi.x - lo.x, hi.y - lo.y)
    let s = 560 / span, pad = 20.0
    let width = (hi.x - lo.x) * s + 2 * pad, height = (hi.y - lo.y) * s + 2 * pad + 40
    func xy(_ p: GeoPoint) -> String { String(format: "%.2f,%.2f", (p.x - lo.x) * s + pad, (hi.y - p.y) * s + pad + 40) }
    var body = ""
    for t in mesh.triangles {
        body += "<polygon points=\"\(xy(mesh.points[t.x])) \(xy(mesh.points[t.y])) \(xy(mesh.points[t.z]))\"/>\n"
    }
    var lines = ""
    for e in mesh.boundaryEdges { lines += "<line class=\"b\" x1=\"\(xy(mesh.points[e.x]).split(separator: ",")[0])\" y1=\"\(xy(mesh.points[e.x]).split(separator: ",")[1])\" x2=\"\(xy(mesh.points[e.y]).split(separator: ",")[0])\" y2=\"\(xy(mesh.points[e.y]).split(separator: ",")[1])\"/>\n" }
    for e in mesh.interfaceEdges { lines += "<line class=\"i\" x1=\"\(xy(mesh.points[e.x]).split(separator: ",")[0])\" y1=\"\(xy(mesh.points[e.x]).split(separator: ",")[1])\" x2=\"\(xy(mesh.points[e.y]).split(separator: ",")[0])\" y2=\"\(xy(mesh.points[e.y]).split(separator: ",")[1])\"/>\n" }
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(width))" height="\(Int(height))" viewBox="0 0 \(Int(width)) \(Int(height))">
    <style>polygon{fill:#eef2f7;stroke:#5b6b80;stroke-width:0.6} .b{stroke:#111;stroke-width:1.6} .i{stroke:#c2410c;stroke-width:1.6} text{font:13px sans-serif;fill:#111}</style>
    <rect width="100%" height="100%" fill="#fff"/>
    <text x="\(pad)" y="18">\(title)</text>
    <text x="\(pad)" y="34">Generated mesh (mesher output, not a simulation result). \(mesh.triangles.count) triangles.</text>
    \(body)\(lines)</svg>
    """
    try? svg.write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: - 1. Mesh generation and quality

print("1. Mesh generation and quality (numerical verification of the mesher)")
var generated: [String: TriangleMesh] = [:]
for c in cases {
    let start = ProcessInfo.processInfo.systemUptime
    let result = Mesher.generate(MeshRequest(region: c.region, targetEdgeLength: c.h))
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    guard let mesh = result.mesh else { check(false, "\(c.name): \(result.issues.joined(separator: " "))"); continue }
    generated[c.name] = mesh
    let q = MeshQuality(mesh)
    let region = c.region
    print(String(format: "- %@: %d nodes, %d triangles in %.3f s. Angles %.1f°–%.1f° (%d below 20°), shape q min %.2f mean %.3f, edges %.2f–%.2f mm, smallest altitude %.2f mm. Fingerprint %@",
                 c.name, q.nodes, q.triangles, elapsed, q.minimumAngle, q.maximumAngle, q.trianglesBelow20, q.minimumShape, q.meanShape,
                 q.shortestEdge / mm, q.longestEdge / mm, q.smallestAltitude / mm, fingerprint(mesh)))
    for note in result.notes { print("    mesher note: \(note)") }
    for note in ResolutionAdvice(region: region, targetEdgeLength: c.h).notes where note.level == .caution || note.text.hasPrefix("Re-entrant") {
        print("    advice (\(note.level.rawValue)): \(note.text)")
    }
    check(q.invertedTriangles == 0, "\(c.name): \(q.invertedTriangles) inverted triangles")
    check(q.topologyErrors == 0, "\(c.name): \(q.topologyErrors) topology errors")
    check(q.eulerCharacteristic == 1 - region.holes.count, "\(c.name): Euler characteristic \(q.eulerCharacteristic), expected \(1 - region.holes.count)")
    check(abs(q.area / region.area - 1) < 1e-12, "\(c.name): mesh area differs from polygon area by \(q.area / region.area - 1)")
    check(abs(q.boundaryLength / region.perimeter - 1) < 1e-12, "\(c.name): boundary length differs from perimeter by \(q.boundaryLength / region.perimeter - 1)")
    check(q.longestEdge <= c.h * (1 + 1e-4), "\(c.name): longest edge \(q.longestEdge) exceeds target \(c.h)")
    if c.cleanAngles { check(q.minimumAngle >= 25 - 1e-9, "\(c.name): minimum angle \(q.minimumAngle)° below 25°") }
    check(!result.notes.contains { $0.contains("budget") || $0.contains("non-positive") || $0.contains("classified differently") },
          "\(c.name): \(result.notes)")
    if c.name.hasPrefix("Layered") {
        let lineX: [Double] = [0.35, 0.7].map { ($0 - 0.5) * 80 * mm }
        let onLines = mesh.interfaceEdges.allSatisfy { e -> Bool in
            let a: Double = mesh.points[e.x].x, b: Double = mesh.points[e.y].x
            return lineX.contains { x in abs(a - x) < 1e-12 && abs(b - x) < 1e-12 }
        }
        let length = mesh.interfaceEdges.reduce(0) { $0 + simdLengthPublic(mesh.points[$1.y] - mesh.points[$1.x]) }
        check(onLines && abs(length - 60 * mm) < 1e-12, "Layered block: interface edges off the lines or total length \(length)")
    }
    if let svgDirectory, c.svg {
        let file = c.name.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").prefix(4).joined(separator: "-")
        writeSVG(mesh, title: c.name, to: (svgDirectory as NSString).appendingPathComponent(file + ".svg"))
    }
}

func simdLengthPublic(_ v: GeoPoint) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

// MARK: - 2. Invalid input is explained, not crashed on

print("\n2. Invalid regions are rejected with reasons")
let invalid: [(String, PolygonRegion)] = [
    ("bow-tie", PolygonRegion(outer: [GeoPoint(0, 0), GeoPoint(0.02, 0.02), GeoPoint(0.02, 0), GeoPoint(0, 0.02)])),
    ("hole outside", PolygonRegion(outer: Shapes.rectangle(width: 0.02, height: 0.02), holes: [Shapes.rectangle(width: 0.005, height: 0.005, center: GeoPoint(0.05, 0))])),
    ("hole crossing the edge", PolygonRegion(outer: Shapes.rectangle(width: 0.02, height: 0.02), holes: [Shapes.rectangle(width: 0.01, height: 0.01, center: GeoPoint(0.01, 0))])),
    ("two points", PolygonRegion(outer: [GeoPoint(0, 0), GeoPoint(1, 0)])),
    ("repeated point", PolygonRegion(outer: [GeoPoint(0, 0), GeoPoint(0.01, 0), GeoPoint(0.01, 0), GeoPoint(0, 0.01)])),
    ("interior line leaving the body", PolygonRegion(outer: Shapes.rectangle(width: 0.02, height: 0.02), interiorLines: [[GeoPoint(0, 0), GeoPoint(0.03, 0)]])),
]
for (name, region) in invalid {
    let result = Mesher.generate(MeshRequest(region: region, targetEdgeLength: 0.002))
    print("- \(name): \(result.issues.first ?? "(accepted)")")
    check(result.mesh == nil && !result.issues.isEmpty, "\(name) was not rejected")
}

// MARK: - 3. Determinism, scale invariance and refinement

print("\n3. Determinism, scale invariance and refinement")
let plate = cases[5]
let again = Mesher.generate(MeshRequest(region: plate.region, targetEdgeLength: plate.h)).mesh
check(again == generated[plate.name], "Plate mesh is not reproducible within a process")
let scaled = PolygonRegion(outer: plate.region.outer.map { $0 * 1e-3 }, holes: plate.region.holes.map { $0.map { $0 * 1e-3 } })
let small = Mesher.generate(MeshRequest(region: scaled, targetEdgeLength: plate.h * 1e-3)).mesh
check(small?.triangles == generated[plate.name]?.triangles, "Mesh topology changes when the plate is scaled by 1/1000")
print("- Plate regenerated: identical \(again == generated[plate.name]); scaled to micrometres: identical topology \(small?.triangles == generated[plate.name]?.triangles)")
var counts: [Int] = []
for h in [6.0, 3.0, 1.5, 0.75] {
    let start = ProcessInfo.processInfo.systemUptime
    let result = Mesher.generate(MeshRequest(region: plate.region, targetEdgeLength: h * mm))
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let q = result.mesh.map(MeshQuality.init) ?? MeshQuality()
    counts.append(q.triangles)
    print(String(format: "- h = %.2f mm: %d triangles in %.3f s, minimum angle %.1f°, longest edge %.2f mm, smallest altitude %.3f mm",
                 h, q.triangles, elapsed, q.minimumAngle, q.longestEdge / mm, q.smallestAltitude / mm))
    check(q.minimumAngle >= 25 - 1e-9 && q.longestEdge <= h * mm * (1 + 1e-4), "Plate at h = \(h) mm misses the quality or size target")
}
for (coarse, fine) in zip(counts, counts.dropFirst()) {
    let ratio = Double(fine) / Double(coarse)
    check((3.0...5.0).contains(ratio), "Halving h changed the triangle count by \(ratio)×, expected about 4×")
}

// MARK: - 4. Plug-in to the existing FEM element

print("\n4. Generated meshes in the existing FEM (unchanged ImpactPhysics code)")
func femMesh(_ m: TriangleMesh) -> Mesh {
    Mesh(reference: m.points, triangles: m.triangles.map { ($0.x, $0.y, $0.z) }, boundary: m.boundaryEdges.map { Edge($0.x, $0.y) })
}

// Patch test, the same construction as ImpactCheck's patchCheck: rigid motions give zero
// nodal force, and a uniform deformation gives forces only from boundary tractions.
func patchResiduals(_ mesh: Mesh) -> (translation: Double, rotation: Double, affine: Double, scale: Double)? {
    let simulation = Simulation(mesh: mesh, material: Material(young: 1e6, density: 1000, poisson: 0.25))
    func maxForce(_ positions: [Point]) -> Double? { simulation.internalForces(at: positions)?.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }.max() }
    guard let translation = maxForce(mesh.reference.map { $0 + Point(1, -0.3) }) else { return nil }
    let theta = 0.73
    guard let rotation = maxForce(mesh.reference.map { Point(cos(theta) * $0.x - sin(theta) * $0.y, sin(theta) * $0.x + cos(theta) * $0.y) })
    else { return nil }
    let x = 1.03, y = 0.97, shear = 0.08
    let mu = 400_000.0, lambda = 400_000.0
    let correction = (lambda * log(x * y) - mu) / (x * y)
    let p0 = Point(mu * x + correction * y, -correction * shear)
    let p1 = Point(mu * shear, mu * y + correction * x)
    var expected = Array(repeating: Point.zero, count: mesh.reference.count)
    for edge in mesh.boundary {
        let tangent = mesh.reference[edge.b] - mesh.reference[edge.a]
        let traction = p0 * tangent.y - p1 * tangent.x
        expected[edge.a] -= 0.5 * traction
        expected[edge.b] -= 0.5 * traction
    }
    guard let actual = simulation.internalForces(at: mesh.reference.map { Point(x * $0.x + shear * $0.y, y * $0.y) }) else { return nil }
    let mismatch = zip(actual, expected).map { simdLengthPublic($0 - $1) }.max()!
    let scale = expected.map(simdLengthPublic).max()!
    return (translation, rotation, mismatch, scale)
}

for name in [cases[1].name, cases[2].name, cases[5].name, cases[6].name] {
    guard let mesh = generated[name] else { continue }
    let fem = femMesh(mesh)
    guard let r = patchResiduals(fem) else { check(false, "\(name): patch configuration rejected as inverted"); continue }
    let density = 1000.0
    let body = Simulation(mesh: fem, material: Material(young: 1e6, density: density, poisson: 0.25)).body
    let massError = body.totalMass / (density * MeshQuality(mesh).area) - 1
    print(String(format: "- %@: residual / boundary force: translation %.1e, rotation %.1e, affine patch %.1e; mass error %.1e",
                 name, r.translation / r.scale, r.rotation / r.scale, r.affine / r.scale, massError))
    check(max(r.translation, r.rotation, r.affine) / r.scale < 1e-9, "\(name): patch test residual too large")
    check(abs(massError) < 1e-12, "\(name): lumped mass does not equal density × area")
}

// Bar striking the rigid wall: a 1D elastic bar (ν = 0) stays in contact for 2L/c and rebounds at its impact speed.
struct WallRun { let contact, rebound, energy, momentum, dt: Double; let steps: Int; let triangles: Int }
func wallImpact(_ mesh: Mesh, material: Material, duration: Double) -> WallRun? {
    var simulation = Simulation(mesh: mesh, material: material, speed: 0.4)
    let initial = simulation.diagnostics.momentum
    var peakEnergy = 0.0
    var steps = 0
    while simulation.time < duration {
        guard simulation.step() else { print("    step rejected: \(simulation.failure ?? "?")"); return nil }
        peakEnergy = max(peakEnergy, abs(simulation.diagnostics.relativeEnergyError))
        steps += 1
    }
    let change = simulation.diagnostics.momentum - initial
    let mismatch = simdLengthPublic(change + Point(simulation.wallImpulse, 0)) / abs(initial.x)
    let first = simulation.gap / 0.4
    return WallRun(contact: (simulation.lastWallContactTime ?? .nan) - first, rebound: -simulation.body.centerVelocity.x / 0.4,
                   energy: peakEnergy, momentum: mismatch, dt: simulation.dt, steps: steps, triangles: mesh.elements.count)
}

let barMaterial = Material(young: 1e6, density: 1000, poisson: 0)
let predicted = 2 * 0.5 / barMaterial.waveSpeed
let barRegion = PolygonRegion(outer: [GeoPoint(-0.5, -0.025), GeoPoint(0, -0.025), GeoPoint(0, 0.025), GeoPoint(-0.5, 0.025)])
if let barMesh = Mesher.generate(MeshRequest(region: barRegion, targetEdgeLength: 0.01)).mesh,
   let structured = wallImpact(.bar(columns: 50, rows: 5, width: 0.5, height: 0.05), material: barMaterial, duration: 2 * predicted),
   let unstructured = wallImpact(femMesh(barMesh), material: barMaterial, duration: 2 * predicted) {
    print(String(format: "- 500 × 50 mm elastic bar (E = 1 MPa, ν = 0) hits the wall at 0.4 m/s. 1D prediction: contact %.2f ms, rebound 1.000.", predicted * 1000))
    for (label, run) in [("structured legacy mesh", structured), ("generated mesh", unstructured)] {
        print(String(format: "    %@ (%d triangles, dt %.1f µs, %d steps): contact %.2f ms (%+.1f%%), rebound %.3f, peak energy error %.1e, momentum + wall impulse mismatch %.1e",
                     label, run.triangles, run.dt * 1e6, run.steps, run.contact * 1000, (run.contact / predicted - 1) * 100,
                     run.rebound, run.energy, run.momentum))
        check(abs(run.contact / predicted - 1) < 0.05, "\(label): contact time off the 1D prediction by more than 5%")
        check(run.energy < 0.02 && run.momentum < 1e-6, "\(label): energy or momentum balance outside the gate")
    }
}

if let plateMesh = generated[cases[5].name],
   let run = wallImpact(femMesh(plateMesh), material: Material(young: 1e6, density: 1000, poisson: 0.25), duration: 0.02) {
    print(String(format: "- Plate with holes hits the wall at 0.4 m/s for 20 ms: %d steps, dt %.1f µs, peak energy error %.1e, momentum mismatch %.1e",
                 run.steps, run.dt * 1e6, run.energy, run.momentum))
    check(run.energy < 0.02 && run.momentum < 1e-6, "Plate with holes: energy or momentum balance outside the gate")
}

print(failures.isEmpty ? "\nPASS: all mesh prototype checks" : "\nFAILED: \(failures.count) checks")
exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
