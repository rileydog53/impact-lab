import Charts
import ImpactPhysics
import SwiftUI

struct MaterialLibraryStore {
    private let defaults: UserDefaults
    private let key = "custom-metal-profiles-v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> [MaterialProfile] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let profiles = try JSONDecoder().decode([MaterialProfile].self, from: data)
        guard profiles.allSatisfy({ $0.isValid && $0.provenance.isCustom }),
              Set(profiles.map(\.id)).count == profiles.count else { throw StoreError.invalidProfiles }
        return profiles
    }

    func save(_ profile: MaterialProfile) throws {
        guard profile.isValid && profile.provenance.isCustom else { throw StoreError.invalidProfiles }
        var profiles = try load()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        defaults.set(try JSONEncoder().encode(profiles), forKey: key)
    }

    private enum StoreError: LocalizedError {
        case invalidProfiles
        var errorDescription: String? { "The custom profile data is invalid." }
    }
}

enum MaterialTarget: String, Identifiable {
    case body = "Body"
    case second = "Second layer"
    case third = "Third layer"

    var id: Self { self }

    func current(in part: AssemblyPart) -> ImpactPhysics.Material? {
        switch self {
        case .body: part.material
        case .second: part.bondedLayer?.material
        case .third: part.bondedLayer?.third?.material
        }
    }

    func requiresElastic(in part: AssemblyPart) -> Bool { self != .body || part.bondedLayer != nil }

    func apply(_ profile: MaterialProfile, to part: inout AssemblyPart, elasticOnly: Bool) {
        switch self {
        case .body: profile.apply(to: &part, elasticOnly: elasticOnly || requiresElastic(in: part))
        case .second: part.bondedLayer?.material = profile.material
        case .third: part.bondedLayer?.third?.material = profile.material
        }
    }
}

