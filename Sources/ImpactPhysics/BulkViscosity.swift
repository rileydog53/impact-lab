import Foundation

/// Standard artificial bulk viscosity for explicit shock and stress-wave calculations (layered target plan, step 4).
///
/// While an element is being compressed it carries an extra pressure
///
///     q = ρ · l · ( b1 · c · |ε̇v|  +  b2² · l · ε̇v² )      (ε̇v < 0 only; q = 0 otherwise)
///
/// with ρ the current density, c the element's elastic longitudinal wave speed, l the element size
/// (square root of the current area, as LS-DYNA uses in 2D) and ε̇v the volumetric strain rate (rate of ln J).
/// The quadratic term is von Neumann and Richtmyer's (J. Appl. Phys. 21, 1950): it spreads a shock over a few
/// elements. The linear term damps the ringing behind the front.
///
/// Sources checked 2026-11-24:
/// - Abaqus Analysis User's Guide, "Bulk viscosity": linear p1 = b1 ρ c_d L_e ε̇vol, b1 = 0.06 by default;
///   quadratic p2 = ρ (b2 L_e)² |ε̇vol| min(0, ε̇vol), b2 = 1.2 by default, applied only while the volumetric
///   strain rate is compressive; the linear term alone is about 6% of critical damping in the highest mode.
/// - d3VIEW note on LS-DYNA *CONTROL_BULK_VISCOSITY: defaults Q1 = 1.5 (quadratic), Q2 = 0.06 (linear),
///   a positive strain-rate trace is ignored (compression only), element size √area in 2D.
/// The defaults here are Abaqus's (b2 = 1.2, squared in the formula, effective 1.44, close to LS-DYNA's 1.5).
/// Unlike Abaqus, the linear term is also compression only, as in LS-DYNA, so a body in tension is never damped.
///
/// q is a numerical stress, not a material property. It is off unless a scene sets it, and when it is off
/// none of this arithmetic runs, so earlier scenes replay bit for bit.
public struct BulkViscosity: Codable, Equatable, Sendable {
    /// b1, the linear coefficient.
    public var linear: Double
    /// b2, the quadratic coefficient (it enters the formula squared).
    public var quadratic: Double

    public static let standard = BulkViscosity(linear: 0.06, quadratic: 1.2)
    public static let linearRange = 0.0...0.5
    public static let quadraticRange = 0.0...3.0

    public init(linear: Double = 0.06, quadratic: Double = 1.2) {
        self.linear = linear
        self.quadratic = quadratic
    }

    public var isValid: Bool {
        Self.linearRange.contains(linear) && Self.quadraticRange.contains(quadratic) && linear + quadratic > 0
    }

    /// Fraction of critical damping in an element's highest mode (Abaqus's expression):
    /// ξ = b1 + b2² · (l / c) · |ε̇v| while compressing.
    func damping(length: Double, waveSpeed: Double, rate: Double) -> Double {
        linear + quadratic * quadratic * length / waveSpeed * Swift.max(0, -rate)
    }

    /// The stable step of a damped central-difference oscillator is (2/ω)(√(1 + ξ²) − ξ).
    static func stepFactor(damping ξ: Double) -> Double { (1 + ξ * ξ).squareRoot() - ξ }

    /// Factor applied to the undamped step at the start of a run, for the linear term (about 0.942 at b1 = 0.06).
    var startingStepFactor: Double { Self.stepFactor(damping: linear) }

    /// A run stops if the quadratic term ever needs more than this share of the step's safety margin.
    /// Engineering choice: the 0.8 margin on the step also covers stiffening during impact, so viscosity
    /// may use at most a fifth of it.
    static let allowedStepShrink = 0.8
}

/// Per-step state of the viscous pass of one body (element pressures at the start and end of the step).
struct ViscousState: Sendable {
    let model: BulkViscosity
    let dt: Double
    var q: [Double]
    var next: [Double]
    /// Work done against q on the trial step (J per metre of depth), trapezoid rule; added to the running total on acceptance.
    var trialWork = 0.0
    /// Largest fraction of critical damping seen on the trial step.
    var trialDamping = 0.0

    init(model: BulkViscosity, dt: Double, elements: Int) {
        self.model = model
        self.dt = dt
        q = Array(repeating: 0, count: elements)
        next = q
    }

    mutating func accept() { swap(&q, &next) }
}
