import Foundation

// Mesh-dependent size limits, the fracture on/off status of a body, and advisory (never blocking) resolution notes.

extension AssemblyPart {
    /// The smallest body the standard mesh accepts, in metres. Every earlier scene satisfies it.
    public static let baseMinimumSize = 0.025

    /// The smallest body dimension for a mesh. The requirement is numerical: a body must span about three
    /// nominal elements, as a 25 mm body does at the standard mesh (about 9 mm elements). The nominal element
    /// is r times smaller on a ×r mesh, so the minimum is r times smaller. It never exceeds 25 mm, so every
    /// scene saved under the old fixed minimum stays valid. Very small bodies on fine meshes have tiny
    /// elements and long run times; the run-cost warning reports that, and nothing here blocks it.
    public static func minimumSize(resolution: AssemblyScene.Resolution) -> Double {
        baseMinimumSize / Double(resolution.rawValue)
    }

    /// An enclosure also needs a 5 mm wall (two element layers) that is at most 40% of its smaller side,
    /// so its smaller side is at least 12.5 mm whatever the mesh.
    static let minimumEnclosureSide = 0.0125

    private func lowerSize(_ resolution: AssemblyScene.Resolution) -> Double {
        let mesh = Self.minimumSize(resolution: resolution)
        return shape == .enclosure ? max(mesh, Self.minimumEnclosureSide) : mesh
    }

    public func sizeRange(resolution: AssemblyScene.Resolution) -> ClosedRange<Double> {
        lowerSize(resolution)...Self.maximumSize
    }

    public func widthRange(resolution: AssemblyScene.Resolution) -> ClosedRange<Double> {
        lowerSize(resolution)...(support == .fixed ? Self.fixtureWidthRange.upperBound : Self.maximumSize)
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
        if bondedLayer != nil {
            return "Bonded-layer blocks cannot fracture: permanent bonds share nodes, so there is no seam to open. Use two bodies joined by a Breakable link, or remove the bonded layers."
        }
        if let support {
            return support.isFixture
                ? "A fixed support is rigid and never calculated as a deforming body, so it cannot fracture."
                : "A clamped body cannot fracture yet: inserting a crack would move the held nodes. Remove the clamp to allow fracture."
        }
        if fracture == nil, let provenance = material.provenance,
           let profile = MaterialProfile.references.first(where: { $0.id == provenance.id }),
           case let .unavailable(reason) = profile.fractureEstimate {
            return "This material has no sourced fracture estimate. \(reason)"
        }
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
        return "Advisory: this slender body has about \(across) elements across its thickness and \(cause), so it may bend. Bending is usually resolved with roughly 8 or more; fewer tends to make it too stiff. This is a guideline, not a limit: check the result against a finer mesh."
    }
}

extension AssemblyScene {
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
            Limit(name: "Smallest body", value: "25 mm at the standard mesh, 25 mm ÷ n at a ×n mesh", kind: .numerical,
                  cause: "A body must span about three nominal elements (the standard mesh has ≈9 mm elements). The minimum shrinks with the mesh element size, so a finer mesh can resolve a smaller body. It never exceeds 25 mm. Very small bodies on fine meshes run slowly; the run-cost estimate says so."),
            Limit(name: "Largest body", value: "300 mm (a fixed support: 1,000 mm wide)", kind: .workshop,
                  cause: "Keeps triangle counts and run times manageable. It is not physical. A fixed support is never calculated as a deforming body, so it may be wider."),
            Limit(name: "Bodies", value: "\(maximumParts)", kind: .implementation,
                  cause: "Contact detection checks body pairs and storage is sized for this many; it is not a physical limit."),
            Limit(name: "Connections", value: "\(maximumConnections)", kind: .implementation,
                  cause: "Springs and breakable links are stored with a fixed capacity; it is not a physical limit."),
            Limit(name: "Wall thickness", value: "5 mm to 40% of the smaller side", kind: .numerical,
                  cause: "At least two element layers through the wall; thicker than 40% leaves no hollow."),
            Limit(name: "Bending resolution", value: "about 8 elements across thickness (advisory)", kind: .numerical,
                  cause: "A guideline for linear triangles in bending, shown as a note for slender bodies. It does not block anything."),
        ]
    }
}
