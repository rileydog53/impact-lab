import Foundation
import ImpactPhysics
import simd

private struct SeparationResult {
    var insertion, damage, failure, detachment: Double?
    var energyError = 0.0
    var momentumError = 0.0
    var angularError = 0.0
    var relativeFragmentSpeed = 0.0
    var previousDissipation = 0.0
}

func tensileSeparationCheck(sceneURL: URL, refinedOnly: Bool = false) throws {
    cohesivePatchCheck(tensileInitiation: true)
    tensileFaceFrameCheck()
    let scene = try AssemblyScene.open(sceneURL)
    require(scene.parts.count == 5 && scene.resolution == .extraFine,
            "The verification requires the ×3 bend coupon scene with its support and receiver bodies")
    let reopened = try AssemblyScene.document(JSONEncoder().encode(scene))
    require(reopened == scene && scene.parts[0].fracture?.tensileStrength != nil,
            "The tensile initiation option failed to round-trip")
    var unsupported = scene
    unsupported.parts[0].plasticity.response = .elastoplastic
    require((try? AssemblySimulation(unsupported)) == nil
            && unsupported.issues().contains { $0.contains("requires a custom elastic material") },
            "The unverified tensile initiation and J2 combination was accepted")
    let nominal = try AssemblySimulation(scene)
    if !refinedOnly {
        runSeparation("native ×3", nominal, expect: .separation)
        var weak = scene
        weak.parts[1].velocity *= 0.10
        try runSeparation("weak loading ×3", AssemblySimulation(weak), expect: .intact)
    }

    var refined = scene
    refined.parts[0].refinement = .x4
    let fine = try AssemblySimulation(refined)
    let common = min(fine.dt, 0.4346e-6)
    if !refinedOnly {
        try runSeparation("×3 at common step",
                          AssemblySimulation(scene, refinement: scene.resolution.rawValue, stepLimit: common), expect: .receiver)
    }
    try runSeparation("×4 coupon at common step",
                      AssemblySimulation(refined, refinement: scene.resolution.rawValue, stepLimit: common), expect: .crackFace)
}

private enum ExpectedMotion {
    case intact, separation, receiver, crackFace
}

