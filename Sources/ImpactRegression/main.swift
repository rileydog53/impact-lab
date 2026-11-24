import Foundation
import ImpactPhysics
import simd

// Regression measurement harness. It RUNS ordinary lab experiments through the public solver
// API and writes raw measurements as JSON. It does not judge them: tests/regression/run.py
// compares them with analytic references (reference_calculator.py) and the recorded baseline.
// Nothing here changes solver code. Numerical verification only, not physical validation.

struct Measurement: Codable {
    var experiment: String
    var quantity: String
    var value: Double
    var unit: String
    var note: String = ""
}

nonisolated(unsafe) var measurements: [Measurement] = []
func record(_ experiment: String, _ quantity: String, _ value: Double, _ unit: String, _ note: String = "") {
    measurements.append(Measurement(experiment: experiment, quantity: quantity, value: value, unit: unit, note: note))
    print(String(format: "  %@ / %@ = %.6g %@", experiment, quantity, value, unit))
}

let g = AssemblyScene.standardGravity

struct Trace {
    var time: [Double] = []
    var series: [String: [Double]] = [:]
}

/// Runs a scene to its end. `observe` is called at t = 0 and after every accepted step.
func run(_ scene: AssemblyScene, _ observe: (AssemblySimulation) -> Void) -> (AssemblySimulation, steps: Int, seconds: Double)? {
    guard scene.issues().isEmpty, var sim = try? AssemblySimulation(scene), sim.initialIssue == nil else { return nil }
    let start = ProcessInfo.processInfo.systemUptime
    observe(sim)
    var steps = 0
    while sim.time < scene.duration {
        guard sim.step() else { print("  step failed: \(sim.failure ?? "?")"); return nil }
        steps += 1
        observe(sim)
    }
    return (sim, steps, ProcessInfo.processInfo.systemUptime - start)
}

/// Impulse–momentum balance for a gravity scene with fixed supports:
/// ∫ (support reaction) dt = ∫ (weight of the free bodies) dt + Δ(vertical momentum of the free bodies).
/// This holds exactly for the physical system; the residual measures the solver's time integration and contact.
struct ImpulseBalance {
    private var reaction = 0.0
    private var lastReaction: Double?
    private var lastTime = 0.0
    private var p0: Double?
    private(set) var p1 = 0.0
    /// Second half of the run: reaction impulse, momentum at the half-way step, time of that step.
    private(set) var halfReaction = 0.0, halfMomentum: Double?, halfTime = 0.0
    private let duration: Double
    private(set) var weight = 0.0
    private(set) var supportIndices: [Int]
    private(set) var freeIndices: [Int]
    init(scene: AssemblyScene) {
        supportIndices = scene.parts.indices.filter { scene.parts[$0].support != nil }
        freeIndices = scene.parts.indices.filter { scene.parts[$0].support != .fixed }
        duration = scene.duration
    }
    mutating func observe(_ sim: AssemblySimulation) {
        let r = supportIndices.reduce(0.0) { $0 + sim.supportReaction($1).y }
        let p = freeIndices.reduce(0.0) { $0 + sim.body($1).totalMass * sim.body($1).centerVelocity.y }
        if p0 == nil { p0 = p; weight = freeIndices.reduce(0.0) { $0 + sim.body($1).totalMass } * (sim.scene.gravity ?? 0) }
        if let last = lastReaction {
            let piece = 0.5 * (r + last) * (sim.time - lastTime)
            reaction += piece
            if halfMomentum != nil { halfReaction += piece }
        }
        if halfMomentum == nil && sim.time >= 0.5 * duration { halfMomentum = p; halfTime = sim.time }
        lastReaction = r; lastTime = sim.time; p1 = p
    }
    /// (impulse from supports, expected impulse m g T + Δp)
    /// Same balance over the second half of the run only.
    var secondHalf: (supports: Double, expected: Double) {
        (halfReaction, weight * (lastTime - halfTime) + (p1 - (halfMomentum ?? p1)))
    }
    var result: (supports: Double, expected: Double) { (reaction, weight * lastTime + (p1 - (p0 ?? 0))) }
}