struct MaterialLibrary: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var custom: [MaterialProfile] = []
    @State private var selectedID: String?
    @State private var draft: MaterialProfile?
    @State private var recovered: MaterialProfile?
    @State private var elasticOnly: Bool
    @State private var error: String?
    private let store: MaterialLibraryStore
    let target: MaterialTarget
    let part: AssemblyPart
    let canAssign: Bool
    let assign: (MaterialProfile, Bool) -> Void

    init(target: MaterialTarget, part: AssemblyPart, canAssign: Bool, store: MaterialLibraryStore = .init(),
         assign: @escaping (MaterialProfile, Bool) -> Void) {
        self.target = target
        self.part = part
        self.canAssign = canAssign
        self.store = store
        self.assign = assign
        let current = target.current(in: part)?.provenance
        _selectedID = State(initialValue: current?.id ?? MaterialProfile.structuralSteel.id)
        _elasticOnly = State(initialValue: target.requiresElastic(in: part)
            || (current != nil && part.plasticity.response == .elastic))
    }

    private var profiles: [MaterialProfile] {
        MaterialProfile.references + custom + (recovered.map { [$0] } ?? [])
    }

    private var filtered: [MaterialProfile] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return profiles.filter { profile in
            let text = [profile.name, profile.provenance.family, profile.provenance.condition].joined(separator: " ")
            return terms.allSatisfy { text.localizedStandardContains(String($0)) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Material Library").font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("\(part.name) · \(target.rawValue)").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search materials", text: $query)
                        .accessibilityIdentifier("material-search")
                    List(filtered, selection: $selectedID) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                    if filtered.isEmpty { Text("No matching materials").font(.caption) }
                }.frame(width: 225)
                Divider()
                ScrollView {
                    if let draft {
                        editProfile(draft)
                    } else if let profile = profiles.first(where: { $0.id == selectedID }) {
                        inspect(profile)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(assemblyAmber).font(.caption) }
        }
        .padding(20)
        .frame(width: 800, height: 610)
        .task {
            refresh()
            // The assembly is an independent snapshot of the applied values.
            if target == .body, let table = part.plasticity.table, part.material.provenance != nil {
                let snapshot = MaterialProfile(material: part.material, hardening: table)
                if !profiles.contains(snapshot) {
                    var copy = snapshot.duplicate()
                    copy.material.provenance?.name = String(snapshot.name.prefix(53)) + " (assigned)"
                    recovered = copy
                    selectedID = copy.id
                }
            }
        }
        .onChange(of: selectedID) { _, _ in draft = nil }
    }

    private func refresh() {
        do { custom = try store.load() }
        catch { self.error = error.localizedDescription }
    }

    private func inspect(_ profile: MaterialProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(profile.name).font(.headline)
            Text(profile.provenance.condition).foregroundStyle(.secondary)
            Text("E \(profile.material.young / 1e9, specifier: "%.3g") GPa · ρ \(profile.material.density, specifier: "%.5g") kg/m³ · ν \(profile.material.poisson, specifier: "%.3g")")
            Toggle("Assign as elastic only", isOn: $elasticOnly)
                .disabled(target.requiresElastic(in: part))
            if elasticOnly {
                Text("Plane-strain compressible neo-Hookean elasticity (v1).")
                if target.requiresElastic(in: part) {
                    Text("Bonded regions share nodes and support elastic materials only.").foregroundStyle(.secondary)
                }
            } else {
                Text("Plane-strain Hencky elasticity with rate-independent J2 plasticity (v1).")
                Text("Initial equivalent flow stress \(profile.hardening.points[0].stress / 1e6, specifier: "%.4g") MPa")
                HardeningPreview(table: profile.hardening)
                Text("Reported yield or proof stress is used as the initial flow stress. The solver interpolates linearly and holds stress constant past the final point.")
                    .foregroundStyle(.secondary)
            }
            if profile.provenance.isCustom {
                Text("Custom input. The source describes the parent reference; edits are user-specified.")
                    .foregroundStyle(.secondary)
            }
            Text(profile.provenance.evidence)
            Link(profile.provenance.sourceName, destination: profile.provenance.source)
            Text("Isotropic, room-temperature approximation. Fracture, rate and temperature dependence are unavailable for these profiles.")
                .foregroundStyle(.secondary)
            if target == .body && part.fracture != nil {
                Text("Turn off the body's illustrative fracture model before assigning a metal profile.")
                    .foregroundStyle(assemblyAmber)
            }
            HStack {
                Button("Duplicate and Edit") { draft = profile.duplicate() }
                if custom.contains(where: { $0.id == profile.id }) {
                    Button("Edit Saved Copy") { draft = profile }
                }
                Spacer()
                Button("Assign to \(target.rawValue)") {
                    assign(profile, elasticOnly)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAssign || (target == .body && part.fracture != nil))
            }.padding(.top, 4)
        }
        .font(.callout)
        .padding(.trailing, 8)
    }

    private func editProfile(_ profile: MaterialProfile) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Edit Custom Profile").font(.headline)
            TextField("Profile name", text: Binding(get: { profile.name }, set: { draft?.material.provenance?.name = $0 }))
                .accessibilityIdentifier("material-profile-name")
            Grid(alignment: .leading) {
                GridRow {
                    Text("Young’s modulus (GPa)")
                    number("Young’s modulus (GPa)", profile.material.young / 1e9) { draft?.material.young = $0 * 1e9 }
                }
                GridRow {
                    Text("Density (kg/m³)")
                    number("Density (kg/m³)", profile.material.density) { draft?.material.density = $0 }
                }
                GridRow {
                    Text("Poisson ratio")
                    number("Poisson ratio", profile.material.poisson) { draft?.material.poisson = $0 }
                }
            }
            Text("Flow curve").font(.headline)
            Grid(alignment: .leading) {
                GridRow {
                    Text("Plastic strain (%)")
                    Text("Flow stress (MPa)")
                    Color.clear.frame(width: 20, height: 1)
                }
                ForEach(profile.hardening.points.indices, id: \.self) { index in
                    let point = profile.hardening.points[index]
                    GridRow {
                        number("Point \(index + 1) plastic strain (%)", 100 * point.strain) { value in
                            guard draft?.hardening.points.indices.contains(index) == true else { return }
                            draft?.hardening.points[index].strain = value / 100
                        }.disabled(index == 0)
                        number("Point \(index + 1) flow stress (MPa)", point.stress / 1e6) { value in
                            guard draft?.hardening.points.indices.contains(index) == true else { return }
                            draft?.hardening.points[index].stress = value * 1e6
                        }
                        Button("Remove point", systemImage: "minus.circle") {
                            draft?.hardening.points.remove(at: index)
                        }.labelStyle(.iconOnly).disabled(index == 0 || profile.hardening.points.count <= 2)
                    }
                }
            }
            Button("Add Point", systemImage: "plus") {
                if let last = profile.hardening.points.last {
                    draft?.hardening.points.append(.init(strain: min(1, last.strain + 0.01), stress: last.stress))
                }
            }.disabled(profile.hardening.points.count >= 32 || (profile.hardening.points.last?.strain ?? 0) > 0.999999)
            Text("Start at zero plastic strain. Use increasing strains up to 100% and positive, nondecreasing stresses.")
                .foregroundStyle(.secondary)
            if !profile.isValid {
                Text("Enter a name and valid material values. E 0.0005–400 GPa, density 100–25,000 kg/m³, ν −0.9–0.48, flow stress > 0 to 20,000 MPa.")
                    .foregroundStyle(assemblyAmber)
            }
            HStack {
                Button("Cancel Edit") { draft = nil }
                Spacer()
                Button("Save Profile") {
                    do {
                        try store.save(profile)
                        refresh()
                        query = ""
                        selectedID = profile.id
                        draft = nil
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!profile.isValid)
            }
        }.font(.callout).padding(.trailing, 8)
    }

    private func number(_ label: String, _ value: Double, set: @escaping (Double) -> Void) -> some View {
        TextField(label, value: Binding(get: { value }, set: { newValue in set(newValue) }), format: .number.precision(.significantDigits(1...9)))
            .labelsHidden().frame(width: 110)
    }
}

struct HardeningPreview: View {
    let table: HardeningTable

    var body: some View {
        Chart(Array(table.points.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Plastic strain (%)", 100 * point.strain),
                     y: .value("Flow stress (MPa)", point.stress / 1e6))
            PointMark(x: .value("Plastic strain (%)", 100 * point.strain),
                      y: .value("Flow stress (MPa)", point.stress / 1e6))
                .accessibilityLabel("Plastic strain \(100 * point.strain, specifier: "%.3g") percent")
                .accessibilityValue("\(point.stress / 1e6, specifier: "%.4g") MPa")
        }
        .chartXAxisLabel("Equivalent plastic strain (%)")
        .chartYAxisLabel("Kirchhoff flow stress (MPa)")
        .frame(height: 155)
        .accessibilityLabel("Solver hardening table")
    }
}
