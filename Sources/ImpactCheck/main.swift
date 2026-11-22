import Foundation
import ImpactPhysics

struct WaveResult {
    let arrival: Double
    let predicted: Double
    let trace: [Double]
}

func wave(young: Double, columns: Int = 120, rows: Int = 6, penalty: Double = 2500,
          stepScale: Double = 1) -> WaveResult {
    let material = Material(young: young)
    let speed = 0.4
    var simulation = Simulation(mesh: .bar(columns: columns, rows: rows), material: material,
                                speed: speed, penalty: penalty, stepScale: stepScale)
    let predicted = 0.5 / material.waveSpeed
    let contact = simulation.gap / speed
    let threshold = -0.5 * speed / material.waveSpeed
    var arrival: Double?
    var trace: [Double] = []
    while simulation.time < contact + 2 * predicted {
        let previous = simulation.probeStrain
        precondition(simulation.step(), simulation.failure ?? "")
        let current = simulation.probeStrain
        trace.append(current)
        if arrival == nil && current <= threshold {
            let fraction = (threshold - previous) / (current - previous)
            arrival = simulation.time - (1 - fraction) * simulation.dt - contact
        }
    }
    return WaveResult(arrival: arrival!, predicted: predicted, trace: trace)
}

let nominal = wave(young: 1e6)
let stiff = wave(young: 4e6)
let repeatRun = wave(young: 1e6)
for (label, result) in [("1 MPa", nominal), ("4 MPa", stiff)] {
    print(String(format: "%@: arrival %.3f ms, predicted %.3f ms (%+.2f%%)",
                 label, result.arrival * 1000, result.predicted * 1000,
                 100 * (result.arrival / result.predicted - 1)))
}
let ratio = stiff.arrival / nominal.arrival
let repeatable = repeatRun.trace == nominal.trace
print(String(format: "Arrival ratio %.4f; reset trace identical: %@", ratio, repeatable.description))
precondition(abs(nominal.arrival / nominal.predicted - 1) < 0.05)
precondition(abs(stiff.arrival / stiff.predicted - 1) < 0.05)
precondition(abs(ratio - 0.5) < 0.025 && repeatable)
