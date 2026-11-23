import Foundation

/// Paired experiments that compare one physical variable at a time.
/// Each scenario builds an ordinary editable assembly for cases A and B and
/// measures the recorded replays. Predictions are computed from the scenes
/// actually run, so edited reruns are measured against their own inputs.
public enum LabScenario: String, CaseIterable, Identifiable, Sendable {
    case elasticContrast = "Elastic contrast"
    case elasticVersusYielding = "Elastic versus yielding"
    case strainHardening = "Strain hardening"
    case bondedLayers = "Bonded layers"
    case interfaceFailure = "Interface failure"

    public var id: Self { self }

    public enum Evidence: String, Sendable {
        case verified = "Verified model, reference-backed elastic data"
        case mixed = "Verified model, illustrative hardening"
        case analytic = "Verified against an analytic prediction"
        case illustrative = "Verified numerics, illustrative material"
    }

    public struct Settings: Equatable, Sendable {
        public var first: Int
        public var second: Int
        public var shared: Int
        public var speed: Double

        public init(first: Int, second: Int, shared: Int, speed: Double) {
            self.first = first
            self.second = second
            self.shared = shared
            self.speed = speed
        }
    }

    // MARK: Description

    public var question: String {
        switch self {
        case .elasticContrast: "How fast does a stress wave cross two different metals, and how much motion does each one take from the same striker?"
        case .elasticVersusYielding: "What changes when the same metal is allowed to yield instead of staying perfectly elastic?"
        case .strainHardening: "How do two metals with different hardening curves absorb the same impact?"
        case .bondedLayers: "How much of a pulse reflects and how much passes through a permanent bond between two layers?"
        case .interfaceFailure: "What does a crack change in the same bending impact, and where does the energy go?"
        }
    }

    public var procedure: String {
        switch self {
        case .elasticContrast: "An elastic steel striker hits the end of a long elastic bar. Two gauges 150 mm apart time the wave front. Only the bar material differs between A and B."
        case .elasticVersusYielding: "A steel striker hits a metal block. Case A uses only the block's elastic constants. Case B adds its J2 yield and hardening curve."
        case .strainHardening: "A steel striker hits two different J2 metal blocks at the same speed. Each block uses its own tabulated hardening curve."
        case .bondedLayers: "A striker launches a small pulse along a two-layer bar bonded with shared nodes. Case A is a matched control. Case B changes the second layer's impedance while keeping its wave speed."
        case .interfaceFailure: "A striker bends a beam on two supports. Case A cannot crack. Case B can open cohesive cracks with the chosen fracture energy."
        }
    }

    public var limitations: String {
        switch self {
        case .elasticContrast: "2D plane strain with elastic constants only. The prediction is the plane-strain bar speed √(E/ρ(1−ν²)). Short pulses in a 25 mm bar disperse, so expect agreement within several percent rather than exactly. Gauge timing is limited by the recorded frame spacing. The striker is about as long as it is thick, so its rebound shows the impedance trend but not the 1D formula."
        case .elasticVersusYielding: "Rate-independent J2 plasticity in plane strain, with no strain-rate or thermal effects. Real metals are stronger at high strain rates, so measured permanent strain here is not a prediction for a real part. The elastic stress estimate is one-dimensional."
        case .strainHardening: "Initial yield values are reference-backed, but every post-yield hardening curve is illustrative. Compare the trend, not the exact numbers. No strain-rate, temperature or damage effects."
        case .bondedLayers: "Small-amplitude elastic waves with an illustrative soft material. The bond never fails. The analytic values are 1D impedance predictions, and the automatic windows assume the scenario's geometry."
        case .interfaceFailure: "Illustrative elastic material with cohesive crack insertion between existing triangles. Crack paths follow the mesh and change with refinement. This is not a model of a specific real material."
        }
    }

    public var evidence: Evidence {
        switch self {
        case .elasticContrast: .verified
        case .elasticVersusYielding, .strainHardening: .mixed
        case .bondedLayers: .analytic
        case .interfaceFailure: .illustrative
        }
    }

    public var icon: String {
        switch self {
        case .elasticContrast: "waveform.path"
        case .elasticVersusYielding: "arrow.uturn.backward"
        case .strainHardening: "chart.line.uptrend.xyaxis"
        case .bondedLayers: "square.split.2x1"
        case .interfaceFailure: "bolt.horizontal"
        }
    }

