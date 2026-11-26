import Foundation

/// The Material Library as the app shows it: the four reference metals (unchanged, so every check and scenario
/// that iterates `references` keeps its old meaning) plus more literature-sourced materials. Values follow the
/// project rule: literature first, two sources that agree, or the average of the two closest of three.
/// Sources and arithmetic: docs/laminate-material-profiles.md and docs/library-materials.md.
extension MaterialProfile {
    /// Everything the Library offers, in display order.
    public static let library: [MaterialProfile] = references + [titanium64, brassC260] + nonMetals

    public static let nonMetals: [MaterialProfile] = [carbonFabric, sodaLimeGlass, structuralEpoxy, polycarbonate,
                                                      pvbInterlayer, naturalRubber, oakAlongGrain]

    /// A Library profile by its own id or, for a user's edited copy, by the id it was copied from.
    public static func libraryProfile(for provenance: MaterialProvenance?) -> MaterialProfile? {
        guard let provenance else { return nil }
        let key = provenance.referenceID ?? provenance.id
        return library.first { $0.id == key }
    }

    /// Materials with no permanent bending in this app: they spring back fully (and crack, if cracking is on).
    public var springsBackOnly: Bool { Self.springsBackIDs.contains(provenance.referenceID ?? id) }

    /// The everyday name shown first in the app; the technical grade stays in the source details.
    public var plainName: String {
        if provenance.isCustom { return name }
        return Self.plainNames[id] ?? name
    }

    /// How this material behaves, in plain words, with the technical name in brackets.
    public var behaviourSummary: String {
        springsBackOnly ? "Springs back to its shape (elastic)" : "Metal: bends for good past a point (J2 plasticity)"
    }

    /// The stress the app shows as "Bends for good at" for metals, or the listed breaking strength otherwise.
    public var listedStrength: Double { hardening.points[0].stress }

    private static let plainNames: [String: String] = [
        "structural-steel-a36": "Steel (structural, A36)",
        "stainless-304-annealed": "Stainless steel (304)",
        "aluminum-6061-t6": "Aluminium (6061-T6)",
        "copper-c11000-annealed": "Copper (soft, annealed)",
    ]

    static let springsBackIDs: Set<String> = Set(nonMetals.map(\.id))

    /// A material that only springs back. Its one-point "hardening table" holds the listed breaking strength for
    /// display; the body is always given an elastic response, so the table is never used by the calculation.
    private static func elastic(_ id: String, _ name: String, family: String, condition: String,
                                young: Double, density: Double, poisson: Double, strength: Double,
                                source: String, url: String, evidence: String) -> Self {
        var material = Material(young: young * 1e9, density: density, poisson: poisson)
        material.provenance = MaterialProvenance(id: id, name: name, family: family, condition: condition,
                                                source: URL(string: url)!, sourceName: source, evidence: evidence,
                                                referenceID: nil)
        return Self(material: material, hardening: HardeningTable(points: [
            HardeningPoint(strain: 0, stress: strength * 1e6), HardeningPoint(strain: 0.12, stress: strength * 1e6),
        ]))
    }

    private static func metal(_ id: String, _ name: String, family: String, condition: String,
                              young: Double, density: Double, poisson: Double,
                              source: String, url: String, evidence: String, flow: [(Double, Double)]) -> Self {
        var material = Material(young: young * 1e9, density: density, poisson: poisson)
        material.provenance = MaterialProvenance(id: id, name: name, family: family, condition: condition,
                                                source: URL(string: url)!, sourceName: source, evidence: evidence,
                                                referenceID: nil)
        return Self(material: material, hardening: HardeningTable(points: flow.map {
            HardeningPoint(strain: $0.0, stress: $0.1 * 1e6)
        }))
    }

    // MARK: Metals (new). Values: docs/library-materials.md.

    public static let titanium64 = metal("titanium-ti6al4v-annealed", "Titanium (Ti-6Al-4V)",
        family: "Titanium alloy", condition: "Grade 5, annealed, room temperature",
        young: TitaniumValues.young, density: TitaniumValues.density, poisson: TitaniumValues.poisson,
        source: TitaniumValues.sourceName, url: TitaniumValues.url, evidence: TitaniumValues.evidence,
        flow: TitaniumValues.flow)

    public static let brassC260 = metal("brass-c26000-annealed", "Brass (cartridge, C26000)",
        family: "Copper-zinc alloy (70/30)", condition: "Annealed, room temperature",
        young: BrassValues.young, density: BrassValues.density, poisson: BrassValues.poisson,
        source: BrassValues.sourceName, url: BrassValues.url, evidence: BrassValues.evidence,
        flow: BrassValues.flow)

    // MARK: Non-metals. Glass, PVB and carbon fabric: docs/laminate-material-profiles.md (already used by the presets).

