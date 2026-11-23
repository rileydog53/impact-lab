public struct AssemblyRun: Sendable {
    public private(set) var simulation: AssemblySimulation
    public private(set) var samples: [TraceSample]
    private let monitoredIndex: Int?
    private let relativeIndex: Int?
    private let referenceOffset: Point

    package var work: AssemblyWork? { simulation.work }

    package mutating func measureWork(sampleKernels: Bool = false, parallelFEM: Bool = false) {
        if simulation.work == nil { simulation.work = AssemblyWork() }
        simulation.sampleKernels = sampleKernels
        simulation.configureParallelFEM(parallelFEM && !sampleKernels)
    }

    package mutating func step(recording replay: inout AssemblyReplay) -> Bool {
        guard step() else { return false }
        let started = simulation.work == nil ? 0 : AssemblyWork.now
        replay.record(self)
        if started != 0 { simulation.work?.output += AssemblyWork.now - started }
        return true
    }

    public var finished: Bool { simulation.time >= simulation.scene.duration }

    public init(_ scene: AssemblyScene) throws {
        let simulation = try AssemblySimulation(scene)
        self.simulation = simulation
        let monitoredIndex = scene.parts.firstIndex { $0.id == scene.monitor } ?? scene.parts.indices.first
        self.monitoredIndex = monitoredIndex
        let relativeIndex = scene.parts.firstIndex { $0.id == scene.relativeTo }
        self.relativeIndex = relativeIndex
        let referenceCenter = relativeIndex.map { simulation.body($0).centerOfMass } ?? .zero
        referenceOffset = (monitoredIndex.map { simulation.body($0).centerOfMass } ?? .zero) - referenceCenter
        samples = [TraceSample(time: 0, values: Point(0, monitoredIndex.map(simulation.kineticEnergy) ?? 0),
                               plasticDissipation: 0)]
    }

    public var relativeMotion: Point {
        guard let monitoredIndex else { return .zero }
        let reference = relativeIndex.map { simulation.body($0).centerOfMass } ?? .zero
        return simulation.body(monitoredIndex).centerOfMass - reference - referenceOffset
    }

    private var current: TraceSample {
        let energy = simulation.energies
        let fracture = monitoredIndex.flatMap(simulation.fractureReading)
        return TraceSample(time: simulation.time, values: Point(relativeMotion.x * 1000,
                                                               monitoredIndex.map(simulation.kineticEnergy) ?? 0),
                           plasticDissipation: energy.plastic, connectionEnergy: energy.connection,
                           materialFracture: fracture?.dissipation ?? 0, crackLength: (fracture?.crackLength ?? 0) * 1000,
                           crackSeparation: (fracture?.separation ?? 0) * 1000,
                           peakStress: (monitoredIndex.map { simulation.stress($0).max() ?? 0 } ?? 0) / 1000)
    }

    @discardableResult public mutating func step() -> Bool {
        let next = Double(samples.count) * simulation.scene.sampleInterval
        let crosses = simulation.time + simulation.dt >= next && next <= simulation.scene.duration
        let traceStarted = crosses && simulation.work != nil ? AssemblyWork.now : 0
        let before = crosses ? current : nil
        if traceStarted != 0 { simulation.work?.output += AssemblyWork.now - traceStarted }
        guard simulation.step() else { return false }
        if let before {
            let started = simulation.work == nil ? 0 : AssemblyWork.now
            let after = current
            var time = next
            while time <= min(after.time, simulation.scene.duration) {
                let fraction = (time - before.time) / (after.time - before.time)
                samples.append(TraceSample(time: time, values: before.values + fraction * (after.values - before.values),
                                           plasticDissipation: before.plasticDissipation + fraction * (after.plasticDissipation - before.plasticDissipation),
                                           connectionEnergy: before.connectionEnergy + fraction * (after.connectionEnergy - before.connectionEnergy),
                                           materialFracture: before.materialFracture + fraction * (after.materialFracture - before.materialFracture),
                                           crackLength: before.crackLength, // Topology changes discretely at acceptance.
                                           crackSeparation: before.crackSeparation + fraction * (after.crackSeparation - before.crackSeparation),
                                           peakStress: before.peakStress + fraction * (after.peakStress - before.peakStress)))
                time = Double(samples.count) * simulation.scene.sampleInterval
            }
            if started != 0 { simulation.work?.output += AssemblyWork.now - started }
        }
        return true
    }
}

extension AssemblyScene {
    public static func enclosureExample() -> Self {
        var scene = Self()
        var shell = AssemblyPart("Enclosure", shape: .enclosure, center: Point(-0.090, 0.008), size: Point(0.140, 0.105))
        shell.angle = 5
        shell.velocity = Point(1.1, 0)
        shell.material = Material(young: 2.2e6, density: 950, poisson: 0.10)
        shell.plasticity.response = .elastoplastic
        var mass = AssemblyPart("Internal mass", center: Point(-0.105, 0.010), size: Point(0.048, 0.045))
        mass.velocity = shell.velocity
        mass.material = Material(young: 2.7e6, density: 1850, poisson: 0.12)
        var face = AssemblyPart("Obstacle facing", center: Point(0.018, -0.012), size: Point(0.032, 0.115))
        face.material = Material(young: 1.3e6, density: 1250, poisson: 0.16)
        let rear = AssemblyPart("Obstacle backing", center: Point(0.060, -0.012), size: Point(0.047, 0.115))
        var mount = AssemblyConnection(first: shell.id, second: mass.id,
                                       firstAnchor: Point(-0.73, 0), secondAnchor: Point(-1, 0))
        mount.stiffness = 10_000
        var bond = AssemblyConnection(first: face.id, second: rear.id)
        bond.kind = .cohesive
        bond.span = 1.7
        bond.stiffness = 100_000
        bond.criticalExtension = 0.0025
        scene.duration = 0.155
        scene.parts = [shell, mass, face, rear]
        scene.connections = [mount, bond]
        scene.monitor = mass.id
        scene.relativeTo = shell.id
        return scene
    }
}

extension AssemblyScene {
    public static func bendingFractureExample() -> Self {
        var scene = Self()
        var specimen = AssemblyPart("Fracture specimen", size: Point(0.163, 0.026))
        specimen.material = Material(young: 1.0e6, density: 950, poisson: 0.12)
        specimen.fracture = MaterialFractureSettings()
        var tup = AssemblyPart("Striker", center: Point(-0.018, 0.040), size: Point(0.025, 0.043))
        tup.material = Material(young: 3.0e6, density: 2200, poisson: 0.15)
        tup.velocity.y = -1.45
        var left = AssemblyPart("Left support", center: Point(-0.062, -0.070), size: Point(0.033, 0.110))
        left.material = Material(young: 3.5e6, density: 2500, poisson: 0.1)
        var right = AssemblyPart("Right support", center: Point(0.062, -0.070), size: left.size)
        right.material = left.material
        var receiver = AssemblyPart("Receiver", center: Point(0.002, -0.076), size: Point(0.064, 0.031))
        receiver.material = Material(young: 2.5e6, density: 2100, poisson: 0.15)
        scene.parts = [specimen, tup, left, right, receiver]
        scene.monitor = specimen.id
        scene.duration = 0.115
        return scene
    }
}
