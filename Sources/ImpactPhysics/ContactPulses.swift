import Foundation

// Reporting only. Nothing here feeds back into contact forces or the timestep.
//
// The raw per-step contact load of penalty contact is not a physical result:
// its peak scales with the penalty stiffness and the mesh. The contact
// verification gate (23 November 2026, soft and metal) found that the
// impulse of each contact pulse, and force averaged over a stated window of
// roughly ten element wave-transit times or more, do not depend on penalty or
// mesh. Those numbers are empirical guidelines from one fixture, not
// universal constants, so every window and gap below is stated explicitly.

/// Settings for turning a per-step load history into contact pulses.
public struct ContactPulseSettings: Codable, Equatable, Sendable {
    /// Two loaded spans separated by less than this time (s) are one pulse.
    /// Merges the on/off chatter of node-scale penalty contact.
    public var mergeGap: Double
    /// Pulses whose impulse is below this fraction of the largest pulse are
    /// counted as minor touches instead of being listed as pulses.
    public var minorFraction: Double
    /// Trailing moving-average windows (s) for the averaged contact force.
    public var windows: [Double]

    public init(mergeGap: Double, minorFraction: Double = 0.01, windows: [Double]) {
        self.mergeGap = mergeGap
        self.minorFraction = minorFraction
        self.windows = windows
    }

    /// Guideline settings from an element wave-transit time `transit` (s):
    /// merge gaps under 5 transit times, average over 10 transit times rounded
    /// up to a 1-2-5 value, and also report half and double that window so the
    /// window dependence stays visible. Use the same transit time for every
    /// case that will be compared, so the windows are common physical times.
    public static func guideline(transit: Double) -> Self {
        let window = roundedUp125(10 * transit)
        return Self(mergeGap: 5 * transit, windows: [window / 2, window, 2 * window])
    }

    static func roundedUp125(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return value }
        let decade = pow(10, floor(log10(value)))
        for step in [1.0, 2, 5, 10] where step * decade >= value * (1 - 1e-12) { return step * decade }
        return 10 * decade
    }
}

public struct ContactPulse: Sendable, Equatable {
    /// First and last step time with a positive load (s).
    public internal(set) var start, end: Double
    /// Integrated normal load over the pulse (N·s/m). Window-free.
    public internal(set) var impulse = 0.0
    /// Largest single-step load (N/m). A numerical diagnostic, not a result.
    public internal(set) var rawPeak = 0.0
    /// Peak of each trailing moving average while the pulse is open (N/m),
    /// one entry per window in the settings.
    public internal(set) var windowPeaks: [Double]
    /// Solver on/off contact episodes merged into this pulse.
    public internal(set) var episodes = 0

    public var duration: Double { end - start }
    /// Impulse divided by duration (N/m); zero for a single-step touch.
    public var meanForce: Double { duration > 0 ? impulse / duration : 0 }
}

public struct ContactPulseReport: Sendable {
    public let settings: ContactPulseSettings
    /// Pulses at or above the minor fraction of the largest pulse.
    public let pulses: [ContactPulse]
    /// Number and total impulse of pulses below the minor fraction.
    public let minorCount: Int
    public let minorImpulse: Double
    /// Raw solver on/off episodes before merging.
    public let rawEpisodes: Int
    /// Peak of each moving average over the whole run (N/m).
    public let windowPeaks: [Double]
    /// Largest single-step load over the whole run (N/m). Diagnostic only.
    public let rawPeak: Double
    public let totalImpulse: Double
}

/// Accumulates one contact pair's load step by step.
public struct ContactPulseTracker: Sendable {
    public let settings: ContactPulseSettings
    private var all: [ContactPulse] = []
    private var open = false
    private var previousLoad = 0.0
    private var rawEpisodes = 0
    private var totalImpulse = 0.0
    private var rawPeak = 0.0
    private var windowPeaks: [Double]
    // Cumulative impulse history for the moving averages, trimmed to the
    // longest window.
    private var times: [Double] = [0], cumulative: [Double] = [0]
    private var head = 0

