import simd

public struct AssemblyStress: Sendable {
    public let equivalent, pressure, maximumPrincipal, minimumPrincipal: Double
}

public struct AssemblyReplayBody: Sendable {
    public let body: Body
    public let strain, plasticStrain, damage: [Double]
    public let stress: [AssemblyStress]
    public let cracks: [CrackFace]
    public let fracture: MaterialFractureReading?
    public let pieces: [MaterialPiece]
}

public struct AssemblyReplayContact: Sendable {
    public let pair: SIMD2<Int>
    public let force, impulse: Double
    public let position: Point?
}

public struct AssemblyReplayFrame: Sendable {
    public let time: Double
    public let bodies: [AssemblyReplayBody]
    public let gauges: [AssemblyGaugeReading]
    public let energies: AssemblyEnergy
    public let relativeMotion, momentum: Point
    public let angularMomentum, peakRelativePenetration: Double
    public let links: [AssemblyLinkReading]
    public let contacts: [AssemblyReplayContact]
    public let fragments: [FragmentContactReading]

    public var recoverableEnergy: Double {
        energies.elastic + energies.hardening + energies.contact + energies.connection + energies.cohesive
    }
    public var dissipatedEnergy: Double { energies.plastic + energies.fracture }
}

public struct AssemblyReplayEvent: Identifiable, Sendable {
    public let label: String
    public let time: Double
    public let id: String
}

/// Records exact accepted states. Frame storage is bounded approximately by
/// mesh size. The trace and integration timestep are independent of that budget.
public struct AssemblyReplay: Sendable {
    public private(set) var frames: [AssemblyReplayFrame] = []
    public private(set) var events: [AssemblyReplayEvent] = []
    private let interval: Double
    private var next: Double
    private var seen: Set<String> = []
    private var impulse: [SIMD2<Int>: Double] = [:]
    private var previous: [SIMD2<Int>: Double] = [:]
    private let fractureIndices: [Int]
    private let names: [String]
    private var observedFragmentCount = 0
    private var observedOpenFragments: Set<Int> = []

    public init(_ run: AssemblyRun) {
        let sim = run.simulation
        let triangles = (0..<sim.bodyCount).reduce(0) { $0 + sim.body($1).mesh.elements.count }
        names = sim.scene.parts.map(\.name)
        fractureIndices = sim.scene.parts.indices.filter { sim.scene.parts[$0].fracture != nil }
        let estimate = max(1, triangles) * (fractureIndices.isEmpty ? 110 : 320)
        let target = min(160, max(4, (96 * 1024 * 1024) / estimate))
        interval = sim.scene.duration / Double(target)
        next = interval
        append(run)
    }

    public mutating func record(_ run: AssemblyRun) {
        let sim = run.simulation
        let live = sim.recordedNormalLoads
        for (pair, force) in previous { impulse[pair, default: 0] += 0.5 * sim.dt * force }
        for (pair, force) in live { impulse[pair, default: 0] += 0.5 * sim.dt * force }
        previous = live
        let priorCount = events.count
        for pair in sim.activeContacts {
            let title = pair.x == pair.y ? "\(names[pair.x]) fragments" : "\(names[pair.x]) / \(names[pair.y])"
            add("First contact · \(title)", key: "pair-\(pair.x)-\(pair.y)", at: sim.time)
        }
        for index in fractureIndices {
            guard let state = sim.fractureReading(index) else { continue }
            if state.damagedEdges > 0 { add("First interface damage · \(names[index])", key: "damage-\(index)", at: sim.time) }
            if state.failedEdges > 0 { add("First failed face · \(names[index])", key: "face-\(index)", at: sim.time) }
            if state.pieces > 1 { add("First detached piece · \(names[index])", key: "piece-\(index)", at: sim.time) }
        }
        if !fractureIndices.isEmpty {
            observedOpenFragments.formUnion(observedFragmentCount..<sim.fragmentContacts.count)
            observedFragmentCount = sim.fragmentContacts.count
            let open = observedOpenFragments
            observedOpenFragments = open.filter { index in
                let event = sim.fragmentContacts[index]
                if event.firstExposedTime == sim.time {
                    let pair = event.parts
                    let title = pair.x == pair.y ? "\(names[pair.x]) fragments" : "\(names[pair.x]) / \(names[pair.y])"
                    add("New-face contact · \(title)", key: "new-\(pair.x)-\(pair.y)", at: sim.time)
                    return false
                }
                return event.lastTime == sim.time && !event.onExposedFace
            }
        }
        if sim.time >= next {
            next = (floor(sim.time / interval) + 1) * interval
            if next <= sim.time { next += interval }
            append(run)
        } else if events.count != priorCount || run.finished {
            append(run)
        }
    }

    public mutating func finish(_ run: AssemblyRun) {
        if frames.last?.time != run.simulation.time { append(run) }
    }

    /// Nearest recorded frame, used for time selection only.
    public func index(at time: Double) -> Int {
        var lower = 0, upper = frames.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if frames[middle].time < time { lower = middle + 1 }
            else { upper = middle }
        }
        if lower > 0, abs(frames[lower - 1].time - time) < abs(frames[lower].time - time) { return lower - 1 }
        return lower
    }

    private mutating func add(_ label: String, key: String, at time: Double) {
        if seen.insert(key).inserted { events.append(AssemblyReplayEvent(label: label, time: time, id: key)) }
    }

    private mutating func append(_ run: AssemblyRun) {
        let s = run.simulation
        let pairs = Set(impulse.keys).union(s.activeContacts)
        let contacts = pairs.sorted { ($0.x, $0.y) < ($1.x, $1.y) }.map {
            AssemblyReplayContact(pair: $0, force: s.recordedNormalLoads[$0] ?? 0,
                                  impulse: impulse[$0] ?? 0, position: s.recordedContactPositions[$0]?.position)
        }
        let frame = AssemblyReplayFrame(time: s.time, bodies: (0..<s.bodyCount).map(s.replayBody),
            gauges: (s.scene.gauges ?? []).indices.map(s.gaugeReading), energies: s.energies,
            relativeMotion: run.relativeMotion, momentum: s.momentum, angularMomentum: s.angularMomentum,
            peakRelativePenetration: s.peakRelativePenetration, links: s.linkReadings,
            contacts: contacts, fragments: s.fragmentContacts)
        frames.append(frame)
    }
}
