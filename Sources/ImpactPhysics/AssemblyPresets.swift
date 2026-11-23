import simd

/// Starting values for controlled numerical experiments.
public enum AssemblyMaterialProfile: String, CaseIterable, Sendable {
    case compliant = "Compliant elastic"
    case reference = "Reference elastic"
    case stiff = "Stiff elastic"
    case yielding = "Yielding J2 solid"

    public var material: Material {
        switch self {
        case .compliant: Material(young: 0.65e6, density: 760, poisson: 0.14)
        case .reference: Material(young: 1.0e6, density: 1000, poisson: 0.12)
        case .stiff: Material(young: 3.2e6, density: 2150, poisson: 0.16)
        case .yielding: Material(young: 1.35e6, density: 1200, poisson: 0.14)
        }
    }

    public var response: CouponResponse { self == .yielding ? .elastoplastic : .elastic }

    public func apply(to part: inout AssemblyPart) {
        part.material = material
        part.plasticity.table = nil
        part.plasticity.response = response
        if self == .yielding {
            part.plasticity.yieldFraction = 0.013
            part.plasticity.hardeningFraction = 0.28
        }
    }
}

public enum AssemblyExperimentPreset: String, CaseIterable, Identifiable, Sendable {
    case inclinedPlate = "Inclined plate"
    case separatedPlates = "Separated plates"
    case bondedComposite = "Bonded composite"
    case hollowSandwich = "Hollow sandwich"
    case angledPanels = "Adjustable panels"

    public enum Boundary: String, CaseIterable, Sendable {
        case free = "Free bodies"
        case supports = "Deformable end supports"
    }

    public var id: Self { self }

    public var defaultBoundary: Boundary {
        switch self {
        case .inclinedPlate, .hollowSandwich: .supports
        default: .free
        }
    }

    public var defaultResolution: AssemblyScene.Resolution { self == .bondedComposite ? .fine : .standard }

    public func scene(boundary: Boundary? = nil, resolution: AssemblyScene.Resolution? = nil) -> AssemblyScene {
        var setup = AssemblyScene()
        setup.meshResolution = resolution ?? defaultResolution
        let targets: [AssemblyPart]
        let gauges: [AssemblyGauge]
        let striker: AssemblyPart

        switch self {
        case .inclinedPlate:
            let plate = part("Inclined plate", size: Point(0.148, 0.026), angle: 12, profile: .yielding)
            targets = [plate]
            striker = loading(plate, x: -0.022, speed: 0.48)
            gauges = [gauge(plate, "Plate center", 0, 0), gauge(plate, "Plate lower face", -0.25, -0.96)]
            setup.duration = 0.052
        case .separatedPlates:
            let front = part("Front plate", size: Point(0.138, 0.028))
            let rear = part("Receiver plate", center: Point(0.005, -0.034), size: Point(0.148, 0.028), profile: .compliant)
            targets = [front, rear]
            striker = loading(front, x: -0.008, speed: 0.59)
            gauges = [gauge(front, "Front plate center", 0, 0), gauge(rear, "Receiver center", 0, 0)]
            setup.duration = 0.070
        case .bondedComposite:
            var composite = part("Three-layer coupon", size: Point(0.061, 0.147), angle: 90, profile: .stiff)
            var layers = AssemblyPart.BondedLayer()
            layers.interfaceFraction = 0.25
            layers.material = AssemblyMaterialProfile.compliant.material
            layers.third = .init(interfaceFraction: 0.75, material: AssemblyMaterialProfile.reference.material)
            composite.bondedLayer = layers
            targets = [composite]
            striker = loading(composite, x: 0, speed: 0.32)
            gauges = [gauge(composite, "Upper layer", 0.76, 0.05), gauge(composite, "Core", 0.04, 0.05),
                      gauge(composite, "Lower layer", -0.76, 0.05)]
            setup.duration = 0.040
        case .hollowSandwich:
            var panel = AssemblyPart("Hollow panel", shape: .enclosure, size: Point(0.158, 0.071))
            panel.wall = 0.011
            AssemblyMaterialProfile.reference.apply(to: &panel)
            targets = [panel]
            striker = loading(panel, x: 0.007, speed: 0.49)
            gauges = [gauge(panel, "Front face", 0.08, 0.98), gauge(panel, "Rear face", 0.08, -0.98),
                      gauge(panel, "Side wall", 0.98, 0.05)]
            setup.duration = 0.055
        case .angledPanels:
            let front = part("Front panel", center: Point(-0.016, 0.024), size: Point(0.119, 0.026), angle: -8)
            let rear = part("Rear panel", center: Point(0.014, -0.019), size: Point(0.125, 0.026), angle: 9, profile: .compliant)
            targets = [front, rear]
            striker = loading(front, x: 0.005, speed: 0.56)
            gauges = [gauge(front, "Front panel center", 0, 0), gauge(rear, "Rear panel center", 0, 0)]
            setup.duration = 0.085
        }

        let rear = targets[targets.count - 1]
        setup.parts = [striker] + targets
        if (boundary ?? defaultBoundary) == .supports {
            setup.parts += endSupports(for: rear, transverse: self == .bondedComposite)
        }
        setup.monitor = rear.id
        setup.gauges = gauges
        return setup
    }

