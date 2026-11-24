import Foundation
import ImpactPhysics
import Observation

struct AssemblyComparison {
    let details: String
    let samples: [TraceSample]
    let tracksFracture: Bool
    let replay: AssemblyReplay?
    let scene: AssemblyScene
    var label = ""
}

@MainActor @Observable final class AssemblyExperiment {
    private struct Edit {
        let scene: AssemblyScene
        let part: UUID?
        let parts: Set<UUID>
        let connection: UUID?
        let action: String
    }

    private var run: AssemblyRun
    private(set) var replay: AssemblyReplay?
    private(set) var frameIndex = 0
    private(set) var solving = false
    private(set) var cancelling = false
    private(set) var computation: AssemblyComputation?
    @ObservationIgnored private var solveTask: Task<(AssemblyRun, AssemblyReplay, AssemblyComputation), Never>?
    @ObservationIgnored private var solveID: UUID?
    private var playbackTime = 0.0
    var playbackSpeed = 1.0
    var probeBody: Int?
    var probeElement: Int?
    private var savedScene: AssemblyScene
    private var undoEdits: [Edit] = []
    private var redoEdits: [Edit] = []
    private(set) var title = "Enclosure example"
    private(set) var fileURL: URL?
    var previewParts: [UUID: AssemblyPart] = [:]
    var previewPart: AssemblyPart? { selectedPart.flatMap { previewParts[$0] } }
    private(set) var meshQuality: [WorkshopMeshQuality]
    private(set) var running = false
    private var lastTick: Double?
    var error: String?
    private(set) var selectedPart: UUID?
    private(set) var selectedParts: Set<UUID> = []
    var selectedConnection: UUID?
    var placingGauge = false
    var linkPlacement: WorkshopLinkPlacement?
    var gridStep = 0.0
    private(set) var reference: AssemblyComparison?
    /// Completed runs this session, newest last, kept so an earlier result can be compared after editing.
    private(set) var history: [AssemblyComparison] = []
    static let historyLimit = 6
    private var runNumber = 0
    @ObservationIgnored private var runEstimate: RunCostEstimate?
    private(set) var cameraRevision = 0

    init() {
        let initial = AssemblyScene.enclosureExample()
        let initialRun = try! AssemblyRun(initial)
        run = initialRun
        savedScene = initial
        meshQuality = WorkshopMeshQuality.measure(initialRun.simulation)
    }

    deinit { solveTask?.cancel() }

    var scene: AssemblyScene { run.simulation.scene }
    var simulation: AssemblySimulation { run.simulation }
    var samples: [TraceSample] { run.samples }
    var relativeMotion: Point { frame?.relativeMotion ?? run.relativeMotion }
    var frames: [AssemblyReplayFrame] { replay?.frames ?? [] }
    var frame: AssemblyReplayFrame? { replay?.frames[frameIndex] }
    var playbackDuration: Double { frames.last?.time ?? 0 }
    var displayTime: Double { frame?.time ?? 0 }
    func displayedBody(_ index: Int) -> Body { frame?.bodies[index].body ?? simulation.body(index) }
    func displayedGauge(_ index: Int) -> AssemblyGaugeReading { frame?.gauges[index] ?? simulation.gaugeReading(index) }
    var displayedLinks: [AssemblyLinkReading] { frame?.links ?? simulation.linkReadings }
    var canRun: Bool { !solving && simulation.initialIssue == nil && simulation.failure == nil && !scene.parts.isEmpty && !run.finished }
    var canEdit: Bool { !solving && replay == nil && simulation.time == 0 }
    var isDirty: Bool { scene != savedScene }
    var undoAction: String? { undoEdits.last?.action }
    var redoAction: String? { redoEdits.last?.action }
    var finished: Bool { run.finished }
    /// Pre-run cost of the remaining calculation, from this Mac's measured speed when known.
    var estimate: RunCostEstimate { RunCostEstimate(simulation, rate: RuntimeWarnings.measuredRate) }
    var selectedIndex: Int? { scene.parts.firstIndex { $0.id == selectedPart } }
    var displayIndices: [Int] {
        let indices = Dictionary(uniqueKeysWithValues: scene.parts.indices.map { (scene.parts[$0].id, $0) })
        return scene.orderedBodyIDs.compactMap { indices[$0] }
    }
    var gauges: [AssemblyGauge] { scene.gauges ?? [] }
    var monitoredName: String { scene.parts.first { $0.id == scene.monitor }?.name ?? scene.parts.first?.name ?? "Body" }
    var elementCount: Int { (0..<simulation.bodyCount).reduce(0) { $0 + simulation.body($1).mesh.elements.count } }
    var relativeName: String { scene.parts.first { $0.id == scene.relativeTo }?.name ?? "Lab frame" }
    var current: AssemblyComparison {
        let monitored = scene.parts.first { $0.id == scene.monitor } ?? scene.parts.first
        let pattern = monitored.flatMap { $0.shape == .block ? $0.fracture?.pattern.rawValue : nil }
        let mesh = monitored?.refinement ?? scene.resolution
        let details = [monitoredName, monitored?.material.provenance?.name, mesh.label, pattern, "\(elementCount) triangles"].compactMap { $0 }
        return AssemblyComparison(details: details.joined(separator: " · "), samples: samples,
                                  tracksFracture: scene.parts.contains { $0.fracture != nil }, replay: replay, scene: scene)
    }

