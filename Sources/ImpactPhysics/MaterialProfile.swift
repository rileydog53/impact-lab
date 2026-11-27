import Foundation

/// Equivalent plastic strain (dimensionless) and equivalent Kirchhoff flow stress (Pa).
public struct HardeningPoint: Codable, Equatable, Sendable {
    public var strain: Double
    public var stress: Double

    public init(strain: Double, stress: Double) {
        self.strain = strain
        self.stress = stress
    }
}

public struct HardeningTable: Codable, Equatable, Sendable {
    public var points: [HardeningPoint]

    public init(points: [HardeningPoint]) { self.points = points }

    public var isValid: Bool {
        guard (2...32).contains(points.count), points.first?.strain == 0 else { return false }
        return points.allSatisfy { (0...1).contains($0.strain) && (1...20e9).contains($0.stress) }
            && zip(points, points.dropFirst()).allSatisfy {
                $1.strain - $0.strain >= 1e-6 && $1.stress >= $0.stress
            }
    }

    // Solve on the segment containing the root. Its residual is strictly
    // decreasing, including on the constant-stress tail.
    func plasticIncrement(trial: Double, oldStrain: Double, threeShear: Double) -> Double {
        let oldStress = flowStress(at: oldStrain)
        guard trial > oldStress else { return 0 }
        var lower = HardeningPoint(strain: oldStrain, stress: oldStress)
        for upper in points where upper.strain > oldStrain {
            let distance = upper.strain - lower.strain
            let residual = trial - threeShear * (upper.strain - oldStrain) - upper.stress
            if residual <= 0 {
                let modulus = (upper.stress - lower.stress) / distance
                let startResidual = trial - threeShear * (lower.strain - oldStrain) - lower.stress
                return lower.strain - oldStrain + startResidual / (threeShear + modulus)
            }
            lower = upper
        }
        return (trial - lower.stress) / threeShear
    }

    package func flowStress(at strain: Double) -> Double {
        var lower = points[0]
        for upper in points.dropFirst() {
            if strain <= upper.strain {
                return lower.stress + (upper.stress - lower.stress)
                    * (strain - lower.strain) / (upper.strain - lower.strain)
            }
            lower = upper
        }
        return lower.stress
    }

    // Integrate the increase above initial yield. The existing J2 energy
    // convention stores this work and dissipates initial yield times strain.
    func storedEnergy(at strain: Double) -> Double {
        let initial = points[0].stress
        var lower = points[0]
        var area = 0.0
        for upper in points.dropFirst() {
            let width = min(strain, upper.strain) - lower.strain
            let increase = (upper.stress - lower.stress) * width / (upper.strain - lower.strain)
            area += width * (lower.stress - initial + 0.5 * increase)
            if strain <= upper.strain { return area }
            lower = upper
        }
        return area + (strain - lower.strain) * (lower.stress - initial)
    }
}

public struct MaterialProvenance: Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public let family: String
    public let condition: String
    public let source: URL
    public let sourceName: String
    public let evidence: String
    public let referenceID: String?

    public var isCustom: Bool { referenceID != nil }

    /// The same label under a new id and name, marked as the user's version of this material.
    public func editableCopy(named newName: String) -> MaterialProvenance {
        MaterialProvenance(id: UUID().uuidString, name: newName, family: family, condition: condition, source: source,
                           sourceName: sourceName, evidence: evidence, referenceID: referenceID ?? id)
    }
    var isValid: Bool {
        !id.isEmpty && id.count <= 64 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 64 && family.count <= 100 && condition.count <= 200 && evidence.count <= 500
            && sourceName.count <= 120 && source.absoluteString.count <= 500 && source.scheme == "https"
    }
}

public struct MaterialProfile: Codable, Equatable, Identifiable, Sendable {
    public var material: Material
    public var hardening: HardeningTable

    package init(material: Material, hardening: HardeningTable) {
        self.material = material
        self.hardening = hardening
    }

    public var id: String { material.provenance!.id }
    public var name: String { material.provenance!.name }
    public var provenance: MaterialProvenance { material.provenance! }
    public var isValid: Bool {
        material.provenance != nil && material.isValidForAssembly && hardening.isValid
    }

