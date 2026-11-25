import Foundation

/// Ready-made showcase experiments: drawn (outline) geometry, literature material values, speeds at or below
/// 150 m/s, no heat. Each one is an ordinary scene document passed through `AssemblyScene.document`, so it is
/// validated exactly like a file the user opens, and every result is calculated by the solver, never scripted.
/// These are scenes only; nothing here changes the solver.
///
/// Material values (literature first; toughness values are experimental):
///  - PMMA (acrylic): E 3.0 GPa, ρ 1180 kg/m³, ν 0.37, tensile strength 65 MPa, K_IC about 1.0 MPa√m
///    (Wikipedia "Poly(methyl methacrylate)"; strength is the middle of the 47–79 MPa range), G = K²(1−ν²)/E ≈ 290 J/m².
///  - Soda-lime glass: E 72 GPa, ρ 2500, ν 0.23, strength 41 MPa, G 7.4 J/m², as in docs/layered-examples
///    (Wikipedia, Pilkington ATS-129). Glass strength depends strongly on surface flaws.
///  - Metals use the app's reference profiles (A36 steel, 6061-T6 aluminium, C11000 copper) with their own sources.
public enum ShowcasePreset: String, CaseIterable, Identifiable, Sendable {
    case notchedAcrylicBeam = "Notched acrylic beam"
    case glassArch = "Glass arch"
    case aluminumBracket = "Aluminium L-bracket"
    case laminatedGlass = "Laminated glass panel"
    case dogbone = "Dogbone tension test"
    case perforatedBlock = "Perforated copper block"
    case glassWindow = "First crack, slow motion"

    public var id: Self { self }

    public var icon: String {
        switch self {
        case .notchedAcrylicBeam: "line.diagonal"
        case .glassArch: "archivebox"
        case .aluminumBracket: "l.square"
        case .laminatedGlass: "square.3.layers.3d"
        case .dogbone: "arrow.left.and.right"
        case .perforatedBlock: "circle.grid.3x3"
        case .glassWindow: "tortoise"
        }
    }

    public var description: String {
        switch self {
        case .notchedAcrylicBeam:
            "A drawn acrylic (PMMA) beam with a V-notch rests on two rigid supports. A steel ball strikes the top, opposite the notch. Watch whether a crack starts at the notch tip and how far it runs."
        case .glassArch:
            "A drawn soda-lime glass arch, clamped at both feet, is struck on its crown by a steel ball. Arches turn load into compression, so watch where tension appears and where the first crack opens."
        case .aluminumBracket:
            "A drawn 6061-T6 aluminium L-bracket is clamped at its foot. A steel ball lands on the tip of the arm. Watch the plastic-work map at the inside corner, where bending concentrates."
        case .laminatedGlass:
            "Glass laminated with PVB and bonded to aluminium, hit by a steel ball at 40 m/s (a ball-drop style test). Watch for the first glass crack and for the glass coming off the interlayer."
        case .dogbone:
            "A drawn 6061-T6 aluminium dogbone coupon in the virtual test machine: the left grip holds, the right grip pulls at 5 m/s. Watch yielding start in the narrow gauge section."
        case .perforatedBlock:
            "A drawn copper block with nine holes is clamped at the bottom and crushed from the top by the test machine at 8 m/s. Watch the ligaments between the holes yield and the holes squash."
        case .glassWindow:
            "A glass plate with a window cut out, clamped at its base, struck by a steel ball at 20 m/s. After Calculate, open the first-crack milestone and use Slow Down Here to replay it frame by frame."
        }
    }

    public var limitations: String {
        "2D plane strain, so each round striker is really a long rod seen end on. Cracks follow element edges of the generated mesh, and toughness values are experimental. Numerical results, not physical validation."
    }

