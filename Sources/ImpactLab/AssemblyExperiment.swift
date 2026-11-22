import Foundation
import ImpactPhysics
import Observation

struct AssemblyComparison {
    let details: String
    let samples: [TraceSample]
    let tracksFracture: Bool
}

@MainActor @Observable final class AssemblyExperiment {
    private var run = try! AssemblyRun(.enclosureExample())
    private(set) var running = false
    private var lastTick: Double?
    private var budget = 0.0
    var slow = false
    var error: String?
    var selectedPart: UUID?
    var selectedConnection: UUID?
    private(set) var reference: AssemblyComparison?

    var scene: AssemblyScene { run.simulation.scene }
    var simulation: AssemblySimulation { run.simulation }
    var samples: [TraceSample] { run.samples }
    var relativeMotion: Point { run.relativeMotion }
    var canRun: Bool { simulation.initialIssue == nil && simulation.failure == nil && !scene.parts.isEmpty && !run.finished }
    var finished: Bool { run.finished }
    var selectedIndex: Int? { scene.parts.firstIndex { $0.id == selectedPart } }
    var monitoredName: String { scene.parts.first { $0.id == scene.monitor }?.name ?? scene.parts.first?.name ?? "Body" }
    var elementCount: Int { (0..<simulation.bodyCount).reduce(0) { $0 + simulation.body($1).mesh.elements.count } }
    var relativeName: String { scene.parts.first { $0.id == scene.relativeTo }?.name ?? "Lab frame" }
    var current: AssemblyComparison {
        let monitored = scene.parts.first { $0.id == scene.monitor } ?? scene.parts.first
        let pattern = monitored.flatMap { $0.shape == .block ? $0.fracture?.pattern.rawValue : nil }
        let details = [monitoredName, scene.resolution.label, pattern, "\(elementCount) triangles"].compactMap { $0 }
        return AssemblyComparison(details: details.joined(separator: " · "), samples: samples,
                                  tracksFracture: scene.parts.contains { $0.fracture != nil })
    }

    var canRefine: Bool { scene.resolution != .extraFine && samples.count > 1 }

    func refine() {
        guard canRefine, let resolution = AssemblyScene.Resolution(rawValue: scene.resolution.rawValue + 1) else { return }
        pin()
        edit { $0.meshResolution = resolution }
        if self.scene.resolution == resolution { toggle() }
    }

    func configure(_ scene: AssemblyScene) throws {
        let next = try AssemblyRun(scene)
        pause()
        run = next
        if !scene.parts.contains(where: { $0.id == selectedPart }) { selectedPart = nil }
        if !scene.connections.contains(where: { $0.id == selectedConnection }) { selectedConnection = nil }
    }

    func edit(_ change: (inout AssemblyScene) -> Void) {
        var modified = scene
        change(&modified)
        guard modified != scene else { return }
        do { try configure(modified) }
        catch { self.error = error.localizedDescription }
    }

    func select(_ part: UUID) {
        selectedPart = part
        selectedConnection = nil
    }

    func selectConnection(_ connection: UUID) {
        selectedConnection = connection
        selectedPart = nil
    }

    @discardableResult func add(_ shape: AssemblyPart.Shape) -> UUID? {
        guard scene.parts.count < AssemblyScene.maximumParts else { return nil }
        let size = shape == .block ? Point(0.060, 0.050) : Point(0.130, 0.100)
        let right = scene.parts.map { $0.center.x + 0.5 * max($0.size.x, $0.size.y) }.max()
        let x = right.map { min(0.93, $0 + size.x / 2 + 0.035) } ?? 0
        let part = AssemblyPart("\(shape.rawValue) \(scene.parts.count + 1)", shape: shape, center: Point(x, 0), size: size)
        edit { $0.parts.append(part) }
        select(part.id)
        return part.id
    }

    func updatePart(_ id: UUID, _ change: (inout AssemblyPart) -> Void) {
        edit { scene in
            guard let index = scene.parts.firstIndex(where: { $0.id == id }) else { return }
            change(&scene.parts[index])
            let part = scene.parts[index]
            if part.shape == .enclosure {
                scene.parts[index].wall = min(part.wall, 0.4 * min(part.size.x, part.size.y))
            }
        }
    }

    @discardableResult func addConnection(first: UUID, second: UUID) -> UUID? {
        guard first != second, scene.connections.count < AssemblyScene.maximumConnections else { return nil }
        let new = AssemblyConnection(first: first, second: second)
        edit { $0.connections.append(new) }
        selectConnection(new.id)
        return new.id
    }

    func updateConnection(_ id: UUID, _ change: (inout AssemblyConnection) -> Void) {
        edit { scene in
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
        else if canRun { running = true }
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
        while simulation.time < time && advance() {}
    }
}
