import Foundation

public enum SeamResponse: String, CaseIterable, Codable, Sendable {
    case intact = "Intact"
    case separating = "Separating"
}

public struct SeamSettings: Codable, Equatable, Sendable {
    public var response = SeamResponse.separating
    public var strengthFraction = 0.012
    public var criticalOpening = 0.008

    public static let strengthRange = 0.009...0.014
    public static let openingRange = 0.008...0.010

    var isValid: Bool {
        Self.strengthRange.contains(strengthFraction) && Self.openingRange.contains(criticalOpening)
    }

    func law(left: Material, right: Material) -> CohesiveLaw {
        CohesiveLaw(strength: strengthFraction * min(left.young, right.young), finalOpening: criticalOpening)
    }
}

package struct CohesiveLaw: Sendable {
    package let strength, finalOpening: Double
    package var onset: Double { 0.25 * finalOpening }
    package var stiffness: Double { strength / onset }
    package var contactStiffness: Double { 4 * stiffness }
    package var fractureEnergy: Double { 0.5 * strength * finalOpening }

    package init(strength: Double, finalOpening: Double) {
        self.strength = strength
        self.finalOpening = finalOpening
    }

    package struct Sample: Sendable {
        package let maximumOpening, traction, bondEnergy, contactEnergy, dissipated: Double
    }

    package func evaluate(opening: Double, previousMaximum: Double, canSeparate: Bool) -> Sample {
        let maximum = canSeparate ? max(previousMaximum, opening) : 0
        let softening = min(1, max(0, (maximum - onset) / (finalOpening - onset)))
        let secant = softening > 0 ? strength * (1 - softening) / maximum : stiffness
        let tensile = max(0, opening)
        let compressive = min(0, opening)
        return Sample(maximumOpening: maximum,
                      traction: secant * tensile + contactStiffness * compressive,
                      bondEnergy: 0.5 * secant * tensile * tensile,
                      contactEnergy: 0.5 * contactStiffness * compressive * compressive,
                      dissipated: fractureEnergy * softening)
    }
}

public struct SeamReadings: Sendable {
    public internal(set) var opening = 0.0
    public internal(set) var force = 0.0
    public internal(set) var dissipated = 0.0
    public internal(set) var separatedFraction = 0.0
    public let criticalEnergy: Double
    let height: Double
    public var dissipatedPerArea: Double { dissipated / height }
}

struct CohesiveSeam: Sendable {
    struct Pair: Sendable {
        let left, right: Int
        let weight: Double
    }

    struct Grip: Sendable {
        let nodes: [Int]
        let initialX, direction: Double
    }

    struct Motion {
        let displacement, velocity, acceleration: Double
    }

    struct Trial {
        var readings: SeamReadings
        var maxima: [Double]
        var bondEnergy = 0.0
        var contact = ContactResult()
    }

    static let transitsPerPhase = 16.0
    static let transitsToSettle = 4.0
    private static let targets = [0, 1.30, -0.13, 0.45]

    let law: CohesiveLaw
    let canSeparate: Bool
    let height, spacing, phaseDuration: Double
    let pairs: [Pair]
    let leftGrip, rightGrip: Grip
    var initialReadings: SeamReadings { SeamReadings(criticalEnergy: law.fractureEnergy, height: height) }

    func motion(at time: Double) -> Motion {
        let target = Self.targets
        let phase = time / phaseDuration
        guard phase < 3 else { return Motion(displacement: target[3] * law.finalOpening, velocity: 0, acceleration: 0) }
        let stage = Int(phase)
        let u = phase - Double(stage)
        let u2 = u * u
        let v = 1 - u
        let travel = (target[stage + 1] - target[stage]) * law.finalOpening
        return Motion(displacement: target[stage] * law.finalOpening + travel * u2 * u * (10 - 15 * u + 6 * u2),
                      velocity: travel * 30 * u2 * v * v / phaseDuration,
                      acceleration: travel * 60 * u * v * (1 - 2 * u) / (phaseDuration * phaseDuration))
    }

    func assemble(left: [Point], right: [Point], maxima: [Double],
                  leftForce: inout [Point], rightForce: inout [Point]) -> Trial {
        var trial = Trial(readings: initialReadings, maxima: maxima)
        for (i, pair) in pairs.enumerated() {
            let opening = right[pair.right].x - left[pair.left].x
            let sample = law.evaluate(opening: opening, previousMaximum: maxima[i], canSeparate: canSeparate)
            let weight = pair.weight
            let force = sample.traction * weight
            leftForce[pair.left] = Point(force, 0)
            rightForce[pair.right] = Point(-force, 0)
            trial.maxima[i] = sample.maximumOpening
            trial.readings.opening += opening * weight / height
            trial.readings.force += force
            trial.readings.dissipated += sample.dissipated * weight
            if sample.maximumOpening >= law.finalOpening { trial.readings.separatedFraction += weight / height }
            trial.bondEnergy += sample.bondEnergy * weight
            trial.contact.energy += sample.contactEnergy * weight
            trial.contact.penetration = max(trial.contact.penetration, -opening)
        }
        trial.contact.relativePenetration = trial.contact.penetration / spacing
        return trial
    }
}

extension Simulation {
    static func layeredSeam(scene: SceneConfiguration, rows: Int, stepScale: Double) -> Simulation {
        let rightPart = scene.second!
        let settings = scene.seam!
        let height = scene.first.height!
        let columns = 16
        let leftMesh = Mesh.rectangle(columns: columns, rows: rows) { u, v in
            Point(scene.first.width * (u - 1), height * (v - 0.5))
        }
        let rightMesh = Mesh.rectangle(columns: columns, rows: rows) { u, v in
            Point(rightPart.width * u, height * (v - 0.5))
        }
        let offset = Point(0, scene.centerY)
        let left = Body(mesh: leftMesh, material: scene.first.material,
                        position: leftMesh.reference.map { $0 + offset }, velocity: .zero)
        let right = Body(mesh: rightMesh, material: rightPart.material,
                         position: rightMesh.reference.map { $0 + offset }, velocity: .zero)
        let stride = columns + 1
        let spacing = height / Double(rows)
        let pairs = (0...rows).map { j in
            CohesiveSeam.Pair(left: j * stride + columns, right: j * stride,
                              weight: j == 0 || j == rows ? 0.5 * spacing : spacing)
        }
        let seam = CohesiveSeam(law: settings.law(left: left.material, right: right.material),
                                canSeparate: settings.response == .separating,
                                height: height, spacing: spacing, phaseDuration: scene.seamPhaseDuration,
                                pairs: pairs,
                                leftGrip: .init(nodes: (0...rows).map { $0 * stride },
                                                initialX: -scene.first.width, direction: -0.5),
                                rightGrip: .init(nodes: (0...rows).map { $0 * stride + columns },
                                                 initialX: rightPart.width, direction: 0.5))
        return Simulation(primary: left, secondary: right, gap: 0, stepScale: stepScale, seam: seam)
    }
}
