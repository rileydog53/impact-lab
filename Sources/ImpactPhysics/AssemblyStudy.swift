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
    /// Largest single-step load (N/m). A numerical diagnostic: it scales with
    /// the penalty stiffness and the mesh, so it is not a physical result.
    public internal(set) var peak = 0.0
    public internal(set) var impulse = 0.0
    public internal(set) var firstTime: Double?
    /// Pulse summary with stated merge gap and averaging windows.
    public internal(set) var pulses: ContactPulseReport?
}

public struct AssemblyStudySample: Sendable {
    public let time: Double
    public let energy: AssemblyEnergy
    public let residual: Double
    public let gauges: [AssemblyGaugeReading]
    public let normalLoads, normalImpulses: [Double]
    /// Trailing averaged load per pair, one value per window in that pair's pulse settings (N/m).
    public let averagedLoads: [[Double]]
    public let fractures: [MaterialFractureReading?]
}

public struct AssemblyStudyCase: Sendable {
    public let label: String
    public let bodyRefinements: [AssemblyScene.Resolution]
    public let triangles, steps: Int
    public let dt, wallTime, peakPenetration: Double
    /// Deepest absolute overlap (m), reported beside the edge-relative value.
    public let peakPenetrationDepth: Double
    public let samples: [AssemblyStudySample]
    public let contacts: [AssemblyStudyContact]
    public let firstInsertions: [Double?]
    public let failure: String?
}

package struct AssemblyStudyProgress: Sendable, Identifiable {
    package let id: String
    package let time, duration: Double
    package let steps: Int
    package let finished: Bool

    package var fraction: Double { finished ? 1 : min(1, time / duration) }
}

public struct AssemblyStudy: Sendable {
    public let scene: AssemblyScene
    public let pairs: [AssemblyStudyPair]
    /// Element wave-transit time per pair (s), the longest over all cases,
    /// and the pulse settings derived from it. Every case uses the same
    /// settings, so averaged forces are compared over common physical windows.
    public let transitTimes: [Double]
    public let pulseSettings: [ContactPulseSettings]
    public let cases: [AssemblyStudyCase]
    public let wallTime: Double
    public static let sampleInterval = SceneRun.sampleInterval

    public static func run(_ scene: AssemblyScene, variation: AssemblyStudyVariation,
                           parallel: Bool = true) async throws -> Self {
        try await run(scene, variation: variation, parallel: parallel, progress: nil)
    }

