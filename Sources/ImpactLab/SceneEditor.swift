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
            }
            if let seam = scene.seam {
                DisclosureGroup("Seam settings") {
                    VStack(alignment: .leading, spacing: 9) {
                        seamControl("Peak stress / softer E", unit: "%", \.strengthFraction,
                                    range: scene.hasImpactedLayers ? SeamSettings.impactStrengthRange : SeamSettings.strengthRange, scale: 100, digits: 2, seam: seam)
                        seamControl(scene.offAxis == nil ? "Critical opening" : "Critical extension", unit: "mm", \.criticalOpening,
                                    range: scene.hasImpactedLayers ? SeamSettings.impactOpeningRange : SeamSettings.openingRange, scale: 1000, digits: 2, seam: seam)
                        if scene.hasImpactedLayers {
                            let peak = seam.strengthFraction * min(scene.second!.material.young, scene.third!.material.young)
                            Text(String(format: "Peak traction %.2f kPa · Gc %.3f J/m²",
                                        peak / 1000, 0.5 * peak * seam.criticalOpening))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("The grips move the layers along the seam normal. Transverse motion is guided.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            if scene.tension == nil && (scene.seam == nil || scene.hasImpactedLayers) {
                DisclosureGroup("Initial conditions") {
                    VStack(alignment: .leading, spacing: 9) {
                        initialControls
                        if scene.isLayeredImpact {
                            backstopControls
                        }
                    }
                    .padding(.top, 8)
                }
            }
            DisclosureGroup(scene.second == nil ? "Material and dimensions" : firstLabel) {
                specimenControls(.first)
                if scene.preset == .materialImpact { yieldControls }
            }
            if scene.second != nil {
                DisclosureGroup(secondLabel) {
                    specimenControls(.second)
                }
            }
            if scene.hasImpactedLayers {
                DisclosureGroup("Backing layer · elastic") { specimenControls(.third) }
                if scene.offAxis != nil {
                    DisclosureGroup("Receiver · elastic") { specimenControls(.receiver) }
                }
                if scene.impactPlasticity?.response == .elastoplastic {
                    DisclosureGroup("Striker and facing yield") { yieldControls.padding(.top, 8) }
                }
            }
        }
        .id(scene.preset)
    }

    private var firstLabel: String {
        switch scene.preset {
        case .twoBars, .bondedBar: "Left bar"
        case .puckStrip: "Puck"
        case .layeredSeam: "Left layer"
        case .layeredImpact, .offAxisImpact: "Striker"
        default: "Specimen"
        }
    }

    private var secondLabel: String {
        switch scene.preset {
        case .puckStrip: "Strip"
        case .layeredSeam: "Right layer"
        case .layeredImpact, .offAxisImpact: "Facing layer"
        default: "Right bar"
        }
    }

    @ViewBuilder
    private var initialControls: some View {
        let speedTitle = scene.isBonded ? "Pulse amplitude" : ((scene.isPair || scene.hasImpactedLayers) ? "Closing speed" : "Initial speed X")
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
        if let options = scene.offAxis {
            offAxisControl("Striker offset Y", unit: "mm", options, \.strikerOffset, OffAxisSettings.strikerOffsetRange, scale: 1000)
            offAxisControl("Striker angle", unit: "°", options, \.strikerAngle, OffAxisSettings.angleRange)
            sceneControl("Striker relative velocity Y", unit: "m/s", key: \.velocityY, range: OffAxisSettings.transverseRange, digits: 2)
            sceneControl("Specimen velocity X", unit: "m/s", key: \.targetVelocityX, range: scene.targetVelocityXRange, digits: 2)
            offAxisControl("Specimen velocity Y", unit: "m/s", options, \.targetVelocityY, OffAxisSettings.transverseRange)
            Divider()
            offAxisControl("Receiver clearance X", unit: "mm", options, \.receiverGap, OffAxisSettings.receiverGapRange, scale: 1000)
            offAxisControl("Receiver offset Y", unit: "mm", options, \.receiverOffset, OffAxisSettings.receiverOffsetRange, scale: 1000)
            offAxisControl("Receiver angle", unit: "°", options, \.receiverAngle, OffAxisSettings.angleRange)
            offAxisControl("Receiver initial velocity X", unit: "m/s", options, \.receiverVelocityX, OffAxisSettings.receiverSpeedRange)
            offAxisControl("Receiver initial velocity Y", unit: "m/s", options, \.receiverVelocityY, OffAxisSettings.transverseRange)
            Divider()
            offAxisControl("Run duration", unit: "ms", options, \.duration, OffAxisSettings.durationRange, scale: 1000)
        } else if scene.hasImpactedLayers {
            sceneControl("Specimen velocity", unit: "m/s", key: \.targetVelocityX,
                         range: scene.targetVelocityXRange, digits: 2)
        } else {
            sceneControl("Center Y", unit: "mm", key: \.centerY, range: SceneConfiguration.centerYRange,
                         scale: 1000, digits: 1)
            sceneControl(scene.isPair ? "Shared initial Y velocity" : "Initial Y velocity", unit: "m/s",
                         key: \.velocityY, range: SceneConfiguration.velocityYRange, digits: 2)
        }
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

    private func offAxisControl(_ label: String, unit: String, _ options: OffAxisSettings,
                                _ key: WritableKeyPath<OffAxisSettings, Double>, _ range: ClosedRange<Double>,
                                scale: Double = 1) -> some View {
        slider(label, unit: unit, value: options[keyPath: key], range: range,
               scale: scale, digits: unit == "m/s" ? 2 : 1) { value in
            var draft = scene
            draft.offAxis?[keyPath: key] = value
            experiment.edit(draft)
        }
    }

    @ViewBuilder
    private var backstopControls: some View {
        Toggle("Rigid backstop", isOn: Binding(get: { scene.backstopGap != nil }, set: { enabled in
            var draft = scene
            draft.backstopGap = enabled ? SceneConfiguration.standard(.layeredImpact).backstopGap : nil
            experiment.edit(draft)
        }))
        if let gap = scene.backstopGap {
            slider("Backstop clearance", unit: "mm", value: gap, range: SceneConfiguration.backstopGapRange,
                   scale: 1000, digits: 1) { value in
                var draft = scene
                draft.backstopGap = value
                experiment.edit(draft)
            }
        }
    }

    @ViewBuilder
    private var yieldControls: some View {
        if let plasticity = scene.impactPlasticity, plasticity.response == .elastoplastic {
            impactControl("Yield stress / E", plasticity, key: \.yieldFraction, range: ImpactPlasticity.yieldRange)
            impactControl("Hardening / E", plasticity, key: \.hardeningFraction, range: ImpactPlasticity.hardeningRange)
        }
    }

    private enum Region {
        case first, second, third, receiver

        func specimen(in scene: SceneConfiguration) -> SpecimenConfiguration {
            switch self {
            case .first: scene.first
            case .second: scene.second!
            case .third: scene.third!
            case .receiver: scene.offAxis!.receiver
            }
        }
    }

    private func specimenControls(_ region: Region) -> some View {
        let nominal = region.specimen(in: .standard(scene.preset))
        let diameter = region == .first && (scene.preset == .puckStrip || scene.preset == .ring)
        let sharedHeight = scene.sharesHeight || (scene.hasImpactedLayers && region == .second) ? "Shared height" : "Height"
        return VStack(alignment: .leading, spacing: 9) {
            let widthLabel = (scene.tension != nil || scene.impactPlasticity != nil) ? "Length" : (diameter ? "Diameter" : "Width")
            specimenControl(widthLabel, unit: "mm", region: region,
                            range: SceneConfiguration.sizeRange(nominal.width), scale: 1000, digits: 1,
                            read: { $0.width }, write: { $0.width = $1 })
            if let height = nominal.height, region != .third, region != .second || !scene.sharesHeight {
                specimenControl(sharedHeight, unit: "mm", region: region,
                                range: SceneConfiguration.sizeRange(height), scale: 1000, digits: 1,
                                read: { $0.height! }, write: { $0.height = $1 })
            }
            if let radius = nominal.cornerRadius {
                specimenControl("Corner radius", unit: "mm", region: region,
                                range: SceneConfiguration.sizeRange(radius), scale: 1000, digits: 1,
                                read: { $0.cornerRadius! }, write: { $0.cornerRadius = $1 })
            }
            if let thickness = nominal.wallThickness {
                specimenControl("Wall thickness", unit: "mm", region: region,
                                range: SceneConfiguration.sizeRange(thickness), scale: 1000, digits: 1,
                                read: { $0.wallThickness! }, write: { $0.wallThickness = $1 })
            }
            specimenControl("Young’s modulus", unit: "MPa", region: region,
                            range: SceneConfiguration.youngRange, scale: 1e-6, digits: 2,
                            read: { $0.material.young }, write: { $0.material.young = $1 })
            specimenControl("Density", unit: "kg/m³", region: region,
                            range: SceneConfiguration.densityRange, digits: 0,
                            read: { $0.material.density }, write: { $0.material.density = $1 })
            specimenControl("Poisson ratio", unit: "", region: region,
                            range: SceneConfiguration.poissonRange, digits: 2,
                            read: { $0.material.poisson }, write: { $0.material.poisson = $1 })
        }
        .padding(.top, 8)
    }

    private func impactControl(_ label: String, _ plasticity: ImpactPlasticity,
                               key: WritableKeyPath<ImpactPlasticity, Double>, range: ClosedRange<Double>) -> some View {
        slider(label, unit: "%", value: plasticity[keyPath: key], range: range, scale: 100, digits: 1) { value in
            var draft = scene
            draft.impactPlasticity?[keyPath: key] = value
            experiment.edit(draft)
        }
    }

    private func tensionControl(_ label: String, _ tension: TensionSettings, key: WritableKeyPath<TensionSettings, Double>,
                                range: ClosedRange<Double>) -> some View {
        slider(label, unit: "%", value: tension[keyPath: key], range: range, scale: 100, digits: 1) { value in
            var draft = scene
            draft.tension?[keyPath: key] = value
            experiment.edit(draft)
        }
    }

    private func seamControl(_ label: String, unit: String, _ key: WritableKeyPath<SeamSettings, Double>,
                             range: ClosedRange<Double>, scale: Double, digits: Int, seam: SeamSettings) -> some View {
        slider(label, unit: unit, value: seam[keyPath: key], range: range, scale: scale, digits: digits) { value in
            var draft = scene
            draft.seam?[keyPath: key] = value
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

    private func specimenControl(_ label: String, unit: String, region: Region,
                                 range: ClosedRange<Double>, scale: Double = 1, digits: Int,
                                 read: @escaping (SpecimenConfiguration) -> Double,
                                 write: @escaping (inout SpecimenConfiguration, Double) -> Void) -> some View {
        slider(label, unit: unit, value: read(region.specimen(in: scene)),
               range: range, scale: scale, digits: digits) { value in
            var draft = scene
            var specimen = region.specimen(in: draft)
            write(&specimen, value)
            switch region {
            case .first:
                draft.first = specimen
                if draft.sharesHeight { draft.second?.height = specimen.height }
            case .second:
                draft.second = specimen
                if draft.hasImpactedLayers { draft.third?.height = specimen.height }
            case .third:
                draft.third = specimen
            case .receiver:
                draft.offAxis?.receiver = specimen
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
