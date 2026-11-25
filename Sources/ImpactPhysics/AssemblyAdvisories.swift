import Foundation

// Mesh-dependent size limits, the fracture on/off status of a body, and advisory (never blocking) resolution notes.

extension AssemblyPart {
    /// The smallest body the standard mesh accepts, in metres. Every earlier scene satisfies it.
    public static let baseMinimumSize = 0.025

    /// The body size that spans about three nominal elements of a mesh (25 mm at the standard ≈9 mm mesh,
    /// 25 mm ÷ n on a ×n mesh). Advisory only since 2026-11-24 (Joseph's decision 2): a smaller block or round
    /// body still gets at least three cells across, so its elements are simply smaller, its time step shorter
    /// and its run longer. `sizeAdvisory` says so; the run-cost estimate gives the time.
    public static func minimumSize(resolution: AssemblyScene.Resolution) -> Double {
        baseMinimumSize / Double(resolution.rawValue)
    }

    /// An enclosure needs a 5 mm wall that is at most 40% of its smaller side, so its smaller side is at
    /// least 12.5 mm. This is the enclosure's own geometry rule; an outline body with a hole has no such limit.
    public static let minimumEnclosureSide = 0.0125

    private var lowerSize: Double {
        shape == .enclosure ? max(Self.acceptedSizeRange.lowerBound, Self.minimumEnclosureSide) : Self.acceptedSizeRange.lowerBound
    }

    /// Accepted heights. The same for every mesh: resolution is advice, not a limit.
    public func sizeRange(resolution: AssemblyScene.Resolution) -> ClosedRange<Double> {
        lowerSize...Self.maximumSize
    }

    public func widthRange(resolution: AssemblyScene.Resolution) -> ClosedRange<Double> {
        lowerSize...Self.maximumSize
    }

    // MARK: Fracture status

    public enum FractureStatus: Equatable, Sendable {
        case on
        case off
        /// Material fracture cannot be switched on for this body, with the plain-text cause and what to change.
        case unavailable(String)

        public var tag: String {
            switch self {
            case .on: "fracture on"
            case .off: "fracture off"
            case .unavailable: "fracture n/a"
            }
        }
    }

    /// Why Material fracture cannot be enabled, or nil when it can (whether or not it is currently on).
    public var fractureUnavailableReason: String? {
        if shape == .round {
            return "Round bodies cannot fracture: they use an elliptical mesh with no grid of element faces for cracks to open along. Use a rectangular block."
        }
        if bondedLayer != nil && notch != nil {
            return "A bonded-layer block cannot also have a V-notch. Remove the notch to let the layers crack and delaminate."
        }
        if support?.isFixture == true {
            return "A fixed support is rigid and never calculated as a deforming body, so it cannot fracture. Clamp an edge instead to hold it and let it crack."
        }
        // A Library material with no sourced crack numbers can still crack with numbers the user types
        // (Joseph, 2026-11-25); the editor says plainly that those numbers are not from a source.
        return nil
    }

    public var fractureStatus: FractureStatus {
        if fracture != nil { return .on }
        if let reason = fractureUnavailableReason { return .unavailable(reason) }
        return .off
    }
}

extension AssemblyScene {
    /// A resolution advisory for a body, or nil. It never blocks an edit or a run: it compares the number of
    /// elements the mesh places across a slender block's thickness with the roughly 8 that a bending response
    /// of linear triangles usually needs, and only speaks when that body can plausibly be loaded in bending.
    public func bendingAdvisory(for part: AssemblyPart) -> String? {
        guard part.shape == .block, part.support != .fixed else { return nil }
        let long = max(part.size.x, part.size.y), thin = min(part.size.x, part.size.y)
        guard long / thin >= 4 else { return nil }
        let refinement = (part.refinement ?? resolution).rawValue
        let across = max(3, Int((thin / 0.009).rounded())) * refinement
        guard across < 8 else { return nil }
        let clamped = part.support != nil
        let others = parts.count > 1
        let hasGravity = (gravity ?? 0) > 0
        guard clamped || others || hasGravity else { return nil }
        let cause = clamped ? "it is clamped" : hasGravity ? "gravity acts on it" : "it can be struck or loaded by another body"
        return "Note: this thin body has only about \(across) triangles across its thickness and \(cause), so it may bend. Bending usually needs about 8 or more across; with fewer it comes out too stiff. Not a limit: compare with a finer mesh."
    }
}