    // MARK: Controls

    /// Choices for each case. A single entry means the case is fixed.
    public var firstOptions: [String] {
        switch self {
        case .elasticContrast, .strainHardening: Self.metals.map(\.name)
        case .elasticVersusYielding: ["Elastic only"]
        case .bondedLayers: ["Matched second layer"]
        case .interfaceFailure: ["Cracking disabled"]
        }
    }

    public var secondOptions: [String] {
        switch self {
        case .elasticContrast, .strainHardening: Self.metals.map(\.name)
        case .elasticVersusYielding: ["J2 yielding with hardening"]
        case .bondedLayers: Self.impedanceRatios.map { "Second layer impedance \($0.label)" }
        case .interfaceFailure: Self.fractureEnergies.map { String(format: "Cracking, G꜀ %.1f J/m²", $0) }
        }
    }

    public var sharedLabel: String? { self == .elasticVersusYielding ? "Metal" : nil }
    public var sharedOptions: [String] { self == .elasticVersusYielding ? Self.metals.map(\.name) : [] }

    public var speedRange: ClosedRange<Double> {
        switch self {
        case .elasticContrast: 2...20
        case .elasticVersusYielding, .strainHardening: 5...40
        case .bondedLayers: 0.05...0.2
        case .interfaceFailure: 0.8...2.0
        }
    }

    public var speedStep: Double {
        switch self {
        case .elasticContrast, .elasticVersusYielding, .strainHardening: 1
        case .bondedLayers: 0.01
        case .interfaceFailure: 0.05
        }
    }

    public var defaultSettings: Settings {
        switch self {
        case .elasticContrast: Settings(first: 0, second: 3, shared: 0, speed: 10)
        case .elasticVersusYielding: Settings(first: 0, second: 0, shared: 3, speed: 24)
        case .strainHardening: Settings(first: 3, second: 1, shared: 0, speed: 24)
        case .bondedLayers: Settings(first: 0, second: 1, shared: 0, speed: 0.10)
        case .interfaceFailure: Settings(first: 0, second: 0, shared: 0, speed: 1.45)
        }
    }

    public static let metals = MaterialProfile.references
    static let impedanceRatios: [(ratio: Double, label: String)] = [(0.5, "½×"), (2, "2×"), (4, "4×"), (8, "8×")]
    static let fractureEnergies = [3.5, 7.0, 14.0]

    public func caseLabel(_ settings: Settings, case index: Int) -> String {
        let options = index == 0 ? firstOptions : secondOptions
        let choice = index == 0 ? settings.first : settings.second
        var label = options[min(max(0, choice), options.count - 1)]
        if self == .elasticVersusYielding { label += " · " + Self.metals[settings.shared].name }
        return label
    }

    // MARK: Scenes

    public func scene(_ settings: Settings, case index: Int) -> AssemblyScene {
        let choice = index == 0 ? settings.first : settings.second
        switch self {
        case .elasticContrast:
            return Self.waveBar(Self.metals[choice], speed: settings.speed)
        case .elasticVersusYielding:
            return Self.metalBlock(Self.metals[settings.shared], yielding: index == 1, speed: settings.speed)
        case .strainHardening:
            return Self.metalBlock(Self.metals[choice], yielding: true, speed: settings.speed)
        case .bondedLayers:
            var scene = AssemblyScene.bondedWaveExample()
            let soft = scene.parts[1].material
            let ratio = index == 0 ? 1 : Self.impedanceRatios[choice].ratio
            scene.parts[1].bondedLayer?.material = Material(young: soft.young * ratio, density: soft.density * ratio,
                                                            poisson: soft.poisson)
            scene.parts[0].velocity.x = settings.speed
            return scene
        case .interfaceFailure:
            var scene = AssemblyScene.bendingFractureExample()
            if index == 0 {
                scene.parts[0].fracture = nil
            } else {
                scene.parts[0].fracture?.energy = Self.fractureEnergies[choice]
            }
            scene.parts[1].velocity.y = -settings.speed
            return scene
        }
    }

