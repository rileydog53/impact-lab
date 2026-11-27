import ImpactPhysics

/// The "Limits and advice" panel (Joseph, 2026-11-26: hard limits and advice read as the same thing).
/// A hard limit is a number the app will not accept; every box also says so when it changes a typed value.
/// Advice never blocks a run; it only warns that a run may be slow or rough.
enum AssemblyLimitsGuide {
    static let hard: [(String, String)] = [
        ("Stiffness", "0.0005 to 1,200 GPa. Diamond, the stiffest real material, is about 1,050 GPa."),
        ("Weight per size", "100 to 25,000 kg/m³. Osmium, the densest metal, is about 22,600."),
        ("Squish sideways", "−0.9 to 0.48. At 0.5 the calculation cannot work; rubber is 0.48."),
        ("Starting speed", "Up to 150 m/s in each direction. A project choice, not a calculation limit: real materials ran cleanly at 150 m/s, but this app does not model heating, which matters above roughly that speed."),
        ("Body size", "0.5 mm to 10 m on each side."),
        ("Run length", "0.1 ms to 2,000 ms."),
        ("Bodies", "Up to \(AssemblyScene.maximumParts) in one experiment."),
        ("Links between bodies", "Up to \(AssemblyScene.maximumConnections)."),
        ("Hollow wall", "5 mm thick up to 40% of the smaller side, so a hollow remains."),
        ("Outline mesh", "About 750,000 triangles per body, set by this Mac's memory."),
    ]

    static let advice: [(String, String)] = [
        ("Small or large bodies", "Below 25 mm ÷ n (on the ×n mesh) the triangles shrink to fit, so the run takes longer. Above 300 mm a body has many triangles. Both still run."),
        ("Many bodies", "More than \(AssemblyScene.advisoryParts) bodies is allowed; every pair is checked for touching, so the run slows."),
        ("Thin parts", "Aim for at least three triangles across the thinnest part, and about eight for bending. Fewer still runs but gives a rough picture."),
        ("Cracking", "Experimental. Run again on a finer mesh; if the result changes a lot, trust neither."),
        ("Soft materials hit fast", "Rubber-soft materials hit faster than about 8 m/s can make the shock smoothing force tiny steps and stop the run. The app warns before you start."),
    ]
}