    private func part(_ name: String, center: Point = .zero, size: Point, angle: Double = 0,
                      profile: AssemblyMaterialProfile = .reference) -> AssemblyPart {
        var part = AssemblyPart(name, center: center, size: size)
        part.angle = angle
        profile.apply(to: &part)
        return part
    }

    private func loading(_ target: AssemblyPart, x: Double, speed: Double) -> AssemblyPart {
        let size = Point(0.048, 0.037)
        let angle = target.angle * .pi / 180
        let upper: Double
        if target.bondedLayer != nil {
            upper = target.size.x / 2
        } else {
            let furthest = x - target.center.x + (target.angle < 0 ? -1 : 1) * size.x / 2
            upper = (target.size.y / 2 + sin(angle) * furthest) / cos(angle)
        }
        var striker = part("Striker", center: Point(x, target.center.y + upper + size.y / 2 + 0.0015),
                           size: size, profile: .stiff)
        striker.velocity.y = -speed
        return striker
    }

    private func endSupports(for target: AssemblyPart, transverse: Bool) -> [AssemblyPart] {
        let angle = transverse ? target.angle - 90 : target.angle
        let width = transverse ? target.size.y : target.size.x
        let height = transverse ? target.size.x : target.size.y
        let size = Point(0.032, 0.046)
        let radians = angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        return [-1.0, 1.0].map { side in
            let x = side * 0.33 * width
            let y = -(height + size.y) / 2 - 0.0012
            let position = target.center + Point(c * x - s * y, s * x + c * y)
            return part(side < 0 ? "Left support" : "Right support", center: position,
                        size: size, angle: angle, profile: .stiff)
        }
    }

    private func gauge(_ body: AssemblyPart, _ name: String, _ x: Double, _ y: Double) -> AssemblyGauge {
        AssemblyGauge(body: body.id, name: name, location: Point(x, y), usesBodyFractions: true)
    }
}

extension AssemblyScene {
    /// Free two-body contact at nominal material stiffness and density.
    public static func metalImpactExample() -> Self {
        var scene = Self()
        var target = AssemblyPart("Metal specimen", center: Point(0.02265, 0), size: Point(0.045, 0.036))
        MaterialProfile.copperC110.apply(to: &target)
        var striker = AssemblyPart("Steel striker", center: Point(-0.02265, 0), size: Point(0.045, 0.036))
        MaterialProfile.structuralSteel.apply(to: &striker, elasticOnly: true)
        striker.velocity.x = 24
        scene.parts = [target, striker]
        scene.duration = 0.00015
        scene.monitor = target.id
        scene.gauges = [
            AssemblyGauge(body: target.id, name: "Near impact face", location: Point(-0.018, 0)),
            AssemblyGauge(body: target.id, name: "Near rear face", location: Point(0.018, 0))
        ]
        return scene
    }
}
