import Foundation
import ImpactPhysics
import simd

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

struct WaveResult {
    let arrival, predicted, peakError, impulseError, penetration, microsecondsPerStep, dt: Double
    let trace: [Double]
    var arrivalError: Double { arrival / predicted - 1 }
}

func wave(young: Double = 1e6, columns: Int = 120, rows: Int = 6, penalty: Double = 2500,
          targetStep: Double? = nil) -> WaveResult {
    let material = Material(young: young)
    let speed = 0.4
    var simulation = Simulation(mesh: .bar(columns: columns, rows: rows), material: material,
                                speed: speed, penalty: penalty)
    if let targetStep {
        require(targetStep <= simulation.dt, "Requested comparison timestep exceeds the stability estimate")
        let scale = targetStep / simulation.dt
        simulation = Simulation(mesh: simulation.body.mesh, material: material,
                                speed: speed, penalty: penalty, stepScale: scale)
    }
    let predicted = 0.5 / material.waveSpeed
    let contact = simulation.gap / speed
    let threshold = -0.5 * speed / material.waveSpeed
    let initialMomentum = simulation.diagnostics.momentum
    var peakError = 0.0
    var arrival: Double?
    var trace: [Double] = []
    let start = ProcessInfo.processInfo.systemUptime
    while simulation.time < contact + 2.5 * predicted {
        let previous = simulation.probeStrain
        let accepted = simulation.step()
        require(accepted, simulation.failure ?? "Bar step rejected")
        let current = simulation.probeStrain
        trace.append(current)
        peakError = max(peakError, abs(simulation.diagnostics.relativeEnergyError))
        if arrival == nil && current <= threshold {
            let fraction = (threshold - previous) / (current - previous)
            arrival = simulation.time - (1 - fraction) * simulation.dt - contact
        }
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let momentumChange = simulation.diagnostics.momentum - initialMomentum
    let mismatch = simd_length(momentumChange + Point(simulation.wallImpulse, 0))
        / abs(initialMomentum.x)
    require(arrival != nil, "Bar probe never crossed the arrival threshold")
    return WaveResult(arrival: arrival!, predicted: predicted, peakError: peakError,
                      impulseError: mismatch, penetration: simulation.peakPenetration,
                      microsecondsPerStep: elapsed * 1e6 / Double(trace.count), dt: simulation.dt, trace: trace)
}

func patchCheck() {
    let mesh = Mesh.bar(columns: 8, rows: 4)
    let material = Material(young: 1e6, density: 1000, poisson: 0.25)
    let simulation = Simulation(mesh: mesh, material: material)
    func maxForce(_ positions: [Point]) -> Double {
        guard let forces = simulation.internalForces(at: positions) else { return .infinity }
        return forces.map(simd_length).max()!
    }
    let translation = maxForce(mesh.reference.map { $0 + Point(1, -0.3) })
    let theta = 0.73
    let rotation = maxForce(mesh.reference.map {
        Point(cos(theta) * $0.x - sin(theta) * $0.y, sin(theta) * $0.x + cos(theta) * $0.y)
    })
    // Affine shear and dilation. A constant Piola stress gives only boundary
    // nodal forces, small enough here to compare every node directly.
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
    let positions = mesh.reference.map { Point(x * $0.x + shear * $0.y, y * $0.y) }
    guard let actual = simulation.internalForces(at: positions) else {
        require(false, "Affine patch was rejected")
        return
    }
    let mismatch = zip(actual, expected).map { simd_length($0 - $1) }.max()!
    print(String(format: "Maximum residual force (N/m): translation %.2e, rotation %.2e, affine patch %.2e",
                 translation, rotation, mismatch))
    require(max(translation, rotation, mismatch) < 1e-7, "Rigid-motion or affine patch residual")
    require(simulation.internalForces(at: mesh.reference.map { Point(-$0.x, $0.y) }) == nil,
            "Inverted elements must be rejected")
}

// The sibling- and detachment-contact replays reproduce specific 0.8 crack
// trajectories to test contact handoff, so they keep the element-mean
// insertion criterion that generated those trajectories.
if ["--legacy-insertion", "--sibling-contact", "--detachment-contact"].contains(where: CommandLine.arguments.contains) {
    MaterialFracture.recoveredInsertionStress = false
}

if CommandLine.arguments.dropFirst().contains("--contact-handoff") {
    exit(try contactHandoffCheck() ? EXIT_SUCCESS : EXIT_FAILURE)
}

if let index = CommandLine.arguments.firstIndex(of: "--fracture-convergence") {
    let passed = try fractureConvergenceCheck(Array(CommandLine.arguments.dropFirst(index + 1)))
    exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
}

if let index = CommandLine.arguments.firstIndex(of: "--fracture-map") {
    let a = Array(CommandLine.arguments.dropFirst(index + 1))
    try fractureMapProbe(a[0], refinement: Int(a[1])!, dt: Double(a[2])! * 1e-6, duration: Double(a[3])! * 1e-3,
                         strikerX: a.count > 4 ? Double(a[4])! * 1e-3 : nil, quiet: a.contains("quiet"), production: a.contains("production"))
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--fracture") {
    try fractureCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--fracture-study") {
    let gatesPassed = try fractureStudy()
    exit(gatesPassed ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.dropFirst().contains("--notched-bend") {
    let gatePassed = try notchedBendStudy()
    exit(gatePassed ? EXIT_SUCCESS : EXIT_FAILURE)
}

if let index = CommandLine.arguments.firstIndex(of: "--compliant-fracture") {
    let arguments = Array(CommandLine.arguments.dropFirst(index + 1))
    require(arguments.count >= 2 && arguments.count <= 3, "Usage: --compliant-fracture aligned|staggered 3|4 [half]")
    guard let resolution = Int(arguments[1]), (3...4).contains(resolution) else { exit(EXIT_FAILURE) }
    try compliantFractureCheck(arguments[0], refinement: resolution, halfStep: arguments.last == "half")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--receiver-quarter-step") {
    try receiverRefinementCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--receiver-extended") {
    try receiverRefinementCheck(extended: true)
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--contact-reporting") {
    try contactReportingCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--compliant-striker") {
    try compliantStrikerCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--elastic-bend-loading") {
    try elasticBendLoadingCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--sibling-contact") {
    try siblingContactCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--detachment-contact") {
    slidingDetachmentPatch()
    let gatesPassed = try detachmentContactCheck()
    exit(gatesPassed ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.dropFirst().contains("--sliding-contact-patch") {
    slidingDetachmentPatch()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--fracture-stability") {
    try fractureStabilityProbe()
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--fracture-case") {
    let values = Array(CommandLine.arguments.dropFirst(index + 1))
    require(values.count == 2, "Usage: --fracture-case aligned|staggered 1|2|3")
    try fractureAssemblyCase(values[0], values[1])
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--assembly") {
    try assemblyCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--assembly-study") {
    try await assemblyStudyCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--experiment-library") {
    try await experimentLibraryCheck()
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--showcase") {
    try showcaseReport(Array(CommandLine.arguments.dropFirst(index + 1)))
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--mpm-compare") {
    mpmComparison(Array(CommandLine.arguments.dropFirst(index + 1)))
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--scene-documents") {
    let args = CommandLine.arguments
    let directory = args.indices.contains(index + 1) ? args[index + 1] : "docs/scene-examples"
    try sceneDocumentsCheck(examples: URL(fileURLWithPath: directory))
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--scenario-library") {
    let args = CommandLine.arguments
    try scenarioLibraryCheck(only: args.indices.contains(index + 1) ? args[index + 1].lowercased() : nil)
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--off-axis") {
    try offAxisImpactCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--layered-impact") {
    try layeredImpactCheck()
    try layeredImpactEnvelopeCheck()
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--assembly-scaling") {
    let args = CommandLine.arguments
    guard args.indices.contains(index + 1) else {
        print("Usage: ImpactCheck --assembly-scaling copper|elastic|linear|enclosure|fracture [--parallel-fem] [--kernel-profile] [--resume-check] [--write-scene PATH]")
        exit(EXIT_FAILURE)
    }
    let output = args.firstIndex(of: "--write-scene").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    try assemblyScalingCheck(args[index + 1], sceneFile: output)
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--results-export") {
    let args = CommandLine.arguments
    try resultsExportCheck(directory: args.indices.contains(index + 1) ? args[index + 1] : NSTemporaryDirectory() + "impactlab-export")
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--smooth-field") {
    let args = CommandLine.arguments
    try smoothFieldCheck(snapshot: args.indices.contains(index + 1) ? args[index + 1] : nil)
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--run-cost") {
    try runCostCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--lab-examples") {
    try labExamplesCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--supports-gravity") {
    try supportsGravityCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--fracture-guard") {
    try fractureGuardCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--workshop-improvements") {
    try workshopImprovementsCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--materials") {
    try materialsCheck()
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--legacy-replay") {
    let args = CommandLine.arguments
    guard args.indices.contains(index + 2), ["record", "check"].contains(args[index + 1]) else {
        print("Usage: ImpactCheck --legacy-replay record|check BASELINE_FILE")
        exit(EXIT_FAILURE)
    }
    try legacyReplayCheck(mode: args[index + 1], baseline: args[index + 2])
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--assembly-replay") {
    try assemblyReplayCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--metal-profiles") {
    try metalProfilesCheck()
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--layered-bodies") {
    let args = CommandLine.arguments
    if args.indices.contains(index + 1) && args[index + 1] == "probe" { try layeredBondProbe(); exit(EXIT_SUCCESS) }
    try layeredBodiesCheck(quick: args.indices.contains(index + 1) && args[index + 1] == "quick")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--layered-examples") {
    try layeredExamplesCheck()
    exit(EXIT_SUCCESS)
}

if let index = CommandLine.arguments.firstIndex(of: "--locking") {
    let args = CommandLine.arguments
    if args.indices.contains(index + 1) && args[index + 1] == "probe" { lockingProbe(); exit(EXIT_SUCCESS) }
    let quick = args.dropFirst(index + 1).contains("quick")
    let ratio = args.dropFirst(index + 1).compactMap { Double($0) }.first ?? 100
    lockingCheck(quick: quick, stiffness: ratio)
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--spall") {
    try spallCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--bulk-viscosity") {
    try bulkViscosityCheck()
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.dropFirst().contains("--plasticity") {
    try plasticityCheck()
    try materialImpactCheck()
    exit(EXIT_SUCCESS)
}

let nominal = wave()
let stiff = wave(young: 4e6)
let repeatRun = wave()
let comparisonStep = nominal.dt / 2
let fineSpace = wave(columns: 240, rows: 12, targetStep: comparisonStep)
let fineTime = wave(targetStep: comparisonStep)
let softWall = wave(penalty: 1250, targetStep: comparisonStep)
let stiffWall = wave(penalty: 5000, targetStep: comparisonStep)
for (label, result) in [("Reference", nominal), ("4 MPa", stiff), ("Finer mesh", fineSpace),
                        ("Half timestep", fineTime), ("Half wall penalty", softWall),
                        ("Double wall penalty", stiffWall)] {
    print(String(format: "%@: arrival %.3f ms (%+.2f%%), peak imbalance %.3f%%, peak penetration %.3f mm, momentum residual %.2e, dt %.2f µs",
                 label, result.arrival * 1000, 100 * result.arrivalError, 100 * result.peakError,
                 result.penetration * 1000, result.impulseError, result.dt * 1e6))
}
print(String(format: "Reference prediction %.3f ms; arrival ratio %.4f; reset identical: %@",
             nominal.predicted * 1000, stiff.arrival / nominal.arrival, (repeatRun.trace == nominal.trace).description))
print(String(format: "Reference bar with diagnostics %.1f µs/step; headless throughput %.3f simulated s/wall s",
             nominal.microsecondsPerStep, nominal.dt * 1e6 / nominal.microsecondsPerStep))
require([nominal, stiff].allSatisfy { abs($0.arrivalError) < 0.05 }, "Bar arrival-time error above 5%")
require(nominal.peakError < 0.01, "Reference bar energy imbalance above 1%")
require([nominal, stiff, fineSpace, fineTime, softWall, stiffWall].allSatisfy { $0.impulseError < 1e-11 },
        "Wall impulse and momentum change disagree")
require(abs(stiff.arrival / nominal.arrival - 0.5) < 0.025 && repeatRun.trace == nominal.trace,
        "Stiffness scaling or repeatability check failed")
patchCheck()

ringCheck()
blockCheck()
twoBarCheck()
puckStripCheck()
try configurationCheck()
try bondedBarCheck()
try plasticityCheck()
try materialImpactCheck()
try cohesiveCheck()
try layeredImpactCheck()
try layeredImpactEnvelopeCheck()
try offAxisImpactCheck()
try assemblyCheck()
try fractureCheck()
try layeredBodiesCheck(quick: true)
