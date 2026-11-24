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

    public var fractureEstimate: FractureEstimate {
        switch id {
        case "aluminum-6061-t6":
            // K_IC 29 MPa√m (TL, ASM-derived datasheet; 22–35 range for wrought 6xxx), typical UTS 310 MPa.
            let energy = Self.energyRelease(toughness: 29e6, material: material)
            return .available(strength: 310e6, energy: energy, source: FractureEstimateSource(
                citation: "6061-T6 typical ultimate tensile strength 310 MPa and plane-strain K_IC 29 MPa√m (TL), aerospacemetals.com Aluminum 6061-T6/T651 datasheet (ASM-derived); G = K²(1−ν²)/E.",
                url: "https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf",
                caution: "A handbook estimate, not a measurement of your part: real K_IC varies about 22–35 MPa√m with orientation and heat, and this crack model is simplified."))
        case "structural-steel-a36":
            return .unavailable(reason: "No sourced fracture toughness found for A36. Its toughness is mostly beyond the valid plane-strain K_IC range, so no value is assumed.")
        case "stainless-304-annealed":
            return .unavailable(reason: "No sourced room-temperature K_IC found for annealed 304 (only cryogenic or irradiated data), so no value is assumed.")
        case "copper-c11000-annealed":
            return .unavailable(reason: "No sourced fracture toughness found for annealed C11000 copper, so no value is assumed.")
        default:
            return .unavailable(reason: "No sourced fracture toughness for this material, so no value is assumed.")
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
