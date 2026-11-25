import Foundation
import ImpactPhysics

/// Smooth replay and slow-motion clips keep only calculated frames:
/// 1. A smooth recording keeps every standard frame bit for bit, adds more frames, and leaves the physics untouched.
/// 2. Every milestone (first crack and the like) lands exactly on a recorded frame.
/// 3. A window recalculated from a checkpoint reproduces the original frames bit for bit and adds many more.
func smoothReplayCheck() throws {
    let scene = AssemblyScene.bendingFractureExample()

    var plainRun = try AssemblyRun(scene)
    var plain = AssemblyReplay(plainRun)
    while plainRun.step(recording: &plain) {}
    plain.finish(plainRun)

    var run = try AssemblyRun(scene)
    var smooth = AssemblyReplay(run, density: .smooth)
    var rewind = SlowMotionRewind(run, replay: smooth)
    while run.step(recording: &smooth) { rewind.capture(run, smooth) }
    smooth.finish(run)
    require(run.finished && run.simulation.failure == nil, run.simulation.failure ?? "Smooth replay run incomplete")

    require(zip(smooth.frames, smooth.frames.dropFirst()).allSatisfy { $0.time < $1.time },
            "Smooth frame times not strictly increasing")
    require(smooth.frames.count > plain.frames.count && smooth.extraFrames == smooth.frames.count - plain.frames.count,
            "Smooth recording added no frames, or counted them wrongly (\(smooth.frames.count) vs \(plain.frames.count))")
    for frame in plain.frames {
        let match = smooth.frames[AssemblyReplay.nearest(smooth.frames, to: frame.time)]
        require(match.time == frame.time && match.bitFingerprint == frame.bitFingerprint,
                "Smooth recording changed the standard frame at t = \(frame.time)")
    }
    require(smooth.events.map(\.time) == plain.events.map(\.time) && smooth.milestones.map(\.time) == plain.milestones.map(\.time),
            "Smooth recording changed event or milestone times")
    require(run.simulation.energies.total.bitPattern == plainRun.simulation.energies.total.bitPattern
            && run.simulation.energies.fracture.bitPattern == plainRun.simulation.energies.fracture.bitPattern,
            "Recording density changed the physics")
    require(smooth.timeline.allSatisfy { smooth.frames[smooth.index(at: $0.time)].time == $0.time },
            "An event or milestone has no frame of its own in the smooth recording")

    require(rewind.count >= 2, "Too few slow-motion checkpoints (\(rewind.count))")
    let moment = smooth.milestones.first?.time ?? smooth.timeline.first?.time ?? 0.5 * scene.duration
    let span = scene.duration / 40
    let end = min(smooth.frames.last!.time, max(0, moment - 0.25 * span) + span)
    let start = max(0, end - span)
    guard let clip = rewind.clip(from: start, to: end, original: smooth.frames, cancelled: { false }) else {
        require(false, "Slow-motion clip could not be recalculated")
        return
    }
    let inside = smooth.frames.filter { $0.time >= start && $0.time <= end }.count
    require(clip.shared == inside && clip.isExact,
            "Recalculated clip reproduced \(clip.reproduced) of \(clip.shared) shared frames (\(inside) original frames in the window)")
    require(clip.frames.count > inside && zip(clip.frames, clip.frames.dropFirst()).allSatisfy { $0.time < $1.time },
            "Slow-motion clip is not denser than the original (\(clip.frames.count) vs \(inside)) or out of order")
    print("Smooth replay: \(plain.frames.count) standard frames kept bit for bit among \(smooth.frames.count) smooth frames; "
          + "\(rewind.count) checkpoints; clip of \(clip.frames.count) frames every \(clip.stride) steps over "
          + "\(String(format: "%.3g", 1000 * (clip.end - clip.start))) ms reproduced all \(clip.shared) shared frames.")
}
