import Foundation

public enum AssemblyStudyVariation: Sendable {
    case current
    case mesh(body: UUID?, levels: [AssemblyScene.Resolution])
    case timestep
}

public struct AssemblyStudyPair: Sendable {
    public let bodies: SIMD2<Int>
    public let name: String
}

public struct AssemblyStudyContact: Sendable {
    public internal(set) var peak = 0.0
    public internal(set) var impulse = 0.0
    public internal(set) var firstTime: Double?
}

public struct AssemblyStudySample: Sendable {
    public let time: Double
    public let energy: AssemblyEnergy
    public let residual: Double
    public let gauges: [AssemblyGaugeReading]
    public let normalLoads, normalImpulses: [Double]
    public let fractures: [MaterialFractureReading?]
}

public struct AssemblyStudyCase: Sendable {
    public let label: String
    public let bodyRefinements: [AssemblyScene.Resolution]
    public let triangles, steps: Int
    public let dt, wallTime, peakPenetration: Double
    public let samples: [AssemblyStudySample]
    public let contacts: [AssemblyStudyContact]
    public let firstInsertions: [Double?]
    public let failure: String?
}

public struct AssemblyStudy: Sendable {
    public let scene: AssemblyScene
    public let pairs: [AssemblyStudyPair]
    public let cases: [AssemblyStudyCase]
    public let wallTime: Double
    public static let sampleInterval = SceneRun.sampleInterval