extension AssemblyScene {
    /// Advisory notes for one body: resolution, size against the mesh, outline mesh guidance. Never blocking.
    public func advisories(for part: AssemblyPart) -> [String] {
        var notes: [String] = []
        let mesh = part.refinement ?? resolution
        if let bending = bendingAdvisory(for: part) { notes.append(bending) }
        if part.shape != .outline, part.support != .fixed {
            let resolved = AssemblyPart.minimumSize(resolution: mesh)
            let small = min(part.size.x, part.size.y)
            if small < resolved - 1e-12 {
                notes.append(String(format: "Note: at %.3g mm this body is smaller than three elements (triangles) of the %@ mesh (%.3g mm), so its triangles are made smaller to fit. Each calculation step gets shorter and the run takes longer (see the time estimate). Nothing is blocked.",
                                    small * 1000, mesh.label, resolved * 1000))
            }
            if max(part.size.x, part.size.y) > AssemblyPart.sizeRange.upperBound + 1e-12 {
                notes.append(String(format: "Note: at %.4g mm this body is larger than the old 300 mm editor limit. Bigger bodies have more triangles at the same mesh, so they take longer (see the time estimate).",
                                    max(part.size.x, part.size.y) * 1000))
            }
        }
        if let advice = part.outlineAdvice(resolution: mesh) {
            let h = part.outline!.edgeLength(resolution: mesh)
            if part.outlineQuality(resolution: mesh) == nil {
                notes.append(String(format: "Mesh: triangle edges about %.3g mm, roughly %@ triangles (estimate).", h * 1000, advice.estimatedTriangles.formatted()))
            }
            if let thin = advice.thinnestSection {
                // Rows of near-equilateral triangles across a section of width t: about t / (0.87 h).
                let rows = thin / (0.866 * h)
                if rows < 8, part.support != .fixed {
                    notes.append(String(format: "Note: the narrowest part (%.3g mm) has about %.1f rows of triangles across it. If it bends, about 8 rows are usually needed; with fewer it comes out too stiff (project beam check: 4 rows about 7%% too stiff, 8 rows about 1%%). Not a limit: a mesh size of %.2g mm gives about 8.",
                                        thin * 1000, rows, thin / (8 * 0.866) * 1000))
                }
            }
            notes += advice.notes.filter { $0.level == .caution || $0.text.hasPrefix("Re-entrant") }
                .filter { !$0.text.hasPrefix("The narrowest part") }.map { "Note: " + $0.text }
        }
        return notes
    }

    /// Scene-wide advisory notes. Never blocking.
    public var sceneAdvisories: [String] {
        guard parts.count > Self.advisoryParts else { return [] }
        return ["Note: \(parts.count) bodies. Every pair is checked for touching (\((parts.count * (parts.count - 1) / 2).formatted()) pairs), so the run gets slower quickly as bodies are added (see the time estimate). The old limit was \(Self.advisoryParts); up to \(Self.maximumParts) are accepted."]
    }

    public struct Limit: Equatable, Sendable {
        public enum Kind: String, Sendable {
            /// A physical or numerical requirement of the model.
            case numerical = "Numerical requirement"
            /// A deliberate editor boundary that keeps run time and memory manageable.
            case workshop = "Workshop limit"
            /// A fixed size in the current implementation, not a physical statement.
            case implementation = "Implementation limit"
        }
        public let name: String
        public let value: String
        public let kind: Kind
        public let cause: String
    }

    /// Each editor limit with its cause, so none is mistaken for physics.
    public static var limits: [Limit] {
        [
            Limit(name: "Body size", value: "0.5 mm to 10 m (advice below 25 mm ÷ n and above 300 mm)", kind: .implementation,
                  cause: "Input bounds only. Since 2026-11-24 size is advice, not a limit: a small body gets smaller elements and a shorter time step, a large one more triangles. The run-cost estimate gives the time and an advisory note explains the cause."),
            Limit(name: "Bodies", value: "up to \(maximumParts) (advice above \(advisoryParts))", kind: .implementation,
                  cause: "Contact checks every pair of bodies, so cost grows with the square of the count. An advisory note and the run-cost estimate report it; the upper bound only keeps the editor responsive."),
            Limit(name: "Outline mesh", value: "about \(OutlineMeshCache.triangleCeiling.formatted()) triangles per body", kind: .implementation,
                  cause: "Memory on this Mac, not physics. Outline bodies take a target edge length (12 mm ÷ n by default) and report triangle count, narrowest section and corner notes as advice."),
            Limit(name: "Connections", value: "\(maximumConnections)", kind: .implementation,
                  cause: "Springs and breakable links are stored with a fixed capacity; it is not a physical limit."),
            Limit(name: "Wall thickness", value: "5 mm to 40% of the smaller side", kind: .numerical,
                  cause: "At least two element layers through the wall; thicker than 40% leaves no hollow."),
            Limit(name: "Bending resolution", value: "about 8 elements across thickness (advisory)", kind: .numerical,
                  cause: "A guideline for linear triangles in bending, shown as a note for slender bodies. It does not block anything."),
        ]
    }
}
