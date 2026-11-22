public struct LayeredImpactEvents: Sendable {
    public internal(set) var strike: Double?
    public internal(set) var failure: Double?
    public internal(set) var backstop: Double?
    public internal(set) var reclosure: Double?
    public internal(set) var receiver: Double?
}

extension Simulation {
    static func layeredImpact(scene: SceneConfiguration, refinement: Int, stepScale: Double) -> Simulation {
        let facing = scene.second!
        let backing = scene.third!
        let height = facing.height!
        let interfaceX = facing.width
        let rows = 6 * refinement
        let columns = 16 * refinement

        func region(_ part: SpecimenConfiguration, start: Double, speed: Double, stop: Bool = false) -> Body {
            let mesh = Mesh.rectangle(columns: columns, rows: rows) { u, v in
                Point(part.width * u, part.height! * (v - 0.5))
            }
            let offset = Point(start, scene.centerY)
            return Body(mesh: mesh, material: part.material, position: mesh.reference.map { $0 + offset },
                        velocity: Point(speed, 0), wallPenalty: stop ? 2500 : 0)
        }

        let striker = region(scene.first, start: -scene.first.width - scene.gap,
                             speed: scene.speed + scene.targetVelocityX)
        let front = region(facing, start: 0, speed: scene.targetVelocityX)
        let rear = region(backing, start: interfaceX, speed: scene.targetVelocityX, stop: scene.backstopX != nil)
        let spacing = height / Double(rows)
        let pairs = (0...rows).map { row in
            CohesiveSeam.Pair(left: row * (columns + 1) + columns, right: row * (columns + 1),
                              weight: row == 0 || row == rows ? spacing / 2 : spacing)
        }
        let settings = scene.seam!
        // A weaker tensile bond must still prevent deep overlap on reclosure.
        // The floor is the softer modulus divided by a 1/60 m penalty length.
        let law = settings.law(left: front.material, right: rear.material, minimumCompressionFactor: 60)
        let seam = CohesiveSeam(law: law,
                                canSeparate: settings.response == .separating, height: height, spacing: spacing,
                                phaseDuration: 0, pairs: pairs, grips: nil)
        return Simulation(primary: striker, secondary: front, pairContact: .init(left: .init(body: striker),
                                                                                right: .init(body: front)),
                          gap: scene.gap, stepScale: stepScale, j2: scene.impactPlasticity!.model(for: striker.material),
                          seam: seam, tertiary: rear, secondaryJ2: scene.impactPlasticity!.model(for: front.material),
                          rearStopX: scene.backstopX)
    }
}
