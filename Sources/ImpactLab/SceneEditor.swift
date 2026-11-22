import ImpactPhysics
import SwiftUI

struct SceneEditor: View {
    let experiment: Experiment

    private var scene: SceneConfiguration { experiment.configuration }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tension = scene.tension {
                DisclosureGroup("Loading and yield") {
                    VStack(alignment: .leading, spacing: 9) {
                        tensionControl("Peak end stress / E", tension, key: \.peakFraction, range: TensionSettings.peakRange)
                        if tension.response == .elastoplastic {
                            tensionControl("Yield stress / E", tension, key: \.yieldFraction, range: TensionSettings.yieldRange)
                            tensionControl("Hardening / E", tension, key: \.hardeningFraction, range: TensionSettings.hardeningRange)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                DisclosureGroup("Initial conditions") {
                    VStack(alignment: .leading, spacing: 9) {
                        initialControls
                    }
                    .padding(.top, 8)
                }
            }
            DisclosureGroup(scene.second == nil ? "Material and dimensions" : firstLabel) {
                specimenControls(second: false)
            }
            if scene.second != nil {
                DisclosureGroup(secondLabel) {
                    specimenControls(second: true)
                }
            }
        }
        .id(scene.preset)
    }

    private var firstLabel: String {
        switch scene.preset {
        case .twoBars, .bondedBar: "Left bar"
        case .puckStrip: "Puck"
        default: "Specimen"
        }
    }

    private var secondLabel: String { scene.preset == .puckStrip ? "Strip" : "Right bar" }

    @ViewBuilder
    private var initialControls: some View {
        let speedTitle = scene.isBonded ? "Pulse amplitude" : (scene.isPair ? "Closing speed" : "Initial speed X")
        sceneControl(speedTitle, unit: "m/s", key: \.speed, range: scene.speedRange, digits: 2)
        if !scene.isBonded {
            sceneControl("Starting gap", unit: "mm", key: \.gap, range: scene.gapRange, scale: 1000, digits: 2)
        }
        if scene.isPair || scene.isBonded {
            sceneControl(scene.isBonded ? "Bond position X" : "Target face X", unit: "mm",
                         key: \.targetX, range: scene.targetXRange, scale: 1000, digits: 1)
            sceneControl(scene.isBonded ? "Bar drift X" : "Target velocity X", unit: "m/s",
                         key: \.targetVelocityX, range: scene.targetVelocityXRange, digits: 2)
        }
        sceneControl("Center Y", unit: "mm", key: \.centerY, range: SceneConfiguration.centerYRange,
                     scale: 1000, digits: 1)
        sceneControl(scene.isPair ? "Shared initial Y velocity" : "Initial Y velocity", unit: "m/s",
                     key: \.velocityY, range: SceneConfiguration.velocityYRange, digits: 2)
        if scene.preset == .puckStrip {
            sceneControl("Puck offset Y", unit: "mm", key: \.puckOffsetY, range: scene.puckOffsetRange,
                         scale: 1000, digits: 1)
        }
        if scene.preset == .block {
            Toggle("Mirror tilt", isOn: Binding(get: { scene.mirrored }, set: { value in
                var draft = scene
                draft.mirrored = value
                experiment.edit(draft)
            }))
        }
    }

    private func specimenControls(second: Bool) -> some View {
        let standard = SceneConfiguration.standard(scene.preset)
        let nominal = second ? standard.second! : standard.first
        let diameter = !second && (scene.preset == .puckStrip || scene.preset == .ring)
        let sharedHeight = scene.sharesHeight ? "Shared height" : "Height"
        return VStack(alignment: .leading, spacing: 9) {
            let widthLabel = scene.tension != nil ? "Length" : (diameter ? "Diameter" : "Width")
            specimenControl(widthLabel, unit: "mm", second: second,
                            range: SceneConfiguration.sizeRange(nominal.width), scale: 1000, digits: 1,
                            read: { $0.width }, write: { $0.width = $1 })
            if let height = nominal.height, !second || !scene.sharesHeight {
                specimenControl(sharedHeight, unit: "mm", second: second,
                                range: SceneConfiguration.sizeRange(height), scale: 1000, digits: 1,
                                read: { $0.height! }, write: { $0.height = $1 })
            }
            if let radius = nominal.cornerRadius {
                specimenControl("Corner radius", unit: "mm", second: second,
                                range: SceneConfiguration.sizeRange(radius), scale: 1000, digits: 1,
                                read: { $0.cornerRadius! }, write: { $0.cornerRadius = $1 })
            }
            if let thickness = nominal.wallThickness {
                specimenControl("Wall thickness", unit: "mm", second: second,
                                range: SceneConfiguration.sizeRange(thickness), scale: 1000, digits: 1,
                                read: { $0.wallThickness! }, write: { $0.wallThickness = $1 })
            }
            specimenControl("Young’s modulus", unit: "MPa", second: second,
                            range: SceneConfiguration.youngRange, scale: 1e-6, digits: 2,
                            read: { $0.material.young }, write: { $0.material.young = $1 })
            specimenControl("Density", unit: "kg/m³", second: second,
                            range: SceneConfiguration.densityRange, digits: 0,
                            read: { $0.material.density }, write: { $0.material.density = $1 })
            specimenControl("Poisson ratio", unit: "", second: second,
                            range: SceneConfiguration.poissonRange, digits: 2,
                            read: { $0.material.poisson }, write: { $0.material.poisson = $1 })
        }
        .padding(.top, 8)
    }

    private func tensionControl(_ label: String, _ tension: TensionSettings, key: WritableKeyPath<TensionSettings, Double>,
                                range: ClosedRange<Double>) -> some View {
        slider(label, unit: "%", value: tension[keyPath: key], range: range, scale: 100, digits: 1) { value in
            var draft = scene
            draft.tension?[keyPath: key] = value
            experiment.edit(draft)
        }
    }

    private func sceneControl(_ label: String, unit: String, key: WritableKeyPath<SceneConfiguration, Double>,
                              range: ClosedRange<Double>, scale: Double = 1, digits: Int) -> some View {
        slider(label, unit: unit, value: scene[keyPath: key], range: range, scale: scale, digits: digits) { value in
            var draft = scene
            draft[keyPath: key] = value
            experiment.edit(draft)
        }
    }

    private func specimenControl(_ label: String, unit: String, second: Bool,
                                 range: ClosedRange<Double>, scale: Double = 1, digits: Int,
                                 read: @escaping (SpecimenConfiguration) -> Double,
                                 write: @escaping (inout SpecimenConfiguration, Double) -> Void) -> some View {
        slider(label, unit: unit, value: read(second ? scene.second! : scene.first),
               range: range, scale: scale, digits: digits) { value in
            var draft = scene
            if second, var specimen = draft.second {
                write(&specimen, value)
                draft.second = specimen
            } else {
                write(&draft.first, value)
                if draft.sharesHeight { draft.second?.height = draft.first.height }
            }
            experiment.edit(draft)
        }
    }

    private func slider(_ label: String, unit: String, value: Double,
                        range: ClosedRange<Double>, scale: Double, digits: Int,
                        change: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.callout)
                Spacer(minLength: 5)
                Text((value * scale).formatted(.number.precision(.fractionLength(digits)))
                     + (unit.isEmpty ? "" : " " + unit))
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { value }, set: { change(min(range.upperBound, max(range.lowerBound, $0))) }),
                   in: range) { Text(label) }
                .labelsHidden()
        }
        .font(.callout)
    }
}