    public init(_ settings: ContactPulseSettings) {
        self.settings = settings
        windowPeaks = Array(repeating: 0, count: settings.windows.count)
    }

    /// Record the load after an accepted step that ended at `time` and lasted `dt`.
    public mutating func record(time: Double, dt: Double, load: Double) {
        let increment = 0.5 * dt * (previousLoad + load)
        totalImpulse += increment
        times.append(time)
        cumulative.append(totalImpulse)
        let longest = settings.windows.max() ?? 0
        while head + 1 < times.count && times[head + 1] <= time - longest { head += 1 }
        if head > 4096 && head * 2 > times.count {
            times.removeFirst(head); cumulative.removeFirst(head); head = 0
        }
        let averages = settings.windows.map { window in
            window > 0 ? (totalImpulse - cumulativeImpulse(at: time - window)) / window : load
        }
        for i in averages.indices { windowPeaks[i] = max(windowPeaks[i], averages[i]) }
        rawPeak = max(rawPeak, load)

        if load > 0 {
            if previousLoad <= 0 { rawEpisodes += 1 }
            if all.isEmpty || time - all[all.count - 1].end > settings.mergeGap {
                all.append(ContactPulse(start: time, end: time, windowPeaks: Array(repeating: 0, count: averages.count)))
            }
            open = true
            let i = all.count - 1
            if previousLoad <= 0 { all[i].episodes += 1 }
            all[i].end = time
            all[i].rawPeak = max(all[i].rawPeak, load)
        } else if open, let last = all.last, time - last.end > settings.mergeGap {
            open = false
        }
        if open, !all.isEmpty {
            let i = all.count - 1
            if load > 0 || previousLoad > 0 { all[i].impulse += increment }
            for k in averages.indices { all[i].windowPeaks[k] = max(all[i].windowPeaks[k], averages[k]) }
        }
        previousLoad = load
    }

    private func cumulativeImpulse(at t: Double) -> Double {
        if t <= times[head] { return head == 0 && t <= times[0] ? 0 : cumulative[head] }
        var low = head, high = times.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if times[mid] <= t { low = mid } else { high = mid }
        }
        let span = times[high] - times[low]
        let f = span > 0 ? (t - times[low]) / span : 1
        return cumulative[low] + f * (cumulative[high] - cumulative[low])
    }

    public var report: ContactPulseReport {
        let largest = all.map(\.impulse).max() ?? 0
        let major = all.filter { $0.impulse >= settings.minorFraction * largest && $0.impulse > 0 }
        let minor = all.filter { !($0.impulse >= settings.minorFraction * largest && $0.impulse > 0) }
        return ContactPulseReport(settings: settings, pulses: major, minorCount: minor.count,
                                  minorImpulse: minor.map(\.impulse).reduce(0, +), rawEpisodes: rawEpisodes,
                                  windowPeaks: windowPeaks, rawPeak: rawPeak, totalImpulse: totalImpulse)
    }

    /// Current trailing averages, one per window (N/m).
    public func averages(at time: Double) -> [Double] {
        settings.windows.map { $0 > 0 ? (totalImpulse - cumulativeImpulse(at: time - $0)) / $0 : previousLoad }
    }
}

extension AssemblySimulation {
    /// Longest element wave-transit time (s) among the given bodies:
    /// characteristic element size sqrt(2 × mean triangle area) over the
    /// body's longitudinal wave speed. Used only to choose reporting windows.
    public func elementTransitTime(bodies: [Int]) -> Double {
        bodies.map { index in
            let body = self.body(index)
            let elements = body.mesh.elements
            let area = elements.map(\.area).reduce(0, +) / Double(max(1, elements.count))
            return sqrt(2 * area) / body.material.waveSpeed
        }.max() ?? 0
    }
}
