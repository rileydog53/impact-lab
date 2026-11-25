import Foundation
import ImpactGeometry
import ImpactPhysics
import simd

// Layered target plan step 6: does the 3-node triangle lock volumetrically
// once a metal is fully plastic?
//
// Test: plane-strain flat-punch indentation of an elastic, perfectly plastic
// (J2) block. The rigid-plastic limit pressure is the Prandtl/Hill value
// p = (2 + π)k with k = Y/√3 for von Mises, about 2.97·Y. A locked mesh
// overshoots it and keeps climbing; a mesh that does not lock levels off near
// it and approaches it on refinement.
//
// Controls:
//  - uniform plane-strain compression between smooth plates. Every triangle has
//    the same strain, so even a locking mesh must give 2k = 1.155·Y. If this
//    fails, the plasticity code is wrong, not the mesh.
//  - the "crossed" mesh (four triangles per square), which Nagtegaal, Parks
//    and Rice (1974) showed does not lock. It shows the test can tell the
//    difference.
//
// This check changes no solver code. It drives nodes directly in its own small
// explicit loop (lumped mass, no damping, slow smoothly ramped loading), but uses the production constitutive law (J2Model) and, for the
// aligned pattern, the production structured-mesh diagonal rule, which it
// confirms against Mesh.bar. The element force assembly is confirmed against
// Simulation.internalForces on an elastic state.

private struct PlainMesh {
    var nodes: [Point]
    var triangles: [SIMD3<Int>]
    let label: String
}

private struct Element {
    let a, b, c: Int
    let g0, g1, g2: Point
    let area: Double
}

private func elements(of mesh: PlainMesh) -> [Element] {
    mesh.triangles.map { t in
        var (a, b, c) = (t.x, t.y, t.z)
        var u = mesh.nodes[b] - mesh.nodes[a], v = mesh.nodes[c] - mesh.nodes[a]
        if u.x * v.y - u.y * v.x < 0 { swap(&b, &c); swap(&u, &v) }
        let twice = u.x * v.y - u.y * v.x
        precondition(twice > 0, "degenerate triangle")
        let g1 = Point(v.y, -v.x) / twice, g2 = Point(-u.y, u.x) / twice
        return Element(a: a, b: b, c: c, g0: -g1 - g2, g1: g1, g2: g2, area: twice / 2)
    }
}

// Production aligned pattern (Mesh.rectangle, staggerDiagonals == false).
private func alignedMesh(columns: Int, rows: Int, width: Double, height: Double, uniform: Bool = false) -> PlainMesh {
    var nodes: [Point] = [], tris: [SIMD3<Int>] = []
    func node(_ i: Int, _ j: Int) -> Int { j * (columns + 1) + i }
    for j in 0...rows { for i in 0...columns {
        nodes.append(Point(width * (Double(i) / Double(columns) - 0.5), height * Double(j) / Double(rows)))
    } }
    for j in 0..<rows { for i in 0..<columns {
        let a = node(i, j), b = node(i + 1, j), c = node(i + 1, j + 1), d = node(i, j + 1)
        if uniform || (i + j).isMultiple(of: 2) { tris += [SIMD3(a, b, c), SIMD3(a, c, d)] }
        else { tris += [SIMD3(a, b, d), SIMD3(b, c, d)] }
    } }
    return PlainMesh(nodes: nodes, triangles: tris, label: uniform ? "uniform" : "aligned")
}

// Four triangles per square around a centre node (Nagtegaal et al. 1974).
private func crossedMesh(columns: Int, rows: Int, width: Double, height: Double) -> PlainMesh {
    var mesh = alignedMesh(columns: columns, rows: rows, width: width, height: height)
    mesh.triangles = []
    func node(_ i: Int, _ j: Int) -> Int { j * (columns + 1) + i }
    for j in 0..<rows { for i in 0..<columns {
        let a = node(i, j), b = node(i + 1, j), c = node(i + 1, j + 1), d = node(i, j + 1)
        let m = mesh.nodes.count
        mesh.nodes.append((mesh.nodes[a] + mesh.nodes[c]) / 2)
        mesh.triangles += [SIMD3(a, b, m), SIMD3(b, c, m), SIMD3(c, d, m), SIMD3(d, a, m)]
    } }
    return PlainMesh(nodes: mesh.nodes, triangles: mesh.triangles, label: "crossed")
}