    package static func run(_ scene: AssemblyScene, variation: AssemblyStudyVariation, parallel: Bool = true,
                            progress: (@Sendable (AssemblyStudyProgress) -> Void)?) async throws -> Self {
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
        let transits = pairs.map { pair in
            prepared.map { $0.1.elementTransitTime(bodies: [pair.bodies.x, pair.bodies.y]) }.max() ?? 0
        }
        let settings = transits.map(ContactPulseSettings.guideline(transit:))
        var measured: [AssemblyStudyCase]
        if parallel && prepared.count > 1 {
            measured = try await withThrowingTaskGroup(of: (Int, AssemblyStudyCase).self) { group in
                for (index, item) in prepared.enumerated() {
                    group.addTask { (index, try measure(item.1, label: item.0, pairs: pairs, settings: settings, progress: progress)) }
                }
                var results: [(Int, AssemblyStudyCase)] = []
                for try await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
        } else {
            measured = try prepared.map { try measure($0.1, label: $0.0, pairs: pairs, settings: settings, progress: progress) }
        }
        return Self(scene: scene, pairs: pairs, transitTimes: transits, pulseSettings: settings, cases: measured,
                    wallTime: ProcessInfo.processInfo.systemUptime - started)
    }

    private static func measure(_ initial: AssemblySimulation, label: String, pairs: [AssemblyStudyPair],
                                settings: [ContactPulseSettings], progress: (@Sendable (AssemblyStudyProgress) -> Void)?) throws -> AssemblyStudyCase {
        let started = ProcessInfo.processInfo.systemUptime
        var simulation = initial
        let triangles = (0..<simulation.bodyCount).reduce(0) { $0 + simulation.body($1).mesh.elements.count }
        let gaugeIndices = (simulation.scene.gauges ?? []).indices
        let fractureParts = simulation.scene.parts.indices.filter { simulation.scene.parts[$0].fracture != nil }
        let indices = Dictionary(uniqueKeysWithValues: pairs.enumerated().map { ($0.element.bodies, $0.offset) })
        var contacts = Array(repeating: AssemblyStudyContact(), count: pairs.count)
        var insertions = Array<Double?>(repeating: nil, count: simulation.bodyCount)
        var previousActive: [(index: Int, load: Double)] = []
        var trackers = settings.map(ContactPulseTracker.init)
        func sample() -> AssemblyStudySample {
            let energy = simulation.energies
            return AssemblyStudySample(time: simulation.time, energy: energy,
                residual: energy.total - simulation.initialEnergy, gauges: gaugeIndices.map(simulation.gaugeReading),
                normalLoads: pairs.map { simulation.normalLoad($0.bodies.x, $0.bodies.y) },
                normalImpulses: contacts.map(\.impulse),
                averagedLoads: trackers.map { $0.averages(at: simulation.time) },
                fractures: (0..<simulation.bodyCount).map(simulation.fractureReading))
        }
        let sampleInterval = simulation.scene.sampleInterval
        var samples = [sample()]
        var steps = 0
        var next = 1
        var lastUpdate = started
        let duration = initial.scene.duration
        progress?(AssemblyStudyProgress(id: label, time: 0, duration: duration, steps: 0, finished: false))
        while !Task.isCancelled && simulation.step() {
            steps += 1
            if progress != nil {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastUpdate >= 0.25 {
                    progress?(AssemblyStudyProgress(id: label, time: simulation.time, duration: duration,
                                                    steps: steps, finished: false))
                    lastUpdate = now
                }
            }
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
            for (index, pair) in pairs.enumerated() {
                trackers[index].record(time: simulation.time, dt: simulation.dt,
                                       load: simulation.normalLoad(pair.bodies.x, pair.bodies.y))
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
        progress?(AssemblyStudyProgress(id: label, time: simulation.time, duration: duration,
                                        steps: steps, finished: simulation.time >= duration && simulation.failure == nil))
        if samples.last!.time != simulation.time { samples.append(sample()) }
        for index in contacts.indices { contacts[index].pulses = trackers[index].report }
        let refinements = simulation.scene.parts.map { $0.refinement ?? simulation.scene.resolution }
        return AssemblyStudyCase(label: label, bodyRefinements: refinements, triangles: triangles, steps: steps, dt: simulation.dt,
            wallTime: ProcessInfo.processInfo.systemUptime - started, peakPenetration: simulation.peakRelativePenetration,
            peakPenetrationDepth: simulation.peakPenetrationDepth, samples: samples, contacts: contacts, firstInsertions: insertions,
            failure: simulation.initialIssue ?? simulation.failure ?? (steps == 0 ? "Add a body before running a study." : nil))
    }

    public func exportCSV(to url: URL) throws {
        var header = ["case", "triangles", "dt_s", "time_s", "initial_energy_J_per_m", "kinetic_J_per_m",
                      "elastic_J_per_m", "hardening_J_per_m", "plastic_dissipation_J_per_m", "penalty_contact_J_per_m",
                      "connection_J_per_m", "cohesive_face_J_per_m", "fracture_dissipation_J_per_m", "residual_J_per_m"]
        // Only scenes with bulk viscosity get the extra column, so earlier exports keep their layout.
        let viscous = scene.bulkViscosity != nil
        if viscous { header.append("bulk_viscosity_J_per_m") }
        header += scene.parts.enumerated().map { "body_\($0.offset + 1) \($0.element.name) mesh_factor" }
        for (i, gauge) in (scene.gauges ?? []).enumerated() {
            header += ["x_m", "y_m", "vx_m_per_s", "vy_m_per_s", "green_strain_xx", "pressure_Pa", "mises_Pa",
                       "plastic_strain", "adjacent_face_damage"].map { "gauge_\(i + 1) \(gauge.name) \($0)" }
        }
        for (i, pair) in pairs.enumerated() {
            let windows = pulseSettings[i].windows.map { "load_avg_\(Self.seconds($0))_N_per_m" }
            header += (["scalar_load_N_per_m", "scalar_impulse_Ns_per_m"] + windows
                       + ["raw_step_peak_numerical_diagnostic_N_per_m", "first_contact_s"])
                .map { "pair_\(i + 1) \(pair.name) \($0)" }
        }
        let fractureParts = scene.parts.indices.filter { scene.parts[$0].fracture != nil }
        for part in fractureParts {
            header += ["inserted_edges", "failed_edges", "pieces", "crack_length_m", "face_dissipation_J_per_m",
                       "first_insertion_s"].map { "body_\(part + 1) \(scene.parts[part].name) \($0)" }
        }
        header += ["peak_relative_penetration", "peak_penetration_depth_m", "case_wall_s", "solver_failure"]
        func quoted(_ cell: String) -> String { "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var csv = header.map(quoted).joined(separator: ",") + "\n"
        for item in cases {
            for sample in item.samples {
                let e = sample.energy
                let initial = item.samples[0].energy.total
                var row = [quoted(item.label), String(item.triangles), String(item.dt), String(sample.time)]
                row += [initial, e.kinetic, e.elastic, e.hardening, e.plastic, e.contact, e.connection, e.cohesive,
                        e.fracture, sample.residual].map { String($0) }
                if viscous { row.append(String(e.viscous)) }
                row += item.bodyRefinements.map { String($0.rawValue) }
                for g in sample.gauges {
                    row += [g.position.x, g.position.y, g.velocity.x, g.velocity.y, g.strain, g.pressure, g.equivalentStress,
                            g.plasticStrain, g.damage].map { String($0) }
                }
                for (index, contact) in item.contacts.enumerated() {
                    row += [String(sample.normalLoads[index]), String(sample.normalImpulses[index])]
                    row += sample.averagedLoads[index].map { String($0) }
                    row += [String(contact.peak), contact.firstTime.map { String($0) } ?? ""]
                }
                for part in fractureParts {
                    let f = sample.fractures[part]!
                    row += [String(f.insertedEdges), String(f.failedEdges), String(f.pieces), String(f.crackLength),
                            String(f.dissipation), item.firstInsertions[part].map { String($0) } ?? ""]
                }
                row += [String(item.peakPenetration), String(item.peakPenetrationDepth), String(item.wallTime),
                        quoted(item.failure ?? "")]
                csv += row.joined(separator: ",") + "\n"
            }
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    /// One row per contact pulse: the headline contact numbers, with the
    /// merge gap and averaging windows stated on every row.
    public func exportPulseCSV(to url: URL) throws {
        var csv = "case,pair,transit_time_s,merge_gap_s,minor_fraction,pulse,start_s,end_s,duration_s,impulse_Ns_per_m,"
            + "mean_force_N_per_m,averaging_windows_s,peak_windowed_force_N_per_m,solver_episodes,"
            + "raw_step_peak_numerical_diagnostic_N_per_m,minor_touches,minor_impulse_Ns_per_m\n"
        func quoted(_ cell: String) -> String { "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        for item in cases {
            for (index, contact) in item.contacts.enumerated() {
                guard let report = contact.pulses else { continue }
                let s = report.settings
                for (n, pulse) in report.pulses.enumerated() {
                    let cells: [String] = [
                        quoted(item.label), quoted(pairs[index].name), String(transitTimes[index]), String(s.mergeGap),
                        String(s.minorFraction), String(n + 1), String(pulse.start), String(pulse.end),
                        String(pulse.duration), String(pulse.impulse), String(pulse.meanForce),
                        quoted(s.windows.map { String($0) }.joined(separator: " ")),
                        quoted(pulse.windowPeaks.map { String($0) }.joined(separator: " ")), String(pulse.episodes),
                        String(pulse.rawPeak), String(report.minorCount), String(report.minorImpulse)]
                    csv += cells.joined(separator: ",") + "\n"
                }
            }
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    static func seconds(_ value: Double) -> String { String(format: "%.3g", value) + "s" }
}