    public static let carbonFabric = elastic("carbon-fibre-epoxy-fabric", "Carbon fibre (woven, epoxy)",
        family: "Carbon-fibre/epoxy 0/90 fabric laminate", condition: "Standard-modulus fabric, 50% fibre, room temperature",
        young: 70, density: 1600, poisson: 0.10, strength: 600,
        source: "ACP Composites property table (2014)",
        url: "https://acpcomposites.com/wp-content/uploads/2024/05/Mechanical-Properties-of-Carbon-Fiber-Composite-Materials.pdf",
        evidence: "Stiffness along either fibre direction, used in every direction here (the app's materials are the same in all directions), so it is too stiff off-axis. Single source. No crack resistance found.")

    public static let sodaLimeGlass = elastic("soda-lime-glass", "Window glass (soda-lime)",
        family: "Soda-lime silica float glass", condition: "Annealed, weathered, room temperature",
        young: 72, density: 2500, poisson: 0.23, strength: 41,
        source: "Pilkington ATS-129 (2013)",
        url: "https://www.pilkington.com/-/media/pilkington/site-content/usa/window-manufacturers/technical-bulletins/ats129propertiesofglass20130114.pdf",
        evidence: "Stiffness 72 GPa (Pilkington 72, Wikipedia 74, MakeItFrom 71), weight 2500 kg/m³, breaking strength 41 MPa mean (60 s load). Brittle: no permanent bending.")

    public static let pvbInterlayer = elastic("pvb-interlayer", "Safety-glass plastic (PVB)",
        family: "Polyvinyl butyral interlayer", condition: "3 s load, 20 °C (shortest sourced load time)",
        young: 0.033, density: 1070, poisson: 0.48, strength: 20,
        source: "AGC Stratobel PVB datasheet (2022)",
        url: "https://www.agc-yourglass.com/sites/default/files/2022-10/Material%20Properties%20of%20PVB%200722_EN_0.pdf",
        evidence: "33 MPa at a 3 s load; during an impact real PVB is far stiffer, so treat this as a soft lower bound. Squish sideways lowered from 0.5 to the app's limit 0.48. Never cracks here.")

    public static let structuralEpoxy = elastic("epoxy-bulk", "Epoxy (hard glue/resin)",
        family: "Cured bisphenol-A epoxy, unfilled", condition: "Room temperature",
        young: EpoxyValues.young, density: EpoxyValues.density, poisson: EpoxyValues.poisson, strength: EpoxyValues.strength,
        source: EpoxyValues.sourceName, url: EpoxyValues.url, evidence: EpoxyValues.evidence)

    public static let polycarbonate = elastic("polycarbonate", "Polycarbonate (clear tough plastic)",
        family: "Polycarbonate, general purpose", condition: "Room temperature",
        young: PolycarbonateValues.young, density: PolycarbonateValues.density, poisson: PolycarbonateValues.poisson,
        strength: PolycarbonateValues.strength,
        source: PolycarbonateValues.sourceName, url: PolycarbonateValues.url, evidence: PolycarbonateValues.evidence)

    public static let naturalRubber = elastic("natural-rubber", "Rubber (natural)",
        family: "Vulcanised natural rubber", condition: "Small stretch, room temperature",
        young: RubberValues.young, density: RubberValues.density, poisson: RubberValues.poisson, strength: RubberValues.strength,
        source: RubberValues.sourceName, url: RubberValues.url, evidence: RubberValues.evidence)

    public static let oakAlongGrain = elastic("oak-along-grain", "Oak wood (along the grain)",
        family: "Hardwood, oak", condition: "About 12% moisture, loaded along the grain",
        young: OakValues.young, density: OakValues.density, poisson: OakValues.poisson, strength: OakValues.strength,
        source: OakValues.sourceName, url: OakValues.url, evidence: OakValues.evidence)
}

extension AssemblyPart {
    /// Typed starting crack resistance for a Library material with no sourced value, in J/m². A starting point
    /// for the user to change, not a material value; the editor says so next to it.
    public static let typedCrackResistanceStart = 1000.0

    /// Crack settings when cracking is switched on for a Library material: its sourced estimate, or, when it has
    /// none, a start for the user to change (its highest listed stress and `typedCrackResistanceStart`), with no
    /// source attached so the editor marks the numbers as typed.
    public static func startingFracture(for profile: MaterialProfile) -> MaterialFractureSettings {
        if let estimate = profile.defaultFracture { return estimate }
        var settings = MaterialFractureSettings()
        settings.strength = profile.hardening.points.last?.stress ?? profile.listedStrength
        settings.energy = typedCrackResistanceStart
        return settings
    }

    /// Crack settings when cracking is switched on for a material with typed numbers: the old default
    /// (crack starts at 3% of the stiffness, 7 J/m²) written as a real strength in pascals, so the crack
    /// resistance box is no longer capped at 50 J/m². Equal to the old fraction-of-stiffness default, which
    /// replays identically (checked by ImpactCheck --materials), up to the 4 GPa strength limit.
    public static func customStartingFracture(young: Double) -> MaterialFractureSettings {
        var settings = MaterialFractureSettings()
        settings.strength = min(MaterialFractureSettings.absoluteStrengthRange.upperBound,
                                max(MaterialFractureSettings.absoluteStrengthRange.lowerBound, young * settings.strengthFraction))
        return settings
    }
}