private func runSeparation(_ label: String, _ initial: AssemblySimulation, expect: ExpectedMotion) {
    var s = initial
    let initialMass = s.body(0).totalMass
    let initialTriangles = s.body(0).mesh.elements.count
    let momentum = s.momentum, angular = s.angularMomentum
    var result = SeparationResult()
    var nextPieceMeasurement = 0.0
    require(s.initialIssue == nil, s.initialIssue ?? "")
    while s.step() {
        let reading = s.fractureReading(0)!
        if reading.insertedEdges > 0 && result.insertion == nil { result.insertion = s.time }
        if reading.damagedEdges > 0 && result.damage == nil { result.damage = s.time }
        if reading.failedEdges > 0 && result.failure == nil { result.failure = s.time }
        if reading.pieces > 1 && result.detachment == nil { result.detachment = s.time }
        if reading.pieces > 1 && s.time >= nextPieceMeasurement {
            let pieces = s.materialPieces(0)
            for (i, piece) in pieces.enumerated() {
                for other in pieces.dropFirst(i + 1) {
                    result.relativeFragmentSpeed = max(result.relativeFragmentSpeed, simd_distance(piece.velocity, other.velocity))
                }
            }
            require(abs(pieces.reduce(0) { $0 + $1.mass } - initialMass) < 1e-12, "Fragment masses do not sum to initial mass")
            nextPieceMeasurement = s.time + 0.0005
        }
        require(reading.dissipation >= result.previousDissipation - 1e-12, "Fracture dissipation decreased")
        result.previousDissipation = reading.dissipation
        result.energyError = max(result.energyError, abs(s.energies.total / s.initialEnergy - 1))
        result.momentumError = max(result.momentumError, simd_distance(s.momentum, momentum))
        result.angularError = max(result.angularError, abs(s.angularMomentum - angular))
    }
    let reading = s.fractureReading(0)!
    let balance = reading.insertionBalance
    let pieces = s.materialPieces(0)
    let contacts = s.fragmentContacts.filter { $0.parts == SIMD2(0, 4) && $0.time > (result.detachment ?? .infinity) }
    let firstExposedContact = s.fragmentContacts.lazy.filter { $0.parts.x == 0 }
        .compactMap(\.firstExposedTime).filter { $0 > (result.detachment ?? .infinity) }.min()
    let impulse = contacts.reduce(0) { $0 + $1.normalImpulse }
    let firstReceiver = contacts.map(\.time).min()
    let receiverSpeed = simd_length(s.body(4).centerVelocity)
    func ms(_ time: Double?) -> String { time.map { String(format: "%.3f", 1000 * $0) } ?? "none" }
    print(String(format: "%@, dt %.3f µs, %d coupon triangles: insert %@ ms, damage %@ ms, first failure %@ ms, detach %@ ms; %d pieces, %d failed faces, %.3f mm failed length, %.6f J/m dissipated",
                 label, 1e6 * s.dt, initialTriangles, ms(result.insertion), ms(result.damage), ms(result.failure), ms(result.detachment),
                 pieces.count, reading.failedEdges, 1000 * reading.crackLength, reading.dissipation))
    print(String(format: "  Receiver contact %@ ms, first post-detachment exposed-face contact %@ ms, scalar impulse %.6f N·s/m, receiver speed %.4f m/s, peak relative fragment speed %.4f m/s",
                 ms(firstReceiver), ms(firstExposedContact), impulse, receiverSpeed, result.relativeFragmentSpeed))
    print(String(format: "  Energy error %.5f%%, overlap %.4f%%, ΔP %.2e N·s/m, ΔL %.2e N·s, split Δmass %.2e kg/m, split Δkinetic %.2e J/m%@",
                 100 * result.energyError, 100 * s.peakRelativePenetration, result.momentumError, result.angularError,
                 balance.mass, balance.kinetic, s.failure.map { " STOPPED: " + $0 } ?? ""))
    require(s.failure == nil && s.time >= s.scene.duration, "\(label) did not complete")
    require(s.body(0).mesh.elements.count == initialTriangles && abs(s.body(0).totalMass - initialMass) < 1e-12,
            "\(label) removed an element or changed mass")
    require(result.energyError < 0.005 && max(result.momentumError, result.angularError) < 1e-9,
            "\(label) missed the conservation tolerances")
    require(s.peakRelativePenetration <= 0.02, "\(label) exceeded the 2% overlap tolerance")
    require(max(balance.mass, balance.kinetic, balance.momentum, balance.angularMomentum) < 1e-10,
            "\(label) changed mass, momentum, or kinetic energy at insertion")
    let toughness = s.scene.parts[0].fracture!.energy
    require(reading.dissipation + 1e-12 >= toughness * reading.crackLength,
            "\(label) dissipated less than Gc times failed length")
    if expect == .intact {
        require(result.insertion == nil && reading.dissipation == 0 && pieces.count == 1,
                "Weak loading started a crack")
    } else {
        guard let insertion = result.insertion, let damage = result.damage, let failure = result.failure,
              let detachment = result.detachment else {
            require(false, "\(label) missed a fracture event")
            return
        }
        require(insertion <= damage && damage < failure && failure <= detachment,
                "\(label) recorded events out of order")
        require(pieces.count > 1 && result.relativeFragmentSpeed > 0.1,
                "\(label) did not produce independently moving fragments")
        if expect == .receiver || expect == .crackFace {
            require(firstReceiver.map { $0 > detachment } == true && impulse > 0 && receiverSpeed > 0.001,
                    "\(label) did not transfer load from a moving fragment to the receiver")
        }
        if expect == .crackFace {
            require(firstExposedContact != nil,
                    "\(label) did not record contact on a newly exposed face")
        }
    }
}
