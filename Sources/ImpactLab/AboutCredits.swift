import SwiftUI

/// Which build this is, so a test report can name it (Joseph, 2026-11-26: he needs a build ID he can see inside
/// the app). The bundle step writes "<date> <commit>" into CFBundleVersion; a plain `swift run` has none.
enum BuildInfo {
    static var label: String {
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        guard let version, !version.isEmpty, version != "1" else { return "development build" }
        return version
    }
}

/// Credits and licences, kept out of the experiment controls (Joseph, 2026-11-26: attribution was more prominent
/// than explanations of the controls). Opened from Help > Credits and Licences.
struct CreditsView: View {
    private let credits: [(String, String)] = [
        ("Clipper2 (polygon Cut and Join)",
         "By Angus Johnson, release 2.0.1, used unmodified under the Boost Software License 1.0. Used only by Cut and Join in the geometry editor, not by the mesher or the calculation."),
        ("Quality triangle mesher (outline bodies)",
         "Written for Impact Lab from the published methods: J. Ruppert, “A Delaunay Refinement Algorithm for Quality 2-Dimensional Mesh Generation”, Journal of Algorithms 18 (1995); J. R. Shewchuk, “Delaunay Refinement Algorithms for Triangular Mesh Generation”, Computational Geometry 22 (2002); Bowyer (1981) and Watson (1981) point insertion. No code copied from another mesher."),
        ("Shock smoothing usual values",
         "The usual values 0.06 (gentle) and 1.2 (strong) for artificial bulk viscosity are the defaults documented in the Abaqus/Explicit manual (Dassault Systèmes)."),
        ("Material values",
         "Each Material Library entry names its own source (for example MatWeb, the Copper Development Association, Outokumpu, Pilkington, AGC and ACP Composites data sheets) with a link, shown when you pick the material."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Impact Lab").font(.title2.weight(.semibold))
                Text("Matter in slow motion").foregroundStyle(.secondary)
                Text("Build \(BuildInfo.label)").font(.callout.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("build-id")
                Divider()
                Text("Credits and licences").font(.headline)
                ForEach(credits, id: \.0) { name, text in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).fontWeight(.medium)
                        Text(text).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 520)
    }
}

/// Help menu and About item.
struct ImpactLabCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Impact Lab") { openWindow(id: "credits") }
        }
        CommandGroup(replacing: .help) {
            Button("Credits and Licences") { openWindow(id: "credits") }
        }
    }
}