    var initialMotionNote: String? {
        guard canEdit, !scene.parts.isEmpty else { return nil }
        if scene.parts.allSatisfy({ $0.velocity == .zero }) {
            return "Static setup. All bodies start at rest and assembly links start unloaded."
        }
        guard scene.connections.isEmpty else { return nil }
        guard scene.parts.count > 1 else { return "Free translation. Add a second body to create contact." }
        let bounds = scene.parts.indices.map { index in
            let positions = simulation.body(index).position
            return (lower: Point(positions.map(\.x).min()!, positions.map(\.y).min()!),
                    upper: Point(positions.map(\.x).max()!, positions.map(\.y).max()!))
        }
        for i in bounds.indices {
            for j in bounds.indices where j > i {
                let travel = (scene.parts[j].velocity - scene.parts[i].velocity) * scene.duration
                let start = bounds[j]
                let lower = start.lower + Point(min(0, travel.x), min(0, travel.y))
                let upper = start.upper + Point(max(0, travel.x), max(0, travel.y))
                if (0..<2).allSatisfy({ lower[$0] <= bounds[i].upper[$0] && upper[$0] >= bounds[i].lower[$0] }) {
                    return nil
                }
            }
        }
        return "No contact in this window. With the current velocities, the bodies' swept bounds stay apart."
    }

    var canRefine: Bool {
        scene.parts.contains { $0.refinement == nil } && scene.resolution != .x7 && samples.count > 1
    }

    func refine() {
        guard canRefine, let resolution = AssemblyScene.Resolution(rawValue: scene.resolution.rawValue + 1) else { return }
        pin()
        edit("Refine Assembly Mesh") { $0.meshResolution = resolution }
        if self.scene.resolution == resolution { calculate() }
    }

    func configure(_ scene: AssemblyScene) throws {
        let next = try AssemblyRun(scene)
        let meshChanged = self.scene.parts != scene.parts || self.scene.meshResolution != scene.meshResolution
        pause()
        solveTask?.cancel()
        solveTask = nil
        solveID = nil
        solving = false
        cancelling = false
        computation = nil
        replay = nil
        frameIndex = 0
        probeBody = nil
        probeElement = nil
        placingGauge = false
        linkPlacement = nil
        previewParts.removeAll()
        if meshChanged { meshQuality = WorkshopMeshQuality.measure(next.simulation) }
        run = next
        selectedParts.formIntersection(scene.parts.map(\.id))
        if let selectedPart, !selectedParts.contains(selectedPart) {
            self.selectedPart = scene.orderedBodyIDs.first(where: selectedParts.contains)
        }
        if !scene.connections.contains(where: { $0.id == selectedConnection }) { selectedConnection = nil }
    }

