import Foundation
import simd

public enum CouponResponse: String, CaseIterable, Codable, Sendable {
    case elastic = "Elastic"
    case elastoplastic = "Elastoplastic"
}

public struct TensionSettings: Codable, Equatable, Sendable {
    public var response = CouponResponse.elastoplastic
    public var peakFraction = 0.038
    public var yieldFraction = 0.018
    public var hardeningFraction = 0.32

    public static let peakRange = 0.030...0.041
    public static let yieldRange = 0.014...0.025
    public static let hardeningRange = 0.25...0.45

    var isValid: Bool {
        Self.peakRange.contains(peakFraction) && Self.yieldRange.contains(yieldFraction)
            && Self.hardeningRange.contains(hardeningFraction)
    }
}

struct TensionLoad: Sendable {
    let ends: [(node: Int, weight: Double)]
    let height, peak, transitTime, referenceEnergy: Double
    static let rampTransits = 24.0
    static let settleTransits = 8.0
    static let measurementTransits = 6.0

    init(body: Body, width: Double, height: Double, peak: Double) {
        self.height = height
        self.peak = peak
        transitTime = width / body.material.waveSpeed
        referenceEnergy = width * height * peak * peak / (2 * body.material.young)
        let reference = body.mesh.reference
        var weights = Array(repeating: 0.0, count: reference.count)
        for edge in body.mesh.boundary {
            let a = reference[edge.a], b = reference[edge.b]
            if a.x == b.x {
                let weight = (a.x < 0 ? -0.5 : 0.5) * abs(b.y - a.y)
                weights[edge.a] += weight
                weights[edge.b] += weight
            }
        }
        ends = weights.enumerated().filter { $0.element != 0 }.map { ($0.offset, $0.element) }
    }

    var releaseTime: Double { 2 * Self.rampTransits * transitTime }

    func traction(at time: Double) -> Double {
        guard time < releaseTime else { return 0 }
        return 0.5 * peak * (1 - cos(.pi * time / (Self.rampTransits * transitTime)))
    }

    func length(of position: [Point]) -> Double {
        let gauge = ends.reduce(Point.zero) { $0 + $1.weight * position[$1.node] }
        return simd_length(gauge) / height
    }

    func apply(from oldPosition: [Point], to position: [Point], time: Double, dt: Double,
               forces: inout [Point]) -> Double {
        let next = traction(at: time + dt)
        let mean = 0.5 * (traction(at: time) + next)
        var displacement = 0.0
        for (i, weight) in ends {
            forces[i] = Point(weight * next, 0)
            displacement += weight * (position[i].x - oldPosition[i].x)
        }
        return mean * displacement
    }
}

extension Simulation {
    static func tensionCoupon(scene: SceneConfiguration, columns: Int, rows: Int, stepScale: Double) -> Simulation {
        let settings = scene.tension!
        let material = scene.first.material
        let width = scene.first.width
        let height = scene.first.height!
        let mesh = Mesh.rectangle(columns: columns, rows: rows) { u, v in
            Point(width * (u - 0.5), height * (v - 0.5))
        }
        let body = Body(mesh: mesh, material: material,
                        position: mesh.reference.map { $0 + Point(0, scene.centerY) }, velocity: .zero)
        let load = TensionLoad(body: body, width: width, height: height, peak: material.young * settings.peakFraction)
        let model = J2Model(material: material,
                            yieldStress: settings.response == .elastoplastic ? material.young * settings.yieldFraction : nil,
                            hardening: material.young * settings.hardeningFraction)
        return Simulation(primary: body, gap: 0, stepScale: stepScale, tension: load, j2: model)
    }
}
