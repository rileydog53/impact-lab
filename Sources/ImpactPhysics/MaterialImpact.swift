import simd

public struct ImpactPlasticity: Codable, Equatable, Sendable {
    public var response = CouponResponse.elastoplastic
    public var yieldFraction = 0.016
    public var hardeningFraction = 0.32

    public static let yieldRange = 0.010...0.035
    public static let hardeningRange = TensionSettings.hardeningRange

    func model(for material: Material) -> J2Model {
        J2Model(material: material, yieldStress: response == .elastoplastic ? material.young * yieldFraction : nil,
                hardening: material.young * hardeningFraction)
    }

    var isValid: Bool {
        Self.yieldRange.contains(yieldFraction) && Self.hardeningRange.contains(hardeningFraction)
    }
}

extension Simulation {
    static func materialImpact(scene: SceneConfiguration, columns: Int, rows: Int, stepScale: Double) -> Simulation {
        let settings = scene.impactPlasticity!
        let material = scene.first.material
        let mesh = Mesh.bar(columns: columns, rows: rows, width: scene.first.width, height: scene.first.height!)
        let body = Body(mesh: mesh, material: material, velocity: Point(scene.speed, scene.velocityY),
                        gap: scene.gap, penalty: 2500, tilt: 0, centerY: scene.centerY)
        return Simulation(primary: body, gap: scene.gap, stepScale: stepScale, j2: settings.model(for: material))
    }
}

struct EndGauge {
    private let weights: [(node: Int, value: Double)]

    init(body: Body, length: Double, height: Double) {
        let reference = body.mesh.reference
        var weights = Array(repeating: 0.0, count: reference.count)
        for edge in body.mesh.boundary {
            let a = reference[edge.a], b = reference[edge.b]
            if a.x == b.x && (a.x == 0 || a.x == -length) {
                let weight = (a.x == 0 ? 0.5 : -0.5) * abs(b.y - a.y) / height
                weights[edge.a] += weight
                weights[edge.b] += weight
            }
        }
        self.weights = weights.enumerated().filter { $0.element != 0 }.map { ($0.offset, $0.element) }
    }

    func length(of position: [Point]) -> Double {
        simd_length(weights.reduce(.zero) { $0 + $1.value * position[$1.node] })
    }
}
