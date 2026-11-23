import ImpactPhysics
import SwiftUI

struct AssemblyEditor: View {
    let experiment: AssemblyExperiment
    @State private var bodySettings = true
    @State private var materialSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
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
                    .disabled(experiment.scene.parts.count >= AssemblyScene.maximumParts)
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

                Divider()
                HStack {
                    Text("Connections").font(.headline)
                    Spacer()
                    Menu("Add link", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        if let first = experiment.scene.parts.first(where: { $0.id == experiment.selectedPart })
                            ?? experiment.scene.parts.first {
                            Section("From \(first.name)") {
                                ForEach(experiment.scene.parts.filter { $0.id != first.id }) { next in
                                    Button("To \(next.name)") { experiment.addConnection(first: first.id, second: next.id) }
                                }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(experiment.scene.parts.count < 2
                              || experiment.scene.connections.count >= AssemblyScene.maximumConnections)
                }
                ForEach(experiment.scene.connections) { link in
                    row("\(name(link.first)) → \(name(link.second))",
                        icon: link.kind == .spring ? "waveform.path" : "link",
                        color: link.kind == .spring ? assemblyInk : assemblyMint,
                        selected: experiment.selectedConnection == link.id) {
                        experiment.selectConnection(link.id)
                    }
                }
                Divider()
                if let index = experiment.selectedIndex {
                    bodyInspector(experiment.scene.parts[index])
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
            .padding(.horizontal, 9).padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(selected ? color.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func bodyInspector(_ part: AssemblyPart) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(part.shape.rawValue).font(.headline)
                Spacer()
                Button("Remove body", systemImage: "trash") {
                    experiment.edit { $0.removePart(part.id) }
                }
                .labelStyle(.iconOnly)
                .help("Remove this body and its connections")
            }
            TextField("Body name", text: Binding(get: { part.name }, set: { value in
                let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { experiment.updatePart(part.id) { $0.name = String(name.prefix(48)) } }
            }))
            .textFieldStyle(.roundedBorder)
            Picker("Body mesh", selection: Binding(get: { part.refinement }, set: { level in
                experiment.updatePart(part.id) { $0.refinement = level }
            })) {
                Text("Use assembly mesh").tag(nil as AssemblyScene.Resolution?)
                ForEach(AssemblyScene.Resolution.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            Toggle("Material fracture", isOn: Binding(get: { part.fracture != nil }, set: { enabled in
                experiment.updatePart(part.id) { $0.fracture = enabled ? MaterialFractureSettings() : nil }
            })).toggleStyle(.checkbox)
                .disabled(part.bondedLayer != nil)
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
                Text("Experimental fracture. Crack paths and later contacts can change with the mesh.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Geometry and initial motion", isExpanded: $bodySettings) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
                    GridRow {
                        bodyNumber("X (mm)", part, \.center.x, -1...1, scale: 1000)
                        bodyNumber("Y (mm)", part, \.center.y, -1...1, scale: 1000)
                    }
                    GridRow {
                        bodyNumber("Width (mm)", part, \.size.x, 0.025...0.30, scale: 1000)
                        bodyNumber("Height (mm)", part, \.size.y, 0.025...0.30, scale: 1000)
                    }
                    GridRow {
                        bodyNumber("Angle (°)", part, \.angle, -360...360)
                        if part.shape == .enclosure {
                            bodyNumber("Wall (mm)", part, \.wall, 0.005...0.4 * min(part.size.x, part.size.y), scale: 1000)
                        }
                    }
                    GridRow {
                        bodyNumber("VX (m/s)", part, \.velocity.x, -1.5...1.5)
                        bodyNumber("VY (m/s)", part, \.velocity.y, -1.5...1.5)
                    }
                }.padding(.top, 7)
                if part.shape == .block && part.bondedLayer == nil { notchEditor(part) }
            }
            DisclosureGroup("Material", isExpanded: $materialSettings) {
                VStack(alignment: .leading, spacing: 7) {
                    Picker("Response", selection: Binding(get: { part.plasticity.response },
                                                          set: { response in experiment.updatePart(part.id) { $0.plasticity.response = response } })) {
                        ForEach(CouponResponse.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .disabled(part.bondedLayer != nil)
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
                        GridRow {
                            bodyNumber("Modulus (MPa)", part, \.material.young, SceneConfiguration.youngRange, scale: 1e-6)
                            bodyNumber("Density (kg/m³)", part, \.material.density, SceneConfiguration.densityRange)
                        }
                        GridRow {
                            bodyNumber("Poisson ratio", part, \.material.poisson, SceneConfiguration.poissonRange)
                        }
                        if part.plasticity.response == .elastoplastic {
                            GridRow {
                                bodyNumber("Yield / E (%)", part, \.plasticity.yieldFraction, ImpactPlasticity.yieldRange, scale: 100)
                                bodyNumber("Hardening / E (%)", part, \.plasticity.hardeningFraction, ImpactPlasticity.hardeningRange, scale: 100)
                            }
                        }
                    }
                    if part.shape == .block { bondedLayerEditor(part) }
                }.padding(.top, 7)
            }
            gaugeEditor(part)
        }
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
        VStack(alignment: .leading, spacing: 7) {
            Toggle("Bonded second material", isOn: Binding(get: { part.bondedLayer != nil }, set: { enabled in
                experiment.updatePart(part.id) { $0.bondedLayer = enabled ? AssemblyPart.BondedLayer() : nil }
            }))
            .toggleStyle(.checkbox)
            .disabled(part.notch != nil || part.fracture != nil || part.plasticity.response != .elastic)
            .help("Available on unnotched elastic blocks with material fracture off")
            if let layer = part.bondedLayer {
                Text("The two elastic materials share nodes at a permanent bond. The second material lies to its local right.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    numeric("Bond from left (% width)", value: layer.interfaceFraction, range: 0.10...0.90, scale: 100) { value in
                        experiment.updatePart(part.id) { $0.bondedLayer?.interfaceFraction = value }
                    }
                    numeric("Second E (MPa)", value: layer.material.young, range: SceneConfiguration.youngRange, scale: 1e-6) { value in
                        experiment.updatePart(part.id) { $0.bondedLayer?.material.young = value }
                    }
                }
                HStack {
                    numeric("Second density (kg/m³)", value: layer.material.density, range: SceneConfiguration.densityRange, scale: 1) { value in
                        experiment.updatePart(part.id) { $0.bondedLayer?.material.density = value }
                    }
                    numeric("Second Poisson ratio", value: layer.material.poisson, range: SceneConfiguration.poissonRange, scale: 1) { value in
                        experiment.updatePart(part.id) { $0.bondedLayer?.material.poisson = value }
                    }
                }
            }
        }.padding(.vertical, 4)
    }

    private func gaugeEditor(_ part: AssemblyPart) -> some View {
        ForEach(experiment.gauges.filter { $0.body == part.id }) { gauge in
            if let index = experiment.gauges.firstIndex(where: { $0.id == gauge.id }) {
                let value = experiment.simulation.gaugeReading(index)
                DisclosureGroup {
                    HStack {
                        numeric("Local X (mm)", value: gauge.location.x, range: -part.size.x/2...part.size.x/2, scale: 1000) { x in
                            experiment.updateGauge(gauge.id) { $0.location.x = x }
                        }
                        numeric("Local Y (mm)", value: gauge.location.y, range: -part.size.y/2...part.size.y/2, scale: 1000) { y in
                            experiment.updateGauge(gauge.id) { $0.location.y = y }
                        }
                        Button("Remove gauge", systemImage: "trash") {
                            experiment.edit { $0.gauges?.removeAll { $0.id == gauge.id } }
                        }.labelStyle(.iconOnly)
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
                    experiment.edit { $0.connections.removeAll { $0.id == link.id } }
                }.labelStyle(.iconOnly)
            }
            Picker("Type", selection: Binding(get: { link.kind }, set: { kind in
                experiment.updateConnection(link.id) { $0.kind = kind }
            })) {
                ForEach(AssemblyConnection.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
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
        VStack(alignment: .leading, spacing: 9) {
            Text("Run settings").font(.headline)
            Picker("Assembly mesh", selection: Binding(get: { experiment.scene.resolution }, set: { resolution in
                experiment.edit { $0.meshResolution = resolution }
            })) {
                ForEach(AssemblyScene.Resolution.allCases, id: \.self) { Text($0.label).tag($0) }
            }
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
                }
                Picker("Relative to", selection: Binding(get: { experiment.scene.relativeTo }, set: { id in
                    experiment.edit { $0.relativeTo = id }
                })) {
                    Text("Lab frame").tag(nil as UUID?)
                    ForEach(experiment.scene.parts.filter {
                        $0.id != (experiment.scene.monitor ?? experiment.scene.parts.first?.id)
                    }) { Text($0.name).tag(Optional($0.id)) }
                }
            }
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
        }
    }
}
