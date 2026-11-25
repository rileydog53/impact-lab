import ImpactPhysics

/// Every body and layer the user adds starts as a real Library material (Joseph, 2026-11-25). The old rubber-soft
/// demo materials stay in the physics package only, so older scenes, presets and checks replay exactly.
enum RealMaterialDefaults {
    /// New free bodies: aluminium that bends for good.
    static let body = MaterialProfile.aluminum6061
    /// Supports, benches and rollers: steel. Fixed ones spring back only, since a fixed support never deforms.
    static let support = MaterialProfile.structuralSteel
    static let secondLayer = MaterialProfile.structuralSteel
    static let thirdLayer = MaterialProfile.aluminum6061

    static func apply(to part: inout AssemblyPart) {
        let profile = part.support == nil ? body : support
        profile.apply(to: &part, elasticOnly: part.support == .fixed)
    }

    static func plasticity(of profile: MaterialProfile) -> ImpactPlasticity? {
        var applied = AssemblyPart("layer")
        profile.apply(to: &applied)
        return applied.plasticity.response == .elastoplastic ? applied.plasticity : nil
    }
}

extension AssemblyPart.BondedLayer {
    static func realDefault() -> Self {
        var layer = Self()
        layer.material = RealMaterialDefaults.secondLayer.material
        layer.plasticity = RealMaterialDefaults.plasticity(of: RealMaterialDefaults.secondLayer)
        return layer
    }
}

extension AssemblyPart.BondedLayer.ThirdLayer {
    static func realDefault(interfaceFraction: Double) -> Self {
        var layer = Self(interfaceFraction: interfaceFraction, material: RealMaterialDefaults.thirdLayer.material)
        layer.plasticity = RealMaterialDefaults.plasticity(of: RealMaterialDefaults.thirdLayer)
        return layer
    }
}
