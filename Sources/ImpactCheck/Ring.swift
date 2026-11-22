import Foundation
import ImpactPhysics

private struct RingResult {
    let period, peakChange: Double
}

private func ring(sectors: Int, layers: Int) -> RingResult {
    let speed = 0.4
    var simulation = Simulation(mesh: .ring(sectors: sectors, layers: layers), speed: speed,
                                gap: 0.004)
    let initial = simulation.body.diameters
    var peakChange = 0.0
    var lastContact = 0.0
    var lastImpulse = 0.0
    // Sample the same fixed physical times at all resolutions.
    let sampleStep = 0.00025
    var samples = [0.0]
    var previous = 0.0
    while simulation.time < 0.27 {
        let accepted = simulation.step()
        require(accepted, simulation.failure ?? "Ring step rejected")
        let change = simulation.body.diameters - initial
        let difference = change.x - change.y
        if simulation.wallImpulse > lastImpulse {
            lastContact = simulation.time
            lastImpulse = simulation.wallImpulse
        }
        if simulation.time < 0.15 {
            peakChange = max(peakChange, abs(change.x), abs(change.y))
        }
        let sampleTime = Double(samples.count) * sampleStep
        if simulation.time >= sampleTime {
            let fraction = (simulation.time - sampleTime) / simulation.dt
            samples.append(difference + fraction * (previous - difference))
        }
        previous = difference
    }

    // A centered, 16 ms triangular average suppresses mesh-scale ringing and
    // leaves the ~70 ms ovalization cycle. Require a negative lobe between peaks.
    let halfWindow = 32
    let weights = (-halfWindow...halfWindow).map { Double(halfWindow + 1 - abs($0)) }
    var peaks: [(index: Int, value: Double)] = []
    var positivePeak: (index: Int, value: Double)?
    for i in max(halfWindow, Int(ceil(lastContact / sampleStep)))..<(samples.count - halfWindow) {
        var filtered = 0.0
        for j in -halfWindow...halfWindow {
            filtered += weights[j + halfWindow] * samples[i + j]
        }
        filtered /= Double((halfWindow + 1) * (halfWindow + 1))
        if filtered > 0.0005 && filtered > (positivePeak?.value ?? 0) {
            positivePeak = (i, filtered)
        } else if filtered < -0.0005, let peak = positivePeak {
            peaks.append(peak)
            positivePeak = nil
        }
    }
    require(peaks.count >= 2, "Missing two separated post-impact ovalization peaks")
    let period = Double(peaks[1].index - peaks[0].index) * sampleStep
    print(String(format: "Ring %d × %d: period %.3f ms, peak diameter change %.3f mm, last contact %.2f ms",
                 sectors, layers, period * 1000, peakChange * 1000, lastContact * 1000))
    return RingResult(period: period, peakChange: peakChange)
}

func ringCheck() {
    let coarse = ring(sectors: 48, layers: 4)
    let shipped = ring(sectors: 96, layers: 8)
    let fine = ring(sectors: 144, layers: 12)
    for (label, previous, next) in [("Coarse → shipped", coarse, shipped), ("Shipped → fine", shipped, fine)] {
        print(String(format: "%@: period change %.2f%%, peak diameter change %.2f%%",
                     label, 100 * abs(previous.period / next.period - 1),
                     100 * abs(previous.peakChange / next.peakChange - 1)))
    }
    require(abs(shipped.period / fine.period - 1) < 0.05, "Ring period failed the 5% refinement gate")
    require(abs(shipped.peakChange / fine.peakChange - 1) < 0.05, "Ring diameter failed the 5% refinement gate")
}
