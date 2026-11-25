// Slow motion from calculated frames only.
//
// A run keeps a handful of solver checkpoints (complete copies of the solver and its recorder; every part of the
// solver state is a value type, so a copy is an exact snapshot). To slow a moment down, the window around it is
// recalculated from the checkpoint just before it while keeping every n-th accepted step. The solver is repeatable,
// so the recalculation passes through the original run's states exactly; the clip checks this by comparing, bit for
// bit, every frame it shares with the original replay. Nothing is interpolated.

extension AssemblyReplay {
    /// Nearest frame to `time` in a time-ordered list (the same rule as `index(at:)`).
    public static func nearest(_ frames: [AssemblyReplayFrame], to time: Double) -> Int {
        guard !frames.isEmpty else { return 0 }
        var lower = 0, upper = frames.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if frames[middle].time < time { lower = middle + 1 }
            else { upper = middle }
        }
        if lower > 0, abs(frames[lower - 1].time - time) < abs(frames[lower].time - time) { return lower - 1 }
        return lower
    }
}

extension AssemblyReplayFrame {
    /// Bit patterns of the recorded state rolled into one number (FNV-1a over the stored values), so two frames can
    /// be compared exactly. Covers time, energies, geometry, mesh, every field, cracks, contacts and gauges.
    package var bitFingerprint: UInt64 {
        var hash: UInt64 = 14695981039346656037
        func add(_ value: Double) { hash = (hash ^ value.bitPattern) &* 1099511628211 }
        func addIndex(_ value: Int) { hash = (hash ^ UInt64(bitPattern: Int64(value))) &* 1099511628211 }
        let e = energies
        for value in [time, e.kinetic, e.elastic, e.hardening, e.plastic, e.fracture, e.cohesive, e.contact,
                      e.connection, e.gravitational, e.viscous, angularMomentum, peakRelativePenetration] { add(value) }
        for state in bodies {
            for p in state.body.position { add(p.x); add(p.y) }
            for v in state.body.velocity { add(v.x); add(v.y) }
            for t in state.body.mesh.elements { addIndex(t.a); addIndex(t.b); addIndex(t.c) }
            for value in state.strain { add(value) }
            for value in state.plasticStrain { add(value) }
            for value in state.damage { add(value) }
            for s in state.stress { add(s.equivalent); add(s.pressure); add(s.maximumPrincipal); add(s.minimumPrincipal) }
            for face in state.cracks {
                addIndex(face.first.a); addIndex(face.first.b); addIndex(face.second.a); addIndex(face.second.b)
                add(face.damage); add(face.separation)
            }
        }
        for c in contacts { addIndex(c.pair.x); addIndex(c.pair.y); add(c.force); add(c.impulse) }
        for g in gauges { add(g.strain); add(g.equivalentStress) }
        return hash
    }
}

/// A recalculated stretch of a run, kept at every `stride`-th solver step.
public struct SlowMotionClip: Sendable {
    public let frames: [AssemblyReplayFrame]
    public let start, end: Double
    /// Every `stride`-th accepted solver step inside the window is a frame.
    public let stride: Int
    public let dt: Double
    /// Solver steps recalculated, including the lead-in from the checkpoint.
    public let steps: Int
    /// Frames this clip shares with the original replay (same solver step), and how many of them came out bit for bit
    /// identical. They should always be equal; anything else means the recalculation did not reproduce the run.
    public let shared, reproduced: Int

    public var isExact: Bool { shared > 0 && shared == reproduced }
    public func index(at time: Double) -> Int { AssemblyReplay.nearest(frames, to: time) }
}

/// Solver checkpoints taken while a run is calculated, for recalculating a window of it later.
public struct SlowMotionRewind: Sendable {
    /// Memory for checkpoints, estimated from the solver's own state payload.
    public static let budget = 128 * 1024 * 1024
    public static let maximumCheckpoints = 24
    /// Most frames one clip keeps; the step stride grows for longer windows.
    public static let maximumClipFrames = 600

    private struct Checkpoint: Sendable {
        let run: AssemblyRun
        let replay: AssemblyReplay
    }

    private var saved: [Checkpoint]
    private let interval: Double
    private var next: Double
    private let capacity: Int

    public var count: Int { saved.count }
    /// Earliest time a window can start (the first checkpoint).
    public var earliest: Double { saved.first?.run.simulation.time ?? 0 }

    public init(_ run: AssemblyRun, replay: AssemblyReplay) {
        let bytes = max(1, run.simulation.statePayload.bytes)
        capacity = max(2, min(Self.maximumCheckpoints, Self.budget / bytes))
        interval = run.simulation.scene.duration / Double(capacity)
        let time = run.simulation.time
        next = (time / interval).rounded(.down) * interval + interval
        saved = [Checkpoint(run: run, replay: replay)]
    }

    /// Call after every accepted, recorded step; keeps a copy when the next checkpoint time is reached.
    package mutating func capture(_ run: AssemblyRun, _ replay: AssemblyReplay) {
        let time = run.simulation.time
        guard time >= next else { return }
        next = (time / interval).rounded(.down) * interval + interval
        if next <= time { next += interval }
        guard saved.count < capacity else { return }
        saved.append(Checkpoint(run: run, replay: replay))
    }

    /// Recalculates `start...end` from the last checkpoint at or before `start`, keeping every n-th step so the clip
    /// has at most `maximumFrames` frames, and checks it against `original`. Returns nil when cancelled or when no
    /// checkpoint precedes `start`.
    public func clip(from start: Double, to end: Double, original: [AssemblyReplayFrame],
                     maximumFrames: Int = SlowMotionRewind.maximumClipFrames,
                     cancelled: () -> Bool) -> SlowMotionClip? {
        guard end > start, let base = saved.last(where: { $0.run.simulation.time <= start }) else { return nil }
        var run = base.run
        var replay = base.replay
        let dt = run.simulation.dt
        let window = Int(((end - start) / dt).rounded(.up)) + 1
        let stride = max(1, (window + max(1, maximumFrames) - 1) / max(1, maximumFrames))
        replay.focus(from: start, to: end, every: stride)
        var steps = 0
        while run.simulation.time < end, run.step(recording: &replay) {
            steps += 1
            if steps % 64 == 0, cancelled() { return nil }
        }
        if cancelled() { return nil }
        let frames = replay.frames.filter { $0.time >= start && $0.time <= end }
        guard frames.count > 1 else { return nil }
        var shared = 0, reproduced = 0
        for frame in original where frame.time >= start && frame.time <= end {
            let match = frames[AssemblyReplay.nearest(frames, to: frame.time)]
            guard match.time == frame.time else { continue }
            shared += 1
            if match.bitFingerprint == frame.bitFingerprint { reproduced += 1 }
        }
        return SlowMotionClip(frames: frames, start: frames[0].time, end: frames[frames.count - 1].time,
                              stride: stride, dt: dt, steps: steps, shared: shared, reproduced: reproduced)
    }
}
