/// Step-acceptance rule for assembly runs with fracture: the energy ledger must close to within
/// 2% of an energy scale that does not depend on where the zero of gravitational potential is put.
///
/// Before 24 Nov 2026 the scale was the starting energy alone (kinetic + stored at t = 0). Gravity's
/// zero is the starting position, so a body released from rest started with zero energy and the
/// "2%" test became an absolute 1e-9 J/m test. A 40 mm drop with fracture on then stopped at first
/// contact on a residual of 0.047% of m·g·h, with no damage (decision record 27.1 and 27.7).
///
/// The scale is now the starting energy plus the largest gravitational work released so far
/// (the drop of potential energy below its starting value). Without gravity that term is zero, so
/// the rule is the old one exactly. With gravity it is never smaller than the old scale, so every
/// step the old rule accepted is still accepted and every run that used to finish is unchanged.
public enum EnergyAcceptance {
    /// Allowed residual as a fraction of the energy scale.
    public static let fraction = 0.02
    /// Absolute floor (J/m) for runs whose scale is zero.
    public static let floor = 1e-9

    /// Energy scale in J/m: starting energy plus the largest gravitational work released so far.
    public static func scale(initialEnergy: Double, gravitationalRelease: Double) -> Double {
        initialEnergy + max(0, gravitationalRelease)
    }

    /// True when `residual` (current ledger total minus the starting energy, J/m) is within budget.
    public static func accepts(residual: Double, initialEnergy: Double, gravitationalRelease: Double) -> Bool {
        abs(residual) <= max(floor, fraction * scale(initialEnergy: initialEnergy, gravitationalRelease: gravitationalRelease))
    }

    /// The rule used before 24 Nov 2026, kept only so the regression check can show what it decided.
    public static func legacyAccepts(residual: Double, initialEnergy: Double) -> Bool {
        abs(residual) <= max(floor, fraction * initialEnergy)
    }
}