    func load(_ scene: AssemblyScene, title: String, url: URL? = nil) throws {
        try configure(scene)
        self.title = title
        fileURL = url
        savedScene = scene
        undoEdits.removeAll()
        redoEdits.removeAll()
        selectedPart = scene.monitor ?? scene.parts.first?.id
        selectedParts = selectedPart.map { [$0] } ?? []
        selectedConnection = nil
        cameraRevision += 1
    }

    func save(to url: URL) throws {
        try scene.save(to: url)
        savedScene = scene
        fileURL = url
        title = Self.fileTitle(url)
    }

    static func fileTitle(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.hasSuffix(".impact-assembly") ? String(name.dropLast(".impact-assembly".count)) : name
    }

    func edit(_ action: String = "Edit Assembly", _ change: (inout AssemblyScene) -> Void) {
        var modified = scene
        change(&modified)
        guard modified != scene else { return }
        let previous = checkpoint(action)
        do {
            try configure(modified)
            undoEdits.append(previous)
            if undoEdits.count > 100 { undoEdits.removeFirst() }
            redoEdits.removeAll()
        }
        catch { self.error = error.localizedDescription }
    }

    func undo() { restoreEdit(fromUndo: true) }
    func redo() { restoreEdit(fromUndo: false) }

    private func checkpoint(_ action: String) -> Edit {
        Edit(scene: scene, part: selectedPart, parts: selectedParts, connection: selectedConnection, action: action)
    }

    private func restoreEdit(fromUndo: Bool) {
        guard canEdit, let previous = fromUndo ? undoEdits.last : redoEdits.last else { return }
        let current = checkpoint(previous.action)
        do {
            try configure(previous.scene)
            selectedPart = previous.part
            selectedParts = previous.parts
            selectedConnection = previous.connection
            if fromUndo {
                undoEdits.removeLast()
                redoEdits.append(current)
            } else {
                redoEdits.removeLast()
                undoEdits.append(current)
            }
        } catch { self.error = error.localizedDescription }
    }

    func select(_ part: UUID, adding: Bool = false) {
        if adding {
            if selectedParts.remove(part) == nil {
                selectedParts.insert(part)
                selectedPart = part
            } else if selectedPart == part {
                selectedPart = scene.orderedBodyIDs.first(where: selectedParts.contains)
            }
        } else {
            selectedPart = part
            selectedParts = [part]
        }
        selectedConnection = nil
    }

    func selectParts(_ ids: Set<UUID>, primary: UUID? = nil) {
        selectedParts = ids
        selectedPart = primary ?? scene.orderedBodyIDs.first(where: ids.contains)
        selectedConnection = nil
    }

    func selectConnection(_ connection: UUID) {
        selectedConnection = connection
        selectedPart = nil
        selectedParts.removeAll()
    }

    @discardableResult func addGauge(body id: UUID, at world: Point) -> UUID? {
        guard simulation.time == 0, gauges.count < AssemblyGauge.limit,
              let part = scene.parts.first(where: { $0.id == id }) else { return nil }
        let radians = part.angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        let offset = world - part.center
        let local = Point(c * offset.x + s * offset.y, -s * offset.x + c * offset.y)
        let used = Set(gauges.map(\.name))
        let number = (1...AssemblyGauge.limit).first { !used.contains("Gauge \($0)") }!
        let gauge = AssemblyGauge(body: id, name: "Gauge \(number)", location: local)
        edit("Place Gauge") { $0.gauges = ($0.gauges ?? []) + [gauge] }
        select(id)
        placingGauge = false
        return gauges.contains { $0.id == gauge.id } ? gauge.id : nil
    }

    func updateGauge(_ id: UUID, _ change: (inout AssemblyGauge) -> Void) {
        edit("Edit Gauge") {
            guard let index = $0.gauges?.firstIndex(where: { $0.id == id }) else { return }
            change(&$0.gauges![index])
        }
    }

    @discardableResult func add(_ shape: AssemblyPart.Shape) -> UUID? {
        let geometry: WorkshopGeometry = switch shape {
        case .block: .block
        case .enclosure: .enclosure
        case .round: .round
        }
        return insert(geometry)
    }

