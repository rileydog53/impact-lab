import Foundation
import ImpactPhysics

func blockCheck() {
    var positive = Preset.block.makeSimulation()
    var negative = Preset.block.makeSimulation(mirrored: true)
    let startPositive = positive.body.orientation
    let startNegative = negative.body.orientation
    let initialAngularPositive = positive.diagnostics.angularMomentum
    let initialAngularNegative = negative.diagnostics.angularMomentum
    var maxTorqueError = 0.0
    var maxAngleError = 0.0
    var maxImpulseError = 0.0
    while positive.time < 0.18 {
        let acceptedPositive = positive.step()
        let acceptedNegative = negative.step()
        require(acceptedPositive && acceptedNegative, positive.failure ?? negative.failure ?? "Block step rejected")
        let a = positive.body.orientation - startPositive
        let b = negative.body.orientation - startNegative
        maxAngleError = max(maxAngleError, abs(a + b))
        maxImpulseError = max(maxImpulseError, abs(positive.wallImpulse - negative.wallImpulse))
        maxTorqueError = max(maxTorqueError,
                             abs(positive.diagnostics.angularMomentum - initialAngularPositive - positive.wallAngularImpulse),
                             abs(negative.diagnostics.angularMomentum - initialAngularNegative - negative.wallAngularImpulse))
    }
    let rotationPositive = positive.body.orientation - startPositive
    let rotationNegative = negative.body.orientation - startNegative
    print(String(format: "Mirrored block: rotations %+.3f° / %+.3f°, normal impulses %.4f / %.4f N·s/m",
                 rotationPositive * 180 / .pi, rotationNegative * 180 / .pi,
                 positive.wallImpulse, negative.wallImpulse))
    print(String(format: "Maximum mirrored rotation residual %.2e rad, normal impulse residual %.2e N·s/m, angular-momentum balance residual %.2e N·m·s/m",
                 maxAngleError, maxImpulseError, maxTorqueError))
    require(rotationPositive * rotationNegative < 0 && abs(rotationPositive) > 0.01,
            "The block did not visibly rotate in opposite directions")
    require(positive.wallImpulse > 0 && maxImpulseError < 1e-8 * positive.wallImpulse && maxAngleError < 1e-8,
            "Mirrored angle or normal impulse disagrees")
    require(abs(positive.wallAngularImpulse) > 0.01 && maxTorqueError < 1e-9,
            "Wall torque did not account for angular-momentum change")
}
