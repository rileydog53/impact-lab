import ImpactPhysics
import SwiftUI

struct AssemblyEditor: View {
    let experiment: AssemblyExperiment
    @State private var bodySettings = true
    @State private var materialSettings = false
    @State private var connectionList = false
    @State private var meshSettings = false
    @State private var simulationSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Inspector").font(.headline)
                    Spacer()
                    Button("Undo", systemImage: "arrow.uturn.backward") { experiment.undo() }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(!experiment.canEdit || experiment.undoAction == nil)
                        .help(experiment.undoAction.map { "Undo \($0)" } ?? "Undo the last assembly edit")
                    Button("Redo", systemImage: "arrow.uturn.forward") { experiment.redo() }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .disabled(!experiment.canEdit || experiment.redoAction == nil)
                        .help(experiment.redoAction.map { "Redo \($0)" } ?? "Redo the last undone assembly edit")
                }
                .controlSize(.small)
                if !experiment.canEdit {
                    Text("Reset Run to edit the starting assembly.")
                        .font(.caption).foregroundStyle(assemblyAmber)
                }
                HStack {
                    Text("Components").font(.headline)
                    Spacer()
                    Menu("Add body", systemImage: "plus") {
                        ForEach(AssemblyPart.Shape.allCases, id: \.self) { shape in
                            Button(shape.rawValue) { experiment.add(shape) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!experiment.canEdit || experiment.scene.parts.count >= AssemblyScene.maximumParts)
                    .help("Add a deformable block or hollow enclosure (up to \(AssemblyScene.maximumParts) bodies)")
                }
                ForEach(Array(experiment.scene.parts.enumerated()), id: \.element.id) { index, part in
                    row(part.name, icon: part.shape == .enclosure ? "square.dashed" : "square.fill",
                        color: assemblyColor(index), selected: experiment.selectedPart == part.id) {
                        experiment.select(part.id)
                    }
                }
                if experiment.scene.parts.isEmpty {
                    Text("Add a body to the empty scene. Drag bodies in the workspace or enter exact positions below.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                HStack(alignment: .top) {
                    DisclosureGroup("Connections (\(experiment.scene.connections.count))", isExpanded: $connectionList) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(experiment.scene.connections) { link in
                                row("\(name(link.first)) → \(name(link.second))",
                                    icon: link.kind == .spring ? "waveform.path" : "link",
                                    color: link.kind == .spring ? assemblyInk : assemblyMint,
                                    selected: experiment.selectedConnection == link.id) {
                                    experiment.selectConnection(link.id)
                                }
                            }
                            if experiment.scene.connections.isEmpty {
                                Text("No links between bodies.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Menu("Add link", systemImage: "link.badge.plus") {
                        if let first = experiment.scene.parts.first(where: { $0.id == experiment.selectedPart })
                            ?? experiment.scene.parts.first {
                            Section("From \(first.name)") {
                                ForEach(experiment.scene.parts.filter { $0.id != first.id }) { next in
                                    Button("To \(next.name)") {
                                        experiment.addConnection(first: first.id, second: next.id)
                                        connectionList = true
                                    }
                                }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!experiment.canEdit || experiment.scene.parts.count < 2
                              || experiment.scene.connections.count >= AssemblyScene.maximumConnections)
                    .help("Connect two bodies with a spring or a breakable link")
                }
                Divider()
                if let index = experiment.selectedIndex {
                    let part = experiment.previewPart ?? experiment.scene.parts[index]
                    bodyInspector(part).id(part.id)
                } else if let link = experiment.scene.connections.first(where: { $0.id == experiment.selectedConnection }) {
                    connectionInspector(link)
                } else if !experiment.scene.parts.isEmpty {
                    Text("Select a body or connection to edit it.").font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                runSettings
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
        }
        .background(assemblyPanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func name(_ id: UUID) -> String {
        experiment.scene.parts.first { $0.id == id }?.name ?? "Body"
    }

    private func row(_ title: String, icon: String, color: Color, selected: Bool,
                     select: @escaping () -> Void) -> some View {
        Button(action: select) {
            Label {
                Text(title).lineLimit(1).foregroundStyle(assemblyInk)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(selected ? color.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func bodyInspector(_ part: AssemblyPart) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(part.name).font(.headline).lineLimit(1)
                Spacer()
                Button("Remove body", systemImage: "trash") {
                    experiment.edit("Remove Body") { $0.removePart(part.id) }
                }
                .labelStyle(.iconOnly)
                .disabled(!experiment.canEdit)
                .help("Remove this body and its connections")
            }
            Text("\(part.shape.rawValue) · \(materialDescription(part))")
                .font(.caption).foregroundStyle(.secondary)
            AssemblyBodyName(part: part, experiment: experiment)
            DisclosureGroup("Geometry", isExpanded: $bodySettings) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
                    GridRow {
                        bodyNumber("Center X (mm)", part, \.center.x, -1...1, scale: 1000)
                        bodyNumber("Center Y (mm)", part, \.center.y, -1...1, scale: 1000)
                    }
                    GridRow {
                        bodyNumber("Local width (mm)", part, \.size.x, 0.025...0.30, scale: 1000)
                        bodyNumber("Local height (mm)", part, \.size.y, 0.025...0.30, scale: 1000)
                    }
                    GridRow {
                        bodyNumber("Rotation (°)", part, \.angle, -360...360)
                            .help("Counterclockwise angle from the assembly X axis")
                        if part.shape == .enclosure {
                            bodyNumber("Wall thickness (mm)", part, \.wall, 0.005...0.4 * min(part.size.x, part.size.y), scale: 1000)
                        }
                    }
                }.padding(.top, 5)
                if part.shape == .block && part.bondedLayer == nil {
                    notchEditor(part).disabled(!experiment.canEdit)
                }
            }
            Text("Initial motion").font(.subheadline.weight(.semibold)).padding(.top, 4)
            HStack(spacing: 6) {
                bodyNumber("X velocity (m/s)", part, \.velocity.x, -1.5...1.5)
                bodyNumber("Y velocity (m/s)", part, \.velocity.y, -1.5...1.5)
            }
            let links = experiment.scene.connections.filter { $0.first == part.id || $0.second == part.id }
            Text(links.isEmpty ? "Constraints · Free body" : "Constraints · \(links.count) body-to-body \(links.count == 1 ? "link" : "links")")
                .font(.caption).foregroundStyle(.secondary)
                .help("Assembly bodies can translate and rotate. Links transfer load between the connected bodies.")
            DisclosureGroup("Mesh", isExpanded: $meshSettings) {
                Picker("Body mesh", selection: Binding(get: { part.refinement }, set: { level in
                    experiment.updatePart(part.id) { $0.refinement = level }
                })) {
                    Text("Use assembly mesh").tag(nil as AssemblyScene.Resolution?)
                    ForEach(AssemblyScene.Resolution.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                    .disabled(!experiment.canEdit)
                    .help("Override the triangle size for this body")
            }
            DisclosureGroup("Material", isExpanded: $materialSettings) {
                VStack(alignment: .leading, spacing: 7) {
                    profiles("Apply illustrative profile", elasticOnly: part.bondedLayer != nil) { profile in
                        experiment.updatePart(part.id, action: "Apply Material") { profile.apply(to: &$0) }
                    }.disabled(!experiment.canEdit)
                    Text("Profiles use illustrative numerical values.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Response", selection: Binding(get: { part.plasticity.response },
                                                          set: { response in experiment.updatePart(part.id) { $0.plasticity.response = response } })) {
                        ForEach(CouponResponse.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .disabled(!experiment.canEdit || part.bondedLayer != nil)
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
                        GridRow {
                            bodyNumber("Young’s modulus (MPa)", part, \.material.young, SceneConfiguration.youngRange, scale: 1e-6)
                                .help("Elastic stiffness in uniaxial loading")
                            bodyNumber("Density (kg/m³)", part, \.material.density, SceneConfiguration.densityRange)
                        }
                        GridRow {
                            bodyNumber("Poisson ratio", part, \.material.poisson, SceneConfiguration.poissonRange)
                                .help("Transverse contraction relative to axial extension in uniaxial loading")
                        }
                        if part.plasticity.response == .elastoplastic {
                            GridRow {
                                bodyNumber("Yield / E (%)", part, \.plasticity.yieldFraction, ImpactPlasticity.yieldRange, scale: 100)
                                bodyNumber("Hardening / E (%)", part, \.plasticity.hardeningFraction, ImpactPlasticity.hardeningRange, scale: 100)
                            }
                        }
                    }
                    if part.bondedLayer == nil {
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle("Material fracture", isOn: Binding(get: { part.fracture != nil }, set: { enabled in
                                experiment.updatePart(part.id) { $0.fracture = enabled ? MaterialFractureSettings() : nil }
                            })).toggleStyle(.checkbox)
                            if let fracture = part.fracture {
                                HStack {
                                    numeric("Strength / E (%)", value: fracture.strengthFraction,
                                            range: MaterialFractureSettings.strengthRange, scale: 100) { value in
                                        experiment.updatePart(part.id) { $0.fracture?.strengthFraction = value }
                                    }
                                    numeric("Fracture energy (J/m²)", value: fracture.energy,
                                            range: MaterialFractureSettings.energyRange, scale: 1) { value in
                                        experiment.updatePart(part.id) { $0.fracture?.energy = value }
                                    }
                                }
                                if part.shape == .block {
                                    Picker("Interior mesh", selection: Binding(get: { fracture.pattern }, set: { pattern in
                                        experiment.updatePart(part.id) { $0.fracture?.meshPattern = pattern }
                                    })) {
                                        ForEach(MaterialFractureSettings.MeshPattern.allCases, id: \.self) {
                                            Text($0.rawValue).tag($0)
                                        }
                                    }
                                }
                                let resolution = part.refinement ?? experiment.scene.resolution
                                Text(resolution.rawValue <= 3
                                     ? "Coarse fracture preview. Crack paths and fragment motion are qualitative."
                                     : "Experimental fracture. Check mesh and timestep sensitivity before using the readings quantitatively.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(!experiment.canEdit)
                    } else {
                        Text("Bonded layers require elastic material and use permanent bonds.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if part.shape == .block { bondedLayerEditor(part).disabled(!experiment.canEdit) }
                }.padding(.top, 7)
            }
            gaugeEditor(part)
        }
    }

    private func materialDescription(_ part: AssemblyPart) -> String {
        if let layer = part.bondedLayer {
            return layer.third == nil ? "Two bonded elastic layers" : "Three bonded elastic layers"
        }
        if let profile = AssemblyMaterialProfile.allCases.first(where: {
            $0.response == part.plasticity.response && $0.material == part.material
        }) {
            return profile.rawValue
        }
        return part.plasticity.response.rawValue
    }

    private func notchEditor(_ part: AssemblyPart) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("V-notch on local bottom edge", isOn: Binding(get: { part.notch != nil }, set: { enabled in
                experiment.updatePart(part.id) { $0.notch = enabled ? AssemblyPart.Notch() : nil }
            })).toggleStyle(.checkbox)
            if let notch = part.notch {
                HStack {
                    numeric("Offset (% width)", value: notch.centerFraction, range: -0.30...0.30, scale: 100) { value in
                        experiment.updatePart(part.id) { $0.notch?.centerFraction = value }
                    }
                    numeric("Width (%)", value: notch.widthFraction, range: 0.12...0.36, scale: 100) { value in
                        experiment.updatePart(part.id) { $0.notch?.widthFraction = value }
                    }
                    numeric("Depth (%)", value: notch.depthFraction, range: 0.02...0.45, scale: 100) { value in
                        experiment.updatePart(part.id) { $0.notch?.depthFraction = value }
                    }
                }
            }
        }
    }

    private func bondedLayerEditor(_ part: AssemblyPart) -> some View {
        let minimum = AssemblyPart.BondedLayer.minimumFraction
        return VStack(alignment: .leading, spacing: 7) {
            Toggle("Bonded second material", isOn: Binding(get: { part.bondedLayer != nil }, set: { enabled in
                experiment.updatePart(part.id) { $0.bondedLayer = enabled ? AssemblyPart.BondedLayer() : nil }
            }))
            .toggleStyle(.checkbox)
            .disabled(part.notch != nil || part.fracture != nil || part.plasticity.response != .elastic)
            .help("Available on unnotched elastic blocks with material fracture off")
            if let layer = part.bondedLayer {
                Text("Elastic layers share nodes at permanent bonds. Layer positions are measured along the local width.")
                    .font(.caption).foregroundStyle(.secondary)
                let firstUpperBound = layer.third.map { $0.interfaceFraction - minimum } ?? 1 - minimum
                numeric("First bond from left (% width)", value: layer.interfaceFraction,
                        range: minimum...max(minimum, firstUpperBound), scale: 100) { value in
                    experiment.updatePart(part.id) { $0.bondedLayer?.interfaceFraction = value }
                }
                layerMaterial("Second layer", layer.material) { material in
                    experiment.updatePart(part.id) { $0.bondedLayer?.material = material }
                }
                Toggle("Bonded third material", isOn: Binding(get: { layer.third != nil }, set: { enabled in
                    experiment.updatePart(part.id) {
                        let fraction = min(1 - minimum, max(0.75, layer.interfaceFraction + minimum))
                        $0.bondedLayer?.third = enabled ? .init(interfaceFraction: fraction) : nil
                    }
                })).toggleStyle(.checkbox)
                    .disabled(layer.third == nil && layer.interfaceFraction > 1 - 2 * minimum)
                if let third = layer.third {
                    numeric("Second bond from left (% width)", value: third.interfaceFraction,
                            range: min(1 - minimum, layer.interfaceFraction + minimum)...(1 - minimum), scale: 100) { value in
                        experiment.updatePart(part.id) { $0.bondedLayer?.third?.interfaceFraction = value }
                    }
                    layerMaterial("Third layer", third.material) { material in
                        experiment.updatePart(part.id) { $0.bondedLayer?.third?.material = material }
                    }
                }
            }
        }.padding(.vertical, 4)
    }

    private func profiles(_ title: String, elasticOnly: Bool, choose: @escaping (AssemblyMaterialProfile) -> Void) -> some View {
        Menu(title) {
            ForEach(AssemblyMaterialProfile.allCases.filter { !elasticOnly || $0.response == .elastic }, id: \.self) { profile in
                Button(profile.rawValue) { choose(profile) }
            }
        }
    }

    private func layerMaterial(_ title: String, _ material: ImpactPhysics.Material,
                               set: @escaping (ImpactPhysics.Material) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            profiles("\(title) illustrative profiles", elasticOnly: true) { set($0.material) }
            HStack {
                numeric("E (MPa)", value: material.young, range: SceneConfiguration.youngRange, scale: 1e-6) { value in
                    var next = material
                    next.young = value
                    set(next)
                }
                numeric("Density (kg/m³)", value: material.density, range: SceneConfiguration.densityRange, scale: 1) { value in
                    var next = material
                    next.density = value
                    set(next)
                }
                numeric("Poisson ratio", value: material.poisson, range: SceneConfiguration.poissonRange, scale: 1) { value in
                    var next = material
                    next.poisson = value
                    set(next)
                }
            }
        }
    }

    private func gaugeEditor(_ part: AssemblyPart) -> some View {
        ForEach(experiment.gauges.filter { $0.body == part.id }) { gauge in
            if let index = experiment.gauges.firstIndex(where: { $0.id == gauge.id }) {
                let value = experiment.simulation.gaugeReading(index)
                let fractions = gauge.usesBodyFractions == true
                let unit = fractions ? "% half-size" : "mm"
                let scale = fractions ? 100.0 : 1000.0
                DisclosureGroup {
                    HStack {
                        numeric("Local X (\(unit))", value: gauge.location.x,
                                range: fractions ? -1...1 : -part.size.x/2...part.size.x/2, scale: scale) { x in
                            experiment.updateGauge(gauge.id) { $0.location.x = x }
                        }
                        numeric("Local Y (\(unit))", value: gauge.location.y,
                                range: fractions ? -1...1 : -part.size.y/2...part.size.y/2, scale: scale) { y in
                            experiment.updateGauge(gauge.id) { $0.location.y = y }
                        }
                        Button("Remove gauge", systemImage: "trash") {
                            experiment.edit("Remove Gauge") { $0.gauges?.removeAll { $0.id == gauge.id } }
                        }.labelStyle(.iconOnly).disabled(!experiment.canEdit)
                    }
                    Text("Pressure \(value.pressure / 1000, specifier: "%+.3f") kPa · Strain \(100 * value.strain, specifier: "%+.3f")%")
                        .font(.caption.monospacedDigit())
                } label: {
                    Label(gauge.name, systemImage: "scope")
                }
            }
        }
    }

    private func connectionInspector(_ link: AssemblyConnection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Connection properties").font(.headline)
                Spacer()
                Button("Remove connection", systemImage: "trash") {
                    experiment.edit("Remove Connection") { $0.connections.removeAll { $0.id == link.id } }
                }.labelStyle(.iconOnly).disabled(!experiment.canEdit)
            }
            Picker("Type", selection: Binding(get: { link.kind }, set: { kind in
                experiment.updateConnection(link.id) { $0.kind = kind }
            })) {
                ForEach(AssemblyConnection.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.disabled(!experiment.canEdit)
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
                GridRow {
                    linkNumber("Stiffness (kN/m²)", link, \.stiffness, 500...250_000, scale: 0.001)
                    if link.kind == .cohesive {
                        linkNumber("Failure extension (mm)", link, \.criticalExtension, 0.0005...0.04, scale: 1000)
                    }
                }
                GridRow {
                    linkNumber("First local X (%)", link, \.firstAnchor.x, -1...1, scale: 100)
                    linkNumber("First local Y (%)", link, \.firstAnchor.y, -1...1, scale: 100)
                }
                GridRow {
                    linkNumber("Second local X (%)", link, \.secondAnchor.x, -1...1, scale: 100)
                    linkNumber("Second local Y (%)", link, \.secondAnchor.y, -1...1, scale: 100)
                }
                GridRow {
                    linkNumber("Link band height (%)", link, \.span, 0...1.9, scale: 50)
                }
            }
            if let index = experiment.scene.connections.firstIndex(where: { $0.id == link.id }) {
                let readings = experiment.simulation.linkReadings.filter { $0.connection == index }
                let maxLoad = readings.map { abs($0.force) }.max() ?? 0
                let stored = readings.reduce(0) { $0 + $1.storedEnergy }
                let lost = readings.reduce(0) { $0 + $1.fractureDissipation }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max link load \(maxLoad, specifier: "%.2f") N/m")
                    Text("Stored \(stored, specifier: "%.3f") J/m  ·  Fracture \(lost, specifier: "%.3f") J/m")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(assemblyMint)
            }
            Text("Anchors follow the body’s local axes. An anchor in a cavity snaps to the nearest wall. A nonzero band height spreads stiffness across five links.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var runSettings: some View {
        DisclosureGroup("Simulation settings", isExpanded: $simulationSettings) {
            VStack(alignment: .leading, spacing: 9) {
                Picker("Assembly mesh", selection: Binding(get: { experiment.scene.resolution }, set: { resolution in
                    experiment.edit { $0.meshResolution = resolution }
                })) {
                    ForEach(AssemblyScene.Resolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }.disabled(!experiment.canEdit)
                Text("\(experiment.elementCount) triangles · \(experiment.simulation.dt * 1e6, specifier: "%.2f") µs step")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                numeric("Duration (ms)", value: experiment.scene.duration, range: 0.02...0.25, scale: 1000) { value in
                    experiment.edit { $0.duration = value }
                }
                if !experiment.scene.parts.isEmpty {
                    Picker("Track body", selection: Binding(get: { experiment.scene.monitor ?? experiment.scene.parts.first?.id }, set: { id in
                        experiment.edit {
                            $0.monitor = id
                            if $0.relativeTo == id { $0.relativeTo = nil }
                        }
                    })) {
                        ForEach(experiment.scene.parts) { Text($0.name).tag(Optional($0.id)) }
                    }.disabled(!experiment.canEdit)
                    Picker("Relative to", selection: Binding(get: { experiment.scene.relativeTo }, set: { id in
                        experiment.edit { $0.relativeTo = id }
                    })) {
                        Text("Lab frame").tag(nil as UUID?)
                        ForEach(experiment.scene.parts.filter {
                            $0.id != (experiment.scene.monitor ?? experiment.scene.parts.first?.id)
                        }) { Text($0.name).tag(Optional($0.id)) }
                    }.disabled(!experiment.canEdit)
                }
            }.padding(.top, 5)
        }
    }

    private func bodyNumber(_ label: String, _ part: AssemblyPart, _ key: WritableKeyPath<AssemblyPart, Double>,
                            _ range: ClosedRange<Double>, scale: Double = 1) -> some View {
        numeric(label, value: part[keyPath: key], range: range, scale: scale) { value in
            experiment.updatePart(part.id) { $0[keyPath: key] = value }
        }
    }

    private func linkNumber(_ label: String, _ link: AssemblyConnection, _ key: WritableKeyPath<AssemblyConnection, Double>,
                            _ range: ClosedRange<Double>, scale: Double) -> some View {
        numeric(label, value: link[keyPath: key], range: range, scale: scale) { value in
            experiment.updateConnection(link.id) { $0[keyPath: key] = value }
        }
    }

    private func numeric(_ label: String, value: Double, range: ClosedRange<Double>, scale: Double,
                         set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: Binding(get: { value * scale }, set: { newValue in
                if newValue.isFinite { set(min(range.upperBound, max(range.lowerBound, newValue / scale))) }
            }), format: .number.precision(.fractionLength(0...3)))
            .labelsHidden().textFieldStyle(.roundedBorder).monospacedDigit()
            .disabled(!experiment.canEdit)
            .help("Allowed range \((range.lowerBound * scale).formatted()) to \((range.upperBound * scale).formatted()). Press Return to apply.")
        }
    }
}

private struct AssemblyBodyName: View {
    let part: AssemblyPart
    let experiment: AssemblyExperiment
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Body name", text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .disabled(!experiment.canEdit)
            .help("Press Return to rename the body")
            .onAppear { draft = part.name }
            .onChange(of: part.name) { draft = part.name }
            .onChange(of: focused) { if !focused { commit() } }
            .onSubmit { commit() }
    }

    private func commit() {
        guard experiment.canEdit else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? part.name : String(trimmed.prefix(48))
        draft = name
        experiment.updatePart(part.id, action: "Rename Body") { $0.name = name }
    }
}