/// Local minima of a sampled series, refined by a parabola through three samples.
func troughTimes(_ t: [Double], _ v: [Double]) -> [Double] {
    var out: [Double] = []
    guard v.count > 3 else { return out }
    for i in 1..<(v.count - 1) where v[i] <= v[i - 1] && v[i] < v[i + 1] {
        let d = v[i - 1] - 2 * v[i] + v[i + 1]
        let shift = d != 0 ? 0.5 * (v[i - 1] - v[i + 1]) / d : 0
        out.append(t[i] + shift * (t[i + 1] - t[i]))
    }
    return out
}

func meanPeriod(_ troughs: [Double]) -> Double {
    guard troughs.count >= 2 else { return .nan }
    return (troughs.last! - troughs.first!) / Double(troughs.count - 1)
}

func loadExample(_ example: LabExample) -> AssemblyScene { try! example.scene() }

func commonMetrics(_ name: String, _ scene: AssemblyScene, _ final: AssemblySimulation, balance: ImpulseBalance,
                   steps: Int, seconds: Double, worstEnergy: Double, energyScale: Double) {
    let b = balance.result
    record(name, "impulse_support", b.supports, "N·s/m", "∫ support reaction dt")
    record(name, "impulse_expected", b.expected, "N·s/m", "m g T + Δp of free bodies")
    record(name, "impulse_residual_relative", abs(b.supports - b.expected) / max(abs(b.expected), 1e-12), "")
    let h = balance.secondHalf
    record(name, "impulse_residual_relative_second_half", abs(h.supports - h.expected) / max(abs(h.expected), 1e-12), "",
           "same balance over the second half of the run (window effect check)")
    record(name, "energy_drift_relative", worstEnergy / energyScale, "", "max |E − E0| / scale")
    record(name, "peak_relative_penetration", final.peakRelativePenetration, "", "contact overlap relative to the body size")
    record(name, "steps", Double(steps), "")
    record(name, "wall_seconds", seconds, "s", "informational, machine dependent; never compared")
    record(name, "estimated_seconds", RunCostEstimate(try! AssemblySimulation(scene)).seconds, "s", "app's pre-run estimate")
}

// MARK: Experiments

func blockOnBench() {
    print("block on bench")
    let scene = loadExample(.block_on_bench)
    var balance = ImpulseBalance(scene: scene)
    var late: [Double] = []
    var e0 = 0.0, worst = 0.0, scale = 0.0
    guard let (final, steps, secs) = run(scene, { sim in
        balance.observe(sim)
        if sim.time == 0 { e0 = sim.initialEnergy }
        worst = max(worst, abs(sim.energies.total - sim.initialEnergy))
        if sim.time > 0.5 * scene.duration { late.append(sim.supportReaction(0).y) }
    }) else { record("block_on_bench", "run_failed", 1, ""); return }
    let weight = final.body(1).totalMass * g
    scale = weight * 0.0255
    _ = e0
    record("block_on_bench", "mean_reaction_over_weight_second_half", late.reduce(0, +) / Double(late.count) / weight, "")
    commonMetrics("block_on_bench", scene, final, balance: balance, steps: steps, seconds: secs, worstEnergy: worst, energyScale: scale)
}

func dropTest() {
    print("drop test")
    let scene = loadExample(.drop_test)
    var balance = ImpulseBalance(scene: scene)
    var y0 = 0.0, mass = 0.0
    var worstFall = 0.0, worst = 0.0
    var contactTime: Double?
    var keAtContact = 0.0, dropAtContact = 0.0
    var topAfter = -Double.infinity
    guard let (final, steps, secs) = run(scene, { sim in
        balance.observe(sim)
        worst = max(worst, abs(sim.energies.total - sim.initialEnergy))
        let ball = sim.body(1)
        if sim.time == 0 { y0 = ball.centerOfMass.y; mass = ball.totalMass }
        if contactTime == nil && !sim.activeContacts.isEmpty { contactTime = sim.time }
        if contactTime == nil {
            let drop = y0 - ball.centerOfMass.y
            worstFall = max(worstFall, abs(drop - 0.5 * g * sim.time * sim.time))
            keAtContact = 0.5 * mass * simd_length_squared(ball.centerVelocity)
            dropAtContact = drop
        } else if sim.time > (contactTime ?? 0) + 0.02 {
            topAfter = max(topAfter, ball.centerOfMass.y)
        }
    }) else { record("drop_test", "run_failed", 1, ""); return }
    record("drop_test", "free_fall_max_position_error", worstFall, "m", "before first contact, vs y0 − g t²/2")
    record("drop_test", "free_fall_height_before_contact", dropAtContact, "m")
    record("drop_test", "ke_before_contact_over_mgh", keAtContact / (mass * g * dropAtContact), "", "kinetic energy over m g h at the last pre-contact step")
    record("drop_test", "first_contact_time", contactTime ?? .nan, "s")
    record("drop_test", "rebound_height_over_drop", (topAfter - y0 + dropAtContact) / max(dropAtContact, 1e-12), "",
           "ILLUSTRATIVE: depends on contact penalty and mesh; recorded as a baseline only")
    commonMetrics("drop_test", scene, final, balance: balance, steps: steps, seconds: secs, worstEnergy: worst, energyScale: mass * g * 0.04)
}

