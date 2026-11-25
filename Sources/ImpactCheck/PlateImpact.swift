import Foundation
import ImpactPhysics
import simd

// Flat-plate impact in the Assembly solver: a striker plate of thickness δ moving along +x hits a target
// plate at rest. Shared by the bulk viscosity check (plan step 4) and the spall check (plan step 5).
//
// NUMERICAL VERIFICATION against 1D uniaxial-strain wave theory, not physical validation of any material.
// The plates are tall (8 striker thicknesses) so that release waves from the top and bottom edges cannot
// reach the centre line inside the measured time window; only the centre band is measured.

struct PlateImpact {
    var striker: Double = 0.027        // δ, m. 27 mm keeps three standard cells (and an integer refinement) through it.
    var target: Double = 0.054         // T, m.
    var height: Double = 0.216         // 8δ.
    var speed: Double = 50             // m/s.
    var gap: Double = 0.0002           // m, starting clearance.
    var refinement: AssemblyScene.Resolution = .x4
    var profile: MaterialProfile = .structuralSteel
    var plastic = false
    var viscosity: BulkViscosity?
    var targetFracture: MaterialFractureSettings?

    var scene: AssemblyScene {
        var scene = AssemblyScene()
        var s = AssemblyPart("Striker plate", size: Point(striker, height))
        s.center = Point(-gap / 2 - striker / 2, 0)
        s.velocity = Point(speed, 0)
        profile.apply(to: &s, elasticOnly: !plastic)
        var t = AssemblyPart("Target plate", size: Point(target, height))
        t.center = Point(gap / 2 + target / 2, 0)
        profile.apply(to: &t, elasticOnly: !plastic)
        t.fracture = targetFracture
        scene.parts = [s, t]
        scene.meshResolution = refinement
        scene.duration = AssemblyScene.durationRange.lowerBound
        scene.bulkViscosity = viscosity
        return scene
    }

    /// Element columns through a plate of this thickness (the block mesher's rule).
    func columns(_ thickness: Double) -> Int { max(3, Int((thickness / 0.009).rounded())) * refinement.rawValue }
    var cell: Double { target / Double(columns(target)) }
    var waveSpeed: Double { profile.material.waveSpeed }
    /// Peak stress of the 1D elastic wave, ρ c v / 2 (equal impedance, interface speed v/2).
    var elasticStress: Double { profile.material.density * waveSpeed * speed / 2 }
    /// Pressure that goes with σxx in uniaxial strain: σyy = σzz = ν/(1−ν) σxx, so p = σxx (1+ν) / (3(1−ν)).
    var elasticPressure: Double {
        let nu = profile.material.poisson
        return elasticStress * (1 + nu) / (3 * (1 - nu))
    }
}

/// Centre-line column profile of one body: (distance from its left face, mean element value), left to right.
func centreProfile(_ values: [Double], body: Body, thickness: Double, height: Double, columns: Int) -> [(x: Double, value: Double)] {
    var sum = Array(repeating: 0.0, count: columns), count = Array(repeating: 0, count: columns)
    let h = thickness / Double(columns)
    for (i, e) in body.mesh.elements.enumerated() {
        let c = (body.mesh.reference[e.a] + body.mesh.reference[e.b] + body.mesh.reference[e.c]) / 3
        guard abs(c.y) < height / 16 else { continue }
        let column = min(columns - 1, max(0, Int((c.x + thickness / 2) / h)))
        sum[column] += values[i]
        count[column] += 1
    }
    return (0..<columns).map { ((Double($0) + 0.5) * h, count[$0] > 0 ? sum[$0] / Double(count[$0]) : 0) }
}

struct PlateRun {
    var simulation: AssemblySimulation
    let contact: Double
    var worstEnergyError = 0.0
}

