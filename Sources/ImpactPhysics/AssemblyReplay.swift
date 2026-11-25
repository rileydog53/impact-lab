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
    /// Deepest absolute contact overlap so far (m).
    public let peakPenetrationDepth: Double
    public let links: [AssemblyLinkReading]
    public let contacts: [AssemblyReplayContact]
    public let fragments: [FragmentContactReading]

    var fieldPayloadBytes: Int {
        bodies.reduce(0) { total, item in
            total + (item.body.position.count + item.body.velocity.count) * MemoryLayout<Point>.stride
                + (item.strain.count + item.plasticStrain.count + item.damage.count) * MemoryLayout<Double>.stride
                + item.stress.count * MemoryLayout<AssemblyStress>.stride
        }
    }

    public var recoverableEnergy: Double {
        energies.elastic + energies.hardening + energies.contact + energies.connection + energies.cohesive
    }
    public var dissipatedEnergy: Double { energies.plastic + energies.fracture + energies.viscous }
}

public struct AssemblyReplayEvent: Identifiable, Sendable {
    public let label: String
    public let time: Double
    public let id: String
}

/// How densely a replay keeps calculated frames. Every frame in either mode is an accepted solver state; nothing
/// is interpolated. `.standard` is the original cadence (and what every legacy check records). `.smooth` keeps the
/// same scheduled frames bit for bit and adds extra calculated frames: an even fill between them, and a dense burst
/// starting at the exact step of every event and milestone, each under its own memory budget.
public enum ReplayDensity: Sendable {
    case standard, smooth
}

/// Records exact accepted states. Frame storage is bounded approximately by
/// mesh size. The trace and integration timestep are independent of that budget.
public struct AssemblyReplay: Sendable {
    /// Extra memory for the smooth fill and for event bursts, estimated per frame like the scheduled budget.
    public static let smoothFillBudget = 160 * 1024 * 1024
    public static let smoothBurstBudget = 96 * 1024 * 1024
    /// Frames in one burst after an event or milestone, spaced an eighth of the fill spacing apart.
    public static let framesPerBurst = 48

    private struct Focus: Sendable {
        let start, end: Double
        let every: Int
        var count = 0
    }

    public let density: ReplayDensity
    /// Calculated frames kept beyond the scheduled and event frames (smooth fill, bursts, slow-down focus).
    public private(set) var extraFrames = 0
    private var fillInterval = Double.infinity
    private var nextFill = Double.infinity
    private var burstInterval = 0.0
    private var burstLeft = 0
    private var burstCapacity = 0
    private var nextBurst = Double.infinity
    private var focusWindow: Focus?
    public private(set) var frames: [AssemblyReplayFrame] = []
    public private(set) var events: [AssemblyReplayEvent] = []
    /// Later material milestones (first crack, first delamination, first interior crack). Kept apart from `events`,
    /// which each sit exactly on a recorded frame and are part of the legacy-replay fingerprint; a milestone jumps to
    /// the nearest recorded frame and adds none, so scenes recorded before them replay exactly as before.
    public private(set) var milestones: [AssemblyReplayEvent] = []
    /// Events and milestones together, in time order, for the Events menu and the timeline ticks.
    public var timeline: [AssemblyReplayEvent] { (events + milestones).sorted { $0.time < $1.time } }
    /// Gauge readings on a fixed fine cadence, independent of the field frames. Field frames are
    /// thinned by a memory budget (fracture scenes keep fewer), but gauges cost a few bytes each, so
    /// window averages over gauges should not depend on how many field frames fit.
    public private(set) var gaugeTrack: [(time: Double, readings: [AssemblyGaugeReading])] = []
    private let gaugeInterval: Double
    private var nextGauge: Double
    package private(set) var fieldPayloadBytes = 0
    private var resumeCheckpoint = false
    private let interval: Double
    private var next: Double
    private var seen: Set<String> = []
    private var impulse: [SIMD2<Int>: Double] = [:]
    private var previous: [SIMD2<Int>: Double] = [:]
    private let fractureIndices: [Int]
    private let names: [String]
    private var observedFragmentCount = 0
    private var interiorWatch: [Int: InteriorCrackWatch] = [:]
    private var observedOpenFragments: Set<Int> = []

