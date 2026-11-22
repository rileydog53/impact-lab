import Foundation

public struct OffAxisSettings: Codable, Equatable, Sendable {
    public var strikerOffset = 0.026
    public var strikerAngle = -8.0
    public var targetVelocityY = 0.0
    public var receiverGap = 0.020
    public var receiverOffset = -0.017
    public var receiverAngle = 9.0
    public var receiverVelocityX = 0.0
    public var receiverVelocityY = 0.0
    public var duration = 0.11
    public var receiver = SpecimenConfiguration(width: 0.069, height: 0.072, cornerRadius: 0.010,
                                                material: Material(young: 1.8e6))

    public static let strikerOffsetRange = -0.042...0.042
    public static let receiverOffsetRange = -0.065...0.065
    public static let angleRange = -25.0...25.0
    public static let transverseRange = -0.30...0.30
    public static let receiverGapRange = 0.009...0.055
    public static let receiverSpeedRange = -0.08...0.18
    public static let durationRange = 0.075...0.22

    var isValid: Bool {
        Self.strikerOffsetRange.contains(strikerOffset) && Self.receiverOffsetRange.contains(receiverOffset)
            && Self.angleRange.contains(strikerAngle) && Self.angleRange.contains(receiverAngle)
            && Self.transverseRange.contains(targetVelocityY) && Self.transverseRange.contains(receiverVelocityY)
            && Self.receiverGapRange.contains(receiverGap) && Self.receiverSpeedRange.contains(receiverVelocityX)
            && Self.durationRange.contains(duration)
    }
}

struct FreeImpactContacts: Sendable {
    let layerContact, receiverContact: BoundaryContact
    let strikerBacking, strikerReceiver, facingReceiver: BoundaryContact

    init(striker: ContactSurface, facing: ContactSurface, backing: Body, receiver: Body) {
        let back = ContactSurface(body: backing)
        let catchBody = ContactSurface(body: receiver)
        layerContact = BoundaryContact(left: facing, right: back)
        receiverContact = BoundaryContact(left: back, right: catchBody)
        strikerBacking = BoundaryContact(left: striker, right: back)
        strikerReceiver = BoundaryContact(left: striker, right: catchBody)
        facingReceiver = BoundaryContact(left: facing, right: catchBody)
    }
}

extension Simulation {
    static func offAxisImpact(scene: SceneConfiguration, refinement: Int, stepScale: Double) -> Simulation {
        let options = scene.offAxis!
        let facing = scene.second!
        let backing = scene.third!
        let height = facing.height!
        let rows = 10 * refinement
        let columns = 12 * refinement
        // Finite-length tensile links span a thin initial clearance. Bulk
        // contact supplies compression as the clearance closes.
        let bridgeLength = 0.0015
        let targetVelocity = Point(scene.targetVelocityX, options.targetVelocityY)

        func layer(_ part: SpecimenConfiguration, x: Double) -> Body {
            let mesh = Mesh.rectangle(columns: columns, rows: rows) { u, v in
                Point(part.width * u, part.height! * (v - 0.5))
            }
            return Body(mesh: mesh, material: part.material,
                        position: mesh.reference.map { $0 + Point(x, scene.centerY) }, velocity: targetVelocity)
        }

        func rounded(_ part: SpecimenConfiguration, face: Double, y: Double, degrees: Double,
                     velocity: Point, leftOfFace: Bool) -> Body {
            let mesh = Mesh.roundedBlock(columns: columns, rows: rows, width: part.width,
                                         height: part.height!, radius: part.cornerRadius!)
            let angle = degrees * .pi / 180
            let c = cos(angle), s = sin(angle)
            let rotated = mesh.reference.map { Point(c * $0.x - s * $0.y, s * $0.x + c * $0.y) }
            let edge = leftOfFace ? rotated.map(\.x).max()! : rotated.map(\.x).min()!
            let offset = Point(face - edge, scene.centerY + y)
            return Body(mesh: mesh, material: part.material, position: rotated.map { $0 + offset }, velocity: velocity)
        }

        let striker = rounded(scene.first, face: -scene.gap, y: options.strikerOffset, degrees: options.strikerAngle,
                              velocity: targetVelocity + Point(scene.speed, scene.velocityY), leftOfFace: true)
        let front = layer(facing, x: 0)
        let rear = layer(backing, x: facing.width + bridgeLength)
        let receiver = rounded(options.receiver, face: facing.width + bridgeLength + backing.width + options.receiverGap,
                                y: options.receiverOffset, degrees: options.receiverAngle,
                                velocity: Point(options.receiverVelocityX, options.receiverVelocityY), leftOfFace: false)
        let spacing = height / Double(rows)
        let pairs = (0...rows).map { row in
            CohesiveSeam.Pair(left: row * (columns + 1) + columns, right: row * (columns + 1),
                              weight: row == 0 || row == rows ? spacing / 2 : spacing)
        }
        let settings = scene.seam!
        let seam = CohesiveSeam(law: settings.law(left: front.material, right: rear.material),
                                canSeparate: settings.response == .separating, height: height, spacing: spacing,
                                phaseDuration: 0, pairs: pairs, grips: nil, bridgeLength: bridgeLength)
        return Simulation(primary: striker, secondary: front, pairContact: .init(left: .init(body: striker),
                                                                                right: .init(body: front)),
                          gap: scene.gap, stepScale: stepScale, j2: scene.impactPlasticity!.model(for: striker.material),
                          seam: seam, tertiary: rear, secondaryJ2: scene.impactPlasticity!.model(for: front.material),
                          receiver: receiver)
    }
}