    public func duplicate() -> Self {
        var copy = self
        copy.material.provenance = MaterialProvenance(id: UUID().uuidString, name: String(name.prefix(57)) + " Copy",
            family: provenance.family, condition: provenance.condition, source: provenance.source,
            sourceName: provenance.sourceName, evidence: provenance.evidence, referenceID: provenance.referenceID ?? id)
        return copy
    }

    public func apply(to part: inout AssemblyPart, elasticOnly: Bool = false) {
        part.material = material
        part.plasticity = ImpactPlasticity(response: elasticOnly || springsBackOnly ? .elastic : .elastoplastic)
        part.plasticity.table = hardening
    }

    private static func reference(_ id: String, _ name: String, family: String, condition: String,
                                  young: Double, density: Double, poisson: Double,
                                  source: String, url: String, evidence: String, flow: [Double]) -> Self {
        var material = Material(young: young * 1e9, density: density, poisson: poisson)
        material.provenance = MaterialProvenance(id: id, name: name, family: family, condition: condition,
                                                source: URL(string: url)!, sourceName: source, evidence: evidence,
                                                referenceID: nil)
        let strains = [0.0, 0.005, 0.02, 0.06, 0.12]
        return Self(material: material, hardening: HardeningTable(points: zip(strains, flow).map {
            HardeningPoint(strain: $0, stress: $1 * 1e6)
        }))
    }

    public static let structuralSteel = reference("structural-steel-a36", "Structural Steel (A36-like)",
        family: "Carbon steel", condition: "Hot-rolled plate, room temperature",
        young: 200, density: 7850, poisson: 0.30,
        source: "TISCO A36 plate data", url: "https://www.tisco-groups.com/carbon-steel-galvanized-materials/astm-a36-steel-plate/",
        evidence: "Reference-backed density, nominal modulus, and 250 MPa minimum yield for the listed plate. Representative Poisson ratio. Yield plateau and later hardening are illustrative.",
        flow: [250, 250, 285, 365, 440])

    public static let stainless304 = reference("stainless-304-annealed", "304 Stainless Steel",
        family: "Austenitic stainless steel", condition: "Annealed, hot-rolled 304/4301 sheet or coil, 20 °C",
        young: 200, density: 7900, poisson: 0.29,
        source: "Outokumpu Core range data", url: "https://www.outokumpu.com/-/media/files/products/core/outokumpu-core-range-datasheet.pdf",
        evidence: "Reference-backed density, modulus, and 200 MPa minimum 0.2% proof stress for EN hot-rolled coil/sheet. Representative Poisson ratio. Post-yield hardening is illustrative.",
        flow: [200, 245, 320, 450, 560])

    public static let aluminum6061 = reference("aluminum-6061-t6", "6061-T6 Aluminum",
        family: "Wrought aluminum alloy", condition: "Solution heat-treated and artificially aged, room-temperature reference",
        young: 68.9, density: 2700, poisson: 0.33,
        source: "ASM MatWeb, Aluminum Association data", url: "https://asm.matweb.com/search/SpecificMaterial.asp?bassnum=MA6061T6",
        evidence: "Reference-backed typical density, modulus, and 276 MPa tensile yield from the T6/T651 entry. Poisson ratio is estimated. Post-yield hardening is illustrative.",
        flow: [276, 282, 295, 320, 345])

    public static let copperC110 = reference("copper-c11000-annealed", "Annealed Copper (C11000)",
        family: "Electrolytic tough-pitch copper", condition: "Annealed flat product, OS050 grain-size temper, 20 °C",
        young: 117, density: 8910, poisson: 0.33,
        source: "Copper Development Association C11000", url: "https://alloys.copper.org/alloy/C11000",
        evidence: "Reference-backed typical density and tensile modulus, rounded to SI. Poisson ratio is estimated from tensile and shear moduli. Typical 69 MPa at 0.5% extension is used as a representative onset. Post-yield hardening is illustrative.",
        flow: [69, 90, 130, 180, 225])

    public static let references = [structuralSteel, stainless304, aluminum6061, copperC110]
}
