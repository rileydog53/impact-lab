import simd

/// When two bodies will first touch if each keeps its starting speed and direction. A planning aid shown
/// before a run; it reads the starting state only and never changes the calculation. It ignores gravity,
/// springs, grips and bending, so it is an estimate ("about").
public struct ContactForecast: Equatable, Sendable {
    public let first: Int
    public let second: Int
    /// Seconds from the start of the run.
    public let time: Double
    /// Closing speed of the pair along their relative motion, m/s.
    public let closingSpeed: Double
    /// A suggested time to keep running after the touch: how long the faster body takes to travel half the
    /// smaller of the two bodies' thinnest sizes at the closing speed. A rule of thumb, not physics.
    public let suggestedAfter: Double
}

extension AssemblySimulation {
    /// Every pair that touches on straight-line paths, earliest first.
    public func contactForecasts() -> [ContactForecast] {
        let count = bodyCount
        guard count > 1 else { return [] }
        let bodies = (0..<count).map(body)
        let velocities = bodies.map { body -> Point in
            guard body.totalMass > 0 else { return .zero }
            var sum = Point.zero
            for (v, m) in zip(body.velocity, body.mass) { sum += m * v }
            return sum / body.totalMass
        }
        let boxes = bodies.map { body -> (Point, Point) in
            var lower = Point(repeating: .infinity), upper = Point(repeating: -.infinity)
            for edge in body.mesh.boundary {
                lower = simd_min(lower, simd_min(body.position[edge.a], body.position[edge.b]))
                upper = simd_max(upper, simd_max(body.position[edge.a], body.position[edge.b]))
            }
            return (lower, upper)
        }
        var result: [ContactForecast] = []
        for a in 0..<count {
            for b in (a + 1)..<count {
                let relative = velocities[a] - velocities[b]
                let speed = simd_length(relative)
                guard speed > 1e-9,
                      let window = Self.boxWindow(boxes[a], boxes[b], relative: relative) else { continue }
                // Nodes of a moving along `relative` into the edges of b, and nodes of b moving the other way into a.
                let hitA = Self.firstHit(from: bodies[a], into: bodies[b], along: relative, limit: window.upperBound)
                let hitB = Self.firstHit(from: bodies[b], into: bodies[a], along: -relative, limit: window.upperBound)
                guard let time = [hitA, hitB].compactMap({ $0 }).min() else { continue }
                let thinnest = min(boxes[a].1 - boxes[a].0, boxes[b].1 - boxes[b].0)
                let size = min(thinnest.x, thinnest.y)
                result.append(ContactForecast(first: a, second: b, time: time, closingSpeed: speed,
                                              suggestedAfter: 0.5 * size / speed))
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    /// The time window in which the two bounding boxes overlap while moving apart by `relative`, or nil.
    static func boxWindow(_ a: (Point, Point), _ b: (Point, Point), relative: Point) -> ClosedRange<Double>? {
        var start = 0.0, end = Double.infinity
        for axis in 0..<2 {
            let v = relative[axis]
            // a moves with v relative to b: overlap when a.lower + v t <= b.upper and a.upper + v t >= b.lower.
            if abs(v) < 1e-15 {
                if a.0[axis] > b.1[axis] || a.1[axis] < b.0[axis] { return nil }
                continue
            }
            var t0 = (b.0[axis] - a.1[axis]) / v, t1 = (b.1[axis] - a.0[axis]) / v
            if t0 > t1 { swap(&t0, &t1) }
            start = max(start, t0)
            end = min(end, t1)
        }
        return start <= end ? start...end : nil
    }

    /// Earliest time a boundary node of `source` moving by `velocity` crosses a boundary edge of `target`.
    static func firstHit(from source: Body, into target: Body, along velocity: Point, limit: Double) -> Double? {
        let nodes = Set(source.mesh.boundary.flatMap { [$0.a, $0.b] })
        var best: Double?
        for node in nodes {
            let p = source.position[node]
            for edge in target.mesh.boundary {
                let a = target.position[edge.a], b = target.position[edge.b]
                let e = b - a
                let denominator = velocity.x * e.y - velocity.y * e.x
                guard abs(denominator) > 1e-18 else { continue }
                let d = a - p
                let t = (d.x * e.y - d.y * e.x) / denominator
                let s = (d.x * velocity.y - d.y * velocity.x) / denominator
                guard t >= 0, t <= limit, (0...1).contains(s), t < (best ?? .infinity) else { continue }
                best = t
            }
        }
        return best
    }
}
