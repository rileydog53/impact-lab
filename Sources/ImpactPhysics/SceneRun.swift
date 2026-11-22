public struct TraceSample: Equatable, Sendable {
    public let time: Double
    public let values: Point
}

public struct SceneTrace: Sendable {
    public struct Match: Sendable {
        public let time: Double
        public let reference, current: Point
    }

    public let preset: Preset
    public let samples: [TraceSample]
    public let couponResponse: CouponResponse?
    public let residualLength: Double?

    public func matching(_ reference: SceneTrace) -> [Match] {
        guard preset == reference.preset else { return [] }
        return zip(reference.samples, samples).map {
            // Both traces record the same simulation-time grid.
            Match(time: $0.time, reference: $0.values, current: $1.values)
        }
    }
}

public struct SceneRun {
    public static let sampleInterval = 0.00025
    public let configuration: SceneConfiguration
    public let horizon: Double
    public private(set) var simulation: Simulation
    public private(set) var samples: [TraceSample]
    public var finished: Bool { simulation.time >= horizon }
    public var trace: SceneTrace {
        SceneTrace(preset: configuration.preset, samples: samples,
                   couponResponse: configuration.tension?.response, residualLength: residualLength)
    }
    public var residualLength: Double? {
        guard configuration.tension != nil, finished, simulation.failure == nil else { return nil }
        let window = TensionLoad.measurementTransits * configuration.first.width / configuration.first.material.waveSpeed
        let unloaded = samples.reversed().prefix { $0.time >= horizon - window }
        guard !unloaded.isEmpty else { return nil }
        return configuration.first.width + unloaded.reduce(0) { $0 + $1.values.x } / (1000 * Double(unloaded.count))
    }

    public init(_ configuration: SceneConfiguration) throws {
        try self.init(configuration, simulation: configuration.makeSimulation())
    }

    package init(_ configuration: SceneConfiguration, simulation: Simulation) {
        self.configuration = configuration
        self.simulation = simulation
        horizon = configuration.duration
        samples = [TraceSample(time: 0, values: Self.values(in: simulation, configuration: configuration))]
    }

    @discardableResult public mutating func step() -> Bool {
        guard !finished else { return false }
        let timeBefore = simulation.time
        let nextSample = Double(samples.count) * Self.sampleInterval
        let crossesSample = timeBefore + simulation.dt >= nextSample && nextSample <= horizon
        let before = crossesSample ? Self.values(in: simulation, configuration: configuration) : .zero
        guard simulation.step() else { return false }
        if crossesSample {
            let after = Self.values(in: simulation, configuration: configuration)
            var time = nextSample
            while time <= min(simulation.time, horizon) {
                let fraction = (time - timeBefore) / (simulation.time - timeBefore)
                samples.append(TraceSample(time: time, values: before + fraction * (after - before)))
                time = Double(samples.count) * Self.sampleInterval
            }
        }
        return true
    }

    private static func values(in simulation: Simulation, configuration: SceneConfiguration) -> Point {
        switch configuration.preset {
        case .bar, .bondedBar: Point(simulation.probeStrain * 100, 0)
        case .ring: simulation.body.diameters * 1000
        case .block: Point(simulation.body.orientation * 180 / .pi, 0)
        case .twoBars, .puckStrip: Point(simulation.body.centerVelocity.x, simulation.secondBody!.centerVelocity.x)
        case .tensionCoupon:
            Point(1000 * ((simulation.gaugeLength ?? configuration.first.width) - configuration.first.width),
                  100 * simulation.meanPlasticStrain)
        }
    }
}
