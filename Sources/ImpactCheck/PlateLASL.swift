import Foundation
import ImpactPhysics
import simd

// Layered target plan, step 8 part 2: symmetric plate-on-plate impact, 2024-like aluminium, at or below the app's
// 150 m/s cap (Joseph's direction 2026-11-25: verification only, the cap does not move). docs/step8-design.md, Part 3.
//
// NUMERICAL VERIFICATION, not physical validation. Two references:
//  A. Elastic-perfectly-plastic wave theory in uniaxial strain, with the run's own K, G and Y (the code's model).
//     Below the Hugoniot elastic limit (HEL) one elastic wave carries σxx = ρ c_L u_p. Above it an elastic precursor at
//     the HEL, σ_HEL = Y (1 − ν)/(1 − 2ν), travels at c_L, followed by a plastic wave at the bulk speed c_B = √(K/ρ):
//     σxx = σ_HEL + ρ c_B (u_p − u_HEL), with u_HEL = σ_HEL/(ρ c_L), and mean pressure p = K εxx.
//  B. The LASL shock fit for 2024 aluminium (Marsh 1980; ρ0 2785, c0 5328 m/s, s 1.338): P = ρ0 (c0 + s u_p) u_p.
//     That fit is hydrodynamic: it comes from shocks far above the HEL. At 150 m/s the HEL is about two thirds of the
//     stress, so the fit is not expected to match here; the gap is reported, not gated.
// Material: K matched to ρ0 c0² (79.06 GPa) as the design asks: E 73.1 GPa (2024-T3), ν from K. Y 345 MPa (2024-T3,
// typical handbook value), perfectly plastic. Bulk viscosity on (standard coefficients) to settle the plastic front.
//
// Criteria fixed before the first run (2026-11-25):
//  1. 50 m/s (below the HEL): σxx plateau within 2% of ρ c_L u_p. This also checks the stress measurement.
//  2. 100 and 150 m/s: σxx plateau within 3% of reference A, mean-pressure plateau within 3% of K εxx (3%, not 2%,
//     because the code's Hencky law is finite strain and the reference is small strain: about 1.3% apart at 150 m/s).
//  3. x4 and x6 meshes: σxx plateaus agree within 1%.
//  4. Reported only: the gap to the LASL fit, and the plastic-front speed against c_B.
// Measurement: the plates are 54 mm (striker) and 108 mm (target), 216 mm tall. At 12 µs after contact no release wave
// has reached the measured band (striker back face 16.8 µs, top and bottom edges 16.8 µs). The plateau is the median of
// the centre band from 7 mm into the target to 80% of the distance the plastic front has travelled at c_B.
// σxx at a cut is minus the x-sum of internal forces on the band's nodes beyond the cut, over the band's height
// (node rows × row spacing): the force the material behind the cut exerts across it.

private let lasl = (density: 2785.0, c0: 5328.0, s: 1.338)

private struct Aluminium2024 {
    let young = 73.1e9, yield = 345e6
    var bulk: Double { lasl.density * lasl.c0 * lasl.c0 }
    var poisson: Double { (3 * bulk - young) / (6 * bulk) }
    var shear: Double { young / (2 * (1 + poisson)) }
    var longitudinal: Double { ((bulk + 4 * shear / 3) / lasl.density).squareRoot() }
    var bulkSpeed: Double { (bulk / lasl.density).squareRoot() }
    var hel: Double { yield * (1 - poisson) / (1 - 2 * poisson) }
    var helSpeed: Double { hel / (lasl.density * longitudinal) }

    /// Reference A for particle speed u: (σxx, mean pressure).
    func theory(_ u: Double) -> (stress: Double, pressure: Double) {
        guard u > helSpeed else {
            let strain = u / longitudinal
            return (lasl.density * longitudinal * u, bulk * strain)
        }
        let strain = helSpeed / longitudinal + (u - helSpeed) / bulkSpeed
        return (hel + lasl.density * bulkSpeed * (u - helSpeed), bulk * strain)
    }

    var plates: (material: Material, hardening: HardeningTable) {
        (Material(young: young, density: lasl.density, poisson: poisson),
         HardeningTable(points: [HardeningPoint(strain: 0, stress: yield), HardeningPoint(strain: 1, stress: yield)]))
    }
}