/// Cantilever tip response under suddenly applied self-weight: static sag (time mean over whole periods)
/// and first-mode period. `rows` selects the refinement.
func cantilever(_ label: String, scene: AssemblyScene) {
    print(label)
    var t: [Double] = [], v: [Double] = []
    var tip: [Int] = []
    var balance = ImpulseBalance(scene: scene)
    var worst = 0.0, peakPot = 0.0
    guard let (final, steps, secs) = run(scene, { sim in
        balance.observe(sim)
        let body = sim.body(0)
        if tip.isEmpty {
            let right = body.mesh.reference.map(\.x).max()!
            tip = body.mesh.reference.indices.filter { abs(body.mesh.reference[$0].x - right) < 1e-9 }
        }
        let y = tip.reduce(0.0) { $0 + body.position[$1].y - body.mesh.reference[$1].y } / Double(tip.count)
        t.append(sim.time); v.append(-y)
        worst = max(worst, abs(sim.energies.total - sim.initialEnergy))
        peakPot = max(peakPot, abs(sim.energies.gravitational))
    }) else { record(label, "run_failed", 1, ""); return }
    let troughs = troughTimes(t, v)
    // Time mean from t = 0 to the last trough = whole number of periods.
    var mean = Double.nan
    if let last = troughs.last, let lastIndex = t.lastIndex(where: { $0 <= last }) , lastIndex > 1 {
        var integral = 0.0
        for i in 1...lastIndex { integral += 0.5 * (v[i] + v[i - 1]) * (t[i] - t[i - 1]) }
        mean = integral / t[lastIndex]
    }
    record(label, "mean_tip_sag", mean, "m", "time mean over whole periods; static sag for an undamped suddenly loaded beam")
    record(label, "first_period", meanPeriod(troughs), "s", "mean spacing of \(troughs.count) troughs of the tip sag")
    record(label, "trough_count", Double(troughs.count), "")
    record(label, "peak_tip_sag_over_mean", (v.max() ?? 0) / mean, "", "≈ 2 for a suddenly applied load, no damping")
    commonMetrics(label, scene, final, balance: balance, steps: steps, seconds: secs, worstEnergy: worst, energyScale: max(peakPot, 1e-12))
}

func cantileverSag() {
    cantilever("cantilever_sag", scene: loadExample(.cantilever_sag))
}

/// New experiment: the same bar, longer run, so several vibration periods are timed; coarse and fine mesh.
func barVibration() {
    for (label, refinement) in [("bar_vibration_x2", AssemblyScene.Resolution.fine), ("bar_vibration_x4", .x4)] {
        var scene = loadExample(.cantilever_sag)
        scene.duration = 0.55
        scene.parts[0].refinement = refinement
        cantilever(label, scene: scene)
    }
}

/// Geometry editing verification: the same cantilever built as an outline body, meshed by the general mesher
/// (Delaunay refinement) instead of the structured grid. Default edge 12 mm ÷ 4 = 3 mm, and a finer 2.25 mm.
func outlineCantilever() {
    for (label, edge) in [("outline_cantilever_3mm", Optional<Double>.none), ("outline_cantilever_2p25mm", 0.00225)] {
        var scene = loadExample(.cantilever_sag)
        scene.parts[0] = scene.parts[0].reshaped(to: scene.parts[0].region(), meshSize: edge)
        cantilever(label, scene: scene)
    }
}