/// Runs until `until` seconds after first contact. `observe` sees every accepted step with the time since contact.
func runPlate(_ setup: PlateImpact, until: Double, observe: (AssemblySimulation, Double) -> Void = { _, _ in }) throws -> PlateRun {
    let scene = setup.scene
    require(scene.issues().isEmpty, scene.issues().joined(separator: "; "))
    var simulation = try AssemblySimulation(scene)
    require(simulation.initialIssue == nil, simulation.initialIssue ?? "")
    let initial = simulation.initialEnergy
    var worst = 0.0
    var contact: Double?
    // A hard cap on steps keeps a mistake from running unattended.
    var steps = 0
    while contact == nil || simulation.time - contact! < until {
        require(simulation.step(), simulation.failure ?? "plate step rejected at t = \(simulation.time)")
        steps += 1
        require(steps < 200_000, "plate impact exceeded 200,000 steps")
        if contact == nil, let first = simulation.firstContactTimes[SIMD2(0, 1)] { contact = first }
        worst = max(worst, abs(simulation.energies.total - initial) / initial)
        if let contact { observe(simulation, simulation.time - contact) }
    }
    return PlateRun(simulation: simulation, contact: contact!, worstEnergyError: worst)
}

// Plan step 4. Criteria fixed here before the first run (2026-11-24):
//   A. Elastic steel plates, 50 m/s, bulk viscosity on: wave speed between two stations in the target within 5% of
//      the longitudinal speed c (the existing bar arrival tolerance); energy error, counting the viscous term, under 0.5%.
//   B. Plastic copper plates, 100 m/s: with bulk viscosity on, the plastic front is at most 6 elements wide (10% to 90%
//      of its plateau) and overshoots its plateau by at most 5%; with it off, the overshoot is larger than with it on.
//   Reported, not gated: elastic overshoot off and on, the fraction of the starting energy taken by viscosity.
func bulkViscosityCheck() throws {
    print("Bulk viscosity (plan step 4). Numerical verification, not physical validation.")

    // A. Elastic wave speed with viscosity on, and ringing off versus on.
    var elastic = PlateImpact()
    let c = elastic.waveSpeed
    let stations = [0.25 * elastic.target, 0.75 * elastic.target]
    var overshoot: [Double] = []
    for viscosity in [nil, BulkViscosity.standard] {
        elastic.viscosity = viscosity
        var arrivals: [Double?] = [nil, nil]
        var previous: [Double] = [0, 0]
        var peak = 0.0, stationPeak = 0.0
        var peakAt = (0.0, 0.0)
        let window = 0.9 * elastic.target / c // the front has not reached the back face
        let run = try runPlate(elastic, until: window) { sim, t in
            let profile = centreProfile(sim.pressure(1), body: sim.body(1), thickness: elastic.target,
                                        height: elastic.height, columns: elastic.columns(elastic.target))
            for (k, x) in stations.enumerated() where arrivals[k] == nil {
                let value = profile.min { abs($0.x - x) < abs($1.x - x) }!.value
                let level = 0.5 * elastic.elasticPressure
                if value >= level {
                    let fraction = (level - previous[k]) / (value - previous[k])
                    arrivals[k] = t - (1 - fraction) * sim.dt
                }
                previous[k] = value
            }
            // Ringing: the highest centre-line pressure anywhere behind the front.
            if let top = profile.max(by: { $0.value < $1.value }), top.value > peak {
                peak = top.value
                peakAt = (top.x, t)
            }
            stationPeak = max(stationPeak, profile.min { abs($0.x - stations[0]) < abs($1.x - stations[0]) }!.value)
        }
        let a0 = try unwrap(arrivals[0], "station 1 never reached half the elastic pressure")
        let a1 = try unwrap(arrivals[1], "station 2 never reached half the elastic pressure")
        let speed = (stations[1] - stations[0]) / (a1 - a0)
        let energy = run.simulation.energies
        overshoot.append(peak / elastic.elasticPressure - 1)
        let label = viscosity == nil ? "off" : "on "
        print(String(format: "  A. Elastic steel, 50 m/s, viscosity %@: wave speed %.0f m/s vs c %.0f m/s (%+.2f%%), highest centre-line pressure %.1f MPa vs 1D %.1f MPa (%+.1f%%), energy error %.4f%%, viscous energy %.3g%% of start, dt %.3g µs",
                     label, speed, c, 100 * (speed / c - 1), peak / 1e6, elastic.elasticPressure / 1e6,
                     100 * overshoot.last!, 100 * run.worstEnergyError, 100 * energy.viscous / run.simulation.initialEnergy,
                     run.simulation.dt * 1e6))
        print(String(format: "       that peak is %.1f mm into the target (beside the penalty contact face), %.2f µs after contact; ringing inside the plate, at station 1 (%.1f mm), peaks %+.1f%% above 1D",
                     1000 * peakAt.0, 1e6 * peakAt.1, 1000 * stations[0], 100 * (stationPeak / elastic.elasticPressure - 1)))
        if viscosity != nil {
            require(abs(speed / c - 1) < 0.05, "Elastic wave speed with bulk viscosity is more than 5% from c")
            require(run.worstEnergyError < 0.005, "Energy error with bulk viscosity is not below 0.5%")
            require(energy.viscous > 0, "Bulk viscosity took no energy in a compressive wave")
        } else {
            require(energy.viscous == 0, "Viscous energy is not zero with viscosity off")
        }
    }

    // B. Plastic front in copper at 100 m/s.
    var plastic = PlateImpact()
    plastic.profile = .copperC110
    plastic.plastic = true
    plastic.speed = 100
    let h = plastic.cell
    var results: [(width: Double, overshoot: Double, plateau: Double)] = []
    for viscosity in [nil, BulkViscosity.standard] {
        plastic.viscosity = viscosity
        // Sample when the front is near the middle of the target: the bulk speed √(K/ρ) is a lower bound on it.
        let material = plastic.profile.material
        let bulk = (material.young / (3 * (1 - 2 * material.poisson)) / material.density).squareRoot()
        let time = 0.5 * plastic.target / bulk
        let run = try runPlate(plastic, until: time)
        let profile = centreProfile(run.simulation.pressure(1), body: run.simulation.body(1), thickness: plastic.target,
                                    height: plastic.height, columns: plastic.columns(plastic.target)).map(\.value)
        // Plateau: median over the loaded band, from three cells behind the impact face to 60% of the distance the front
        // has travelled at the bulk speed (well behind it).
        let travelled = bulk * time
        let band = Array(profile[3..<max(4, Int(0.6 * travelled / h))])
        let plateau = band.sorted()[band.count / 2]
        // Scan outward from the band for the 90% and 10% crossings.
        func crossing(_ level: Double) -> Double {
            for k in band.count + 3..<profile.count where profile[k] < level {
                let f = (profile[k - 1] - level) / (profile[k - 1] - profile[k])
                return (Double(k - 1) + f) * h
            }
            return Double(profile.count) * h
        }
        let width = (crossing(0.1 * plateau) - crossing(0.9 * plateau)) / h
        let peak = profile[3..<min(profile.count, Int(crossing(0.9 * plateau) / h) + 2)].max()!
        results.append((width, peak / plateau - 1, plateau))
        print(String(format: "  B. Plastic copper, 100 m/s, viscosity %@: front width %.2f elements (10–90%%), plateau pressure %.0f MPa, overshoot %+.1f%%, energy error %.4f%%, plastic %.1f J/m, viscous %.2f J/m (%.3g%% of start)",
                     viscosity == nil ? "off" : "on ", width, plateau / 1e6, 100 * (peak / plateau - 1),
                     100 * run.worstEnergyError, run.simulation.energies.plastic, run.simulation.energies.viscous,
                     100 * run.simulation.energies.viscous / run.simulation.initialEnergy))
    }
    require(results[1].width <= 6, "Plastic front with bulk viscosity is wider than 6 elements")
    require(results[1].overshoot <= 0.05, "Plastic front with bulk viscosity overshoots its plateau by more than 5%")
    require(results[0].overshoot > results[1].overshoot, "Bulk viscosity did not reduce the overshoot")

    // C. Scene files: true turns on the standard coefficients, false and absence leave it off.
    for (text, expected) in [("true", BulkViscosity.standard), ("false", nil), ("{\"quadratic\": 1.5}", BulkViscosity(linear: 0.06, quadratic: 1.5))] {
        let json = "{\"parts\": [{\"name\": \"a\", \"shape\": \"block\", \"center\": [0, 0], \"size\": [0.05, 0.05], \"velocity\": [1, 0]}], \"bulkViscosity\": \(text)}"
        let scene = try AssemblyScene.document(Data(json.utf8))
        require(scene.bulkViscosity == expected, "bulkViscosity \(text) decoded as \(String(describing: scene.bulkViscosity))")
    }
    print("  C. Scene files: bulkViscosity true, false and an object decode as expected; absent stays off")
    print("Bulk viscosity check passed.")
}

func unwrap<T>(_ value: T?, _ message: String) throws -> T {
    require(value != nil, message)
    return value!
}
