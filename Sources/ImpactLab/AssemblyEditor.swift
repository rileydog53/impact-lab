import AppKit
import ImpactPhysics
import simd
import SwiftUI

struct AssemblyEditor: View {
    let experiment: AssemblyExperiment
    @State private var bodySettings = true
    @State private var materialTarget: MaterialTarget?
    @State private var materialSettings = false
    @State private var connectionList = false
    @State private var meshSettings = false
    @State private var simulationSettings = false
    @State private var multiSelect = false
    @State private var layoutGap = 0.010
    @State private var showWorkshopLimits = false
    @AppStorage(RuntimeWarnings.showKey) private var showEstimateAbove = RuntimeWarnings.defaultShow
    @AppStorage(RuntimeWarnings.confirmKey) private var confirmAbove = RuntimeWarnings.defaultConfirm
    @AppStorage(RuntimeWarnings.longKey) private var warnAbove = RuntimeWarnings.defaultLong

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
                    Text("Showing a result. Use Edit a Copy to change the setup while keeping this result as the reference, or Reset Run to discard it.")
                        .font(.caption).foregroundStyle(assemblyAmber)
                }
                components
                if experiment.scene.parts.isEmpty {
                    Text("Add geometry to begin. Drag bodies or enter exact positions in the inspector.")
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
                        Button("Place Spring on Canvas") { experiment.startLinkPlacement(.spring) }
                        Button("Place Breakable Link on Canvas") { experiment.startLinkPlacement(.cohesive) }
                        Divider()
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
                if experiment.selectedParts.count > 1 {
                    selectionInspector
                } else if let index = experiment.selectedIndex {
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
        .sheet(item: $materialTarget) { target in
            if let index = experiment.selectedIndex {
                let part = experiment.scene.parts[index]
                MaterialLibrary(target: target, part: part, canAssign: experiment.canEdit) { profile, elasticOnly in
                    experiment.assignMaterial(profile, to: part.id, target: target, elasticOnly: elasticOnly)
                }
            }
        }
    }

    private var components: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Components").font(.headline)
                Spacer()
                Menu("Add Body", systemImage: "plus") {
                    ForEach(WorkshopGeometry.allCases, id: \.self) { geometry in
                        Button(geometry.rawValue, systemImage: geometry.icon) { experiment.insert(geometry) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(!experiment.canEdit || experiment.scene.parts.count >= AssemblyScene.maximumParts)
                .help("Insert deformable geometry. The assembly supports up to \(AssemblyScene.maximumParts) bodies.")
            }
            ForEach(experiment.displayIndices, id: \.self) { index in
                let part = experiment.scene.parts[index]
                let icon = switch part.shape {
                case .enclosure: "square.dashed"
                case .round: "circle.fill"
                case .block: part.bondedLayer == nil ? "square.fill" : "square.3.layers.3d"
                }
                row(part.name + (part.support == nil ? "" : part.support == .fixed ? " · fixed" : " · clamped")
                    + (part.refinement == nil ? "" : " · own mesh"), tag: part.fractureStatus, icon: icon, color: assemblyColor(index),
                    selected: experiment.selectedParts.contains(part.id)) {
                    experiment.select(part.id, adding: multiSelect || (NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false))
                }
                .help((part.refinement == nil ? part.name : "\(part.name) uses its own mesh (\(part.refinement!.label)) instead of the assembly mesh.")
                      + "\n" + { if case let .unavailable(reason) = part.fractureStatus { return "Fracture not available: " + reason }
                                  return part.fracture == nil ? "Material fracture is off. Turn it on under Material." : "Material fracture is on." }())
            }
            ForEach(Array((experiment.scene.groups ?? []).enumerated()), id: \.element.id) { number, group in
                row("Group \(number + 1) · \(group.members.count) bodies", icon: "square.on.square",
                    color: assemblyInk, selected: Set(group.members) == experiment.selectedParts) {
                    experiment.selectGroup(group)
                }
                .help(group.members.map(name).joined(separator: ", "))
            }
            HStack {
                if !experiment.scene.parts.isEmpty {
                    Toggle("Multi-select", isOn: $multiSelect).toggleStyle(.checkbox)
                        .help("Add or remove bodies from the selection. You can also Shift-click bodies on the canvas.")
                    Spacer()
                    Menu("Arrange", systemImage: "square.3.layers.3d") {
                        Button("Duplicate Selection") { experiment.duplicateSelection() }
                            .keyboardShortcut("d", modifiers: .command)
                            .disabled(experiment.selectedParts.count + experiment.scene.parts.count > AssemblyScene.maximumParts)
                        Button("Delete Selection", role: .destructive) { experiment.removeSelection() }
                        Divider()
                        Button("Group Selection") { experiment.groupSelection() }
                            .disabled(experiment.selectedParts.count < 2)
                        Button("Ungroup Selection") { experiment.ungroupSelection() }
                            .disabled(!(experiment.scene.groups ?? []).contains { group in
                                group.members.contains(where: experiment.selectedParts.contains)
                            })
                        Divider()
                        Button("Bring to Front") { experiment.reorderSelection(toFront: true) }
                        Button("Send to Back") { experiment.reorderSelection(toFront: false) }
                    }
                    .fixedSize()
                    .disabled(!experiment.canEdit || experiment.selectedParts.isEmpty)
                    .help("Duplicate, group, delete, or reorder selected bodies. Copies carry internal links.")
                }
                Button("Workshop Limits", systemImage: "info.circle") { showWorkshopLimits.toggle() }
                    .labelStyle(.iconOnly)
                    .help("Supported geometry, connections, and constraints")
                    .popover(isPresented: $showWorkshopLimits) { workshopLimits }
            }.controlSize(.small)
        }
    }

    private var workshopLimits: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Workshop limits").font(.headline)
            Text("Bodies may translate and rotate. A body can be a fixed support (a rigid bench, floor or roller that never moves) or have one edge clamped. A deformable support is an ordinary free block that can move and deform under load. Pinned points, rigid joints and partial constraints are unavailable.")
            Text("Gravity can be switched on in Simulation settings; it pulls every free body downward (−Y). No other applied loads, pressures or friction exist; contact is frictionless.")
            Text("Permanent bonds join elastic layers within a block. Use springs (optionally preloaded) or breakable tension links between separate bodies. Round bodies, bonded blocks and supported bodies cannot fracture; each body's list entry says \"fracture on\", \"fracture off\" or \"fracture n/a\", and hovering explains why.")
            Text("Round bodies use an elliptical mesh. Imported outlines, arbitrary cracks, and nested groups are unavailable.")
            Text("Limits and their causes").font(.subheadline.weight(.semibold))
            ForEach(AssemblyScene.limits, id: \.name) { limit in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(limit.name): \(limit.value)").fontWeight(.medium)
                    Text("\(limit.kind.rawValue). \(limit.cause)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Everything is two-dimensional plane strain: forces and energies are per metre of depth.")
            Text("Duplicates retain geometry, materials, initial motion, and links within the copied selection. External links and gauges stay with their original bodies.")
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 310, alignment: .leading)
        .padding(15)
    }

    private var selectionInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(experiment.selectedParts.count) bodies selected").font(.headline)
            Text("Drag any selected body to move the selection. Select one body to rotate or resize it.")
                .font(.caption).foregroundStyle(.secondary)
            if let body = experiment.selectedBodyList.first(where: { $0.id == experiment.selectedPart }) {
                Text("Alignment reference · \(body.name)").font(.caption)
            }
            numeric("Spacing gap (mm)", value: layoutGap, range: 0.0005...0.25, scale: 1000) { layoutGap = $0 }
                .help("Clearance between body extents when spacing horizontally or vertically")
            Menu("Align or Space Bodies") {
                ForEach(WorkshopAlignment.allCases, id: \.self) { alignment in
                    Button(alignment.rawValue) { experiment.alignSelection(alignment, gap: layoutGap) }
                }
            }
            .disabled(!experiment.canEdit)
        }
    }

    private func name(_ id: UUID) -> String {
        experiment.scene.parts.first { $0.id == id }?.name ?? "Body"
    }

    private func row(_ title: String, tag: AssemblyPart.FractureStatus? = nil, icon: String, color: Color, selected: Bool,
                     select: @escaping () -> Void) -> some View {
        Button(action: select) {
            Label {
                HStack(spacing: 6) {
                    Text(title).lineLimit(1).foregroundStyle(assemblyInk)
                    Spacer(minLength: 4)
                    if let tag {
                        Text(tag.tag).font(.caption2.weight(.semibold)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(tag == .on ? assemblyAmber : Color.secondary)
                            .background((tag == .on ? assemblyAmber : Color.secondary).opacity(0.16), in: Capsule())
                    }
                }
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

    private func sizeHelp(_ part: AssemblyPart, mesh: AssemblyScene.Resolution) -> String {
        let minimum = String(format: "%.3g", AssemblyPart.minimumSize(resolution: mesh) * 1000)
        var text = "Sizes \(minimum)–300 mm"
        if part.support == .fixed {
            text += " (a fixed support may be up to 1,000 mm wide because it is never calculated as a deforming body)"
        }
        text += ". Minimum (numerical): a body must span about three elements of the \(mesh.label) mesh, so a finer mesh allows a smaller body and the standard mesh needs 25 mm."
        text += " Maximum (workshop limit, not physical): keeps triangle counts and run times manageable. Typed values outside the range are set to the nearest limit."
        if part.shape == .enclosure { text += " Walls are at least 5 mm (two element layers) and at most 40% of the smaller side." }
        return text
    }

    private func bodyInspector(_ part: AssemblyPart) -> some View {
        let mesh = part.refinement ?? experiment.scene.resolution
        return VStack(alignment: .leading, spacing: 8) {
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
            Text("\(part.shape.rawValue) · \(materialDescription(part)) · \(part.fractureStatus.tag)")
                .font(.caption).foregroundStyle(.secondary)
            AssemblyBodyName(part: part, experiment: experiment)
            DisclosureGroup("Geometry", isExpanded: $bodySettings) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
                    GridRow {
                        bodyNumber("Center X (mm)", part, \.center.x, -1...1, scale: 1000)
                        bodyNumber("Center Y (mm)", part, \.center.y, -1...1, scale: 1000)
                    }
                    GridRow {
                        bodyNumber(part.shape == .round ? "Local X diameter (mm)" : "Local width (mm)", part, \.size.x, part.widthRange(resolution: mesh), scale: 1000)
                        bodyNumber(part.shape == .round ? "Local Y diameter (mm)" : "Local height (mm)", part, \.size.y, part.sizeRange(resolution: mesh), scale: 1000)
                    }
                    GridRow {
                        bodyNumber("Rotation (°)", part, \.angle, -360...360)
                            .help("Counterclockwise angle from the assembly X axis")
                        if part.shape == .enclosure {
                            bodyNumber("Wall thickness (mm)", part, \.wall, 0.005...max(0.005, 0.4 * min(part.size.x, part.size.y)), scale: 1000)
                        }
                    }
                }.padding(.top, 5)
                Text(sizeHelp(part, mesh: mesh))
                       .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if part.shape == .block && part.bondedLayer == nil {
                    notchEditor(part).disabled(!experiment.canEdit)
                } else if part.shape == .block {
                    Text("V-notch is unavailable on a bonded-layer block.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Initial motion").font(.subheadline.weight(.semibold)).padding(.top, 4)
            HStack(spacing: 6) {
                bodyNumber("X velocity (m/s)", part, \.velocity.x, AssemblyPart.velocityRange)
                bodyNumber("Y velocity (m/s)", part, \.velocity.y, AssemblyPart.velocityRange)
            }
            if experiment.canEdit, let index = experiment.selectedIndex {
                let speed = simd_length(part.velocity)
                let mass = experiment.simulation.body(index).totalMass
                let direction = atan2(part.velocity.y, part.velocity.x) * 180 / .pi
                Text(speed > 0 ? "Speed \(speed, specifier: "%.3g") m/s · \(direction, specifier: "%.1f")° from +X" : "Initially at rest")
                    .font(.caption.monospacedDigit())
                Text("Mass \(mass, specifier: "%.3g") kg/m · Kinetic energy \(0.5 * mass * speed * speed, specifier: "%.3g") J/m")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text("Momentum (\(mass * part.velocity.x, specifier: "%.3g"), \(mass * part.velocity.y, specifier: "%.3g")) N·s/m")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            supportEditor(part)
            DisclosureGroup("Mesh", isExpanded: $meshSettings) {
                Picker("Body mesh", selection: Binding(get: { part.refinement }, set: { level in
                    experiment.updatePart(part.id) { $0.refinement = level }
                })) {
                    Text("Use assembly mesh").tag(nil as AssemblyScene.Resolution?)
                    ForEach(AssemblyScene.Resolution.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                    .disabled(!experiment.canEdit)
                    .help("Override the triangle size for this body")
                Text(part.refinement == nil
                     ? "Follows the assembly mesh (\(experiment.scene.resolution.label)) set in Simulation settings."
                     : "Overrides the assembly mesh. This body keeps \(part.refinement!.label) even when the assembly mesh changes. Reset all overrides in Simulation settings.")
                    .font(.caption).foregroundStyle(part.refinement == nil ? Color.secondary : assemblyAmber)
                    .fixedSize(horizontal: false, vertical: true)
                if let advisory = experiment.scene.bendingAdvisory(for: part) {
                    Label(advisory, systemImage: "info.circle").font(.caption).foregroundStyle(assemblyAmber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let index = experiment.selectedIndex {
                    let quality = experiment.meshQuality[index]
                    Text("\(quality.triangleCount) triangles · Minimum shape quality \(quality.minimum, specifier: "%.2f")")
                        .font(.caption).foregroundStyle(.secondary)
                    if !quality.thinTriangles.isEmpty {
                        Text("\(quality.thinTriangles.count) thin triangles marked amber in mesh preview.")
                            .font(.caption).foregroundStyle(assemblyAmber)
                    }
                }
            }
            DisclosureGroup("Material", isExpanded: $materialSettings) {
                VStack(alignment: .leading, spacing: 7) {
                    materialKind(part)
                    Button("Material Library…", systemImage: "square.stack.3d.up") { materialTarget = .body }
                    profiles("Apply illustrative profile", elasticOnly: part.bondedLayer != nil) { profile in
                        experiment.updatePart(part.id, action: "Apply Material") { profile.apply(to: &$0) }
                    }.disabled(!experiment.canEdit)
                    if let provenance = part.material.provenance {
                        Text(provenance.name).font(.subheadline.weight(.semibold))
                        assignedMaterial(part.material)
                        if part.plasticity.response == .elastoplastic, let table = part.plasticity.table {
                            Text("J2 · Initial flow stress \(table.points[0].stress / 1e6, specifier: "%.4g") MPa")
                                .font(.caption)
                            HardeningPreview(table: table)
                        } else {
                            Text("Elastic response").font(.caption)
                        }
                    } else {
                        Text("Profiles in the menu above use illustrative numbers chosen to show a behaviour, not a real material.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Response", selection: Binding(get: { part.plasticity.response },
                                                              set: { response in experiment.updatePart(part.id) { $0.plasticity.response = response } })) {
                            ForEach(CouponResponse.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .disabled(!experiment.canEdit || part.bondedLayer != nil || part.support == .fixed)
                        if part.bondedLayer != nil {
                            Text("Response is Elastic because bonded layers share nodes and the plastic model is per body.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if part.support == .fixed {
                            Text("Response is Elastic because a fixed support never deforms.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
                    }
                    if let profile = MaterialProfile.references.first(where: { $0.id == part.material.provenance?.id }),
                       part.shape != .round, part.bondedLayer == nil {
                        VStack(alignment: .leading, spacing: 7) {
                            if let estimate = profile.defaultFracture {
                                Toggle("Material fracture (sourced estimate)", isOn: Binding(get: { part.fracture != nil }, set: { enabled in
                                    experiment.updatePart(part.id) { $0.fracture = enabled ? estimate : nil }
                                })).toggleStyle(.checkbox)
                                if part.fracture == nil {
                                    Text("Off by default. Turning it on uses the handbook estimate for this material, with its citation.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else if case let .unavailable(reason) = profile.fractureEstimate {
                                Text("Fracture toughness is off for this material. \(reason)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let fracture = part.fracture { fractureControls(part, fracture) }
                        }.disabled(!experiment.canEdit)
                    } else if part.material.provenance != nil {
                        Text("Material fracture is unavailable here: the selected profile has no sourced fracture estimate for this model. Choose an illustrative material to set fracture values yourself.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let reason = part.fractureUnavailableReason {
                        Text("Material fracture is unavailable: \(reason)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if part.bondedLayer == nil {
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle("Material fracture", isOn: Binding(get: { part.fracture != nil }, set: { enabled in
                                experiment.updatePart(part.id) { $0.fracture = enabled ? MaterialFractureSettings() : nil }
                            })).toggleStyle(.checkbox)
                            if let fracture = part.fracture { fractureControls(part, fracture) }
                        }.disabled(!experiment.canEdit)
                    } else {
                        Text("Material fracture is unavailable: bonded-layer blocks are elastic only and joined by permanent bonds. Remove the bonded layers to allow fracture, or join two bodies with a Breakable link.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if part.shape == .block { bondedLayerEditor(part) }
                }.padding(.top, 7)
            }
            gaugeEditor(part)
        }
    }


    @ViewBuilder
    private func fractureControls(_ part: AssemblyPart, _ fracture: MaterialFractureSettings) -> some View {
        let young = part.material.young
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                // Strength is shown and entered in real units (MPa = 10⁶ Pa). Legacy scenes
                // show their fraction-of-E strength converted; the saved value only changes
                // when the user types a new strength.
                numeric("Cohesive strength (MPa)", value: fracture.resolvedStrength(young: young),
                        range: MaterialFractureSettings.absoluteStrengthRange, scale: 1e-6) { value in
                    experiment.updatePart(part.id) { $0.fracture?.strength = value }
                }
                numeric("Fracture energy (J/m²)", value: fracture.energy,
                        range: fracture.activeEnergyRange, scale: 1) { value in
                    experiment.updatePart(part.id) { $0.fracture?.energy = value; $0.fracture?.energySource = nil }
                }
            }
            if let source = fracture.energySource {
                Label("Experimental, not validated. \(source.caution)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(assemblyAmber).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Source") {
                    Text(source.citation).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption)
            }
            if part.shape == .block {
                Picker("Interior mesh", selection: Binding(get: { fracture.pattern }, set: { pattern in
                    experiment.updatePart(part.id) { $0.fracture?.meshPattern = pattern }
                })) {
                    ForEach(MaterialFractureSettings.MeshPattern.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            let resolution = part.refinement ?? experiment.scene.resolution
            Text(resolution.rawValue <= 3
                 ? "Coarse fracture preview. Crack paths and fragment motion are qualitative."
                 : "Experimental fracture. Check mesh and timestep sensitivity before using the readings quantitatively.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func materialDescription(_ part: AssemblyPart) -> String {
        if let layer = part.bondedLayer {
            return layer.third == nil ? "Two bonded elastic layers" : "Three bonded elastic layers"
        }
        if let provenance = part.material.provenance { return provenance.name }
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
            Text("A triangular cut into the body's local bottom edge. It concentrates stress so yielding, or a crack when Material fracture is on, starts there. It is geometry only: not a crack and not a fracture model.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let notch = part.notch {
                Text("Offset and width are % of the body width (offset from the centre); depth is % of the body height.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    numeric("Offset (% width)", value: notch.centerFraction, range: -0.30...0.30, scale: 100) { value in
                        experiment.updatePart(part.id) { $0.notch?.centerFraction = value }
                    }
                    numeric("Width (%)", value: notch.widthFraction, range: 0.12...0.36, scale: 100) { value in
                        experiment.updatePart(part.id) { $0.notch?.widthFraction = value }
                    }
                    numeric("Depth (% height)", value: notch.depthFraction, range: 0.02...0.45, scale: 100) { value in
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
            .disabled(!experiment.canEdit || part.notch != nil || part.fracture != nil || part.plasticity.response != .elastic)
            .help("Available on unnotched elastic blocks with material fracture off")
            Text("Splits this one block into two or three elastic materials side by side along its width, joined by a perfect permanent bond (shared nodes: no slip and no debonding). For an interface that can come apart, use two separate bodies joined by a Breakable link.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if part.bondedLayer == nil, let reason = [part.notch != nil ? "remove the V-notch" : nil,
                                                       part.fracture != nil ? "turn off Material fracture" : nil,
                                                       part.plasticity.response != .elastic ? "set the response to Elastic" : nil].compactMap({ $0 }).first {
                Text("Unavailable here: \(reason) first.").font(.caption).foregroundStyle(assemblyAmber)
            }
            if let layer = part.bondedLayer {
                Text("Layer positions are measured from the left along the local width.")
                    .font(.caption).foregroundStyle(.secondary)
                let firstUpperBound = layer.third.map { $0.interfaceFraction - minimum } ?? 1 - minimum
                numeric("First bond from left (% width)", value: layer.interfaceFraction,
                        range: minimum...max(minimum, firstUpperBound), scale: 100) { value in
                    experiment.updatePart(part.id) { $0.bondedLayer?.interfaceFraction = value }
                }
                layerMaterial(.second, layer.material) { material in
                    experiment.updatePart(part.id) { $0.bondedLayer?.material = material }
                }
                Toggle("Bonded third material", isOn: Binding(get: { layer.third != nil }, set: { enabled in
                    experiment.updatePart(part.id) {
                        let fraction = min(1 - minimum, max(0.75, layer.interfaceFraction + minimum))
                        $0.bondedLayer?.third = enabled ? .init(interfaceFraction: fraction) : nil
                    }
                })).toggleStyle(.checkbox)
                    .disabled(!experiment.canEdit || (layer.third == nil && layer.interfaceFraction > 1 - 2 * minimum))
                if let third = layer.third {
                    numeric("Second bond from left (% width)", value: third.interfaceFraction,
                            range: min(1 - minimum, layer.interfaceFraction + minimum)...(1 - minimum), scale: 100) { value in
                        experiment.updatePart(part.id) { $0.bondedLayer?.third?.interfaceFraction = value }
                    }
                    layerMaterial(.third, third.material) { material in
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

    private func assignedMaterial(_ material: ImpactPhysics.Material) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("E \(material.young / 1e9, specifier: "%.4g") GPa · ρ \(material.density, specifier: "%.5g") kg/m³ · ν \(material.poisson, specifier: "%.3g")")
                .font(.caption.monospacedDigit())
            if let provenance = material.provenance {
                Text(provenance.condition)
                if provenance.isCustom { Text("Saved inputs from a user-edited profile.") }
                Text(provenance.evidence)
                Link(provenance.sourceName, destination: provenance.source)
            }
        }.font(.caption).foregroundStyle(.secondary)
    }

    private func layerMaterial(_ target: MaterialTarget, _ material: ImpactPhysics.Material,
                               set: @escaping (ImpactPhysics.Material) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("\(target.rawValue) Material Library…") { materialTarget = target }
            profiles("\(target.rawValue) illustrative profiles", elasticOnly: true) { set($0.material) }
                .disabled(!experiment.canEdit)
            if let provenance = material.provenance {
                Text(provenance.name).font(.caption.weight(.semibold))
                assignedMaterial(material)
            } else {
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
    }

    private func gaugeEditor(_ part: AssemblyPart) -> some View {
        ForEach(experiment.gauges.filter { $0.body == part.id }) { gauge in
            if let index = experiment.gauges.firstIndex(where: { $0.id == gauge.id }) {
                let value = experiment.displayedGauge(index)
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

    /// Starting length, rest length, preload and stiffness in plain words, with a to-scale picture.
    private func springSummary(_ link: AssemblyConnection, start: Double, rest: Double) -> some View {
        let preload = link.preload ?? 0
        let state = preload > 0 ? "starts stretched, pulling the bodies together"
            : preload < 0 ? "starts squeezed, pushing the bodies apart" : "starts relaxed, so it carries no force until the bodies move"
        return VStack(alignment: .leading, spacing: 5) {
            SpringLengthHint(start: start, rest: rest)
            Text("Starting length \(start * 1000, specifier: "%.3g") mm: the distance between the two anchors at time zero, set by where the bodies and anchors are.")
            Text("Rest length \(rest * 1000, specifier: "%.3g") mm: the length at which the spring pulls or pushes with zero force. Rest length = starting length − preload.")
            Text("Preload \(preload * 1000, specifier: "%.3g") mm: the spring \(state). Starting force \(abs(link.stiffness * preload), specifier: "%.3g") N/m, stored energy \(0.5 * link.stiffness * preload * preload, specifier: "%.3g") J/m.")
            Text("Stiffness k \(link.stiffness / 1000, specifier: "%.3g") kN/m²: force = k × (current length − rest length).")
        }
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            Text(link.kind == .spring
                 ? ((link.preload ?? 0) == 0
                    ? "Unloaded spring: its rest length is the starting distance between the anchors, so it carries no force until the bodies move. It transfers tension and compression and never breaks."
                    : "Preloaded spring: it starts stretched or compressed by the preload, so it pushes or pulls from the first instant. It transfers tension and compression and never breaks.")
                 : "Breakable link: starts unloaded, carries tension that softens and drops to zero as the extension reaches the failure extension; the lost energy is counted as fracture. It cannot be preloaded.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
                GridRow {
                    linkNumber(link.kind == .spring ? "Stiffness k (kN/m²)" : "Stiffness (kN/m²)", link, \.stiffness, 500...250_000, scale: 0.001)
                        .help("Force per unit of stretch, per metre of depth (2-D plane strain). Doubling it doubles the force at the same stretch.")
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
                    if link.kind == .spring {
                        numeric("Preload (mm, + stretched)", value: link.preload ?? 0, range: AssemblyConnection.preloadRange, scale: 1000) { value in
                            experiment.updateConnection(link.id, action: "Set Preload") { $0.preload = value == 0 ? nil : value }
                        }
                        .help("Positive: the spring starts stretched and pulls the bodies together. Negative: it starts compressed and pushes them apart. 0: unloaded.")
                    }
                }
            }
            if link.kind == .spring, let index = experiment.scene.connections.firstIndex(where: { $0.id == link.id }),
               let lengths = experiment.simulation.linkLengths(index) {
                springSummary(link, start: lengths.start, rest: lengths.rest)
            }
            if let index = experiment.scene.connections.firstIndex(where: { $0.id == link.id }) {
                let readings = experiment.displayedLinks.filter { $0.connection == index }
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
            Text("Drag the white end circles on the canvas to move the anchors; the fields above give exact positions as % of the body half-size. Anchors follow the body’s local axes. An anchor in a cavity snaps to the nearest wall. A nonzero band height spreads stiffness across five links.")
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
                if experiment.scene.parts.contains(where: { $0.refinement != nil }) {
                    Button("Reset All Body Mesh Overrides") {
                        experiment.edit("Reset Mesh Overrides") { scene in
                            for i in scene.parts.indices { scene.parts[i].refinement = nil }
                        }
                    }.disabled(!experiment.canEdit)
                    Text("\(experiment.scene.parts.filter { $0.refinement != nil }.count) bodies use their own mesh and ignore the assembly mesh.")
                        .font(.caption).foregroundStyle(assemblyAmber)
                }
                Text("\(experiment.elementCount) triangles · \(experiment.simulation.dt * 1e6, specifier: "%.3g") µs step")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(experiment.simulation.timestep.explanation)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                numeric("Duration (ms)", value: experiment.scene.duration, range: AssemblyScene.durationRange, scale: 1000) { value in
                    experiment.edit { $0.duration = value }
                }
                Toggle("Gravity", isOn: Binding(get: { (experiment.scene.gravity ?? 0) > 0 }, set: { on in
                    experiment.edit(on ? "Turn On Gravity" : "Turn Off Gravity") { $0.gravity = on ? AssemblyScene.standardGravity : nil }
                })).toggleStyle(.checkbox).disabled(!experiment.canEdit)
                if let g = experiment.scene.gravity, g > 0 {
                    numeric("Gravity (m/s², downward)", value: g, range: AssemblyScene.gravityRange, scale: 1) { value in
                        experiment.edit { $0.gravity = value > 0 ? value : nil }
                    }
                    Text("Pulls every free body toward −Y. Bodies start at rest under a suddenly applied load, so with no damping they oscillate about their resting position; time averages give the static values.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Off: no weight acts. Turn it on for anything that rests, sags or falls.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Run-time warnings") {
                    VStack(alignment: .leading, spacing: 6) {
                        numeric("Show estimate above (s)", value: showEstimateAbove, range: 0...3600, scale: 1) { showEstimateAbove = $0 }
                        numeric("Ask to confirm above (s)", value: confirmAbove, range: 0...36_000, scale: 1) { confirmAbove = $0 }
                        numeric("Long-run warning above (s)", value: warnAbove, range: 0...360_000, scale: 1) { warnAbove = $0 }
                        Button("Restore Defaults (30 s, 2 min, 10 min)") {
                            showEstimateAbove = RuntimeWarnings.defaultShow
                            confirmAbove = RuntimeWarnings.defaultConfirm
                            warnAbove = RuntimeWarnings.defaultLong
                        }
                        Text("These only change when the app warns you. They never change the calculation or its safeguards.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 4)
                }.font(.callout)
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

    @ViewBuilder
    private func supportEditor(_ part: AssemblyPart) -> some View {
        let links = experiment.scene.connections.filter { $0.first == part.id || $0.second == part.id }
        VStack(alignment: .leading, spacing: 6) {
            Picker("Support", selection: Binding(get: { part.support }, set: { support in
                experiment.updatePart(part.id, action: "Set Support") { body in
                    body.support = support
                    if support != nil { body.velocity = .zero }
                    if support == .fixed { body.plasticity.response = .elastic }
                }
            })) {
                Text("Free body").tag(nil as AssemblyPart.Support?)
                ForEach(AssemblyPart.Support.allCases.filter { part.shape != .round || $0 == .fixed }, id: \.self) {
                    Text($0.rawValue).tag(Optional($0))
                }
            }
            .disabled(!experiment.canEdit || part.fracture != nil)
            Group {
                switch part.support {
                case nil:
                    Text("Free: moves and deforms under contact, links\(experiment.scene.gravity != nil ? " and gravity" : ""). " + (links.isEmpty ? "No links." : "\(links.count) body-to-body \(links.count == 1 ? "link" : "links")."))
                case .fixed?:
                    Text("Fixed support: a rigid bench, floor or fixture. It never moves or deforms and ignores gravity; its material sets only the contact stiffness. The force it exerts is reported as the support reaction.")
                case .some:
                    Text("Clamped edge: the nodes on that local edge are held in place (no movement, no rotation of the edge). The rest of the body deforms freely. The holding force is reported as the support reaction.")
                }
            }
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if part.fracture != nil {
                Text("Supports are unavailable while Material fracture is on (crack insertion would move held nodes).")
                    .font(.caption).foregroundStyle(assemblyAmber).fixedSize(horizontal: false, vertical: true)
            } else if let conflict = part.supportConflict {
                Text(conflict).font(.caption).foregroundStyle(assemblyAmber)
            }
            if part.support != nil, let index = experiment.selectedIndex, experiment.simulation.time > 0 {
                let reaction = experiment.simulation.supportReaction(index)
                Text("Support reaction at the end of the run (\(replayTime(experiment.simulation.time))): \(reaction.x, specifier: "%+.4g"), \(reaction.y, specifier: "%+.4g") N/m. This is one instant; bodies released under gravity oscillate, so compare averages in Measurements.")
                    .font(.caption.monospacedDigit()).foregroundStyle(assemblyMint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func materialKind(_ part: AssemblyPart) -> some View {
        let (title, detail): (String, String) = if let provenance = part.material.provenance {
            provenance.isCustom
                ? ("User-defined properties", "Your edits to a reference material. The source describes the original, not your values.")
                : ("Reference material, sourced properties", "Elastic constants and initial yield come from the cited source. Hardening beyond yield is illustrative, and fracture toughness estimates are experimental, not validated for this 2-D model.")
        } else if AssemblyMaterialProfile.allCases.contains(where: { $0.response == part.plasticity.response && $0.material == part.material }) {
            ("Illustrative profile", "Numbers chosen to show a behaviour clearly. Not a real material.")
        } else {
            ("User-defined properties", "Values you entered. The app checks only that they are in range.")
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("Material type · \(title)").font(.caption.weight(.semibold))
            Text(detail + " No material in the app is a validated constitutive model yet.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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


/// Two to-scale bars: the starting length against the force-free rest length. The amber part is the preload.
private struct SpringLengthHint: View {
    let start, rest: Double

    var body: some View {
        Canvas { context, size in
            let longest = max(start, rest, 1e-9)
            let scale = (size.width - 2) / longest
            func bar(_ y: CGFloat, _ length: Double, _ color: Color) {
                let end = 1 + length * scale
                var line = Path()
                line.move(to: CGPoint(x: 1, y: y)); line.addLine(to: CGPoint(x: end, y: y))
                context.stroke(line, with: .color(color), lineWidth: 3)
                for x in [1, end] {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: y - 5)); tick.addLine(to: CGPoint(x: x, y: y + 5))
                    context.stroke(tick, with: .color(color), lineWidth: 2)
                }
            }
            bar(8, start, assemblyMint)
            bar(24, rest, assemblyInk.opacity(0.8))
            if abs(start - rest) > 1e-9 {
                var gap = Path()
                gap.move(to: CGPoint(x: 1 + min(start, rest) * scale, y: 16))
                gap.addLine(to: CGPoint(x: 1 + max(start, rest) * scale, y: 16))
                context.stroke(gap, with: .color(assemblyAmber), style: StrokeStyle(lineWidth: 3, dash: [3, 2]))
            }
        }
        .frame(height: 32)
        .overlay(alignment: .topTrailing) {
            Text("top: starting · bottom: rest · amber: preload").font(.caption2).foregroundStyle(.secondary).offset(y: 30)
        }
        .padding(.bottom, 14)
        .accessibilityLabel("Starting length \(start * 1000) millimetres, rest length \(rest * 1000) millimetres")
    }
}