func threePointBend() {
    print("three-point bend")
    let scene = loadExample(.three_point_bend)
    var balance = ImpulseBalance(scene: scene)
    var worst = 0.0
    var sag: [Double] = []
    var mid: [Int] = []
    guard let (final, steps, secs) = run(scene, { sim in
        balance.observe(sim)
        worst = max(worst, abs(sim.energies.total - sim.initialEnergy))
        let body = sim.body(0)
        if mid.isEmpty {
            let ref = body.mesh.reference
            let midX = ref.map { abs($0.x) }.min()!
            mid = ref.indices.filter { abs(abs(ref[$0].x) - midX) < 1e-9 && ref[$0].y < -0.0125 + 1e-9 }
        }
        sag.append(-mid.reduce(0.0) { $0 + body.position[$1].y - body.mesh.reference[$1].y } / Double(mid.count))
    }) else { record("three_point_bend", "run_failed", 1, ""); return }
    record("three_point_bend", "peak_midspan_deflection", sag.max() ?? .nan, "m", "bar plus lowered weight; informational baseline")
    let weight = final.body(0).totalMass * g
    commonMetrics("three_point_bend", scene, final, balance: balance, steps: steps, seconds: secs, worstEnergy: worst,
                  energyScale: weight * 0.002)
}

func hangingSprings() {
    print("hanging springs")
    let scene = loadExample(.hanging_springs)
    var t: [Double] = [], dropped: [Double] = []
    var y0 = [0.0, 0.0], peakSpeed = 0.0, worst = 0.0
    var balance = ImpulseBalance(scene: scene)
    var preloadedMaxMove = 0.0
    guard let (final, steps, secs) = run(scene, { sim in
        balance.observe(sim)
        if sim.time == 0 { y0 = [sim.body(1).centerOfMass.y, sim.body(2).centerOfMass.y] }
        t.append(sim.time); dropped.append(y0[0] - sim.body(1).centerOfMass.y)
        preloadedMaxMove = max(preloadedMaxMove, abs(y0[1] - sim.body(2).centerOfMass.y))
        peakSpeed = max(peakSpeed, simd_length(sim.body(2).centerVelocity))
        worst = max(worst, abs(sim.energies.total - sim.initialEnergy))
    }) else { record("hanging_springs", "run_failed", 1, ""); return }
    let mass = final.body(1).totalMass
    let troughs = troughTimes(t, dropped.map { -$0 })   // maxima of the drop
    record("hanging_springs", "block_mass", mass, "kg/m")
    record("hanging_springs", "unloaded_peak_drop", dropped.max() ?? .nan, "m", "≈ 2 m g / k for a block released at the unstretched length")
    if let last = troughs.last, let lastIndex = t.lastIndex(where: { $0 <= last }), lastIndex > 1 {
        var integral = 0.0
        for i in 1...lastIndex { integral += 0.5 * (dropped[i] + dropped[i - 1]) * (t[i] - t[i - 1]) }
        record("hanging_springs", "unloaded_mean_drop", integral / t[lastIndex], "m", "time mean over whole periods ≈ m g / k")
    }
    record("hanging_springs", "unloaded_period", meanPeriod(troughs), "s", "from \(troughs.count) maxima; vs 2π√(m/k)")
    record("hanging_springs", "preloaded_peak_speed", peakSpeed, "m/s", "starts in equilibrium")
    record("hanging_springs", "preloaded_max_displacement", preloadedMaxMove, "m")
    // m, k, g are echoed so the reference can be formed without re-reading the scene.
    record("hanging_springs", "spring_stiffness", scene.connections[0].stiffness, "N/m/m")
    commonMetrics("hanging_springs", scene, final, balance: balance, steps: steps, seconds: secs, worstEnergy: worst,
                  energyScale: mass * g * 0.0078)
}

