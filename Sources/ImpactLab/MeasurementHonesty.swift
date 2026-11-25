import SwiftUI

/// Plain statements of what each displayed quantity is and how far it has been checked.
/// Display only: nothing here feeds the solver.
///
/// Evidence tags follow the project rule: "verified" means a numerical check in the CI suite
/// compares it with theory or with an independent sum (numerical verification, not experimental
/// validation); "agent-reported" means it is computed but rests on inputs or checks that have only
/// been reported, not independently confirmed; "hypothesis" means an untested expectation.
enum EvidenceTag: String {
    case verified = "verified"
    case agentReported = "agent-reported"
    case hypothesis = "hypothesis"
}

enum MeasurementHonesty {
    static let storedHardening =
        "Stored hardening: the hardening-table energy the J2 model holds above initial yield. A model convention, not measured stored energy of cold work."
    static let modelledPlasticDissipation =
        "Modelled plastic dissipation: initial yield × accumulated plastic strain. Not heat; no temperature is computed and no heat fraction is applied."
    static let noTemperature = "No temperatures are shown: the solver has no thermal model."

    static let energyTag = EvidenceTag.verified
    static let fractureTag = EvidenceTag.agentReported

    /// Footnote under an energy readout: labels, limitations and evidence tags in one place.
    static var energyFootnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Calculated · energy ledger \(energyTag.rawValue) (numerical balance checks, not experimental validation) · fracture \(fractureTag.rawValue) (toughness values are experimental)")
            Text(storedHardening)
            Text(modelledPlasticDissipation)
        }
        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