    static func waveBar(_ profile: MaterialProfile, speed: Double) -> AssemblyScene {
        var scene = AssemblyScene()
        scene.meshResolution = .x4
        var bar = AssemblyPart("Bar · " + profile.name, center: Point(0.1, 0), size: Point(0.2, 0.025))
        profile.apply(to: &bar, elasticOnly: true)
        var striker = AssemblyPart("Steel striker", center: Point(-0.01505, 0), size: Point(0.03, 0.025))
        MaterialProfile.structuralSteel.apply(to: &striker, elasticOnly: true)
        striker.velocity.x = speed
        scene.parts = [striker, bar]
        scene.monitor = bar.id
        scene.duration = 0.0001
        scene.gauges = [
            AssemblyGauge(body: bar.id, name: "Near gauge (25 mm)", location: Point(-0.075, 0)),
            AssemblyGauge(body: bar.id, name: "Far gauge (175 mm)", location: Point(0.075, 0))
        ]
        return scene
    }

    static func metalBlock(_ profile: MaterialProfile, yielding: Bool, speed: Double) -> AssemblyScene {
        var scene = AssemblyScene.metalImpactExample()
        scene.meshResolution = .x4
        profile.apply(to: &scene.parts[0], elasticOnly: !yielding)
        scene.parts[0].name = profile.name + (yielding ? " block" : " block (elastic)")
        scene.parts[1].velocity.x = speed
        return scene
    }

    // MARK: Measurement

    public struct Row: Identifiable, Sendable {
        public let label: String
        public let first: String
        public let second: String
        public let prediction: String?
        public var id: String { label }
    }

    public struct Report: Sendable {
        public let rows: [Row]
        public let finding: String
    }

    /// A finished case: the scene that was calculated and its recording.
    public struct Case: Sendable {
        public let scene: AssemblyScene
        public let replay: AssemblyReplay

        public init(scene: AssemblyScene, replay: AssemblyReplay) {
            self.scene = scene
            self.replay = replay
        }
    }

    public func report(_ a: Case, _ b: Case) -> Report? {
        guard a.replay.frames.count > 2, b.replay.frames.count > 2 else { return nil }
        switch self {
        case .elasticContrast: return Self.waveReport(a, b)
        case .elasticVersusYielding, .strainHardening: return Self.impactReport(a, b, hardening: self == .strainHardening)
        case .bondedLayers: return Self.bondReport(a, b)
        case .interfaceFailure: return Self.fractureReport(a, b)
        }
    }

    // Elastic contrast

    public struct WaveMeasurement: Sendable {
        public let speed, predictedSpeed, strikerVelocity, predictedStrikerVelocity: Double
    }

    public static func measureWave(_ run: Case) -> WaveMeasurement? {
        let scene = run.scene
        guard scene.parts.count == 2, let gauges = scene.gauges, gauges.count == 2 else { return nil }
        let frames = run.replay.frames
        func crossing(_ gauge: Int) -> Double? {
            let values = frames.map { abs($0.gauges[gauge].strain) }
            guard let peak = values.max(), peak > 0 else { return nil }
            let threshold = 0.25 * peak
            guard let i = values.firstIndex(where: { $0 >= threshold }), i > 0 else { return nil }
            let fraction = (threshold - values[i - 1]) / (values[i] - values[i - 1])
            return frames[i - 1].time + fraction * (frames[i].time - frames[i - 1].time)
        }
        guard let near = crossing(0), let far = crossing(1), far > near else { return nil }
        let distance = abs(gauges[1].location.x - gauges[0].location.x)
        let bar = scene.parts[1].material, striker = scene.parts[0].material
        let barSpeed = { (m: Material) in sqrt(m.young / (m.density * (1 - m.poisson * m.poisson))) }
        let zBar = bar.density * barSpeed(bar), zStriker = striker.density * barSpeed(striker)
        let impact = abs(scene.parts[0].velocity.x)
        // A 1D elastic striker leaves with v(Zs − Zb)/(Zs + Zb) after its release wave returns.
        let rebound = run.replay.frames.last!.bodies[0].body.centerVelocity.x
        return WaveMeasurement(speed: distance / (far - near), predictedSpeed: barSpeed(bar),
                               strikerVelocity: rebound, predictedStrikerVelocity: impact * (zStriker - zBar) / (zStriker + zBar))
    }