/// New experiment: two blocks stacked on a fixed bench; the support must carry both weights.
func stackOnSupport() {
    stack("stack_on_support", upperOffset: 0)
    stack("stack_offset", upperOffset: 0.004)
}
func stack(_ name: String, upperOffset: Double) {
    print(name)
    var scene = AssemblyScene()
    var bench = AssemblyPart("Bench", center: Point(0, -0.015), size: Point(0.4, 0.03))
    bench.support = .fixed
    bench.material = Material(young: 1e7, density: 2500, poisson: 0.2)
    var lower = AssemblyPart("Lower block", center: Point(0, 0.025 + 1e-4), size: Point(0.08, 0.05))
    lower.material = Material(young: 3e6, density: 1100, poisson: 0.25)
    var upper = AssemblyPart("Upper block", center: Point(upperOffset, 0.05 + 0.02 + 3e-4), size: Point(0.05, 0.04))
    upper.material = Material(young: 3e6, density: 800, poisson: 0.25)
    scene.parts = [bench, lower, upper]
    scene.gravity = g
    scene.duration = 0.3
    scene.meshResolution = .fine
    var balance = ImpulseBalance(scene: scene)
    var worst = 0.0
    var late: [Double] = []
    var xStart = 0.0, drift = 0.0, rotationStart = 0.0
    guard let (final, steps, secs) = run(scene, { sim in
        balance.observe(sim)
        worst = max(worst, abs(sim.energies.total - sim.initialEnergy))
        if sim.time > 0.5 * scene.duration { late.append(sim.supportReaction(0).y) }
        let u = sim.body(2).centerOfMass
        if sim.time == 0 { xStart = u.x; rotationStart = u.y }
        drift = max(drift, abs(u.x - xStart))
    }) else { record(name, "run_failed", 1, ""); return }
    _ = rotationStart
    let weight = (final.body(1).totalMass + final.body(2).totalMass) * g
    record(name, "mean_reaction_over_total_weight_second_half", late.reduce(0, +) / Double(late.count) / weight, "")
    record(name, "upper_block_lateral_drift", drift, "m", "frictionless contact: a symmetric stack should not slide")
    record(name, "upper_block_height_final", final.body(2).centerOfMass.y, "m")
    commonMetrics(name, scene, final, balance: balance, steps: steps, seconds: secs, worstEnergy: worst, energyScale: weight * 0.001)
}

/// Same scene run twice: results must agree bit for bit (reproducibility, no hidden randomness or thread races).
func determinism() {
    print("determinism")
    let scene = loadExample(.hanging_springs)
    func finalState() -> [Double] {
        guard let (final, _, _) = run(scene, { _ in }) else { return [] }
        return (0..<final.bodyCount).flatMap { final.body($0).position.flatMap { [$0.x, $0.y] } }
    }
    let a = finalState(), b = finalState()
    let diff = zip(a, b).map { abs($0 - $1) }.max() ?? .nan
    record("determinism", "max_abs_position_difference_two_runs", a.count == b.count ? diff : .nan, "m", "hanging springs, run twice in one process")
}

// MARK: Usability probes (verbatim messages go to usability.json for a human to read)

struct Probe: Codable {
    var name: String
    var expectation: String
    var accepted: Bool
    var messages: [String]
}
nonisolated(unsafe) var probes: [Probe] = []

func probeJSON(_ name: String, _ expectation: String, _ json: String) {
    do {
        let scene = try AssemblyScene.document(Data(json.utf8))
        var note: [String] = []
        if let sim = try? AssemblySimulation(scene) { if let issue = sim.initialIssue { note.append("loads, but the run refuses to start: " + issue) } }
        else { note.append("loads, but the run cannot be created") }
        probes.append(Probe(name: name, expectation: expectation, accepted: note.isEmpty, messages: note))
    } catch let e as SceneDocumentError {
        probes.append(Probe(name: name, expectation: expectation, accepted: false, messages: e.issues))
    } catch {
        probes.append(Probe(name: name, expectation: expectation, accepted: false, messages: ["(unstructured error) \(error.localizedDescription)"]))
    }
}

