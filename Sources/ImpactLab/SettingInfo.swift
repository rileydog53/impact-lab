import SwiftUI

/// The ⓘ hover text for each setting the user can change (Joseph, 2026-11-26): what it does, what raising or
/// lowering it changes, and an everyday comparison. Every comparison number is a value from the app's own
/// Material Library (sources in docs/library-materials.md), worked out from those values, plain arithmetic
/// (fall speed √(2gh), sound speed √(E/ρ)) or an everyday fact (water 1000 kg/m³, Earth's gravity).
/// Plain words first, the technical name after.
enum SettingInfo {
    /// Matched against the start of a setting's label, so one entry covers every place the setting appears.
    private static let entries: [(prefix: String, text: String)] = [
        ("Stiffness", "How hard it is to stretch or squash. Higher means it gives less under the same push. Rubber 0.003 GPa · polycarbonate 2.4 · oak 12 · aluminium 69 · window glass 72 · steel 200 · diamond, the stiffest real material, about 1,050. The box accepts 0.0005 to 1,200 GPa. (Young’s modulus)"),
        ("Weight per size", "How heavy a block of it is for its size. Heavier bodies carry more energy at the same speed. Oak 756 kg/m³ · water 1000 · glass 2500 · aluminium 2700 · steel 7850 · copper 8910. (Density)"),
        ("Squish sideways", "Squeeze a rubber eraser between your fingers and it bulges out at the sides; squeeze cork and it hardly bulges. This number is that bulge: how much the material gets wider for each bit it is squashed shorter. 0 means no bulge (cork). 0.5 would mean its volume never changes (rubber is 0.48, the highest the app allows). Most metals are about 0.3. Carbon fabric 0.10 · glass 0.23 · steel 0.30 · aluminium 0.33 · rubber 0.48. A few specially made foams get thinner when squashed; the box accepts down to −0.9 for them. (Poisson ratio)"),
        ("Bends for good at", "Bend a paper clip a little and it springs back; bend it further and it stays bent. This is the push, per square millimetre of material, where springing back stops and the metal stays bent (dents). Higher means it takes a harder hit before it dents. 1 MPa is about 1 kg resting on a square millimetre. Soft copper 69 MPa · stainless 200 · steel 250 · aluminium 276 · titanium 890. (Yield strength)"),
        ("Takes after a big bend", "A bent paper clip is harder to bend further at the same spot: metal gets stronger as it is bent. This is the push the metal needs once it has already been stretched 12% for good (a 10 cm bar now 11.2 cm). Equal to “Bends for good at” means it never gets stronger; much higher means it strengthens a lot, like soft copper. Aluminium goes 276 → 345 MPa; soft copper 69 → 225. (Strain hardening)"),
        ("Bent for good by", "One row of the strengthening table: how far the metal has been bent for good, in percent. (Plastic strain)"),
        ("Takes (MPa)", "The push the metal needs at that bend. Each row must be at least as high as the row above it. (Flow stress)"),
        ("Breaks at", "The pull at which this springy material snaps. Higher means it survives a harder hit. Glass 41 MPa · oak 51 · epoxy 64 · polycarbonate 65. (Tensile strength)"),
        ("Crack starts at", "The pull, per square millimetre, that starts tearing the material apart along a triangle edge. Below it nothing cracks, however long you wait; above it a crack begins. Higher means fewer, later cracks. Metals usually bend for good long before reaching it. Glass 41 MPa · aluminium 310 · steel 475 · titanium 938. (Cohesive strength)"),
        ("Crack resistance", "Once a crack has started, how much energy it takes to open it all the way, per square metre of new crack surface. Low: the crack runs through on its own and the piece shatters, like glass. High: the crack only grows while you keep pulling hard, so it tears slowly, like metal. Glass about 7 J/m² · epoxy 150 · aluminium about 11,000 · steel about 89,000. (Fracture energy)"),
        ("Can crack", "Lets this material itself crack and break into pieces along triangle edges. This is cracking inside the material; a glue line letting go between layers is set separately. Cracking is experimental: check that a finer mesh gives about the same result. (Material fracture)"),
        ("Triangle pattern inside", "Cracks can only run along triangle edges. Staggered gives cracks more directions to choose from; Aligned is the normal pattern."),
        ("How it behaves", "Springs back: it always returns to its shape, like glass or rubber. Metal: past “Bends for good at” it stays bent. (Elastic or J2 plasticity)"),
        ("Springs back only", "Ignore permanent bending for this body: it always returns to its shape. Useful for supports that should not dent."),
        ("Sideways speed", "How fast the body moves left or right at the start. Walking is about 1.4 m/s; a phone dropped from 1.5 m lands at about 5.4 m/s; a car at 110 km/h moves about 30 m/s. The top speed, 150 m/s, is a project choice, not a calculation limit: real materials ran cleanly at 150 m/s in the speed tests. Above roughly that speed metals heat up and soften during the hit, and this app does not include heating, so the results would look confident but be wrong."),
        ("Up/down speed", "How fast the body moves up or down at the start. A phone dropped from 1.5 m lands at about 5.4 m/s; from 5 m, about 10 m/s. Negative means down. The 150 m/s top speed is a project choice (no heating in this app), not a calculation limit."),
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
        ("Glued-on second material", "Glues a second material onto this body along a straight line, like a coating or a laminate. The glue line and the materials can fail in different ways: the glue can let go (the layers peel apart), or a material itself can crack. Each has its own settings. (Bonded layer)"),
        ("Glue between", "Lets this glue line let go. When it fails the two layers peel apart along the line, but neither material cracks: that is set separately under each material's “Can crack”. “Glue lets go at” is how hard the glue must be pulled to start letting go; “Glue peel resistance” is how much energy it takes to peel all the way. (Interface or delamination failure)"),
        ("Glue lets go at", "How hard the glue line must be pulled, per square millimetre, before it starts to let go. Below it the layers stay stuck; above it they start to peel apart. This is the glue, not either material: a material cracking inside itself is set under its own “Can crack”. For scale, solid epoxy (the Library's hard glue) cracks at about 64 MPa; a glue line is usually weaker than the solid glue. (Interface cohesive strength)"),
        ("Glue peel resistance", "Once the glue has started to let go, how much energy it takes to peel the layers fully apart, per square metre of glue. Low: the layers spring apart in one go. High: they peel slowly and only while pulled hard. For scale, solid epoxy takes about 150 J/m²; glass about 7. (Interface fracture energy)"),
        ("Second layer itself", "Lets the second material crack inside itself, separately from the glue letting go. Its own “Crack starts at” and “Crack resistance” apply. (Layer material fracture)"),
        ("Third layer itself", "Lets the third material crack inside itself, separately from the glue letting go. Its own “Crack starts at” and “Crack resistance” apply. (Layer material fracture)"),
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

/// A small ⓘ for a setting: click it to open the explanation, or rest the pointer on it for the same text as a
/// tooltip (Joseph, 2026-11-26: hover alone did nothing he could see).
struct SettingInfoIcon: View {
    let text: String
    @State private var showing = false

    init?(for label: String) {
        guard let text = SettingInfo.text(for: label) else { return nil }
        self.text = text
    }

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(text)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
                .padding(12)
        }
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
