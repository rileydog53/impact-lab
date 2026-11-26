import SwiftUI

/// The ⓘ hover text for each setting the user can change (Joseph, 2026-11-26): what it does, what raising or
/// lowering it changes, and an everyday comparison. Every comparison number is a value from the app's own
/// Material Library (sources in docs/library-materials.md), worked out from those values, plain arithmetic
/// (fall speed √(2gh), sound speed √(E/ρ)) or an everyday fact (water 1000 kg/m³, Earth's gravity).
/// Plain words first, the technical name after.
enum SettingInfo {
    /// Matched against the start of a setting's label, so one entry covers every place the setting appears.
    private static let entries: [(prefix: String, text: String)] = [
        ("Stiffness", "How hard it is to stretch or squash. Higher means it gives less under the same push. Rubber 0.003 GPa · polycarbonate 2.4 · oak 12 · aluminium 69 · window glass 72 · steel 200. (Young’s modulus)"),
        ("Weight per size", "How heavy a block of it is for its size. Heavier bodies carry more energy at the same speed. Oak 756 kg/m³ · water 1000 · glass 2500 · aluminium 2700 · steel 7850 · copper 8910. (Density)"),
        ("Squish sideways", "How much it bulges out sideways when you squash it. 0 means no bulge; 0.5 means it keeps its volume, like rubber. Carbon fabric 0.10 · glass 0.23 · steel 0.30 · aluminium 0.33 · rubber 0.48. (Poisson ratio)"),
        ("Bends for good at", "The push at which a metal stops springing back and stays bent. Higher means it takes a harder hit before it dents. Soft copper 69 MPa · stainless 200 · steel 250 · aluminium 276 · titanium 890. (Yield strength)"),
        ("Takes after a big bend", "How much stronger a metal gets once it has been bent a lot, the way a bent paper clip gets harder to bend further. Equal to “Bends for good at” means no strengthening. Aluminium goes 276 → 345 MPa by a 12% bend; soft copper 69 → 225. (Strain hardening)"),
        ("Bent for good by", "One row of the strengthening table: how far the metal has been bent for good, in percent. (Plastic strain)"),
        ("Takes (MPa)", "The push the metal needs at that bend. Each row must be at least as high as the row above it. (Flow stress)"),
        ("Breaks at", "The pull at which this springy material snaps. Higher means it survives a harder hit. Glass 41 MPa · oak 51 · epoxy 64 · polycarbonate 65. (Tensile strength)"),
        ("Crack starts at", "How hard the material must be pulled apart before a crack opens. Higher means fewer, later cracks. Glass 41 MPa · aluminium 310 · steel 475 · titanium 938. (Cohesive strength)"),
        ("Crack resistance", "How much energy a crack soaks up as it grows. Low means it shatters, high means it tears slowly. Glass about 7 J/m² · epoxy 150 · aluminium about 11,000 · steel about 89,000. (Fracture energy)"),
        ("Can crack", "Lets this body crack and break into pieces along triangle edges. Cracking is experimental: check that a finer mesh gives about the same result. (Material fracture)"),
        ("Triangle pattern inside", "Cracks can only run along triangle edges. Staggered gives cracks more directions to choose from; Aligned is the normal pattern."),
        ("How it behaves", "Springs back: it always returns to its shape, like glass or rubber. Metal: past “Bends for good at” it stays bent. (Elastic or J2 plasticity)"),
        ("Springs back only", "Ignore permanent bending for this body: it always returns to its shape. Useful for supports that should not dent."),
        ("Sideways speed", "How fast the body moves left or right at the start. Walking is about 1.4 m/s; a phone dropped from 1.5 m lands at about 5.4 m/s; a car at 110 km/h moves about 30 m/s. The top speed here is 150 m/s."),
        ("Up/down speed", "How fast the body moves up or down at the start. A phone dropped from 1.5 m lands at about 5.4 m/s; from 5 m, about 10 m/s. Negative means down."),
        ("Run length", "How much time the calculation covers, in thousandths of a second. Real hits are quick: a metal block hitting at 20 m/s is usually over in well under 1 ms. Longer runs take longer to calculate. (Duration)"),
        ("Assembly mesh", "How finely every body is cut into triangles. Finer is more accurate, especially for cracks and bending, but each halving of the triangle size makes a run about 8 times slower."),
        ("Body mesh", "A mesh setting for this body alone, finer or coarser than the rest of the assembly. Finer is more accurate but slower."),
        ("Set this body's mesh size", "Choose the triangle size for this body directly instead of using the mesh setting."),
        ("Target triangle edge", "The length of one triangle edge. Smaller is more accurate but slower: halving it makes the run about 8 times slower. Aim for at least three triangles across the thinnest part."),
        ("Smooth out shock waves", "Adds a small push-back only while a triangle is being squashed, so the shock wave from a hit stays smooth instead of ringing. It is a calculation aid, not part of the material. (Artificial bulk viscosity)"),
        ("Gentle smoothing", "Calms the ringing just behind a shock wave. The usual value is 0.06; higher damps more but also soaks up more energy. (Linear coefficient b1)"),
        ("Strong smoothing for hard hits", "Spreads a sudden shock over a few triangles. The usual value is 1.2. It only causes trouble when a hit is fast compared with how fast sound moves in the material: about 5 km/s in metals and glass, so it is harmless for real materials up to 150 m/s, but only about 60 m/s in rubber and 30 m/s in the old soft test material. There a hard hit makes it force tiny steps and the run stops. (Quadratic coefficient b2)"),
        ("Gravity", "Pulls every free body down. Earth’s gravity is 9.81 m/s². Leave it off for fast hits, where weight hardly matters in a millisecond."),
        ("Preload", "Stretches (+) or compresses (−) this spring before the run starts, in millimetres."),
        ("Failure extension", "How far this link can stretch before it breaks, in millimetres."),
        ("Wall thickness", "How thick the wall of this hollow body is. Keep at least three triangles across it, or bending and cracks are only a rough picture."),
        ("Rotation", "Turns the body about its centre, in degrees. Positive turns it counter-clockwise."),
        ("Spacing gap", "The gap left between bodies when they are lined up."),
        ("Glued-on second material", "Glues a second material onto this body along a straight line, like a coating or a laminate. (Bonded layer)"),
        ("Glued-on third material", "Adds a third glued-on material, for three-layer sandwiches."),
        ("First glue line", "Where the first glue line sits, as a share of the body’s width from the left."),
        ("Second glue line", "Where the second glue line sits, as a share of the body’s width from the left."),
        ("How the layer behaves", "Whether this glued-on layer springs back or, for a metal, can bend for good."),
        ("V-notch", "Cuts a V-shaped notch into the bottom edge. A notch makes a crack start there, as in a standard bend test."),
    ]

    static func text(for label: String) -> String? {
        entries.first { label.hasPrefix($0.prefix) }?.text
    }
}

/// A small ⓘ that shows a setting's plain explanation when the pointer rests on it.
struct SettingInfoIcon: View {
    let text: String

    init?(for label: String) {
        guard let text = SettingInfo.text(for: label) else { return nil }
        self.text = text
    }

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(text)
            .accessibilityLabel("About this setting")
            .accessibilityHint(text)
    }
}

extension View {
    /// Places the setting's ⓘ after this control, when the label has an explanation.
    func settingInfo(_ label: String) -> some View {
        HStack(spacing: 4) {
            self
            SettingInfoIcon(for: label)
        }
    }
}
