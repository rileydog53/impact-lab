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
        var text = "Timestep \(Self.format(dt)), set by the \(cause.rawValue) on \(bodyName)"
        switch cause {
        case .material:
            text += String(format: " (wave crossing its smallest triangles, about %.2g mm high). A coarser mesh or a softer, denser material allows a longer step.", elementSize * 1000)
        case .contact:
            text += ". Contact is a stiff penalty spring scaled from Young's modulus; it is a numerical safeguard and is not relaxed to save time."
        case .connections:
            text += ". A stiffer spring or link than the body itself shortens the step; a softer connection allows a longer one."
        case .fracture:
            text += ". Crack faces are given a stiffness of at least 30·E/h so the uncracked body stays stiff; this is the main cost of fracture on stiff materials. Without fracture the step would be about \(Self.format(withoutFractureStep))."
        }
        if cause != .material { text += " The material alone would allow about \(Self.format(materialStep))." }
        return text
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