    static func waveReport(_ a: Case, _ b: Case) -> Report? {
        guard let first = measureWave(a), let second = measureWave(b) else { return nil }
        let impedance = { (m: Material) in m.density * sqrt(m.young / (m.density * (1 - m.poisson * m.poisson))) / 1e6 }
        let ma = a.scene.parts[1].material, mb = b.scene.parts[1].material
        let rows = [
            Row(label: "Measured wave speed", first: ms(first.speed), second: ms(second.speed),
                prediction: "\(ms(first.predictedSpeed)) · \(ms(second.predictedSpeed))"),
            Row(label: "Speed error vs prediction", first: percent(first.speed / first.predictedSpeed - 1),
                second: percent(second.speed / second.predictedSpeed - 1), prediction: nil),
            Row(label: "Acoustic impedance ρc", first: String(format: "%.1f MPa·s/m", impedance(ma)),
                second: String(format: "%.1f MPa·s/m", impedance(mb)), prediction: nil),
            Row(label: "Striker velocity after impact", first: mps(first.strikerVelocity), second: mps(second.strikerVelocity),
                prediction: nil)
        ]
        let ratio = second.speed / first.speed
        let finding = String(format: "The wave crossed case B at %.2f× the speed of case A (predicted %.2f×). The bar with lower impedance takes less of the striker's momentum, so the striker is left moving faster toward it.",
                             ratio, second.predictedSpeed / first.predictedSpeed)
        return Report(rows: rows, finding: finding)
    }

    // Elastic versus yielding and strain hardening

    public struct ImpactMeasurement: Sendable {
        public let plasticWork, plasticShare, peakPlasticStrain, peakStress, elasticEnergy, restitution: Double
    }

    public static func measureImpact(_ run: Case) -> ImpactMeasurement? {
        guard let first = run.replay.frames.first, let last = run.replay.frames.last, run.scene.parts.count == 2 else { return nil }
        let initial = first.energies.kinetic
        let specimen = last.bodies[0], striker = last.bodies[1]
        let peakStress = run.replay.frames.map { $0.bodies[0].stress.map(\.equivalent).max() ?? 0 }.max() ?? 0
        let v0 = abs(run.scene.parts[1].velocity.x)
        let restitution = (specimen.body.centerVelocity.x - striker.body.centerVelocity.x) / max(v0, 1e-12)
        return ImpactMeasurement(plasticWork: last.energies.plastic, plasticShare: last.energies.plastic / initial,
                                 peakPlasticStrain: specimen.plasticStrain.max() ?? 0, peakStress: peakStress,
                                 elasticEnergy: last.energies.elastic / initial, restitution: restitution)
    }