    public static func run(_ scene: AssemblyScene, variation: AssemblyStudyVariation,
                           parallel: Bool = true) async throws -> Self {
        let started = ProcessInfo.processInfo.systemUptime
        var cases: [(scene: AssemblyScene, label: String, stepScale: Double)] = []
        switch variation {
        case .current:
            cases = [(scene, "Current setup", 1)]
        case .mesh(let body, let levels):
            guard (2...3).contains(levels.count), Set(levels).count == levels.count,
                  body == nil || scene.parts.contains(where: { $0.id == body }) else {
                throw AssemblyError.invalidSettings
            }
            cases = levels.map { resolution in
                var modified = scene
                for i in modified.parts.indices where body == nil || modified.parts[i].id == body {
                    modified.parts[i].refinement = resolution
                }
                return (modified, "Mesh ×\(resolution.rawValue)", 1)
            }
        case .timestep:
            cases = [(scene, "Nominal step", 1), (scene, "Half step", 0.5), (scene, "Quarter step", 0.25)]
        }

        let pairs = scene.parts.indices.flatMap { left in
            ((left + 1)..<scene.parts.count).map { right in
                AssemblyStudyPair(bodies: SIMD2(left, right), name: "\(scene.parts[left].name) / \(scene.parts[right].name)")
            }
        }
        var prepared: [(String, AssemblySimulation)] = []
        for item in cases {
            try Task.checkCancellation()
            let simulation = try AssemblySimulation(item.scene, refinement: item.scene.resolution.rawValue,
                                                    stepLimit: .infinity, stepScale: item.stepScale)
            prepared.append((item.label, simulation))
        }
        if case .mesh = variation {
            let sharedStep = prepared.map { $0.1.dt }.min()!
            for i in cases.indices where prepared[i].1.dt != sharedStep {
                try Task.checkCancellation()
                let setup = cases[i].scene
                prepared[i].1 = try AssemblySimulation(setup, refinement: setup.resolution.rawValue, stepLimit: sharedStep)
            }
        }
        var measured: [AssemblyStudyCase]
        if parallel && prepared.count > 1 {
            measured = try await withThrowingTaskGroup(of: (Int, AssemblyStudyCase).self) { group in
                for (index, item) in prepared.enumerated() {
                    group.addTask { (index, try measure(item.1, label: item.0, pairs: pairs)) }
                }
                var results: [(Int, AssemblyStudyCase)] = []
                for try await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
        } else {
            measured = try prepared.map { try measure($0.1, label: $0.0, pairs: pairs) }
        }
        return Self(scene: scene, pairs: pairs, cases: measured,
                    wallTime: ProcessInfo.processInfo.systemUptime - started)
    }

    private static func measure(_ initial: AssemblySimulation, label: String, pairs: [AssemblyStudyPair]) throws
        -> AssemblyStudyCase {
        let started = ProcessInfo.processInfo.systemUptime
        var simulation = initial
        let triangles = (0..<simulation.bodyCount).reduce(0) { $0 + simulation.body($1).mesh.elements.count }
        let gaugeIndices = (simulation.scene.gauges ?? []).indices
        let fractureParts = simulation.scene.parts.indices.filter { simulation.scene.parts[$0].fracture != nil }
        let indices = Dictionary(uniqueKeysWithValues: pairs.enumerated().map { ($0.element.bodies, $0.offset) })
        var contacts = Array(repeating: AssemblyStudyContact(), count: pairs.count)
        var insertions = Array<Double?>(repeating: nil, count: simulation.bodyCount)
        var previousActive: [(index: Int, load: Double)] = []
        func sample() -> AssemblyStudySample {
            let energy = simulation.energies
            return AssemblyStudySample(time: simulation.time, energy: energy,
                residual: energy.total - simulation.initialEnergy, gauges: gaugeIndices.map(simulation.gaugeReading),
                normalLoads: pairs.map { simulation.normalLoad($0.bodies.x, $0.bodies.y) },
                normalImpulses: contacts.map(\.impulse),
                fractures: (0..<simulation.bodyCount).map(simulation.fractureReading))
        }
        var samples = [sample()]
        var steps = 0
        var next = 1
        while simulation.step() {
            steps += 1
            if steps.isMultiple(of: 256) { try Task.checkCancellation() }
            for previous in previousActive {
                contacts[previous.index].impulse += 0.5 * simulation.dt * previous.load
            }
            previousActive.removeAll(keepingCapacity: true)
            for pair in simulation.activeContacts {
                guard let index = indices[pair] else { continue }
                let load = simulation.normalLoad(pair.x, pair.y)
                previousActive.append((index, load))
                contacts[index].impulse += 0.5 * simulation.dt * load
                contacts[index].peak = max(contacts[index].peak, load)
                if contacts[index].firstTime == nil { contacts[index].firstTime = simulation.time }
            }
            for index in fractureParts where insertions[index] == nil {
                if (simulation.fractureReading(index)?.insertedEdges ?? 0) > 0 {
                    insertions[index] = simulation.time
                }
            }
            if simulation.time >= Double(next) * sampleInterval {
                samples.append(sample())
                repeat { next += 1 } while simulation.time >= Double(next) * sampleInterval
            }
        }
        try Task.checkCancellation()
        if samples.last!.time != simulation.time { samples.append(sample()) }
        let refinements = simulation.scene.parts.map { $0.refinement ?? simulation.scene.resolution }
        return AssemblyStudyCase(label: label, bodyRefinements: refinements, triangles: triangles, steps: steps, dt: simulation.dt,
            wallTime: ProcessInfo.processInfo.systemUptime - started, peakPenetration: simulation.peakRelativePenetration,
            samples: samples, contacts: contacts, firstInsertions: insertions,
            failure: simulation.initialIssue ?? simulation.failure ?? (steps == 0 ? "Add a body before running a study." : nil))
    }

    public func exportCSV(to url: URL) throws {
        var header = ["case", "triangles", "dt_s", "time_s", "initial_energy_J_per_m", "kinetic_J_per_m",
                      "elastic_J_per_m", "hardening_J_per_m", "plastic_dissipation_J_per_m", "penalty_contact_J_per_m",
                      "connection_J_per_m", "cohesive_face_J_per_m", "fracture_dissipation_J_per_m", "residual_J_per_m"]
        header += scene.parts.enumerated().map { "body_\($0.offset + 1) \($0.element.name) mesh_factor" }
        for (i, gauge) in (scene.gauges ?? []).enumerated() {
            header += ["x_m", "y_m", "vx_m_per_s", "vy_m_per_s", "green_strain_xx", "pressure_Pa", "mises_Pa",
                       "plastic_strain", "adjacent_face_damage"].map { "gauge_\(i + 1) \(gauge.name) \($0)" }
        }
        for (i, pair) in pairs.enumerated() {
            header += ["scalar_load_N_per_m", "scalar_impulse_Ns_per_m", "step_peak_N_per_m", "first_contact_s"]
                .map { "pair_\(i + 1) \(pair.name) \($0)" }
        }
        let fractureParts = scene.parts.indices.filter { scene.parts[$0].fracture != nil }
        for part in fractureParts {
            header += ["inserted_edges", "failed_edges", "pieces", "crack_length_m", "face_dissipation_J_per_m",
                       "first_insertion_s"].map { "body_\(part + 1) \(scene.parts[part].name) \($0)" }
        }
        header += ["peak_relative_penetration", "case_wall_s", "solver_failure"]
        func quoted(_ cell: String) -> String { "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var csv = header.map(quoted).joined(separator: ",") + "\n"
        for item in cases {
            for sample in item.samples {
                let e = sample.energy
                let initial = item.samples[0].energy.total
                var row = [quoted(item.label), String(item.triangles), String(item.dt), String(sample.time)]
                row += [initial, e.kinetic, e.elastic, e.hardening, e.plastic, e.contact, e.connection, e.cohesive,
                        e.fracture, sample.residual].map { String($0) }
                row += item.bodyRefinements.map { String($0.rawValue) }
                for g in sample.gauges {
                    row += [g.position.x, g.position.y, g.velocity.x, g.velocity.y, g.strain, g.pressure, g.equivalentStress,
                            g.plasticStrain, g.damage].map { String($0) }
                }
                for (index, contact) in item.contacts.enumerated() {
                    row += [String(sample.normalLoads[index]), String(sample.normalImpulses[index]),
                            String(contact.peak), contact.firstTime.map { String($0) } ?? ""]
                }
                for part in fractureParts {
                    let f = sample.fractures[part]!
                    row += [String(f.insertedEdges), String(f.failedEdges), String(f.pieces), String(f.crackLength),
                            String(f.dissipation), item.firstInsertions[part].map { String($0) } ?? ""]
                }
                row += [String(item.peakPenetration), String(item.wallTime), quoted(item.failure ?? "")]
                csv += row.joined(separator: ",") + "\n"
            }
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