    @discardableResult func insert(_ geometry: WorkshopGeometry) -> UUID? {
        guard scene.parts.count < AssemblyScene.maximumParts else { return nil }
        var part = geometry.makePart(number: scene.parts.count + 1)
        part.center = geometry == .bench ? benchPoint(for: part.size) : insertionPoint(for: part.size)
        edit("Add Body") { $0.parts.append(part) }
        guard scene.parts.contains(where: { $0.id == part.id }) else { return nil }
        select(part.id)
        return part.id
    }

    func updatePart(_ id: UUID, action: String = "Edit Body", _ change: (inout AssemblyPart) -> Void) {
        edit(action) { scene in
            guard let index = scene.parts.firstIndex(where: { $0.id == id }) else { return }
            change(&scene.parts[index])
            fitWall(of: &scene.parts[index])
        }
    }

    func assignMaterial(_ profile: MaterialProfile, to id: UUID, target: MaterialTarget, elasticOnly: Bool) {
        guard canEdit, profile.isValid else { return }
        updatePart(id, action: "Apply Material") { target.apply(profile, to: &$0, elasticOnly: elasticOnly) }
    }

    func fitWall(of part: inout AssemblyPart) {
        if part.shape == .enclosure {
            part.wall = min(part.wall, 0.4 * min(part.size.x, part.size.y))
        }
    }

    @discardableResult func addConnection(first: UUID, second: UUID) -> UUID? {
        addConnection(AssemblyConnection(first: first, second: second))
    }

    @discardableResult func addConnection(_ new: AssemblyConnection) -> UUID? {
        guard new.first != new.second, scene.connections.count < AssemblyScene.maximumConnections else { return nil }
        edit("Add Connection") { $0.connections.append(new) }
        guard scene.connections.contains(where: { $0.id == new.id }) else { return nil }
        selectConnection(new.id)
        return new.id
    }

    func updateConnection(_ id: UUID, action: String = "Edit Connection", _ change: (inout AssemblyConnection) -> Void) {
        edit(action) { scene in
            guard let index = scene.connections.firstIndex(where: { $0.id == id }) else { return }
            change(&scene.connections[index])
            let c = scene.connections[index]
            let span = 2 * (1 - max(abs(c.firstAnchor.y), abs(c.secondAnchor.y)))
            scene.connections[index].span = min(c.span, span)
        }
    }

    func reset() {
        do { try configure(scene) }
        catch { self.error = error.localizedDescription }
    }

    func pin() {
        pause()
        reference = labelled(current)
    }

    private func labelled(_ comparison: AssemblyComparison) -> AssemblyComparison {
        var result = comparison
        if let match = history.last(where: { $0.scene == comparison.scene && $0.samples.count == comparison.samples.count }) {
            result.label = match.label
        } else if result.label.isEmpty {
            result.label = "Unsaved run"
        }
        return result
    }

    /// Keeps the finished run as the comparison reference and returns to editing a copy of
    /// its starting setup. The original result stays intact in the reference and in the run history.
    func editCopy() {
        guard !solving, !canEdit, samples.count > 1 else { return }
        pin()
        reset()
    }

    func useAsReference(_ index: Int) {
        guard history.indices.contains(index) else { return }
        pause()
        reference = history[index]
    }

    func pause() {
        running = false
        lastTick = nil
    }