    public init(_ run: AssemblyRun, density: ReplayDensity = .standard) {
        let sim = run.simulation
        self.density = density
        let triangles = (0..<sim.bodyCount).reduce(0) { $0 + sim.body($1).mesh.elements.count }
        names = sim.scene.parts.map(\.name)
        fractureIndices = sim.scene.parts.indices.filter { sim.scene.parts[$0].fracture != nil }
        for index in fractureIndices {
            interiorWatch[index] = InteriorCrackWatch(part: sim.scene.parts[index], body: sim.body(index))
        }
        let estimate = max(1, triangles) * (fractureIndices.isEmpty ? 110 : 320)
        let target = min(160, max(4, (96 * 1024 * 1024) / estimate))
        interval = sim.scene.duration / Double(target)
        next = interval
        gaugeInterval = sim.scene.duration / 2000
        nextGauge = 0
        if density == .smooth {
            let fill = min(1200, max(target, Self.smoothFillBudget / estimate))
            if fill > target {
                fillInterval = sim.scene.duration / Double(fill)
                nextFill = fillInterval
            }
            burstInterval = max(sim.dt, min(fillInterval, interval) / 8)
            burstCapacity = min(600, Self.smoothBurstBudget / estimate)
        }
        append(run)
        sampleGauges(sim)
    }

    private mutating func sampleGauges(_ sim: AssemblySimulation) {
        guard let count = sim.scene.gauges?.count, count > 0, sim.time >= nextGauge else { return }
        gaugeTrack.append((sim.time, (0..<count).map(sim.gaugeReading)))
        nextGauge = (floor(sim.time / gaugeInterval) + 1) * gaugeInterval
    }