    static func impactReport(_ a: Case, _ b: Case, hardening: Bool) -> Report? {
        guard let first = measureImpact(a), let second = measureImpact(b) else { return nil }
        func elasticEstimate(_ run: Case) -> Double {
            let specimen = run.scene.parts[0].material, striker = run.scene.parts[1].material
            let z = { (m: Material) in m.density * sqrt(m.young / (m.density * (1 - m.poisson * m.poisson))) }
            return abs(run.scene.parts[1].velocity.x) * z(specimen) * z(striker) / (z(specimen) + z(striker))
        }
        func yield(_ run: Case) -> String {
            let part = run.scene.parts[0]
            guard part.plasticity.response == .elastoplastic, let table = part.plasticity.table else { return "none (elastic)" }
            return mpa(table.flowStress(at: 0))
        }
        func flow12(_ run: Case) -> String {
            guard let table = run.scene.parts[0].plasticity.table, run.scene.parts[0].plasticity.response == .elastoplastic else { return "—" }
            return mpa(table.flowStress(at: 0.12))
        }
        var rows = [
            Row(label: "1D elastic impact stress estimate", first: mpa(elasticEstimate(a)), second: mpa(elasticEstimate(b)), prediction: nil),
            Row(label: "Initial yield stress", first: yield(a), second: yield(b), prediction: nil)
        ]
        if hardening {
            rows.append(Row(label: "Flow stress at 12% plastic strain", first: flow12(a), second: flow12(b), prediction: nil))
        }
        rows += [
            Row(label: "Peak equivalent stress (Cauchy)", first: mpa(first.peakStress), second: mpa(second.peakStress), prediction: nil),
            Row(label: "Peak plastic strain", first: percent(first.peakPlasticStrain), second: percent(second.peakPlasticStrain), prediction: nil),
            Row(label: "Plastic work (permanently dissipated)", first: String(format: "%.1f J/m", first.plasticWork),
                second: String(format: "%.1f J/m", second.plasticWork), prediction: nil),
            Row(label: "Share of impact energy dissipated", first: percent(first.plasticShare), second: percent(second.plasticShare), prediction: nil),
            Row(label: "Share left as elastic vibration", first: percent(first.elasticEnergy), second: percent(second.elasticEnergy), prediction: nil),
            Row(label: "Separation speed ÷ impact speed", first: String(format: "%.3f", first.restitution),
                second: String(format: "%.3f", second.restitution), prediction: nil)
        ]
        let finding: String
        if hardening {
            let (more, less) = first.peakPlasticStrain >= second.peakPlasticStrain ? ("A", "B") : ("B", "A")
            finding = String(format: "Case %@ reached %.1f%% peak plastic strain against %.1f%% for case %@, while peak stress was %@ versus %@. Plastic work was %.0f versus %.0f J/m: a metal can absorb similar energy through large strain at low stress or small strain at high stress.",
                             more, 100 * max(first.peakPlasticStrain, second.peakPlasticStrain), 100 * min(first.peakPlasticStrain, second.peakPlasticStrain), less,
                             mpa(first.peakStress), mpa(second.peakStress), first.plasticWork, second.plasticWork)
        } else {
            let yieldPredicted = elasticEstimate(b) > (b.scene.parts[0].plasticity.table?.flowStress(at: 0) ?? .infinity)
            finding = String(format: "%@ Allowing yield turned %.0f%% of the impact energy into plastic work and left %.2f%% peak permanent strain. The elastic case keeps that energy in motion and vibration.",
                             yieldPredicted ? "The elastic stress estimate exceeds initial yield, so yielding was expected." : "The elastic stress estimate is below initial yield, so little yielding was expected.",
                             100 * second.plasticShare, 100 * second.peakPlasticStrain)
        }
        return Report(rows: rows, finding: finding)
    }

    // Bonded layers

    public struct BondMeasurement: Sendable {
        public let reflection, transmission, predictedReflection, predictedTransmission: Double
    }

