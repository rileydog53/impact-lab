public struct TraceSample: Equatable, Sendable {
    public let time: Double
    public let values: Point
    public let plasticDissipation: Double
    public let connectionEnergy: Double
    public let materialFracture, crackLength, crackSeparation, peakStress: Double

    public init(time: Double, values: Point, plasticDissipation: Double, connectionEnergy: Double = 0,
                materialFracture: Double = 0, crackLength: Double = 0, crackSeparation: Double = 0,
                peakStress: Double = 0) {
        self.time = time
        self.values = values
        self.plasticDissipation = plasticDissipation
        self.connectionEnergy = connectionEnergy
        self.materialFracture = materialFracture
        self.crackLength = crackLength
        self.crackSeparation = crackSeparation
        self.peakStress = peakStress
    }

    func interpolated(to next: Self, at time: Double) -> Self {
        if time == next.time { return next }
        let fraction = (time - self.time) / (next.time - self.time)
        func blend(_ a: Double, _ b: Double) -> Double { a + fraction * (b - a) }
        return Self(time: time, values: values + fraction * (next.values - values),
                    plasticDissipation: blend(plasticDissipation, next.plasticDissipation),
                    connectionEnergy: blend(connectionEnergy, next.connectionEnergy),
                    materialFracture: blend(materialFracture, next.materialFracture),
                    crackLength: crackLength, // Topology changes discretely.
                    crackSeparation: blend(crackSeparation, next.crackSeparation),
                    peakStress: blend(peakStress, next.peakStress))
    }
}

public struct SceneTrace: Sendable {
    public struct Match: Sendable {
        public let time: Double
        public let referenceSample, currentSample: TraceSample
        public var reference: Point { referenceSample.values }
        public var current: Point { currentSample.values }
    }

    public let preset: Preset
    public let samples: [TraceSample]
    public let materialResponse: CouponResponse?
    public var couponResponse: CouponResponse? { preset == .tensionCoupon ? materialResponse : nil }
    public let seamResponse: SeamResponse?
    public let hasBackstop: Bool
    public let residualLength: Double?

    public func matching(_ reference: SceneTrace) -> [Match] {
        guard preset == reference.preset else { return [] }
        return Self.matching(reference.samples, samples)
    }

    public static func matching(_ reference: [TraceSample], _ current: [TraceSample]) -> [Match] {
        guard let referenceStart = reference.first?.time, let referenceEnd = reference.last?.time,
              let currentStart = current.first?.time, let currentEnd = current.last?.time else { return [] }
        let start = max(referenceStart, currentStart), end = min(referenceEnd, currentEnd)
        let times = Set(reference.map(\.time) + current.map(\.time)).sorted()
        var i = 0, j = 0
        func sample(_ values: [TraceSample], index: inout Int, at time: Double) -> TraceSample {
            while index + 1 < values.count && values[index + 1].time <= time { index += 1 }
            if values[index].time == time { return values[index] }
            return values[index].interpolated(to: values[index + 1], at: time)
        }
        return times.filter { start <= $0 && $0 <= end }.map { time in
            Match(time: time, referenceSample: sample(reference, index: &i, at: time),
                  currentSample: sample(current, index: &j, at: time))
        }
    }
}

public struct SceneRun {
    public static let sampleInterval = 0.00025
    public let configuration: SceneConfiguration
    public let horizon: Double
    public private(set) var simulation: Simulation
    public private(set) var samples: [TraceSample]
    private let impactGauge: EndGauge?
    public var gaugeLength: Double? { impactGauge?.length(of: simulation.body.position) ?? simulation.gaugeLength }
    public var finished: Bool { simulation.time >= horizon }
    public var trace: SceneTrace {
        SceneTrace(preset: configuration.preset, samples: samples,
                   materialResponse: configuration.impactPlasticity?.response ?? configuration.tension?.response,
                   seamResponse: configuration.seam?.response, hasBackstop: configuration.backstopGap != nil,
                   residualLength: residualLength)
    }
    public var residualLength: Double? {
        guard configuration.tension != nil || impactGauge != nil, finished, simulation.failure == nil else { return nil }
        let window = TensionLoad.measurementTransits * configuration.first.width / configuration.first.material.waveSpeed
        if impactGauge != nil {
            guard let lastContact = simulation.lastWallContactTime, lastContact <= horizon - window else { return nil }
        }
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
        let gauge = configuration.preset == .materialImpact ?
            EndGauge(body: simulation.body, length: configuration.first.width, height: configuration.first.height!) : nil
        impactGauge = gauge
        samples = [TraceSample(time: 0, values: Self.values(in: simulation, configuration: configuration, impactGauge: gauge),
                               plasticDissipation: 0)]
    }

    @discardableResult public mutating func step() -> Bool {
        guard !finished else { return false }
        let timeBefore = simulation.time
        let nextSample = Double(samples.count) * Self.sampleInterval
        let crossesSample = timeBefore + simulation.dt >= nextSample && nextSample <= horizon
        var before = crossesSample ? Self.values(in: simulation, configuration: configuration, impactGauge: impactGauge) : .zero
        let plasticBefore = crossesSample ? simulation.plasticDissipation : 0
        guard simulation.step() else { return false }
        if crossesSample {
            var after = Self.values(in: simulation, configuration: configuration, impactGauge: impactGauge)
            if configuration.preset == .offAxisImpact {
                // Match the nearest equivalent angle before interpolating this sample.
                let previous = samples.last!.values.x
                before.x = previous + (before.x - previous).remainder(dividingBy: 360)
                after.x = before.x + (after.x - before.x).remainder(dividingBy: 360)
            }
            var time = nextSample
            while time <= min(simulation.time, horizon) {
                let fraction = (time - timeBefore) / (simulation.time - timeBefore)
                let plastic = plasticBefore + fraction * (simulation.plasticDissipation - plasticBefore)
                samples.append(TraceSample(time: time, values: before + fraction * (after - before),
                                           plasticDissipation: plastic))
                time = Double(samples.count) * Self.sampleInterval
            }
        }
        return true
    }

    private static func values(in simulation: Simulation, configuration: SceneConfiguration, impactGauge: EndGauge?) -> Point {
        switch configuration.preset {
        case .bar, .bondedBar: Point(simulation.probeStrain * 100, 0)
        case .ring: simulation.body.diameters * 1000
        case .block: Point(simulation.body.orientation * 180 / .pi, 0)
        case .twoBars, .puckStrip: Point(simulation.body.centerVelocity.x, simulation.secondBody!.centerVelocity.x)
        case .tensionCoupon, .materialImpact:
            Point(1000 * ((impactGauge?.length(of: simulation.body.position) ?? simulation.gaugeLength!) - configuration.first.width),
                  100 * simulation.meanPlasticStrain)
        case .offAxisImpact:
            Point(simulation.thirdBody!.orientation * 180 / .pi, simulation.receiverBody!.centerVelocity.x)
        case .layeredSeam, .layeredImpact:
            Point(1000 * (simulation.seamReadings?.opening ?? 0), simulation.seamReadings?.dissipatedPerArea ?? 0)
        }
    }
}