    public func scene() throws -> AssemblyScene {
        let document: [String: Any]
        switch self {
        case .notchedAcrylicBeam:
            // 120 × 16 mm beam, V-notch 4 mm deep and 3 mm wide in the middle of the bottom edge.
            let beam: [[Double]] = [[-0.06, -0.008], [-0.0015, -0.008], [0, -0.004], [0.0015, -0.008],
                                    [0.06, -0.008], [0.06, 0.008], [-0.06, 0.008]]
            document = [
                "duration": 0.0015, "meshResolution": "x4",
                "monitor": "Acrylic beam",
                "parts": [
                    ["name": "Acrylic beam", "shape": "outline", "center": [0, 0],
                     "outline": ["outer": beam, "meshSize": 0.002],
                     "material": Self.pmma, "fracture": Self.pmmaFracture],
                    Self.fixedSupport("Left support", center: [-0.05, -0.0135]),
                    Self.fixedSupport("Right support", center: [0.05, -0.0135]),
                    Self.steelBall(diameter: 0.012, center: [0, 0.0145], velocity: [0, -12])
                ]
            ]
        case .glassArch:
            // Semicircular ring, outer radius 40 mm, inner 30 mm; the feet sit on y = 0 and are clamped.
            let outer = Self.arc(radius: 0.04, from: 0, to: .pi, count: 25)
            let inner = Self.arc(radius: 0.03, from: .pi, to: 0, count: 19)
            let ring = (outer + inner).map { [$0[0], $0[1] - 0.02] }
            document = [
                "duration": 0.0004, "meshResolution": "x4",
                "monitor": "Glass arch",
                "parts": [
                    ["name": "Glass arch", "shape": "outline", "center": [0, 0], "support": "clampBottom",
                     "outline": ["outer": ring, "meshSize": 0.0025],
                     "material": Self.glass, "fracture": Self.glassFracture],
                    Self.steelBall(diameter: 0.010, center: [0, 0.0256], velocity: [0, -8])
                ]
            ]
        case .aluminumBracket:
            // Foot 10 mm wide and 64 mm tall, arm 70 mm long and 8 mm thick at the top, small inside fillet.
            let bracket: [[Double]] = [[-0.035, -0.032], [-0.025, -0.032], [-0.025, 0.020], [-0.023, 0.024],
                                       [0.035, 0.024], [0.035, 0.032], [-0.035, 0.032]]
            document = [
                "duration": 0.0012, "meshResolution": "x4",
                "monitor": "Aluminium bracket",
                "parts": [
                    ["name": "Aluminium bracket", "shape": "outline", "center": [0, 0], "support": "clampBottom",
                     "outline": ["outer": bracket, "meshSize": 0.002],
                     "material": ["profile": "aluminum-6061-t6", "elasticOnly": false]],
                    Self.steelBall(diameter: 0.012, center: [0.026, 0.0395], velocity: [0, -30])
                ]
            ]
        case .laminatedGlass:
            return try Self.laminatedGlassScene()
        case .dogbone:
            // 100 mm coupon: 20 mm wide grip ends, 10 mm wide gauge 40 mm long, 5 mm tapers.
            let half: [[Double]] = [[-0.05, -0.01], [-0.025, -0.01], [-0.02, -0.005], [0.02, -0.005],
                                    [0.025, -0.01], [0.05, -0.01]]
            let dogbone = half + half.reversed().map { [$0[0], -$0[1]] }
            document = [
                "duration": 0.0008, "meshResolution": "x4",
                "monitor": "Dogbone coupon",
                "gauges": [["name": "Gauge centre", "body": "Dogbone coupon", "location": [0, 0]]],
                "parts": [
                    ["name": "Dogbone coupon", "shape": "outline", "center": [0, 0], "support": "clampLeft",
                     "outline": ["outer": dogbone, "meshSize": 0.0025],
                     "material": ["profile": "aluminum-6061-t6", "elasticOnly": false],
                     "grip": ["edge": "right", "velocity": [5, 0], "ramp": 0.0001]]
                ]
            ]
        case .perforatedBlock:
            let square: [[Double]] = [[-0.02, -0.02], [0.02, -0.02], [0.02, 0.02], [-0.02, 0.02]]
            let holes = [-0.0125, 0, 0.0125].flatMap { y in
                [-0.0125, 0, 0.0125].map { x in Self.arc(radius: 0.004, from: 0, to: 2 * .pi, count: 16, closed: false)
                    .map { [$0[0] + x, $0[1] + y] } }
            }
            document = [
                "duration": 0.0006, "meshResolution": "x4",
                "monitor": "Perforated block",
                "parts": [
                    ["name": "Perforated block", "shape": "outline", "center": [0, 0], "support": "clampBottom",
                     "outline": ["outer": square, "holes": holes, "meshSize": 0.0015],
                     "material": ["profile": "copper-c11000-annealed", "elasticOnly": false],
                     "grip": ["edge": "top", "velocity": [0, -8], "ramp": 0.0001]]
                ]
            ]
        case .glassWindow:
            let plate: [[Double]] = [[-0.05, -0.02], [0.05, -0.02], [0.05, 0.02], [-0.05, 0.02]]
            let window: [[Double]] = [[-0.008, -0.006], [0.008, -0.006], [0.008, 0.006], [-0.008, 0.006]]
            document = [
                "duration": 0.0004,
                "monitor": "Glass plate",
                "parts": [
                    ["name": "Glass plate", "shape": "outline", "center": [0, 0], "support": "clampBottom",
                     "outline": ["outer": plate, "holes": [window], "meshSize": 0.003],
                     "material": Self.glass, "fracture": Self.glassFracture],
                    Self.steelBall(diameter: 0.012, center: [0, 0.0262], velocity: [0, -20])
                ]
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: document)
        return try AssemblyScene.document(data)
    }

    // MARK: Materials

    static var pmma: [String: Any] { ["young": 3.0e9, "density": 1180, "poisson": 0.37] }
    static var pmmaFracture: [String: Any] { [
        "strength": 6.5e7, "energy": 290,
        "energySource": ["status": "estimated",
                         "citation": "PMMA K_IC about 1.0 MPa√m and tensile strength 47–79 MPa (Wikipedia); G = K²(1−ν²)/E.",
                         "url": "https://en.wikipedia.org/wiki/Poly(methyl_methacrylate)",
                         "caution": "Experimental; acrylic toughness depends on grade, rate and temperature."]
    ] }
    static var glass: [String: Any] { ["young": 7.2e10, "density": 2500, "poisson": 0.23] }
    static var glassFracture: [String: Any] { [
        "strength": 4.1e7, "energy": 7.4,
        "energySource": ["status": "estimated",
                         "citation": "Soda-lime glass K_IC 0.75 MPa√m (Wikipedia, MakeItFrom) and mean modulus of rupture 41 MPa (Pilkington ATS-129); G = K²(1-ν²)/E.",
                         "url": "https://en.wikipedia.org/wiki/Soda%E2%80%93lime_glass",
                         "caution": "Experimental; glass strength depends strongly on surface flaws."]
    ] }

    static func steelBall(diameter: Double, center: [Double], velocity: [Double]) -> [String: Any] {
        ["name": "Steel ball", "shape": "round", "size": [diameter, diameter], "center": center, "velocity": velocity,
         "material": ["profile": "structural-steel-a36", "elasticOnly": true]]
    }

    static func fixedSupport(_ name: String, center: [Double]) -> [String: Any] {
        ["name": name, "size": [0.01, 0.01], "center": center, "support": "fixed",
         "material": ["profile": "structural-steel-a36", "elasticOnly": true]]
    }

    /// Points on a circular arc about the origin, counter-clockwise when `to > from`.
    static func arc(radius: Double, from: Double, to: Double, count: Int, closed: Bool = true) -> [[Double]] {
        let n = closed ? count - 1 : count
        return (0..<count).map { i in
            let t = from + (to - from) * Double(i) / Double(n)
            return [radius * cos(t), radius * sin(t)]
        }
    }

    /// The documented laminated-glass example (docs/layered-examples/laminated-glass-on-aluminium.json), with the
    /// ball at 40 m/s instead of 20 and the ball started just clear of the glass.
    static func laminatedGlassScene() throws -> AssemblyScene {
        let text = #"""
        { "duration": 0.0002, "meshResolution": "x4", "bulkViscosity": true, "monitor": "Laminated glass on aluminium",
          "parts": [
            { "name": "Laminated glass on aluminium", "size": [0.016, 0.1], "center": [0, 0],
              "material": { "young": 7.2e10, "density": 2500, "poisson": 0.23 },
              "fracture": { "strength": 4.1e7, "energy": 7.4 },
              "bondedLayer": {
                "interfaceFraction": 0.375,
                "material": { "young": 3.3e7, "density": 1070, "poisson": 0.48 },
                "bond": { "strength": 2.0e7, "energy": 329 },
                "third": {
                  "interfaceFraction": 0.475,
                  "material": { "profile": "aluminum-6061-t6", "elasticOnly": false },
                  "fracture": { "strength": 3.1e8, "energy": 10877 },
                  "bond": { "strength": 3.1e7, "energy": 466.5 } } } },
            { "name": "Steel ball", "shape": "round", "size": [0.02, 0.02], "center": [-0.0185, 0], "velocity": [40, 0],
              "material": { "profile": "structural-steel-a36", "elasticOnly": true } } ] }
        """#
        return try AssemblyScene.document(Data(text.utf8))
    }
}