func usabilityProbes() {
    print("usability probes")
    let block = #"{ "name": "B", "size": [0.05, 0.05], "center": [0, 0] }"#
    probeJSON("valid minimal scene", "accepted", #"{ "duration": 0.05, "parts": [ \#(block) ] }"#)
    probeJSON("truncated file", "rejected with a readable message", #"{ "duration": 0.05, "parts": [ { "name": "B""#)
    probeJSON("not JSON", "rejected with a readable message", "hello")
    probeJSON("empty object", "rejected or accepted with a clear reason", "{}")
    probeJSON("body too small", "rejected naming the field", #"{ "parts": [ { "name": "B", "size": [0.001, 0.05] } ] }"#)
    probeJSON("gravity beyond range", "rejected naming the field", #"{ "gravity": 100, "parts": [ \#(block) ] }"#)
    probeJSON("negative gravity", "rejected naming the field", #"{ "gravity": -9.8, "parts": [ \#(block) ] }"#)
    probeJSON("unknown top-level key", "rejected or warned", #"{ "gravty": 9.8, "parts": [ \#(block) ] }"#)
    probeJSON("unknown material name", "rejected listing the available names", #"{ "parts": [ { "name": "B", "size": [0.05, 0.05], "material": "unobtainium" } ] }"#)
    probeJSON("unknown material profile (hand-written provenance)", "rejected naming the profile", #"{ "parts": [ { "name": "B", "size": [0.05, 0.05], "material": { "provenance": { "id": "unobtainium" } } } ] }"#)
    probeJSON("every body fixed", "rejected with the reason", #"{ "parts": [ { "name": "B", "size": [0.05, 0.05], "support": "fixed" } ] }"#)
    probeJSON("spring to a missing body", "rejected naming the body", #"{ "parts": [ \#(block) ], "connections": [ { "first": "B", "second": "Ghost" } ] }"#)
    probeJSON("two bodies overlapping at the start", "rejected with clearance advice",
              #"{ "parts": [ { "name": "A", "size": [0.05, 0.05], "center": [0, 0] }, { "name": "B", "size": [0.05, 0.05], "center": [0.01, 0] } ] }"#)
    probeJSON("friction coefficient requested", "rejected with the reason", #"{ "parts": [ { "name": "B", "size": [0.05, 0.05], "friction": 0.4 } ] }"#)
    probeJSON("young modulus as a string", "rejected naming the field", #"{ "parts": [ { "name": "B", "size": [0.05, 0.05], "material": { "young": "steel" } } ] }"#)
    probeJSON("duration 0", "rejected naming the field", #"{ "duration": 0, "parts": [ \#(block) ] }"#)
    probeJSON("units in millimetres (size 50)", "rejected naming the field", #"{ "parts": [ { "name": "B", "size": [50, 50] } ] }"#)

    // Run-cost estimate against measured time for a few short scenes.
    for example in [LabExample.hanging_springs, .block_on_bench] {
        let scene = loadExample(example)
        var short = scene
        short.duration = min(short.duration, 0.05)
        guard let sim = try? AssemblySimulation(short) else { continue }
        let estimate = RunCostEstimate(sim).seconds
        if let (_, steps, secs) = run(short, { _ in }) {
            probes.append(Probe(name: "run-cost estimate: \(example.fileName), 0.05 s",
                                expectation: "estimate within a factor of two of measured (the app's own claim)",
                                accepted: estimate / secs > 0.5 && estimate / secs < 2,
                                messages: [String(format: "estimated %.2f s, measured %.2f s (%d steps), ratio %.2f", estimate, secs, steps, estimate / secs)]))
        }
    }
}

// MARK: Main

let args = CommandLine.arguments
let outDir = args.firstIndex(of: "--out").map { args[$0 + 1] } ?? (NSTemporaryDirectory() + "impactlab-regression")
let only = args.firstIndex(of: "--only").map { args[$0 + 1] }
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let all: [(String, () -> Void)] = [
    ("block_on_bench", blockOnBench), ("drop_test", dropTest), ("cantilever_sag", cantileverSag),
    ("bar_vibration", barVibration), ("outline_cantilever", outlineCantilever), ("three_point_bend", threePointBend), ("hanging_springs", hangingSprings),
    ("stack_on_support", stackOnSupport), ("determinism", determinism), ("usability", usabilityProbes),
]
for (name, body) in all where only == nil || only == name { body() }

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(measurements).write(to: URL(fileURLWithPath: outDir + "/measurements.json"))
try encoder.encode(probes).write(to: URL(fileURLWithPath: outDir + "/usability.json"))
print("Wrote \(measurements.count) measurements and \(probes.count) probes to \(outDir)")
