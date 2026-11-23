import Foundation
import ImpactPhysics
import simd

func tensilePropagationCheck(_ arguments: [String]) throws {
    let url = URL(fileURLWithPath: arguments.first ?? "docs/scene-examples/tensile-separation.json")
    var scene = try AssemblyScene.open(url)
    require(scene.parts.map(\.name) == ["Bend coupon", "Striker", "Left support", "Right support", "Receiver"]
            && scene.parts[0].fracture?.tensileStrength != nil && scene.duration >= 0.085,
            "The propagation control requires the tensile-separation bend scene")
    let refinement = arguments.dropFirst().first == "4" ? 4 : 3
    scene.parts[0].refinement = refinement == 4 ? .x4 : .extraFine
    if arguments.contains("staggered") { scene.parts[0].fracture?.meshPattern = .staggered }
    MaterialFracture.symmetricTensileFrame = !arguments.contains("left-frame")
    let step = arguments.contains("half") ? 0.2173e-6 : 0.4346e-6
    let gauge = AssemblyGauge(body: scene.parts[0].id, name: "Below the striker",
                              location: Point(-0.018, -0.013))
    scene.gauges = [gauge]
    var simulation = try AssemblySimulation(scene, refinement: scene.resolution.rawValue, stepLimit: step)
    let times = [0.006, 0.012, 0.020, 0.030, 0.060, 0.085, scene.duration]
    var sample = 0
    var fractureWork = 0.0
    var onset: Double?
    var detachment: Double?
    var energyError = 0.0
    var momentumError = 0.0
    let momentum = simulation.momentum
    let initialMass = simulation.body(0).totalMass
    let initialGaugeY = simulation.gaugePosition(0).y
    let receiverMass = simulation.body(4).totalMass
    let initialReceiverVelocity = simulation.body(4).centerVelocity
    var trough = 0.0
    print("mesh=\(scene.parts[0].fracture!.pattern.rawValue), refinement=\(refinement), dt_µs=\(1e6 * simulation.dt)")
    print("ms,edges,failed,pieces,work_J/m,spent_J/m,nonvertical_J/m,separated_mass_fraction,striker_zone_drop_mm,peak_drop_mm,receiver_Px,receiver_Py,receiver_normal_impulse")
    while simulation.step() {
        let reading = simulation.fractureReading(0)!
        require(reading.dissipation + 1e-12 >= fractureWork, "Fracture dissipation decreased")
        fractureWork = reading.dissipation
        if onset == nil && reading.insertedEdges > 0 { onset = simulation.time }
        if detachment == nil && reading.pieces > 1 { detachment = simulation.time }
        energyError = max(energyError, abs(simulation.energies.total / simulation.initialEnergy - 1))
        momentumError = max(momentumError, simd_distance(momentum, simulation.momentum))
        let coupon = simulation.body(0)
        let drop = initialGaugeY - simulation.gaugePosition(0).y
        trough = max(trough, drop)
        guard sample < times.count, simulation.time + 1e-12 >= times[sample] else { continue }
        sample += 1
        let pieces = simulation.materialPieces(0)
        let reference = coupon.mesh.reference
        let toughness = scene.parts[0].fracture!.energy
        let nonVerticalWork = simulation.crackFaces(0).reduce(0.0) { work, face in
            let edge = reference[face.first.b] - reference[face.first.a]
            return work + (abs(edge.x) > 1e-10 ? toughness * simd_length(edge) * face.damage : 0)
        }
        let totalPieceMass = pieces.reduce(0) { $0 + $1.mass }
        require(abs(totalPieceMass - initialMass) < 1e-12, "Fracture changed coupon mass")
        require(reading.dissipation + 1e-12 >= toughness * reading.crackLength,
                "The spent faces exceeded the fracture energy ledger")
        let receiver = simulation.body(4)
        let transfer = receiverMass * (receiver.centerVelocity - initialReceiverVelocity)
        let impulse = simulation.fragmentContacts.filter { $0.parts == SIMD2(0, 4) }.reduce(0) { $0 + $1.normalImpulse }
        print(String(format: "%.5f,%d,%d,%d,%.6f,%.6f,%.6f,%.7f,%.4f,%.4f,%.7f,%.7f,%.7f",
                     1000 * simulation.time, reading.insertedEdges, reading.failedEdges, reading.pieces,
                     reading.dissipation, toughness * reading.crackLength, nonVerticalWork,
                     max(0, 1 - pieces.map(\.mass).max()! / initialMass), 1000 * drop, 1000 * trough,
                     transfer.x, transfer.y, impulse))
    }
    print(String(format: "onset_ms=%.6f,detach_ms=%.6f,max_energy_%%=%.6f,max_overlap_%%=%.6f,max_momentum_error=%.3e",
                 1000 * (onset ?? .nan), 1000 * (detachment ?? .nan), 100 * energyError,
                 100 * simulation.peakRelativePenetration, momentumError))
    require(simulation.failure == nil && simulation.time >= scene.duration && sample == times.count,
            simulation.failure ?? "Incomplete run")
    require(energyError < 0.005 && momentumError < 1e-9, "Propagation run missed the conservation tolerances")
}
