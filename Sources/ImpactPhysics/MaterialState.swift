import Foundation

/// Declares the evolving per-point state a material model carries, apart from
/// physical properties (`Material`), constitutive law (`ImpactPlasticity`,
/// `MaterialFractureSettings`) and numerical configuration (refinement, step
/// scale). This is a schema only: no solver code reads it yet, so results
/// are unchanged. `.reserved` channels have a name, unit and bounds so the
/// slot can be filled later without editing the solver loop; nothing
/// computes them and scenes cannot set them.
public struct StateChannel: Equatable, Sendable {
    public enum Status: String, Sendable { case active, reserved }
    public let name: String
    public let unit: String
    public let bounds: ClosedRange<Double>?
    public let monotonic: Bool
    public let status: Status
    public let note: String
}

public enum MaterialStateSchema {
    public static let channels: [StateChannel] = [
        StateChannel(name: "equivalentPlasticStrain", unit: "1", bounds: 0...1e3, monotonic: true, status: .active,
                     note: "J2 history alpha, per element (existing)."),
        StateChannel(name: "damage", unit: "1", bounds: 0...1, monotonic: true, status: .active,
                     note: "Cohesive seam softening per face (existing, exposed in replay). Element-level continuum damage is not implied."),
        StateChannel(name: "temperature", unit: "K", bounds: 0...5000, monotonic: false, status: .reserved,
                     note: "Reserved. No thermal physics or plastic-work heating exists; the plastic-work convention is unresolved (design note 01)."),
    ]

    public static var reserved: [StateChannel] { channels.filter { $0.status == .reserved } }
}