    func calculate() {
        guard canRun else { return }
        pause()
        placingGauge = false
        linkPlacement = nil
        previewParts.removeAll()
        let existing = run
        let recording = replay
        let carriedElapsed = computation?.elapsed ?? 0
        let id = UUID()
        solveID = id
        runEstimate = estimate
        solving = true
        cancelling = false
        let (updates, continuation) = AsyncStream.makeStream(of: AssemblyComputation.self, bufferingPolicy: .bufferingNewest(1))
        let worker = Task.detached(priority: .userInitiated) {
            var solver = existing
            solver.measureWork(parallelFEM: true)
            let started = AssemblyProcessSample()
            var previous = started
            var next = recording ?? AssemblyReplay(solver)
            next.resume()
            func snapshot(_ state: AssemblyComputation.State, process: AssemblyProcessSample,
                          cpu: Double?) -> AssemblyComputation {
                let simulation = solver.simulation
                let payload = simulation.statePayload
                return AssemblyComputation(state: state, time: simulation.time, duration: simulation.scene.duration,
                    dt: simulation.dt, elapsed: carriedElapsed + process.time - started.time, work: solver.work!,
                    elements: payload.elasticElements + payload.plasticElements, frames: next.frames.count,
                    solverBytes: payload.bytes, replayBytes: next.fieldPayloadBytes, process: process, cpuUtilization: cpu)
            }
            continuation.yield(snapshot(.calculating, process: started, cpu: nil))
            var lastCPU: Double?
            while !Task.isCancelled && solver.step(recording: &next) {
                let now = ProcessInfo.processInfo.systemUptime
                if now - previous.time >= 0.25 {
                    let process = AssemblyProcessSample()
                    lastCPU = process.utilization(since: previous)
                    continuation.yield(snapshot(.calculating, process: process, cpu: lastCPU))
                    previous = process
                }
            }
            let state: AssemblyComputation.State
            if solver.finished {
                state = .completed
                next.finish(solver)
            } else if solver.simulation.failure != nil {
                state = .failed
                next.finish(solver)
            } else {
                state = .paused
                next.checkpoint(solver)
            }
            let process = AssemblyProcessSample()
            let cpu = process.time - previous.time >= 0.10 || lastCPU == nil
                ? process.utilization(since: previous) : lastCPU
            continuation.finish()
            return (solver, next, snapshot(state, process: process, cpu: cpu))
        }
        solveTask = worker
        Task { [weak self] in
            for await update in updates {
                guard let self, solveID == id else { return }
                computation = update
            }
            let (solved, recorded, final) = await worker.value
            guard let self, solveID == id else { return }
            solveID = nil
            solveTask = nil
            run = solved
            replay = solved.simulation.time == 0 && solved.simulation.failure == nil ? nil : recorded
            frameIndex = max(0, (replay?.frames.count ?? 0) - 1)
            computation = final
            solving = false
            cancelling = false
            if final.state == .completed {
                // Calibrate future estimates from what this run actually cost.
                if let start = runEstimate, final.elapsed > 0.5, start.steps > 0 {
                    let perStep = Double(max(1, start.parallel ? start.lanes.heavier : start.elementWeight))
                    RuntimeWarnings.record(rate: Double(final.work.steps) * perStep / final.elapsed)
                }
                runNumber += 1
                var entry = current
                entry.label = "Run \(runNumber)"
                history.append(entry)
                if history.count > Self.historyLimit { history.removeFirst() }
            }
        }
    }

    func cancelCalculation() {
        guard solving, !cancelling else { return }
        cancelling = true
        solveTask?.cancel()
    }

    func seek(to time: Double) {
        guard let replay else { return }
        pause()
        frameIndex = replay.index(at: time)
    }

    func stepFrame(by increment: Int) {
        guard !frames.isEmpty else { return }
        pause()
        frameIndex = min(frames.count - 1, max(0, frameIndex + increment))
    }

    func toggle() {
        if running { pause(); return }
        guard frames.count > 1, !solving else { return }
        if frameIndex == frames.count - 1 { frameIndex = 0 }
        playbackTime = displayTime
        lastTick = nil
        running = true
    }

    func tick(now: Double = ProcessInfo.processInfo.systemUptime) {
        guard running, let replay else { return }
        defer { if running { lastTick = now } }
        guard let lastTick else { return }
        // 1× plays the recorded interval in five wall-clock seconds.
        playbackTime += max(0, now - lastTick) * playbackDuration * playbackSpeed / 5
        frameIndex = replay.index(at: playbackTime)
        if playbackTime >= playbackDuration { pause() }
    }

    // Used by the existing inspection and verification entry points.
    func advance(to time: Double) {
        guard time > simulation.time else { return }
        pause()
        placingGauge = false
        linkPlacement = nil
        var recorded = replay ?? AssemblyReplay(run)
        recorded.resume()
        while simulation.time < time && run.step() { recorded.record(run) }
        recorded.finish(run)
        frameIndex = recorded.frames.count - 1
        replay = recorded
    }
}
