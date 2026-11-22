import Foundation

public struct SpecimenConfiguration: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double?
    public var cornerRadius: Double?
    public var wallThickness: Double?
    public var material = Material()
}

public struct SceneConfiguration: Codable, Equatable, Sendable {
    public private(set) var formatVersion = 1
    public let preset: Preset
    public var first: SpecimenConfiguration
    public var second: SpecimenConfiguration?
    public var gap: Double
    public var targetX = 0.0
    public var centerY = 0.0
    public var puckOffsetY = 0.0
    // Relative horizontal speed for contact scenes and pulse amplitude for a bonded bar.
    public var speed = 0.4
    public var targetVelocityX = 0.0
    public var velocityY = 0.0
    public var mirrored = false
    public var tension: TensionSettings?
    public var impactPlasticity: ImpactPlasticity?
    public var seam: SeamSettings?

    public static let youngRange = 0.5e6...4e6
    public static let densityRange = 500.0...2500.0
    public static let poissonRange = 0.0...0.35
    public static let centerYRange = -0.12...0.12
    public static let velocityYRange = -0.10...0.10

    public static func standard(_ preset: Preset) -> SceneConfiguration {
        switch preset {
        case .bar:
            SceneConfiguration(preset: preset, first: .init(width: 1, height: 0.10), gap: 0.0005)
        case .materialImpact:
            SceneConfiguration(preset: preset, first: .init(width: 0.30, height: 0.06, material: Material(poisson: 0.15)),
                               gap: 0.018, speed: 1.3, impactPlasticity: ImpactPlasticity())
        case .ring:
            SceneConfiguration(preset: preset, first: .init(width: 0.40, wallThickness: 0.09), gap: 0.004)
        case .block:
            SceneConfiguration(preset: preset, first: .init(width: 0.36, height: 0.23, cornerRadius: 0.035), gap: 0.004)
        case .twoBars:
            SceneConfiguration(preset: preset, first: .init(width: 0.50, height: 0.10),
                               second: .init(width: 0.50, height: 0.10), gap: 0.012, targetX: 0.006)
        case .puckStrip:
            SceneConfiguration(preset: preset, first: .init(width: 0.14),
                               second: .init(width: 0.04, height: 0.42), gap: 0.008, puckOffsetY: 0.055)
        case .bondedBar:
            SceneConfiguration(preset: preset, first: .init(width: 1, height: 0.10),
                               second: .init(width: 0.80, height: 0.10, material: Material(young: 4e6)),
                               gap: 0, speed: 0.05)
        case .tensionCoupon:
            SceneConfiguration(preset: preset, first: .init(width: 0.30, height: 0.06, material: Material(poisson: 0.25)),
                               gap: 0, speed: 0, tension: TensionSettings())
        case .layeredSeam:
            SceneConfiguration(preset: preset,
                               first: .init(width: 0.09, height: 0.065, material: Material(young: 1.8e6)),
                               second: .init(width: 0.09, height: 0.065, material: Material(young: 2.6e6)),
                               gap: 0, speed: 0, seam: SeamSettings())
        }
    }

    public var isPair: Bool { preset == .twoBars || preset == .puckStrip }
    public var isBonded: Bool { preset == .bondedBar }
    public var sharesHeight: Bool { preset == .twoBars || isBonded || preset == .layeredSeam }
    public var gapRange: ClosedRange<Double> {
        let standardGap = Self.standard(preset).gap
        return standardGap * 0.5...standardGap * 2
    }
    public var targetXRange: ClosedRange<Double> {
        let x = Self.standard(preset).targetX
        return isPair || isBonded ? (x - 0.025)...(x + 0.025) : 0...0
    }
    public var targetVelocityXRange: ClosedRange<Double> { isPair || isBonded ? -0.15...0.15 : 0...0 }
    public var speedRange: ClosedRange<Double> {
        switch preset {
        case .tensionCoupon, .layeredSeam: 0...0
        case .materialImpact: 0.25...1.5
        case .bondedBar: 0.01...0.10
        default: 0.10...1.0
        }
    }
    public var puckOffsetRange: ClosedRange<Double> { preset == .puckStrip ? 0.04...0.07 : 0...0 }

    public static func sizeRange(_ nominal: Double) -> ClosedRange<Double> {
        nominal * 0.9...nominal * 1.1
    }

    var seamPhaseDuration: Double {
        let right = second!
        let transit = first.width / first.material.waveSpeed + right.width / right.material.waveSpeed
        return CohesiveSeam.transitsPerPhase * transit
    }

    public var duration: Double {
        let reference = Self.standard(preset)
        let duration: Double
        switch preset {
        case .bar: duration = 0.062
        case .materialImpact: return gap / speed + 12 * first.width / first.material.waveSpeed
        case .ring: duration = 0.26
        case .block: duration = 0.17
        case .twoBars: duration = 0.070
        case .puckStrip: duration = 0.11
        case .bondedBar: return 1.05 * first.width / first.material.waveSpeed
        case .tensionCoupon:
            return (2 * TensionLoad.rampTransits + TensionLoad.settleTransits) * first.width / first.material.waveSpeed
        case .layeredSeam:
            return (3 + CohesiveSeam.transitsToSettle / CohesiveSeam.transitsPerPhase) * seamPhaseDuration
        }
        let firstWidth = first.width / reference.first.width
        let firstHeight = (first.height ?? 1) / (reference.first.height ?? 1)
        let secondWidth = (second?.width ?? 1) / (reference.second?.width ?? 1)
        let secondHeight = (second?.height ?? 1) / (reference.second?.height ?? 1)
        let scale = max(firstWidth, firstHeight, secondWidth, secondHeight)
        let waveSpeed = min(first.material.waveSpeed, second?.material.waveSpeed ?? .infinity)
        return (isPair ? 2 : 1) * gap / speed + duration * scale * Material().waveSpeed / waveSpeed
    }