    public mutating func record(_ run: AssemblyRun) {
        let sim = run.simulation
        let live = sim.recordedNormalLoads
        for (pair, force) in previous { impulse[pair, default: 0] += 0.5 * sim.dt * force }
        for (pair, force) in live { impulse[pair, default: 0] += 0.5 * sim.dt * force }
        previous = live
        let priorCount = events.count
        let priorMilestones = milestones.count
        for pair in sim.activeContacts {
            let title = pair.x == pair.y ? "\(names[pair.x]) fragments" : "\(names[pair.x]) / \(names[pair.y])"
            add("First contact · \(title)", key: "pair-\(pair.x)-\(pair.y)", at: sim.time)
        }
        for index in fractureIndices {
            guard let state = sim.fractureReading(index) else { continue }
            if state.insertedEdges > 0 { add("First crack · \(names[index])", key: "crack-\(index)", at: sim.time, milestone: true) }
            if state.damagedEdges > 0 { add("First interface damage · \(names[index])", key: "damage-\(index)", at: sim.time) }
            if state.failedBondEdges > 0 { add("First delamination · \(names[index])", key: "delamination-\(index)", at: sim.time, milestone: true) }
            if var watch = interiorWatch[index], state.insertedEdges > watch.seen {
                watch.seen = state.insertedEdges
                if watch.containsInteriorFace(sim.crackFaces(index), mesh: sim.body(index).mesh) {
                    add("First interior crack (spall-type) · \(names[index])", key: "interior-\(index)", at: sim.time, milestone: true)
                    interiorWatch[index] = nil
                } else {
                    interiorWatch[index] = watch
                }
            }
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
        sampleGauges(sim)
        var appended = true
        if sim.time >= next {
            next = (floor(sim.time / interval) + 1) * interval
            if next <= sim.time { next += interval }
            append(run)
        } else if events.count != priorCount || run.finished {
            append(run)
        } else {
            appended = false
        }
        // Standard density with no focus stops here, so legacy recordings are unchanged.
        guard density == .smooth || focusWindow != nil else { return }
        let newEvent = events.count != priorCount || milestones.count != priorMilestones
        if wantsExtraFrame(at: sim.time, newEvent: newEvent), !appended {
            append(run)
            extraFrames += 1
        }
    }

    /// Advances the smooth-fill, burst and focus schedules for this accepted step and says whether it should be kept.
    /// Called once per step, whether or not the step was already kept, so the schedules don't depend on that.
    private mutating func wantsExtraFrame(at time: Double, newEvent: Bool) -> Bool {
        var wanted = false
        if density == .smooth {
            if newEvent, burstCapacity > 0 {
                burstLeft = min(Self.framesPerBurst, burstCapacity)
                nextBurst = time
            }
            if burstLeft > 0, time >= nextBurst {
                burstLeft -= 1
                burstCapacity -= 1
                nextBurst = time + burstInterval
                wanted = true
            }
            if time >= nextFill {
                nextFill = (floor(time / fillInterval) + 1) * fillInterval
                if nextFill <= time { nextFill += fillInterval }
                wanted = true
            }
        }
        if var window = focusWindow, time >= window.start, time <= window.end {
            if window.count % window.every == 0 { wanted = true }
            window.count += 1
            focusWindow = window
        }
        return wanted
    }

    /// Keeps every `every`-th accepted step from `start` to `end` as well, on top of the normal schedule. Used when a
    /// window is recalculated from a checkpoint to slow it down; the scheduled frames inside it are kept exactly as before.
    package mutating func focus(from start: Double, to end: Double, every: Int) {
        focusWindow = Focus(start: start, end: end, every: max(1, every))
    }

    public mutating func finish(_ run: AssemblyRun) {
        if frames.last?.time != run.simulation.time { append(run) }
    }

    // A cancellation checkpoint is available for inspection immediately.
    // Drop only this unscheduled frame on resume so output matches a full run.
    package mutating func checkpoint(_ run: AssemblyRun) {
        guard frames.last?.time != run.simulation.time else { return }
        append(run)
        resumeCheckpoint = true
    }

    package mutating func resume() {
        if resumeCheckpoint {
            fieldPayloadBytes -= frames.removeLast().fieldPayloadBytes
            resumeCheckpoint = false
        }
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

    private mutating func add(_ label: String, key: String, at time: Double, milestone: Bool = false) {
        guard seen.insert(key).inserted else { return }
        let event = AssemblyReplayEvent(label: label, time: time, id: key)
        if milestone { milestones.append(event) } else { events.append(event) }
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
            peakRelativePenetration: s.peakRelativePenetration,
            peakPenetrationDepth: s.peakPenetrationDepth, links: s.linkReadings,
            contacts: contacts, fragments: s.fragmentContacts)
        fieldPayloadBytes += frame.fieldPayloadBytes
        frames.append(frame)
    }
}


/// Recognises the first crack that opens inside a body rather than at its surface or on a bond between layers: the
/// spall-type crack of the layered target plan (a crack inside the material, opened by tension from reflected waves).
/// Operational definition, not a physical classification: a crack face counts when its midpoint, in the body's
/// reference shape, is at least two element sizes from the original outer boundary and does not lie on a bond line.
struct InteriorCrackWatch: Sendable {
    private let boundary: [(Point, Point)]
    private let bondLines: [Double]
    private let margin: Double
    var seen = 0

    init(part: AssemblyPart, body: Body) {
        let mesh = body.mesh
        boundary = mesh.boundary.map { (mesh.reference[$0.a], mesh.reference[$0.b]) }
        let area = mesh.elements.reduce(0) { $0 + $1.area } / Double(max(1, mesh.elements.count))
        margin = 2 * (2 * area).squareRoot()
        bondLines = part.bondedLayer.map { layer in layer.regions.map { ($0.fraction - 0.5) * part.size.x } } ?? []
    }

    func containsInteriorFace(_ faces: [CrackFace], mesh: Mesh) -> Bool {
        faces.contains { face in
            let a = mesh.reference[face.first.a], b = mesh.reference[face.first.b]
            let m = (a + b) / 2
            let scale = max(1e-12, simd_length(b - a))
            if abs(a.x - b.x) < 1e-9 * scale, bondLines.contains(where: { abs($0 - m.x) < 1e-9 * scale + 1e-12 }) { return false }
            return boundary.allSatisfy { p, q in
                let d = q - p
                let t = min(1, max(0, simd_dot(m - p, d) / max(simd_length_squared(d), 1e-30)))
                return simd_length(m - p - t * d) >= margin
            }
        }
    }
}