// Unstructured quality Delaunay mesh from the outline mesher (PR 6), with
// vertices at the punch edges so the punch boundary is exact.
private func delaunayMesh(edge: Double, width: Double, height: Double, punch: Double) -> PlainMesh {
    let w = width / 2
    let region = PolygonRegion(outer: [GeoPoint(-w, 0), GeoPoint(w, 0), GeoPoint(w, height),
                                       GeoPoint(punch / 2, height), GeoPoint(-punch / 2, height), GeoPoint(-w, height)])
    let result = Mesher.generate(MeshRequest(region: region, targetEdgeLength: edge, minimumAngle: 25))
    guard let mesh = result.mesh else {
        require(false, "Delaunay mesher failed: \(result.issues)")
        fatalError()
    }
    return PlainMesh(nodes: mesh.points, triangles: mesh.triangles, label: "delaunay")
}

/// A·P·∇N for one element, accumulated as the internal (resisting) force ∂W/∂x.
@inline(__always) private func accumulate(_ e: Element, _ px: Point, _ py: Point, into f: inout [Point]) {
    f[e.a] += e.area * (px * e.g0.x + py * e.g0.y)
    f[e.b] += e.area * (px * e.g1.x + py * e.g1.y)
    f[e.c] += e.area * (px * e.g2.x + py * e.g2.y)
}

@inline(__always) private func deformation(_ e: Element, _ x: [Point]) -> (Point, Point) {
    let u = x[e.b] - x[e.a], v = x[e.c] - x[e.a]
    return (u * e.g1.x + v * e.g2.x, u * e.g1.y + v * e.g2.y)
}

/// Cross-check this file's assembly and aligned pattern against the production code.
private func assemblyCrossCheck() {
    let material = Material(young: 1e6, density: 1000, poisson: 0.25)
    let production = Mesh.bar(columns: 8, rows: 4)
    let mine = alignedMesh(columns: 8, rows: 4, width: 1, height: 0.1)
    let shifted = mine.nodes.map { $0 - Point(0.5, 0.05) }
    require(zip(shifted, production.reference).allSatisfy { simd_length($0 - $1) < 1e-12 }
            && production.elements.count == mine.triangles.count
            && zip(production.elements, elements(of: mine)).allSatisfy { Set([$0.a, $0.b, $0.c]) == Set([$1.a, $1.b, $1.c]) },
            "Aligned locking mesh does not reproduce the production diagonal pattern")
    let simulation = Simulation(mesh: production, material: material)
    let positions = production.reference.enumerated().map { i, p in
        Point(1.04 * p.x + 0.07 * p.y + 0.002 * sin(Double(i)), 0.96 * p.y - 0.03 * p.x + 0.001 * cos(Double(3 * i)))
    }
    guard let reference = simulation.internalForces(at: positions) else {
        require(false, "Production force evaluation rejected the cross-check state"); return
    }
    let mu = shearModulus(material), lambda = lameLambda(material)
    var forces = Array(repeating: Point.zero, count: positions.count)
    for e in elements(of: PlainMesh(nodes: production.reference, triangles: production.elements.map { SIMD3($0.a, $0.b, $0.c) }, label: "")) {
        let (fx, fy) = deformation(e, positions)
        let j = cross2D(fx, fy), p = (lambda * log(j) - mu) / j
        accumulate(e, mu * fx + p * Point(fy.y, -fy.x), mu * fy + p * Point(-fx.y, fx.x), into: &forces)
    }
    let scale = reference.map(simd_length).max()!
    let same = zip(forces, reference).map { simd_length($0 - $1) }.max()! / scale
    let opposite = zip(forces, reference).map { simd_length($0 + $1) }.max()! / scale
    print(String(format: "Assembly cross-check against Simulation.internalForces: relative difference %.1e (aligned pattern identical to Mesh.bar)",
                 min(same, opposite)))
    require(min(same, opposite) < 1e-10, "Locking-test force assembly disagrees with the production solver")
}

