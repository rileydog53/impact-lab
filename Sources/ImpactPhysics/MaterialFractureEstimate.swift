import Foundation

/// Where a fracture number came from. Shown next to the number in the app.
public struct FractureEstimateSource: Codable, Equatable, Sendable {
    /// Always "estimated" for handbook-derived values; never "measured" or "validated".
    public var status: String
    public var citation: String
    public var url: String
    /// One plain-English line the user sees with the value.
    public var caution: String

    public init(status: String = "estimated", citation: String, url: String, caution: String) {
        self.status = status
        self.citation = citation
        self.url = url
        self.caution = caution
    }
}

/// Sourced default for a library material's cohesive fracture settings, or the
/// reason none exists. No number is ever invented: a material without a
/// source reports `.unavailable` and fracture stays off.
public enum FractureEstimate: Equatable, Sendable {
    case available(strength: Double, energy: Double, source: FractureEstimateSource)
    case unavailable(reason: String)
}

extension MaterialProfile {
    /// Plane-strain energy release rate from a handbook K_IC: G = K² (1 − ν²) / E.
    static func energyRelease(toughness: Double, material: Material) -> Double {
        toughness * toughness * (1 - material.poisson * material.poisson) / material.young
    }

    /// Sourcing rule (Joseph, 24 Nov 2026): literature first, Wikipedia acceptable; two sources that
    /// roughly agree are used; if they conflict find a third, then average the two closest values.
    /// The citation stays in the data and the editor's collapsed "Source" details.
    public var fractureEstimate: FractureEstimate {
        func estimate(_ strength: Double, _ toughness: Double, _ citation: String, _ url: String) -> FractureEstimate {
            .available(strength: strength, energy: Self.energyRelease(toughness: toughness, material: material),
                       source: FractureEstimateSource(citation: citation, url: url,
                                                      caution: "Handbook estimate; real toughness varies with heat, orientation and thickness."))
        }
        switch id {
        case "aluminum-6061-t6":
            // K_IC 29 MPa√m (TL; ASM-derived datasheet; 22–35 typical wrought 6xxx), UTS 310 MPa typical.
            return estimate(310e6, 29e6, "6061-T6 typical UTS 310 MPa and K_IC 29 MPa√m (TL), aerospacemetals.com 6061-T6/T651 datasheet (ASM-derived); G = K²(1−ν²)/E.",
                            "https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf")
        case "structural-steel-a36":
            // Mild steel K_IC 140 MPa√m in two tables that agree (MIT OCW 1020 steel; eFunda mild steel). UTS 400–550 MPa (ASTM A36), midpoint.
            return estimate(475e6, 140e6, "Mild steel K_IC 140 MPa√m (MIT OCW materials table, 1020 steel; eFunda mild steel; used for A36) and A36 UTS 400–550 MPa (ASTM A36, midpoint 475); G = K²(1−ν²)/E.",
                            "https://www.efunda.com/formulae/solid_mechanics/fracture_mechanics/fm_lefm_Kc_Matl.cfm")
        case "stainless-304-annealed":
            // Sources conflict: 50 (MIT table), 200 (chemeurope 18Cr-8Ni), ~250 (J_IC ≈ 300 kJ/m² converted, ASTM STP 1985). Two closest: 200 and 250 → 225.
            return estimate(600e6, 225e6, "304 K_IC about 225 MPa√m: average of the two closest of three values (200 MPa√m chemeurope 18Cr-8Ni; ≈250 MPa√m from J ≈ 300 kJ/m², ASTM STP 1985; the outlier 50 MPa√m in an MIT table was dropped). UTS 600 MPa mean at 25 °C (ORNL); G = K²(1−ν²)/E.",
                            "https://www.chemeurope.com/en/encyclopedia/Fracture_toughness.html")
        case "titanium-ti6al4v-annealed":
            // K_IC conflict: 75 (AeroSpace Metals), 91 (NIST TN 2065 citing Donachie), 89.5 (NIST citing Salem 2008, 78–101 midpoint). Two closest 91 and 89.5 → 90.3.
            return estimate(938e6, 90.3e6, "Ti-6Al-4V K_IC about 90.3 MPa√m: average of the two closest of 75 (AeroSpace Metals), 91 (NIST TN 2065, citing Donachie) and 89.5 (NIST, citing Salem 2008); tensile strength 938 MPa. G = K²(1−ν²)/E. See docs/library-materials.md.",
                            "https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2065.pdf")
        case "epoxy-bulk":
            return .available(strength: EpoxyValues.strength * 1e6, energy: EpoxyValues.crackEnergy,
                              source: FractureEstimateSource(citation: EpoxyValues.crackCitation, url: EpoxyValues.crackURL,
                                                             caution: "Handbook estimate; epoxy toughness varies a lot with hardener and cure."))
        case "soda-lime-glass":
            // K_IC 0.75 MPa√m (Wikipedia flat glass; MakeItFrom, agree), breaking strength 41 MPa (Pilkington ATS-129; MakeItFrom).
            return estimate(41e6, 0.75e6, "Soda-lime glass K_IC 0.75 MPa√m (Wikipedia, MakeItFrom; agree) and mean breaking strength 41 MPa (Pilkington ATS-129, MakeItFrom); G = K²(1−ν²)/E. See docs/laminate-material-profiles.md.",
                            "https://en.wikipedia.org/wiki/Soda%E2%80%93lime_glass")
        case "copper-c11000-annealed":
            return .unavailable(reason: "Only copper-alloy values were found (94 MPa√m in one table, 73 for dispersion-strengthened copper), none for annealed C11000, and they disagree.")
        default:
            return .unavailable(reason: "No sourced fracture toughness for this material.")
        }
    }

    /// Fracture settings from the sourced estimate, or nil with the reason in `fractureEstimate`.
    public var defaultFracture: MaterialFractureSettings? {
        guard case let .available(strength, energy, source) = fractureEstimate else { return nil }
        var settings = MaterialFractureSettings()
        settings.strength = strength
        settings.energy = energy
        settings.energySource = source
        return settings
    }
}
