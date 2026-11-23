import Foundation
import ImpactPhysics
import Observation

struct AssemblyComparison {
    let details: String
    let samples: [TraceSample]
    let tracksFracture: Bool
}

@MainActor @Observable final class AssemblyExperiment {
    private struct Edit {
        let scene: AssemblyScene
        let part: UUID?
        let connection: UUID?
        let action: String
    }

    private var run: AssemblyRun
    private var savedScene: AssemblyScene
    private var undoEdits: [Edit] = []
    private var redoEdits: [Edit] = []
    private(set) var title = "Enclosure example"
    private(set) var fileURL: URL?
    var previewPart: AssemblyPart?
    private(set) var running = false
    private var lastTick: Double?
    private var budget = 0.0
    var slow = false
    var error: String?
    var selectedPart: UUID?
    var selectedConnection: UUID?
    var placingGauge = false
    private(set) var reference: AssemblyComparison?
    private(set) var cameraRevision = 0

    init() {
        let initial = AssemblyScene.enclosureExample()
        run = try! AssemblyRun(initial)
        savedScene = initial
    }

    var scene: AssemblyScene { run.simulation.scene }
    var simulation: AssemblySimulation { run.simulation }
    var samples: [TraceSample] { run.samples }
    var relativeMotion: Point { run.relativeMotion }
    var canRun: Bool { simulation.initialIssue == nil && simulation.failure == nil && !scene.parts.isEmpty && !run.finished }
    var canEdit: Bool { !running && simulation.time == 0 }
    var isDirty: Bool { scene != savedScene }
    var undoAction: String? { undoEdits.last?.action }
    var redoAction: String? { redoEdits.last?.action }
    var finished: Bool { run.finished }
    var selectedIndex: Int? { scene.parts.firstIndex { $0.id == selectedPart } }
    var gauges: [AssemblyGauge] { scene.gauges ?? [] }
    var monitoredName: String { scene.parts.first { $0.id == scene.monitor }?.name ?? scene.parts.first?.name ?? "Body" }
    var elementCount: Int { (0..<simulation.bodyCount).reduce(0) { $0 + simulation.body($1).mesh.elements.count } }
    var relativeName: String { scene.parts.first { $0.id == scene.relativeTo }?.name ?? "Lab frame" }
    var current: AssemblyComparison {
        let monitored = scene.parts.first { $0.id == scene.monitor } ?? scene.parts.first
        let pattern = monitored.flatMap { $0.shape == .block ? $0.fracture?.pattern.rawValue : nil }
        let mesh = monitored?.refinement ?? scene.resolution
        let details = [monitoredName, mesh.label, pattern, "\(elementCount) triangles"].compactMap { $0 }
        return AssemblyComparison(details: details.joined(separator: " · "), samples: samples,
                                  tracksFracture: scene.parts.contains { $0.fracture != nil })
    }

    var canRefine: Bool {
        scene.parts.contains { $0.refinement == nil } && scene.resolution != .x7 && samples.count > 1
    }

    func refine() {
        guard canRefine, let resolution = AssemblyScene.Resolution(rawValue: scene.resolution.rawValue + 1) else { return }
        pin()
        edit("Refine Assembly Mesh") { $0.meshResolution = resolution }
        if self.scene.resolution == resolution { toggle() }
    }

    func configure(_ scene: AssemblyScene) throws {
        let next = try AssemblyRun(scene)
        pause()
        placingGauge = false
        previewPart = nil
        run = next
        if !scene.parts.contains(where: { $0.id == selectedPart }) { selectedPart = nil }
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
        Edit(scene: scene, part: selectedPart, connection: selectedConnection, action: action)
    }

    private func restoreEdit(fromUndo: Bool) {
        guard canEdit, let previous = fromUndo ? undoEdits.last : redoEdits.last else { return }
        let current = checkpoint(previous.action)
        do {
            try configure(previous.scene)
            selectedPart = previous.part
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

    func select(_ part: UUID) {
        selectedPart = part
        selectedConnection = nil
    }

    func selectConnection(_ connection: UUID) {
        selectedConnection = connection
        selectedPart = nil
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
        guard scene.parts.count < AssemblyScene.maximumParts else { return nil }
        let size = shape == .block ? Point(0.060, 0.050) : Point(0.130, 0.100)
        let right = scene.parts.map { $0.center.x + 0.5 * max($0.size.x, $0.size.y) }.max()
        let x = right.map { min(0.93, $0 + size.x / 2 + 0.035) } ?? 0
        let part = AssemblyPart("\(shape.rawValue) \(scene.parts.count + 1)", shape: shape, center: Point(x, 0), size: size)
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

    func fitWall(of part: inout AssemblyPart) {
        if part.shape == .enclosure {
            part.wall = min(part.wall, 0.4 * min(part.size.x, part.size.y))
        }
    }

    @discardableResult func addConnection(first: UUID, second: UUID) -> UUID? {
        guard first != second, scene.connections.count < AssemblyScene.maximumConnections else { return nil }
        let new = AssemblyConnection(first: first, second: second)
        edit("Add Connection") { $0.connections.append(new) }
        guard scene.connections.contains(where: { $0.id == new.id }) else { return nil }
        selectConnection(new.id)
        return new.id
    }

    func updateConnection(_ id: UUID, _ change: (inout AssemblyConnection) -> Void) {
        edit("Edit Connection") { scene in
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
        reference = current
    }

    func pause() {
        running = false
        lastTick = nil
        budget = 0
    }

    func toggle() {
        if running { pause() }
        else if canRun { placingGauge = false; previewPart = nil; running = true }
    }

    func tick(now: Double = ProcessInfo.processInfo.systemUptime) {
        guard running else { return }
        defer { if running { lastTick = now } }
        guard let lastTick else { return }
        budget += min(0.05, max(0, now - lastTick)) * (slow ? 0.003 : 0.015)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.008
        while budget >= simulation.dt {
            guard advance(), running else { return }
            budget -= simulation.dt
            if ProcessInfo.processInfo.systemUptime > deadline {
                budget = min(budget, simulation.dt)
                return
            }
        }
    }

    @discardableResult func advance() -> Bool {
        let advanced = run.step()
        if !advanced || run.finished { pause() }
        return advanced
    }

    func advance(to time: Double) {
        pause()
        placingGauge = false
        while simulation.time < time && advance() {}
    }
}