private func shearModulus(_ m: Material) -> Double { m.young / (2 * (1 + m.poisson)) }
private func lameLambda(_ m: Material) -> Double { m.young * m.poisson / ((1 + m.poisson) * (1 - 2 * m.poisson)) }

private func cross2D(_ a: Point, _ b: Point) -> Double { a.x * b.y - a.y * b.x }

private struct LoadPoint { let depth, pressure: Double }

private struct DrivenResult {
    let curve: [LoadPoint]
    let kineticOverPlastic: Double
    let checkerboard: Double
    let steps: Int
    let seconds: Double
    let failure: String?
}

/// Explicit quasi-static driving. `driven` nodes follow the prescribed vertical
/// motion; `fixedX`/`fixedY` are held at their reference coordinates.
private func drive(_ mesh: PlainMesh, material: Material, model: J2Model, totalDepth: Double,
                   driven: [Int], drivenFixedX: Bool, fixedX: Set<Int>, fixedY: Set<Int>,
                   transits: Double, samples: Int, loadWidth: (([Point]) -> Double),
                   checkerboardBox: ((Point) -> Bool)?) -> DrivenResult {
    let start = ProcessInfo.processInfo.systemUptime
    let elems = elements(of: mesh)
    let n = mesh.nodes.count
    var mass = Array(repeating: 0.0, count: n)
    var minAltitude = Double.infinity
    for e in elems {
        let m = material.density * e.area / 3
        mass[e.a] += m; mass[e.b] += m; mass[e.c] += m
        let p = [mesh.nodes[e.a], mesh.nodes[e.b], mesh.nodes[e.c]]
        let longest = max(simd_length(p[1] - p[0]), simd_length(p[2] - p[1]), simd_length(p[0] - p[2]))
        minAltitude = min(minAltitude, 2 * e.area / longest)
    }
    let ys = mesh.nodes.map(\.y)
    let height = ys.max()! - ys.min()!
    let wave = material.waveSpeed
    let dt = 0.5 * minAltitude / wave
    let duration = transits * height / wave
    let steps = Int((duration / dt).rounded(.up))
    // No artificial damping: mass-proportional damping resists the bulk
    // flow itself and biased the compression control by several percent.
    // Slow, smoothly ramped loading keeps the run quasi-static instead.
    let ramp = 0.1 * duration
    // Smooth velocity ramp, then constant, reaching totalDepth at `duration`.
    let speed = totalDepth / (duration - ramp / 2)
    func depth(_ t: Double) -> Double {
        t < ramp ? speed * (t * t / (2 * ramp)) : speed * (t - ramp / 2)
    }
    var isDriven = Array(repeating: false, count: n), holdX = isDriven, holdY = isDriven
    for i in driven { isDriven[i] = true }
    for i in fixedX { holdX[i] = true }
    for i in fixedY { holdY[i] = true }
    var x = mesh.nodes
    var v = Array(repeating: Point.zero, count: n)
    var history = Array(repeating: J2History(), count: elems.count)
    var next = history
    var forces = Array(repeating: Point.zero, count: n)
    var plastic = 0.0
    var curve: [LoadPoint] = []
    let sampleEvery = max(1, steps / samples)
    var failure: String?

    @inline(__always) func evaluate() -> Bool {
        for i in 0..<n { forces[i] = .zero }
        plastic = 0
        for (k, e) in elems.enumerated() {
            let (fx, fy) = deformation(e, x)
            guard let r = model.update(x: fx, y: fy, from: history[k]) else { return false }
            next[k] = r.history
            plastic += e.area * r.dissipation
            accumulate(e, r.piolaX, r.piolaY, into: &forces)
        }
        return true
    }

    func pressures() -> [Double] {
        elems.enumerated().map { k, e in
            let (fx, fy) = deformation(e, x)
            guard let r = model.update(x: fx, y: fy, from: history[k]) else { return .nan }
            let j = cross2D(fx, fy)
            let sxx = (r.piolaX.x * fx.x + r.piolaY.x * fy.x) / j
            let syy = (r.piolaX.y * fx.y + r.piolaY.y * fy.y) / j
            return -(sxx + syy + r.cauchyZZ) / 3
        }
    }

    var time = 0.0
    var step = 0
    guard evaluate() else { return DrivenResult(curve: [], kineticOverPlastic: .nan, checkerboard: .nan, steps: 0, seconds: 0, failure: "initial state rejected") }
    while step < steps {
        // Central difference: v(n+½) from f(n), then x(n+1).
        for i in 0..<n where !(isDriven[i] && drivenFixedX) {
            // Driven nodes that may slide (smooth plate) integrate x only.
            v[i] -= dt * forces[i] / mass[i]
            if holdX[i] { v[i].x = 0 }
            if holdY[i] || isDriven[i] { v[i].y = 0 }
            x[i] += dt * v[i]
        }
        time += dt
        step += 1
        let d = depth(time)
        let rate = time < ramp ? speed * time / ramp : speed
        for i in driven {
            x[i].y = mesh.nodes[i].y - d
            v[i].y = -rate
            if drivenFixedX { x[i].x = mesh.nodes[i].x; v[i].x = 0 }
        }
        guard evaluate() else { failure = String(format: "element inverted at depth %.4g", d); break }
        swap(&history, &next)
        if step % sampleEvery == 0 || step == steps {
            let load = -driven.reduce(0.0) { $0 + forces[$1].y }
            curve.append(LoadPoint(depth: d, pressure: load / loadWidth(x)))
        }
    }
    var kinetic = 0.0
    for i in 0..<n where !isDriven[i] { kinetic += 0.5 * mass[i] * simd_length_squared(v[i]) }
    var checker = Double.nan
    if let box = checkerboardBox, failure == nil {
        // RMS pressure jump across interior edges between elements in the box,
        // relative to the RMS pressure there. A checkerboard makes this large.
        let p = pressures()
        let inside = elems.indices.filter { box((x[elems[$0].a] + x[elems[$0].b] + x[elems[$0].c]) / 3) }
        var owner: [SIMD2<Int>: Int] = [:]
        var jump = 0.0, edges = 0
        for k in inside {
            let e = elems[k]
            for (s, t) in [(e.a, e.b), (e.b, e.c), (e.c, e.a)] {
                let key = SIMD2(min(s, t), max(s, t))
                if let other = owner[key] { jump += (p[k] - p[other]) * (p[k] - p[other]); edges += 1 }
                else { owner[key] = k }
            }
        }
        let level = (inside.map { p[$0] * p[$0] }.reduce(0, +) / Double(inside.count)).squareRoot()
        checker = (jump / Double(max(edges, 1))).squareRoot() / level
    }
    return DrivenResult(curve: curve, kineticOverPlastic: kinetic / max(plastic, 1e-300),
                        checkerboard: checker,
                        steps: step, seconds: ProcessInfo.processInfo.systemUptime - start, failure: failure)
}