    private func validate() throws {
        guard formatVersion == 1 else {
            throw SceneFileError.unsupportedVersion(formatVersion)
        }
        let standard = Self.standard(preset)
        func validDimension(_ value: Double?, _ nominal: Double?) -> Bool {
            switch (value, nominal) {
            case let (.some(value), .some(nominal)): Self.sizeRange(nominal).contains(value)
            case (nil, nil): true
            default: false
            }
        }
        func validSpecimen(_ part: SpecimenConfiguration?, _ nominal: SpecimenConfiguration?) -> Bool {
            guard let part, let nominal else { return part == nil && nominal == nil }
            return validDimension(part.width, nominal.width)
                && validDimension(part.height, nominal.height)
                && validDimension(part.cornerRadius, nominal.cornerRadius)
                && validDimension(part.wallThickness, nominal.wallThickness)
                && Self.youngRange.contains(part.material.young)
                && Self.densityRange.contains(part.material.density)
                && Self.poissonRange.contains(part.material.poisson)
        }
        guard validSpecimen(first, standard.first), validSpecimen(second, standard.second),
              !sharesHeight || first.height == second?.height,
              gapRange.contains(gap), speedRange.contains(speed), targetXRange.contains(targetX),
              targetVelocityXRange.contains(targetVelocityX), puckOffsetRange.contains(puckOffsetY),
              Self.centerYRange.contains(centerY), Self.velocityYRange.contains(velocityY),
              preset == .materialImpact ? impactPlasticity?.isValid == true : impactPlasticity == nil,
              preset == .tensionCoupon ? tension?.isValid == true && velocityY == 0 : tension == nil,
              preset == .layeredSeam ? seam?.isValid == true && velocityY == 0 : seam == nil,
              !mirrored || preset == .block else {
            throw SceneFileError.invalidConfiguration
        }
    }

    public func makeSimulation() throws -> Simulation {
        try validate()
        return buildSimulation()
    }

    package func refinedImpact(columns: Int, rows: Int, stepScale: Double) throws -> Simulation {
        try validate()
        precondition(preset == .materialImpact)
        return Simulation.materialImpact(scene: self, columns: columns, rows: rows, stepScale: stepScale)
    }

    package func refinedTension(columns: Int, rows: Int, stepScale: Double) throws -> Simulation {
        try validate()
        precondition(preset == .tensionCoupon)
        return Simulation.tensionCoupon(scene: self, columns: columns, rows: rows, stepScale: stepScale)
    }

    package func refinedSeam(rows: Int, stepScale: Double) throws -> Simulation {
        try validate()
        precondition(preset == .layeredSeam)
        return Simulation.layeredSeam(scene: self, rows: rows, stepScale: stepScale)
    }

    func buildSimulation() -> Simulation {
        let mesh: Mesh
        switch preset {
        case .materialImpact: return Simulation.materialImpact(scene: self, columns: 48, rows: 8, stepScale: 1)
        case .bar: mesh = .bar(width: first.width, height: first.height!)
        case .ring: mesh = .ring(diameter: first.width, thickness: first.wallThickness!)
        case .block: mesh = .roundedBlock(width: first.width, height: first.height!, radius: first.cornerRadius!)
        case .twoBars: return Simulation.alignedBars(scene: self)
        case .puckStrip: return Simulation.puckAndStrip(scene: self)
        case .bondedBar: return Simulation.bondedBar(scene: self)
        case .tensionCoupon: return Simulation.tensionCoupon(scene: self, columns: 32, rows: 6, stepScale: 1)
        case .layeredSeam: return Simulation.layeredSeam(scene: self, rows: 8, stepScale: 1)
        }
        let body = Body(mesh: mesh, material: first.material, velocity: Point(speed, velocityY),
                        gap: gap, penalty: 2500, tilt: preset == .block ? (mirrored ? -Preset.blockTilt : Preset.blockTilt) : 0,
                        centerY: centerY)
        return Simulation(primary: body, gap: gap, stepScale: 1)
    }

    public func save(to url: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func open(_ url: URL) throws -> SceneConfiguration {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 64 * 1024 else { throw SceneFileError.invalidConfiguration }
        let version = try JSONDecoder().decode(SceneVersion.self, from: data).formatVersion
        guard version == 1 else { throw SceneFileError.unsupportedVersion(version) }
        let scene = try JSONDecoder().decode(Self.self, from: data)
        try scene.validate()
        return scene
    }
}

private struct SceneVersion: Decodable {
    let formatVersion: Int
}

private enum SceneFileError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Scene format version \(version) is unsupported."
        case .invalidConfiguration: "This scene has settings outside the supported preset ranges."
        }
    }
}
