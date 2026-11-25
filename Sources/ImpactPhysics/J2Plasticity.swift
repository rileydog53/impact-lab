import Foundation
import simd

// Plane strain preserves the xy/zz block structure of these 3D tensors.
private struct Symmetric3: Sendable {
    var xx, yy, zz, xy: Double
    static let identity = Self(xx: 1, yy: 1, zz: 1, xy: 0)

    func applied(to p: Point) -> Point {
        Point(xx * p.x + xy * p.y, xy * p.x + yy * p.y)
    }

    func pushed(x: Point, y: Point) -> Self {
        let firstRow = Point(x.x, y.x)
        let secondRow = Point(x.y, y.y)
        let a = applied(to: firstRow)
        let b = applied(to: secondRow)
        return Self(xx: simd_dot(firstRow, a), yy: simd_dot(secondRow, b),
                    zz: zz, xy: simd_dot(firstRow, b))
    }
}

package struct J2History: Sendable {
    fileprivate var inversePlasticMetric = Symmetric3.identity
    package fileprivate(set) var equivalentStrain = 0.0
    package init() {}
}

package struct J2Response {
    package let history: J2History
    package let piolaX, piolaY: Point
    package let cauchyZZ, equivalentStress: Double
    package let elasticEnergy, hardeningEnergy, dissipation: Double
}

package struct J2Model: Sendable {
    let shear, bulk: Double
    let yieldStress: Double?
    let hardening: Double
    private let table: HardeningTable?

    package init(material: Material, yieldStress: Double? = nil, hardening: Double = 0) {
        shear = material.shear
        bulk = material.lambda + 2 * shear / 3
        self.yieldStress = yieldStress
        self.hardening = hardening
        table = nil
    }

    package init(material: Material, table: HardeningTable) {
        shear = material.shear
        bulk = material.lambda + 2 * shear / 3
        yieldStress = table.points[0].stress
        hardening = 0
        self.table = table
    }

    /// True when both models give the same response (used to share one model per bonded region).
    func sameParameters(as other: J2Model) -> Bool {
        shear == other.shear && bulk == other.bulk && yieldStress == other.yieldStress && hardening == other.hardening
            && table == other.table
    }

    private func plasticIncrement(trial: Double, strain: Double) -> Double {
        if let table { return table.plasticIncrement(trial: trial, oldStrain: strain, threeShear: 3 * shear) }
        guard let yieldStress, trial > yieldStress + hardening * strain else { return 0 }
        return (trial - yieldStress - hardening * strain) / (3 * shear + hardening)
    }

    package func update(x: Point, y: Point, from old: J2History) -> J2Response? {
        let jacobian = cross2D(x, y)
        guard jacobian > 0 && jacobian.isFinite else { return nil }
        let trial = old.inversePlasticMetric.pushed(x: x, y: y)
        let center = (trial.xx + trial.yy) / 2
        let difference = (trial.xx - trial.yy) / 2
        let radius = hypot(difference, trial.xy)
        guard center - radius > 0, trial.zz > 0 else { return nil }

        // Principal elastic Hencky strains are half the logarithms of b_e.
        let logCenter = 0.25 * (log(center + radius) + log(center - radius))
        let logRadius = 0.5 * atanh(radius / center)
        let logZZ = 0.5 * log(trial.zz)
        let mean = (2 * logCenter + logZZ) / 3
        let centeredXY = logCenter - mean
        let centeredZZ = logZZ - mean
        let normSquared = 2 * (centeredXY * centeredXY + logRadius * logRadius) + centeredZZ * centeredZZ
        let trialStress = 2 * shear * sqrt(1.5 * normSquared)
        let logJ = log(jacobian)
        let pressure = bulk * logJ
        let inverseX = Point(y.y, -x.y) / jacobian
        let inverseY = Point(-y.x, x.x) / jacobian

        var history = old
        var scale = 1.0
        // The Hencky law returns Kirchhoff stress. Cauchy stress is tau/J;
        // these tabulated flow stresses are interpreted as Kirchhoff values.
        let increment = plasticIncrement(trial: trialStress, strain: old.equivalentStrain)
        if increment > 0 {
            history.equivalentStrain += increment
            scale = max(0, 1 - 3 * shear * increment / trialStress)

            // Exponentiate the returned elastic strains and pull b_e back
            // to the reference configuration to retain an objective history.
            let stretch = exp(2 * (logJ / 3 + scale * centeredXY))
            let halfSpan = 2 * scale * logRadius
            let midpoint = stretch * cosh(halfSpan)
            let spread = radius > 0 ? stretch * sinh(halfSpan) / radius : 0
            let returned = Symmetric3(xx: midpoint + spread * difference, yy: midpoint - spread * difference,
                                      zz: exp(2 * (logJ / 3 + scale * centeredZZ)), xy: spread * trial.xy)
            history.inversePlasticMetric = returned.pushed(x: inverseX, y: inverseY)
        }

        // Flow includes the zz deviator even though the total Fzz is one.
        let amplitude = 2 * shear * scale
        let meanXYStress = pressure + amplitude * centeredXY
        let direction = radius > 0 ? amplitude * logRadius / radius : 0
        let tau = Symmetric3(xx: meanXYStress + direction * difference, yy: meanXYStress - direction * difference,
                             zz: pressure + amplitude * centeredZZ, xy: direction * trial.xy)
        let elastic = 0.5 * bulk * logJ * logJ + shear * scale * scale * normSquared
        let alpha = history.equivalentStrain
        let columnX = tau.applied(to: Point(inverseX.x, inverseY.x))
        let columnY = tau.applied(to: Point(inverseX.y, inverseY.y))
        guard (elastic + alpha + tau.zz + columnX.x + columnX.y + columnY.x + columnY.y).isFinite
        else { return nil }
        return J2Response(history: history, piolaX: columnX, piolaY: columnY, cauchyZZ: tau.zz / jacobian,
                          equivalentStress: scale * trialStress, elasticEnergy: elastic,
                          hardeningEnergy: table?.storedEnergy(at: alpha) ?? 0.5 * hardening * alpha * alpha,
                          dissipation: (yieldStress ?? 0) * alpha)
    }
}