func plateLASLCheck() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    let al = Aluminium2024()
    print("Plate-on-plate impact, 2024-like aluminium, at or below 150 m/s (plan step 8 part 2). Numerical verification, not physical validation.")
    print(String(format: "  Material: E %.1f GPa, ν %.4f (K %.2f GPa = ρ0 c0²), Y %.0f MPa perfectly plastic; c_L %.0f m/s, c_B %.0f m/s, HEL %.0f MPa at particle speed %.1f m/s",
                 al.young / 1e9, al.poisson, al.bulk / 1e9, al.yield / 1e6, al.longitudinal, al.bulkSpeed, al.hel / 1e6, al.helSpeed))
    var plateaus: [Double: [Double]] = [:]
    for resolution in [AssemblyScene.Resolution.x4, .x6] {
        for speed in [50.0, 100.0, 150.0] {
            var setup = PlateImpact()
            setup.striker = 0.054
            setup.target = 0.108
            setup.speed = speed
            setup.refinement = resolution
            setup.plastic = true
            setup.viscosity = .standard
            setup.custom = al.plates
            let time = 12e-6
            let started = Date()
            let run = try runPlate(setup, until: time)
            let sim = run.simulation
            let body = sim.body(1)
            let reference = body.mesh.reference
            let band = setup.height / 16
            let rows = max(3, Int((setup.height / 0.009).rounded())) * resolution.rawValue
            let dy = setup.height / Double(rows)
            let columns = Set(reference.map { ($0.x * 1e9).rounded() / 1e9 }).sorted()
            let force = sim.internalForce(1)
            let inBand = reference.indices.filter { abs(reference[$0].y) < band }
            let bandRows = Set(inBand.map { (reference[$0].y * 1e9).rounded() }).count
            // σxx (compression positive) at each node column, measured from the target's impact face.
            let face = -setup.target / 2
            let stress: [(x: Double, value: Double)] = columns.dropLast().map { cut in
                let beyond = inBand.filter { reference[$0].x > cut + 1e-9 }.reduce(0.0) { $0 + force[$1].x }
                return (cut - face, beyond / (Double(bandRows) * dy))
            }
            let pressure = centreProfile(sim.pressure(1), body: body, thickness: setup.target, height: setup.height,
                                         columns: setup.columns(setup.target))
            let u = speed / 2
            let expected = al.theory(u)
            let front = (u > al.helSpeed ? al.bulkSpeed : al.longitudinal) * time
            func plateau(_ profile: [(x: Double, value: Double)]) -> Double {
                let values = profile.filter { $0.x >= 0.007 && $0.x <= 0.8 * front }.map(\.value).sorted()
                return values[values.count / 2]
            }
            let measuredStress = plateau(stress), measuredPressure = plateau(pressure)
            // Plastic front: where σxx crosses halfway between the HEL and the plateau, scanning from the far side.
            var frontAt: Double?
            if u > al.helSpeed {
                let level = (al.hel + measuredStress) / 2
                for (a, b) in zip(stress, stress.dropFirst()) where a.value >= level && b.value < level {
                    frontAt = a.x + (a.value - level) / (a.value - b.value) * (b.x - a.x)
                }
            }
            let fit = lasl.density * (lasl.c0 + lasl.s * u) * u
            plateaus[speed, default: []].append(measuredStress)
            var line = String(format: "  %@ %.0f m/s: σxx plateau %.1f MPa vs theory %.1f (%+.2f%%), mean pressure %.1f MPa vs K εxx %.1f (%+.2f%%), LASL fit %.1f MPa (σxx %+.1f%%, pressure %+.1f%%)",
                              resolution == .x4 ? "x4" : "x6", speed, measuredStress / 1e6, expected.stress / 1e6,
                              100 * (measuredStress / expected.stress - 1), measuredPressure / 1e6, expected.pressure / 1e6,
                              100 * (measuredPressure / expected.pressure - 1), fit / 1e6,
                              100 * (measuredStress / fit - 1), 100 * (measuredPressure / fit - 1))
            if let frontAt {
                line += String(format: ", plastic front speed %.0f m/s vs c_B %.0f", frontAt / time, al.bulkSpeed)
            }
            line += String(format: "; energy error %.3f%%, %.0f s", 100 * run.worstEnergyError, Date().timeIntervalSince(started))
            print(line)
            if u <= al.helSpeed {
                require(abs(measuredStress / expected.stress - 1) <= 0.02, "\(speed) m/s: elastic σxx plateau more than 2% from ρ c_L u")
            } else {
                require(abs(measuredStress / expected.stress - 1) <= 0.03, "\(speed) m/s: σxx plateau more than 3% from wave theory")
                require(abs(measuredPressure / expected.pressure - 1) <= 0.03, "\(speed) m/s: pressure plateau more than 3% from K εxx")
            }
        }
    }
    for speed in plateaus.keys.sorted() {
        let pair = plateaus[speed]!
        let gap = abs(pair[1] / pair[0] - 1)
        print(String(format: "  %.0f m/s: x6 against x4 σxx plateau %.2f%%", speed, 100 * gap))
        require(gap <= 0.01, "\(speed) m/s: x4 and x6 plateaus differ by more than 1%")
    }
    print("Plate impact check passed.")
}