/// Mean pressure over a depth window, to average out small elastic ringing.
private func meanPressure(_ from: Double, _ to: Double, _ curve: [LoadPoint]) -> Double {
    let window = curve.filter { $0.depth >= from && $0.depth <= to }
    return window.map(\.pressure).reduce(0, +) / Double(window.count)
}

private func pressure(at depth: Double, _ curve: [LoadPoint]) -> Double {
    guard let hi = curve.firstIndex(where: { $0.depth >= depth }) else { return curve.last?.pressure ?? .nan }
    guard hi > 0 else { return curve[hi].pressure }
    let a = curve[hi - 1], b = curve[hi]
    return a.pressure + (b.pressure - a.pressure) * (depth - a.depth) / (b.depth - a.depth)
}

func lockingCheck(quick: Bool, stiffness: Double = 100) {
    assemblyCrossCheck()
    // Elastic, perfectly plastic metal with E/Y = 100 so the plastic zone forms early.
    let material = Material(young: 200e9, density: 7800, poisson: 0.3)
    let yield = material.young / stiffness
    let model = J2Model(material: material, yieldStress: yield, hardening: 0)
    let k = yield / 3.0.squareRoot()
    let transits = max(100, stiffness)  // slower loading for stiffer metals keeps ringing small relative to Y

    // 1. Control: uniform plane-strain compression between smooth plates.
    //    Kept to 4% strain: a perfectly plastic block between frictionless
    //    plates has no hardening to keep the flow uniform, and past about 4%
    //    the explicit run drifts into a non-uniform (barrelling-like) mode, so
    //    the top-plate load no longer equals the element flow stress.
    let side = 0.01
    let block = alignedMesh(columns: 8, rows: 8, width: side, height: side)
    let top = block.nodes.indices.filter { abs(block.nodes[$0].y - side) < 1e-12 }
    let bottom = Set(block.nodes.indices.filter { abs(block.nodes[$0].y) < 1e-12 })
    let pin = bottom.min { abs(block.nodes[$0].x) < abs(block.nodes[$1].x) }!
    let control = drive(block, material: material, model: model, totalDepth: 0.04 * side, driven: top,
                        drivenFixedX: false, fixedX: [pin], fixedY: bottom, transits: transits, samples: 60,
                        loadWidth: { x in top.map { x[$0].x }.max()! - top.map { x[$0].x }.min()! },
                        checkerboardBox: nil)
    require(control.failure == nil, "Compression control failed: \(control.failure ?? "")")
    let flow = meanPressure(0.02 * side, 0.04 * side, control.curve)
    print("Control curve (strain %, σ/2k): " + [0.01, 0.02, 0.03, 0.04].map {
        String(format: "%.0f%% %.4f", 100 * $0, pressure(at: $0 * side, control.curve) / (2 * k)) }.joined(separator: ", "))
    print(String(format: "Control, uniform compression: mean flow stress over 2–4%% strain %.4f·Y (plane-strain 2k = %.4f·Y), error %+.2f%%, KE/plastic %.1e",
                 flow / yield, 2 * k / yield, 100 * (flow / (2 * k) - 1), control.kineticOverPlastic))
    require(abs(flow / (2 * k) - 1) < 0.02, "Uniform compression flow stress is not 2k within 2%")

    // 2. Flat punch, rough (punch nodes held sideways), bottom clamped.
    let punch = 0.01, width = 6 * punch, height = 3 * punch
    let limit = (2 + Double.pi) * k
    let finalDepth = 0.22 * punch
    print(String(format: "Flat punch: block %.0fb × %.0fb, E/Y = %.0f, ν = %.2f, prediction (2+π)k = %.3f·Y (Prandtl/Hill)",
                 width / punch, height / punch, material.young / yield, material.poisson, limit / yield))
    print("mesh      b/h  triangles  p/(2+π)k at depth/b = 0.05  0.10  0.15  0.20   rise 0.10→0.20  checkerboard  KE/Wp    time")
    var table: [String: [Double]] = [:]
    let refinements = quick ? [8] : [8, 16]
    for kind in ["crossed", "uniform", "aligned", "delaunay"] {
        for perPunch in refinements {
            let h = punch / Double(perPunch)
            let mesh: PlainMesh
            switch kind {
            case "uniform": mesh = alignedMesh(columns: Int(width / h + 0.5), rows: Int(height / h + 0.5), width: width, height: height, uniform: true)
            case "aligned": mesh = alignedMesh(columns: Int(width / h + 0.5), rows: Int(height / h + 0.5), width: width, height: height)
            case "crossed": mesh = crossedMesh(columns: Int(width / h + 0.5), rows: Int(height / h + 0.5), width: width, height: height)
            default: mesh = delaunayMesh(edge: h, width: width, height: height, punch: punch)
            }
            let tol = 1e-6 * punch
            let punchNodes = mesh.nodes.indices.filter { abs(mesh.nodes[$0].y - height) < tol && abs(mesh.nodes[$0].x) <= punch / 2 + tol }
            let clamped = Set(mesh.nodes.indices.filter { abs(mesh.nodes[$0].y) < tol })
            let result = drive(mesh, material: material, model: model, totalDepth: finalDepth, driven: punchNodes,
                               drivenFixedX: true, fixedX: clamped, fixedY: clamped, transits: transits, samples: 200,
                               loadWidth: { _ in punch },
                               checkerboardBox: { abs($0.x) < 0.75 * punch && $0.y > height - punch && $0.y < height - 0.1 * punch })
            let ratios = [0.05, 0.10, 0.15, 0.20].map { meanPressure(($0 - 0.01) * punch, ($0 + 0.01) * punch, result.curve) / limit }
            let rise = ratios[3] / ratios[1] - 1
            table["\(kind)-\(perPunch)"] = ratios + [rise]
            print(String(format: "%-9@ %3d  %9d       %.3f       %.3f  %.3f  %.3f   %+6.1f%%        %.3f      %.1e  %.0f s%@",
                         kind, perPunch, mesh.triangles.count, ratios[0], ratios[1], ratios[2], ratios[3], 100 * rise,
                         result.checkerboard, result.kineticOverPlastic, result.seconds,
                         result.failure.map { " FAILED: " + $0 } ?? ""))
            require(result.failure == nil, "\(kind) punch run failed: \(result.failure ?? "")")
            require(result.kineticOverPlastic < 0.01, "\(kind) punch run was not quasi-static (KE/plastic ≥ 1%)")
        }
    }
    // Positive control: the crossed mesh is known not to lock. If it does not
    // come near (2+π)k the test itself is not trustworthy. Its curve keeps
    // rising slowly with depth (finite deformation, the punch-corner node
    // carrying part of the neighbouring element, and the elastic-plastic
    // transition at finite E/Y), so locking is judged against it, at the same
    // element size, rather than against the rigid-plastic number alone.
    let fineLevel = refinements.last!, coarseLevel = refinements.first!
    let crossedFine = table["crossed-\(fineLevel)"]!
    print(String(format: "Positive control: crossed mesh (b/h = %d) at depth 0.2b is %.3f× (2+π)k", fineLevel, crossedFine[3]))
    require(abs(crossedFine[3] - 1) < 0.10,
            "Crossed (non-locking) mesh is not within 10% of (2+π)k at depth 0.2b; the punch test is not trustworthy")
    for kind in ["uniform", "aligned", "delaunay"] {
        let fine = table["\(kind)-\(fineLevel)"]!, coarse = table["\(kind)-\(coarseLevel)"]!
        let crossedCoarse = table["crossed-\(coarseLevel)"]!
        let excess = (0..<4).map { fine[$0] / crossedFine[$0] - 1 }
        let worst = excess.max()!
        let coarseWorst = (0..<4).map { coarse[$0] / crossedCoarse[$0] - 1 }.max()!
        let verdict = worst > 0.10 ? "LOCKS (more than 10% stiffer than the non-locking mesh)"
            : worst > 0.05 ? "mild overstiffening (5–10%), not locking"
            : "does not lock (within 5% of the non-locking mesh)"
        print(String(format: "Verdict %@: pressure vs crossed mesh at depth 0.05/0.10/0.15/0.20b = %+.1f%% %+.1f%% %+.1f%% %+.1f%% (b/h = %d); worst %+.1f%% at b/h = %d. %@",
                     kind, 100 * excess[0], 100 * excess[1], 100 * excess[2], 100 * excess[3], fineLevel,
                     100 * coarseWorst, coarseLevel, verdict))
    }
}

func lockingProbe() {
    let material = Material(young: 200e9, density: 7800, poisson: 0.3)
    let yield = material.young / 100
    let model = J2Model(material: material, yieldStress: yield, hardening: 0)
    let k = yield / 3.0.squareRoot()
    var h = J2History()
    var lateral = 1.0
    for step in 1...300 {
        let ey = -0.15 * Double(step) / 300
        let sy = exp(ey)
        // Newton-free bisection on lateral stretch for zero sigma_xx.
        var lo = 0.9, hi = 1.4
        var r: J2Response! = nil
        for _ in 0..<80 {
            lateral = (lo + hi) / 2
            r = model.update(x: Point(lateral, 0), y: Point(0, sy), from: h)!
            if r.piolaX.x > 0 { hi = lateral } else { lo = lateral }
        }
        h = r.history
        if step % 60 == 0 {
            let j = lateral * sy
            let syy = r.piolaY.y * sy / j
            print(String(format: "strain %.2f  sigma_yy/2k %.4f  tau_yy/2k %.4f  J-1 %.2e  szz/k %.3f", -ey, -syy / (2 * k), -syy * j / (2 * k), j - 1, r.cauchyZZ / k))
        }
    }
}
