import Foundation

public struct AssemblyGauge: Codable, Equatable, Identifiable, Sendable {
    public static let limit = 8
    public var id = UUID()
    public var body: UUID
    public var name: String
    /// Local material coordinates in metres, or in fractions of the half-size.
    public var location: Point
    public var usesBodyFractions: Bool?

    public init(body: UUID, name: String, location: Point, usesBodyFractions: Bool? = nil) {
        self.body = body
        self.name = name
        self.location = location
        self.usesBodyFractions = usesBodyFractions
    }

    var isValid: Bool {
        !name.isEmpty && name.count <= 48 && location.x.isFinite && location.y.isFinite
            && (usesBodyFractions != true || max(abs(location.x), abs(location.y)) <= 1)
    }

    public func materialLocation(in part: AssemblyPart) -> Point {
        usesBodyFractions == true ? 0.5 * part.size * location : location
    }
}

public struct AssemblyGaugeReading: Sendable {
    public let position, velocity: Point
    public let strain, pressure, equivalentStress, plasticStrain, damage: Double
}

extension AssemblyScene {
    public static func bondedWaveExample() -> Self {
        var scene = Self()
        let soft = Material(young: 1e6, density: 1000)
        var specimen = AssemblyPart("Bonded specimen", center: Point(0.14, 0), size: Point(0.28, 0.045))
        specimen.material = soft
        specimen.bondedLayer = AssemblyPart.BondedLayer()
        specimen.refinement = .x4
        let strikerLength = 0.035
        var striker = AssemblyPart("Striker", center: Point(-strikerLength / 2 - 0.0005, 0),
                                   size: Point(strikerLength, specimen.size.y))
        striker.material = soft
        striker.velocity.x = 0.10
        striker.refinement = .fine
        scene.parts = [striker, specimen]
        scene.monitor = specimen.id
        scene.duration = 0.026
        scene.gauges = [
            AssemblyGauge(body: specimen.id, name: "Before bond", location: Point(-0.065, 0)),
            AssemblyGauge(body: specimen.id, name: "After bond", location: Point(0.065, 0))
        ]
        return scene
    }
}
