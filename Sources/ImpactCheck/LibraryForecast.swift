import Foundation
import ImpactPhysics
import simd

/// The Material Library additions (2026-11-25) and the pre-run touch estimate. Run with --metal-profiles.
/// NUMERICAL VERIFICATION of bookkeeping only: the touch estimate never changes a calculation.
func libraryAndForecastCheck() throws {
    // 1. Every Library material is valid, uniquely named, and the four reference metals are unchanged.
    let library = MaterialProfile.library
    require(Set(library.map(\.id)).count == library.count, "Library ids are unique")
    require(Array(library.prefix(4)) == MaterialProfile.references, "The four reference metals lead the Library unchanged")
    for profile in library {
        require(profile.isValid, "\(profile.id) is a valid profile")
        var part = AssemblyPart("probe")
        profile.apply(to: &part)
        require(part.material == profile.material, "\(profile.id) applies its material")
        require((part.plasticity.response == .elastic) == profile.springsBackOnly, "\(profile.id) applies the right behaviour")
        require(MaterialProfile.libraryProfile(for: profile.material.provenance) == profile, "\(profile.id) is found again")
        let start = AssemblyPart.startingFracture(for: profile)
        require(start.usesAbsoluteStrength && MaterialFractureSettings.absoluteStrengthRange.contains(start.strength!)
                && MaterialFractureSettings.absoluteEnergyRange.contains(start.energy), "\(profile.id) has a valid starting crack setting")
        if case let .available(_, energy, source) = profile.fractureEstimate {
            require(source.url.hasPrefix("https://") && !source.citation.isEmpty && energy > 0.5, "\(profile.id) estimate is cited")
        }
        print(String(format: "  %@: %.4g GPa, %.5g kg/m³, %@", profile.plainName, profile.material.young / 1e9,
                     profile.material.density, profile.springsBackOnly ? "springs back" : "bends for good"))
    }
    let glass = MaterialProfile.sodaLimeGlass
    if case let .available(strength, energy, _) = glass.fractureEstimate {
        let expected = 0.75e6 * 0.75e6 * (1 - 0.23 * 0.23) / 72e9
        require(strength == 41e6 && abs(energy - expected) < 1e-9 * expected, "Glass crack numbers follow G = K²(1−ν²)/E")
    } else { require(false, "Glass has a sourced crack estimate") }

    // 2. A typed custom crack setting equals the old fraction-of-stiffness default, so it replays identically.
    let custom = AssemblyPart.customStartingFracture(young: 1e6)
    require(custom.resolvedStrength(young: 1e6) == MaterialFractureSettings().resolvedStrength(young: 1e6)
            && custom.energy == MaterialFractureSettings().energy, "Typed crack default equals the old default")

    // 3. Touch estimate: a block 10 mm from a wall, closing at 20 m/s, touches at 0.5 ms.
    var scene = AssemblyScene()
    var block = AssemblyPart("Block", center: Point(-0.03, 0), size: Point(0.02, 0.02))
    MaterialProfile.aluminum6061.apply(to: &block)
    block.velocity = Point(20, 0)
    var wall = AssemblyPart("Wall", center: Point(0.01, 0), size: Point(0.02, 0.06))
    MaterialProfile.structuralSteel.apply(to: &wall, elasticOnly: true)
    wall.support = .fixed
    scene.parts = [block, wall]
    scene.duration = 0.001
    let simulation = try AssemblySimulation(scene)
    let forecasts = simulation.contactForecasts()
    let gap = (0.01 - 0.01) - (-0.03 + 0.01)
    require(forecasts.count == 1 && abs(forecasts[0].time - gap / 20) < 1e-9, "Touch at gap / speed: \(forecasts)")
    require(abs(forecasts[0].suggestedAfter - 0.5 * 0.02 / 20) < 1e-12, "Suggested time after the touch")
    print(String(format: "  Touch estimate: %.4f ms (expected %.4f ms)", forecasts[0].time * 1e3, gap / 20 * 1e3))

    // Moving apart or sideways past each other: no touch.
    var apart = scene
    apart.parts[0].velocity = Point(-20, 0)
    require(try AssemblySimulation(apart).contactForecasts().isEmpty, "Bodies moving apart never touch")
    var past = scene
    past.parts[0].velocity = Point(0, 20)
    require(try AssemblySimulation(past).contactForecasts().isEmpty, "Bodies sliding past never touch")
    // A body inside a hollow one, moving toward its wall, touches the inner face.
    var nested = AssemblyScene()
    var shell = AssemblyPart("Shell", shape: .enclosure, size: Point(0.10, 0.10))
    shell.wall = 0.01
    MaterialProfile.aluminum6061.apply(to: &shell)
    var core = AssemblyPart("Core", size: Point(0.03, 0.03))
    MaterialProfile.structuralSteel.apply(to: &core)
    core.velocity = Point(-10, 0)
    nested.parts = [shell, core]
    let inner = try AssemblySimulation(nested).contactForecasts()
    // Inner face at x = -0.04, core's left face at x = -0.015: 25 mm at 10 m/s = 2.5 ms.
    require(inner.count == 1 && abs(inner[0].time - 0.0025) < 1e-6, "Core reaches the inner face: \(inner)")
    print("Library and touch estimate: \(library.count) materials, all checks passed")
}
