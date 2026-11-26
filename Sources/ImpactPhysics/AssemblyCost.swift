import Foundation
import simd

/// Names the stiffness that sets an assembly's timestep. Reporting only:
/// it repeats the stability bound with terms added one at a time.
public struct TimestepDiagnosis: Sendable, Equatable {
    public enum Cause: String, Sendable {
        case material = "material wave speed"
        case contact = "contact penalty stiffness"
        case connections = "connection stiffness"
        case fracture = "fracture crack-face stiffness"
    }

    public let dt: Double
    /// Index and name of the body whose bound sets dt (nil if no body moves).
    public let body: Int?
    public let bodyName: String
    public let cause: Cause
    /// The step the materials alone would allow, with no contact, links or fracture.
    public let materialStep: Double
    /// The step the assembly would allow without fracture on any body.
    public let withoutFractureStep: Double
    /// Approximate smallest element size of the limiting body (m).
    public let elementSize: Double

    init(scene: AssemblyScene, bodies: [Body], squared: [Double], dt: Double, stepScale: Double,
         stages: [(material: Double, contact: Double, linked: Double)]) {
        self.dt = dt
        let index = squared.indices.max { squared[$0] < squared[$1] }
        body = index.flatMap { squared[$0] > 0 ? $0 : nil }
        bodyName = body.map { scene.parts[$0].name } ?? "—"
        let bound = { (value: Double) in value > 0 ? stepScale * 0.8 / value.squareRoot() : .infinity }
        materialStep = bound(stages.map(\.material).max() ?? 0)
        withoutFractureStep = bound(stages.map(\.linked).max() ?? 0)
        if let body {
            let stage = stages[body], full = squared[body]
            let fractured = scene.parts[body].fracture != nil
            if fractured && full > 1.5 * stage.linked { cause = .fracture }
            else if stage.linked > 1.5 * stage.contact { cause = .connections }
            else if stage.contact > 1.5 * stage.material { cause = .contact }
            else { cause = .material }
            let mesh = bodies[body].mesh
            elementSize = mesh.elements.map { e in
                2 * e.area / [simd_distance(mesh.reference[e.a], mesh.reference[e.b]),
                              simd_distance(mesh.reference[e.b], mesh.reference[e.c]),
                              simd_distance(mesh.reference[e.c], mesh.reference[e.a])].max()!
            }.min() ?? 0
        } else {
            cause = .material
            elementSize = 0
        }
    }

    /// One plain sentence naming what limits the step, for example
    /// "Timestep 9.1 ns, set by fracture crack-face stiffness on Steel target (at least 30·E/h)."
    public var explanation: String {
        guard body != nil else { return "No body moves, so there is nothing to step." }
        var text = "Each calculation step covers \(Self.format(dt)) (time step), set by \(plainCause) on \(bodyName)"
        switch cause {
        case .material:
            text += String(format: ": a step must be shorter than the time sound takes to cross its smallest triangles (about %.2g mm). A coarser mesh, or a softer or heavier material, allows longer steps and a faster run.", elementSize * 1000)
        case .contact:
            text += ". Touching bodies push apart through very stiff springs, and those need short steps. This is a safety margin, not relaxed to save time."
        case .connections:
            text += ". A spring or link stiffer than the body itself needs shorter steps; a softer one allows longer steps."
        case .fracture:
            text += ". Crack faces are held shut by very stiff springs until they open, which needs short steps: the main cost of cracking in stiff materials. Without cracking a step could be about \(Self.format(withoutFractureStep))."
        }
        if cause != .material { text += " The material alone would allow about \(Self.format(materialStep))." }
        return text
    }

    private var plainCause: String {
        switch cause {
        case .material: "how fast sound travels through the material"
        case .contact: "the contact springs"
        case .connections: "a spring or link"
        case .fracture: "the crack-face springs"
        }
    }

    public static func format(_ seconds: Double) -> String {
        if !seconds.isFinite { return "—" }
        if seconds >= 1e-3 { return String(format: "%.3g ms", seconds * 1e3) }
        if seconds >= 1e-6 { return String(format: "%.3g µs", seconds * 1e6) }
        return String(format: "%.3g ns", seconds * 1e9)
    }
}

/// A pre-run cost estimate. The rate is element-weight updates per second on this Mac,
/// either a stated default or one measured from earlier runs.
public struct RunCostEstimate: Sendable {
    public static let defaultRate = 1.0e7
    public let steps: Double
    public let elementWeight: Int
    public let seconds: Double
    public let rate: Double
    public let measuredRate: Bool
    public let parallel: Bool
    public let lanes: (heavier: Int, lighter: Int)

    public init(_ simulation: AssemblySimulation, rate measured: Double? = nil) {
        let remaining = max(0, simulation.scene.duration - simulation.time)
        steps = (remaining / simulation.dt).rounded(.up)
        lanes = simulation.laneLoads
        elementWeight = lanes.heavier + lanes.lighter
        parallel = lanes.lighter >= AssemblySimulation.parallelThreshold && ProcessInfo.processInfo.activeProcessorCount > 1
        rate = measured ?? Self.defaultRate
        measuredRate = measured != nil
        // With two lanes the heavier lane bounds the element work.
        let perStep = Double(max(1, parallel ? lanes.heavier : elementWeight))
        seconds = steps * perStep / rate
    }

    public static func duration(_ seconds: Double) -> String {
        if seconds < 1 { return "under a second" }
        if seconds < 90 { return String(format: "about %.0f s", seconds) }
        if seconds < 5400 { return String(format: "about %.0f min", seconds / 60) }
        return String(format: "about %.1f h", seconds / 3600)
    }

    public var laneNote: String {
        if parallel { return "Two CPU lanes (each carries at least \(AssemblySimulation.parallelThreshold.formatted()) element-weight)." }
        return "One CPU lane: two-lane dispatch needs at least \(AssemblySimulation.parallelThreshold.formatted()) element-weight on the lighter lane, and this assembly has \(lanes.lighter.formatted()) (bodies are split whole between lanes)."
    }

    public var uncertainty: String {
        (measuredRate ? "Based on the speed measured in earlier runs on this Mac. " : "Based on a typical speed of 10 million element updates per second; it is refined after each run. ")
            + "Contact, crack growth and plastic flow change the cost per step during a run, so treat it as within a factor of about two. The estimate is updated from the measured speed while the calculation runs."
    }
}