    /// Uses case A as the matched control that isolates the incident pulse.
    public static func measureBond(control: Case, variant: Case) -> BondMeasurement? {
        let specimen = variant.scene.parts[1]
        guard variant.scene.parts.count == 2, let layer = specimen.bondedLayer, (variant.scene.gauges?.count ?? 0) >= 2,
              (control.scene.gauges?.count ?? 0) >= 2 else { return nil }
        // Windows from the verified scenario geometry scale with the first-layer wave speed.
        let scale = 31.6227766 / specimen.material.waveSpeed
        func average(_ run: Case, gauge: Int, _ range: ClosedRange<Double>) -> Double? {
            let window = (range.lowerBound * scale)...(range.upperBound * scale)
            let values = run.replay.frames.filter { window.contains($0.time) }.map { $0.gauges[gauge].velocity.x }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        guard let incident = average(control, gauge: 0, 0.008...0.009), abs(incident) > 0,
              let before = average(variant, gauge: 0, 0.012...0.013), let baseline = average(control, gauge: 0, 0.012...0.013),
              let after = average(variant, gauge: 1, 0.012...0.013) else { return nil }
        let z1 = specimen.material.density * specimen.material.waveSpeed
        let z2 = layer.material.density * layer.material.waveSpeed
        return BondMeasurement(reflection: (before - baseline) / incident, transmission: after / incident,
                               predictedReflection: (z1 - z2) / (z1 + z2), predictedTransmission: 2 * z1 / (z1 + z2))
    }

    static func bondReport(_ a: Case, _ b: Case) -> Report? {
        guard let bond = measureBond(control: a, variant: b) else { return nil }
        let rows = [
            Row(label: "Velocity reflected at the bond", first: "0 (control)", second: String(format: "%+.3f", bond.reflection),
                prediction: String(format: "%+.3f", bond.predictedReflection)),
            Row(label: "Velocity transmitted past the bond", first: "1 (control)", second: String(format: "%.3f", bond.transmission),
                prediction: String(format: "%.3f", bond.predictedTransmission)),
            Row(label: "Reflection error", first: "—", second: String(format: "%+.3f", bond.reflection - bond.predictedReflection), prediction: nil)
        ]
        let finding = bond.predictedReflection < 0
            ? "The second layer is stiffer and heavier, so the reflected pulse reverses particle velocity and the bond transmits a smaller velocity. The matched control shows no reflection."
            : "The second layer is softer and lighter, so the reflection keeps its sign and the bond transmits a larger velocity. The matched control shows no reflection."
        return Report(rows: rows, finding: finding)
    }

    // Interface failure

    public struct FractureMeasurement: Sendable {
        public let fractureEnergy, crackLength: Double
        public let pieces: Int
        public let firstFailure: Double?
        public let strikerImpulse, elasticShare: Double
    }

    public static func measureFracture(_ run: Case) -> FractureMeasurement? {
        guard let first = run.replay.frames.first, let last = run.replay.frames.last else { return nil }
        let reading = last.bodies[0].fracture
        let impulse = last.contacts.first { $0.pair == SIMD2(0, 1) }?.impulse ?? 0
        return FractureMeasurement(fractureEnergy: last.energies.fracture, crackLength: reading?.crackLength ?? 0,
                                   pieces: reading?.pieces ?? 1,
                                   firstFailure: run.replay.events.first { $0.id.hasPrefix("face-") }?.time,
                                   strikerImpulse: impulse, elasticShare: last.energies.elastic / first.energies.total)
    }

    static func fractureReport(_ a: Case, _ b: Case) -> Report? {
        guard let first = measureFracture(a), let second = measureFracture(b) else { return nil }
        func time(_ t: Double?) -> String { t.map { String(format: "%.2f ms", $0 * 1000) } ?? "none" }
        let rows = [
            Row(label: "First failed crack face", first: time(first.firstFailure), second: time(second.firstFailure), prediction: nil),
            Row(label: "Crack length", first: String(format: "%.1f mm", first.crackLength * 1000),
                second: String(format: "%.1f mm", second.crackLength * 1000), prediction: nil),
            Row(label: "Separate pieces", first: "\(first.pieces)", second: "\(second.pieces)", prediction: nil),
            Row(label: "Crack energy dissipated (incl. partial damage)", first: String(format: "%.4f J/m", first.fractureEnergy),
                second: String(format: "%.4f J/m", second.fractureEnergy),
                prediction: b.scene.parts[0].fracture.map { String(format: "≥ %.4f J/m (G꜀ × crack length)", $0.energy * second.crackLength) }),
            Row(label: "Striker contact impulse", first: String(format: "%.4f N·s/m", first.strikerImpulse),
                second: String(format: "%.4f N·s/m", second.strikerImpulse), prediction: nil),
            Row(label: "Energy left as elastic strain", first: percent(first.elasticShare), second: percent(second.elasticShare), prediction: nil)
        ]
        let finding = second.firstFailure == nil
            ? "No crack face failed in case B at this speed and fracture energy. Raise the striker speed or lower G꜀ to start a crack."
            : String(format: "Case B cracked at %.2f ms into %d piece%@ and dissipated %.4f J/m in new crack faces. Case A did not crack.",
                     second.firstFailure! * 1000, second.pieces, second.pieces == 1 ? "" : "s", second.fractureEnergy)
        return Report(rows: rows, finding: finding)
    }

    // MARK: Formatting

    static func ms(_ v: Double) -> String { String(format: "%.0f m/s", v) }
    static func mps(_ v: Double) -> String { String(format: "%.2f m/s", v) }
    static func mpa(_ v: Double) -> String { String(format: "%.0f MPa", v / 1e6) }
    static func percent(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
}

/// Metal hardening and fracture are not yet available together.
public let brittleVersusDuctileNote = "Brittle versus ductile comparisons are not offered yet. The verified crack model works only with illustrative elastic materials, and the metal profiles have no verified failure criterion. That scenario will be added once a metal failure model passes its own checks."
