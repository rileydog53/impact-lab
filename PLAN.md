# Impact Lab product recovery

The recovery plan started at checkpoint `15e8a6d`. The [original recovery cards](docs/PRODUCT_RECOVERY.md) retain the scope and acceptance criteria for Cards 1–6. The amendment below extends those requirements and governs execution order. The original foundation plan follows for historical reference.

- [x] Card 1 — Make the Application Usable
- [x] Card 2 — Build a Genuine Assembly Workshop
- [x] Card 3 core (3A and 3B) — Material profiles and verified metal mechanics
- [ ] Card 4 — Make the Calculated Physics Visible
- [ ] Card 5 — Scale the Computational Engine
- [ ] Card 7 — Build the Experimental Scenario Library
- [ ] Card 6 — Prove the Complete Product Works

## Amended execution order

**Card 2 → Card 3 core (3A and 3B) → Card 4 → Card 5 → Card 7 → Card 6.** Cards 1 and 2 are complete. Card 7 takes its own acceptance gate before final release verification. Card 6 retains its number and all four original end-to-end exercises.

Impact Lab is a native macOS laboratory for research, education, and exploration in materials and structural dynamics. Users should be able to construct experiments, assign materials, configure supported loads and initial conditions, calculate physical behavior, and inspect deformation, stress, plasticity, damage, fracture, and contact. Use general mechanics terminology and keep the architecture applicable to physical systems. The product scope excludes weapon-specific optimization, human-injury modeling, and depictions of harm to people. Shock waves, energetic-material phenomena, extreme deformation, and fragmentation remain topics for scientific exploration where supported by defensible models.

### Card 3 — Materials and physical conditions

- **3A · Data and usable reference profiles.** Deliver a searchable library starting with structural carbon steel, annealed stainless steel 304, aluminum 6061-T6, and annealed copper C11000. Expose the supported constitutive model, parameters, units, provenance, and limitations. Let users assign, duplicate, edit, save, and recover profiles. Preserve the Card 2 workflow for independently assigning materials to bodies and assigning materials to supported regions. The selected profile must change the solver inputs.
- **3B · Verified metal mechanics.** Review the current Swift J2 update before changing it. Add or improve tabulated isotropic hardening where needed. Provide a preview of the response the solver uses, and verify a meaningful comparison between two metal parameter sets. Apply the conventions and verification gates in the [material specifications](#material-model-specifications-and-source-references).
- **3C · Extensible constitutive architecture.** Reuse the solver’s existing interfaces where they already support the required kinematics, state, stress, energy, timestep, and field outputs. Add testable extension points where a concrete model needs them.
- **3D · Selected advanced material extensions.** Treat brittle and cohesive extensions and the other model families below as independently justified work. Each needs evidence, a compatible numerical formulation, and standalone verification before use in scenarios. This research can continue after initial product acceptance.

Keep the original physical-condition controls and acceptance criteria, including the preview of initial velocity magnitude and direction, constraints, and supported loads. Show relevant mass, momentum, and kinetic energy. Explain static setups, bodies that cannot interact in the run window, and incompatible settings. Fixed or clamped constraints still require solver support. Advance to Card 4 once 3A and 3B satisfy the core material workflow and verification gates. Work in 3C and 3D does not gate later cards.

Run `ImpactCheck --metal-profiles` for the tabulated return-map, work balance, conservation, and refinement gates. In the native Assembly tab, open **New / Examples → Metal Impact Example** to compare materials at the same impact speed. The existing J2 implementation returns Kirchhoff stress and displays Cauchy stress after division by \(J\). For tabulated hardening, the integral of the increase in flow stress above initial yield is stored and initial yield times accumulated plastic strain is dissipated.

### Card 4 — Calculated physics and visualization

Extend the existing replay, field inspection, and instrumentation work with equivalent and principal stress, plastic strain, damage, material-interface state, recoverable energy, dissipated energy, and comparisons of constitutive response where the solver supports them. Give each field a definition, stress measure where relevant, units, and limitations. Show whether a displayed value comes from the solver, a valid derivation, or display interpolation. Distinguish permanent bonds, damaged interfaces, and physical separation. Keep the original playback, gauges, Study comparisons, and export criteria.

### Card 5 — Computational scaling

Profile constitutive updates separately from other FEM work, force assembly, contact, geometry, and output recording. Measure state memory per element and the time and memory costs of representative material models at relevant resolutions. Compare optimized or parallel runs against the verified baseline using documented numerical tolerances. Preserve the original progress, cancellation, reproducibility, and measured-performance criteria.

### Card 7 — Experimental scenario library

Build on the existing library and use the native editor, solver, and replay workflow. Prioritize scenarios built from verified core physics.

| Scenario | What the user compares |
|---|---|
| Elastic contrast | Wave speed and impedance for two elastic materials |
| Elastic versus yielding response | Recovery and permanent set under comparable loading |
| Strain hardening | Two J2 responses with calibrated or clearly illustrative hardening |
| Bonded layers | Stress and wave transmission across a permanent bond |
| Interface failure | Opening, energy dissipation, and recontact for an independently specified cohesive interface, when validated |
| Brittle versus ductile and other nonlinear responses | Material-specific behavior after the corresponding constitutive model and failure criteria have passed standalone checks |

**Acceptance.** Demonstrate the core scenarios in the native app. Each shipped scenario must expose meaningful controls, produce a calculated physical event, show visible results and relevant measurements, and explain the scientific limitations. Users must be able to edit and rerun the scenarios. Advanced demonstrations enter the library when their models are verified and need not delay the core library.

### Card 6 — Final product verification

Add the material comparison to the existing preset exercise and carry the material assignment and provenance checks into the blank-canvas exercise. In the native app, load a recognizable profile, inspect its properties and evidence, assign it to an editable body, and calculate the response. Substitute a materially different profile, measure and compare the changed result, and explain which conclusions are quantitative, qualitative, or illustrative. A profile picker alone does not satisfy acceptance. Keep the refinement and computational stress exercises, regression evidence, native walkthrough, and personal user acceptance. Verify the shipped Card 7 scenario workflow before release.

## Material model specifications and source references

### Common framework

Before adding a model, inspect how the current Swift solver receives deformation, advances internal state, calculates stress, and accounts for energy. Preserve the validated finite-deformation framework. In the reference configuration, momentum balance is

$$
\rho_0\ddot{\mathbf u}=\operatorname{Div}\mathbf P+\rho_0\mathbf b .
$$

Here \(\rho_0\) is reference density, \(\mathbf u\) is displacement, \(\mathbf P\) is first Piola–Kirchhoff stress, and \(\mathbf b\) is body acceleration. Derive any transformation between infinitesimal and finite-deformation formulations. Verify the stress measure, objective update, flow rule, and work conjugacy. State whether a 2D model uses plane strain or plane stress and explain its out-of-plane assumptions.

For 3D isotropic linear elasticity, with Young’s modulus \(E\) and Poisson’s ratio \(\nu\),

$$
G=\frac{E}{2(1+\nu)},\qquad
K=\frac{E}{3(1-2\nu)},\qquad
\lambda=\frac{E\nu}{(1+\nu)(1-2\nu)},\qquad
\boldsymbol\sigma=2G\boldsymbol\varepsilon+\lambda\,\operatorname{tr}(\boldsymbol\varepsilon)\mathbf I .
$$

Check positivity and admissibility of elastic inputs. The model interface should carry identity, units and parameters, element kinematics and prior state, updated stress and state, recoverable energy, dissipation increments, any stable-timestep contribution, and fields available for display. Track recoverable elastic energy, plastic and viscous dissipation, damage or fracture energy, contact work and energy, external work, and kinetic energy where applicable. Account for dissipated and stored energy separately.

### Material data and provenance

Record a stable identifier, display name, family, alloy or grade, temper or processing condition, density, elastic constants, constitutive law and model version. Include plastic, damage, fracture, rate, and thermal parameters where supported. Record source citations or URLs, product form, reference temperature, applicable strain-rate range when known, uncertainty, simplifications, and unsupported behavior. Track provenance per parameter or calibrated set. Values for one part of a model establish evidence for that part only.

- **Reference-backed.** A traceable source supports the relevant values. Identify any remaining calibration gaps and whether each value is typical, a minimum, or an estimate.
- **Representative / approximate.** The values support exploration within stated limits. Identify assumptions and incomplete calibration.
- **Illustrative.** The values demonstrate model behavior without claiming to characterize a specific material condition.

Show the selected material’s explanation, actual model, numerical inputs, represented and unsupported behaviors, evidence, and constitutive preview where applicable. Explain unavailable model combinations. Save custom profiles independently of recoverable built-ins. Attribute hardening, failure strains, fracture toughness, and rate coefficients to real materials only when the data support that attribution.

| Starting candidate | Density (kg/m³) | Young’s modulus (GPa) | Poisson’s ratio | Initial yield (MPa) |
|---|---:|---:|---:|---:|
| Structural carbon steel, A36-like | ~7,850 | ~200 | ~0.30 | ~250 |
| Stainless steel 304, annealed | ~8,000 | ~193 | ~0.29 | ~205 |
| Aluminum 6061-T6 | ~2,700 | ~68.9 | ~0.33 | ~276 |
| Copper C11000, annealed | ~8,940 | ~117 | ~0.34 | ~70 |

These are preliminary candidates. Before treating a value as reference-backed, verify the material condition, product form, temperature, strength definition, and uncertainty with a primary or authoritative source. Prefer data from one consistent material condition. Where no reliable hardening curve is available, retain source-backed elastic values and label optional plastic behavior as illustrative. Aluminum 5083, Ti-6Al-4V, and hardened high-strength steel are later candidates when the data and model support them.

Candidate sources for the implementation session are [NASA MAPTIS](https://maptis.nasa.gov/), [NIST Materials Data Repository](https://www.nist.gov/programs-projects/materials-data-repository), [ASM/MatWeb 6061-T6](https://asm.matweb.com/search/SpecificMaterial.asp?bassnum=MA6061T6), [Copper Development Association C11000](https://alloys.copper.org/alloy/C11000), [Aperam stainless steel technical data](https://www.aperam.com/), and [Abaqus constitutive model documentation](https://docs.software.vt.edu/abaqusv2026/). Check access, reuse rights, and calibration coverage independently. Use citations and manually curated profile records where necessary. Respect restrictions on scraping and dataset redistribution.

### J2 metal plasticity

With Cauchy stress \(\boldsymbol\sigma\), deviatoric stress \(\mathbf s\), and accumulated equivalent plastic strain \(\bar\varepsilon^p\),

$$
\mathbf s=\boldsymbol\sigma-\tfrac13\operatorname{tr}(\boldsymbol\sigma)\mathbf I,\qquad
q=\sqrt{\tfrac32\mathbf s:\mathbf s},\qquad
f=q-\sigma_y(\bar\varepsilon^p)\leq0,\qquad
\sigma_y=H(\bar\varepsilon^p).
$$

J2 is pressure-insensitive. Pressure-sensitive crushing, concrete failure, and foam densification require different formulations. Define table interpolation, extrapolation, and rejection of invalid entries. Use a monotonic or justified regularized hardening curve. For monotonic uniaxial tests before necking, the usual conversions are

$$
\sigma_{\rm true}=\sigma_{\rm eng}(1+\varepsilon_{\rm eng}),\qquad
\varepsilon_{\rm true}=\ln(1+\varepsilon_{\rm eng}),\qquad
\varepsilon^p_{\rm true}\approx\varepsilon_{\rm true}-\sigma_{\rm true}/E .
$$

Use a separate calibration procedure for post-necking data. The conventional small-strain radial-return relation and its linear-hardening specialization are

$$
q_{\rm trial}-3G\Delta\gamma-\sigma_y(\bar\varepsilon_n^p+\Delta\gamma)=0,\qquad
\Delta\gamma=\frac{q_{\rm trial}-\sigma_y(\bar\varepsilon_n^p)}{3G+H'} .
$$

Use these relations as references when evaluating the existing finite-deformation update. Verify uniaxial elasticity, yield onset, monotonic hardening, unloading with permanent strain, reloading, work partition, mesh and timestep sensitivity, and a comparison between different parameter sets. Display the curve the selected model actually consumes. A future \(\sigma_y(\bar\varepsilon^p,\dot{\bar\varepsilon}^p,T)\) law may use calibrated Johnson–Cook, Perzyna, or another suitable model after independent justification.

### Brittle fracture and cohesive interfaces

A simplified tensile criterion \(f_t=\sigma_1-f_t^{\rm crit}\) describes initiation from maximum principal stress. Propagation needs a separate law, regularization, and evidence for energy dissipation and crack-path behavior. For cohesive separation,

$$
G_c=\int_0^{\delta_f}t(\delta)\,d\delta,\qquad
G_c=\tfrac12t_{\max}\delta_f\quad\text{for a triangular traction–separation area}.
$$

Retain the verified cohesive insertion and Version 0.8 and 0.9 contact behavior. Account for initial stiffness, insertion, damage state, opening definition, and mode mixity. Keep bulk damage separate from interface failure. Failure-capable interfaces can use their own normal and shear strengths, mode-I and mode-II fracture energies, and mixed-mode criterion. Permanent bonds remain intact under the permanent-bond model. Glass and ceramic profiles may use simplified tensile behavior with explicit limits on crushing, confinement, pulverization, and 3D crack networks. Verify tensile opening, traction–separation, work of separation, compression, mixed mode when supported, opening and recontact, refinement, and conservation through topology changes.

### Advanced constitutive families

**Hyperelastic elastomers.** A candidate compressible neo-Hookean potential uses \(W=\mu(\bar I_1-3)/2+K(J-1)^2/2\), with \(J=\det\mathbf F\), \(\bar I_1=J^{-2/3}I_1\) in 3D, and \(\mathbf P=\partial W/\partial\mathbf F\). It needs finite-strain kinematics, suitable 2D reduction, deformation data, and a stable treatment of near-incompressibility that checks locking and timestep effects. Verify uniaxial deformation, shear, volume response, unloading, and an independent energy comparison.

**Viscoelastic polymers and interlayers.** A candidate relaxation modulus is \(G(t)=G_\infty+\sum_iG_i e^{-t/\tau_i}\). Use calibrated relaxation times and moduli, history variables, stable time integration, and viscous dissipation. Verify relaxation, cyclic loading, and comparison across loading rates. An ordinary J2 law represents plastic flow.

**Orthotropic composites.** A candidate plane-stress relation in material coordinates is

$$
\begin{bmatrix}\varepsilon_1\\\varepsilon_2\\\gamma_{12}\end{bmatrix}
=
\begin{bmatrix}
1/E_1&-\nu_{21}/E_2&0\\
-\nu_{12}/E_1&1/E_2&0\\
0&0&1/G_{12}
\end{bmatrix}
\begin{bmatrix}\sigma_1\\\sigma_2\\\tau_{12}\end{bmatrix},
\qquad \nu_{12}/E_1=\nu_{21}/E_2 .
$$

Use independent directional data, enforce positive definiteness and reciprocity, and rotate the constitutive tensor by material orientation. Verify axial, transverse, shear, and rotated tests. Woven behavior and fiber failure require their own models and checks.

**Crushable foams and cellular cores.** Use a documented pressure-sensitive yield surface and volumetric hardening law, such as a suitable Deshpande–Fleck formulation. The inputs include \(p=-\operatorname{tr}(\boldsymbol\sigma)/3\), the J2 equivalent stress \(q\) defined above, and volumetric plastic state. Verify irreversible compaction, the crush plateau, densification, work accounting, and rate effects where supported. Explicitly meshed honeycomb walls can buckle as a structure. Distinguish that response from homogenized material crushability.

**Concrete and pressure-sensitive brittle solids.** A suitable Drucker–Prager-type or damaged-plasticity formulation needs data and controls for tensile and compressive response, confinement, irreversible deformation, and regularized damage or fracture energy. Verify tension, compression under different confinement, stiffness degradation, and energy across mesh sizes.

**Dynamic thermomechanics.** A candidate energy balance is \(\rho c_p\dot T=\beta\boldsymbol\sigma:\dot{\boldsymbol\varepsilon}^{p}+\text{heat-transfer terms}\), with \(\beta\) the calibrated or assumed fraction of plastic work converted to heat. Require compatible thermal parameters and boundary conditions, thermodynamic consistency, and verified heating and heat transfer. Localization and extreme-rate flow require separate kinematic, mesh regularization, and coupled-model validation.

### Verification gate for any new family

Start with a minimal standalone control and use analytically tractable tests where possible. Check equations, units and stress measures, state updates, conservation and dissipation, loading and unloading, timestep sensitivity, relevant mesh sensitivity, and pathological inputs. Verify material selection and editing in the app and confirm that reopening a saved scene reconstructs the same model and parameters. Run focused regressions for substantive changes. Use numerical verification to establish whether the implementation solves the stated model and experimental validation to establish whether the model represents the material.

## Card 1 checkpoint

Commit `dded9a2` on `main` ships the native assembly editor. In the running app, scroll zoom held the point under the cursor. Fit Assembly showed a body moved to X = 900 mm, and Zoom to Selection brought the thin block into view. Moving, rotating, and resizing a body updated the inspector. During playback, selection and camera navigation remained available, and dragging left the starting geometry intact.

Native undo and redo restored the edited values. Save and Open restored the same position, dimensions, and rotation, and Open prompted before replacing unsaved edits. The existing launcher opened the release app. `ImpactCheck --assembly`, `ImpactCheck --experiment-library`, and `git diff --check` passed. Physical trackpad pinch remains untested.

## Card 2 verification

The implementation checkpoint is `5317179` on `main`.

In an isolated native release build, a blank assembly became a round driver, a plate with three permanently bonded materials, and a rotated deformable support. The plate and support were aligned and spaced 10 mm apart. A spring was placed by clicking its two material anchors. The native mesh report showed 526 triangles after refining the plate. Saving and reopening preserved the geometry, materials, refinement, group, and spring.

The reopened assembly ran to 120.00 ms. The app recorded first contact at 20.00 ms and showed 43.55 N/m of spring load at 97.50 ms. Group movement with 5 mm snapping, duplication, reordering, delete and undo, breakable-link placement, and overlap validation were also exercised in the app. `ImpactCheck --assembly`, `ImpactCheck --assembly-study`, and `ImpactCheck --experiment-library` passed.

The Workshop Limits panel documents the available geometry and mechanical relationships. Supports can move and deform under load. Fixed and clamped boundaries, rigid joints, imported outlines, and arbitrary cracks are unavailable. Round bodies and bonded blocks have no material-fracture control.

# Phase 0 decision — Build the bar impact first, then grow the working sandbox

**Version 0.1A begins with one launchable experiment.** Open the app, run a deformable bar into a wall, pause on the compression wave, change the stiffness, and run it again. The measured wave should arrive sooner in the stiffer bar. That single interaction exercises the solver, contact, renderer, controls, and a scientific prediction. Add the ring and tilted block to that working application one at a time.

## Agreed architecture

- **Physics.** Use explicit 2D Lagrangian FEM in plane strain, three-node constant-strain triangles, lumped nodal masses, central-difference integration, and compressible neo-Hookean elasticity. Use SI units, double precision, and report forces and energies per metre of out-of-plane depth. Begin with moderately compressible materials and modest impact speeds.
- **Application.** Use a small headless CPU solver and a separate renderer that reads computed positions, strain, and diagnostics. The provisional Mac-native choice is Swift with SwiftUI Canvas, built with the local Apple toolchain. Use the same simulation step for interactive playback and headless verification. Display simulated time and advance physics independently of the display refresh rate.
- **Anticipate two bodies in 0.1A.** Give each deformable body its own reference mesh, current nodal state, material assignment, and identifiable exterior edges. Keep contact forces separate from element forces. In 0.1A, the only contact calculation is a boundary node against an analytic fixed plane, with compressive penalty force weighted by tributary edge length. This leaves a place for two-body forces in 0.1B without building a general contact engine in advance.

## Version 0.1A — First complete application

| Task and user-visible result | Smallest implementation | Scientific verification and completion gate | Critical dependency or blocker |
|---|---|---|---|
| **A1. Launch and rerun a bar impact.** [x] The user can run, pause, reset, and change stiffness or initial speed. | One generated rectangular mesh, one fixed wall, one material, and one window. Draw the computed outline and axial strain. Show simulated time and a strain trace at a marked station. | Run a low-amplitude case with \(\nu=0\). From first wall contact, arrival at a probe a distance \(L_p\) away should approach \(L_p/\sqrt{E/\rho_0}\). Quadrupling \(E\) should approximately halve that time. Stop when this works from the normal app launcher and reset reproduces the trace. | Requires a local compiler and a stable step accounting for both element and wall-contact stiffness. These belong in the first task. |
| **A2. Inspect the bar result.** [x] The user can single-step and judge whether a run is numerically credible. | Add timestep, maximum wall penetration, wall impulse, and energy imbalance to the same window. Include kinetic, elastic, and contact-penalty energy at consistent time levels. Expose density and bounded Poisson ratio alongside stiffness and speed. | Verify zero internal force under rigid translation and rotation, uniform stress in an affine patch, and agreement between wall impulse and change in body momentum. For the reference bar, require under **5% arrival-time error** and under **1% peak energy imbalance** relative to initial kinetic energy. Refine space and time separately and vary the penalty to expose sensitivity. | Use the A1 solver directly. A short verification command is sufficient. |
| **A3. Select a ring and watch it ovalize.** [x] | Add a thick-walled annular mesh to the preset selector. Plot horizontal and vertical diameters through impact and rebound. | Resolve the wall with several triangles through its thickness. Compare the first ovalization period and peak diameter change on successively finer meshes. Stop when both change by under **5%** on the final refinement and the shipped preset meets that comparison. | Constant-strain triangles can make bending too stiff. Increase through-wall resolution if this gate fails. |
| **A4. Select a tilted block and watch it turn.** [x] | Add a rounded-corner block with an initial tilt. Show its orientation and the accumulated wall impulse. Use the existing wall contact and material law. | Mirroring the tilt should reverse the rotation and preserve the normal impulse magnitude within discretization error. Check angular-momentum change against integrated wall torque. Stop when all three presets pass through the same select, edit, run, pause, inspect, and reset workflow. | The corner needs adequate boundary resolution. Rigid rotation must already pass A2. |

The 5% and 1% values are **proposed release tolerances**, with no measured results yet. Stop a run before accepting an inverted element or non-finite state and show the reason. Under load, let playback slow while preserving the physical timestep.

## Subsequent releases — One working experiment at a time

| Release and runnable demonstration | Minimum addition | Verification and stopping condition | Dependency or limit |
|---|---|---|---|
| **0.1B — Two deformable bodies collide and separate.** [x] Start with two aligned elastic bars. Then add a rounded puck striking a free rectangular strip so the player can inspect deformation in both. | For these bounded presets, detect contact between exterior nodes and opposing boundary segments in the current configuration. Apply normal-only compressive forces and distribute the equal-and-opposite reaction to both segment endpoints using the contact location. Handle separation, duplicate corner contacts, and missed crossings within the allowed speed range. | In an isolated equal-bar collision, check the expected small-amplitude exchange of velocities, total linear and angular momentum, and energy including the contact penalty. For the puck and strip, check separation, bound overlap relative to local edge size, and repeat with finer boundaries and smaller steps. Ship when both demos pass and 0.1A still runs. | **Highest implementation risk.** A fixed wall can absorb an unbalanced reaction silently. Two free bodies expose it. Keep the supported shapes and speeds bounded. Friction, self-contact, and arbitrary geometry can wait. |
| **0.2 — Configure and compare experiments.** [x] Edit a preset, save it, reopen it, and compare two runs at matching simulated times. | Add dimensions for the existing shape families, per-body elastic materials, initial positions and velocities, and local configuration files. Include a bonded two-material bar with a shared-node interface. | A saved scene must reproduce its traces. In the small-amplitude bonded-bar case, verify the reflected wave against the 1D impedance prediction, including vanishing reflection for matched impedances. Stop when the full edit–save–reopen–compare workflow works on a two-body scene. | Depends on the bounded contact envelope established in 0.1B. Keep the editor within it. |
| **0.3 — Compare elastic recovery with permanent set.** [x] Run the same specimen and loading with elastic and elastoplastic materials. | Add one rate-independent \(J_2\) model with isotropic hardening, per-element plastic history, and the out-of-plane stress required by plane strain. Display accumulated plastic strain and a residual dimension after unloading. | Check yield onset, unloading slope, residual strain, and nonnegative plastic dissipation against a material-point load–unload solution. Ship when permanent set is measurable after unloading and persists under refinement. | Requires a constitutive update consistent with the solver’s rotation and stress conventions. |
| **0.4 — Open a bonded seam in a layered specimen.** [x] Let the player compare an intact bond with one that separates. | Add one predefined cohesive interface with a traction–separation law, fracture energy, and compressive contact on reclosure. Display opening and dissipated fracture energy. | In pure opening, verify that work per fully separated area approaches \(G_c\). Refine along the seam and check the force–opening curve and total dissipation. Stop with this one verified separation mechanism. | Requires independently moving interface faces. Arbitrary crack paths, fragmentation, 3D, and multiphysics remain later decisions. |

## Execution gates

- **End-of-Turn Handoff Protocol.** Follow the permanent protocol in [the project instructions](AGENTS.md#project-audit-and-end-of-task-handoff) at the end of each development task.
- **Preserve the runnable product.** Start each task from the last demonstrated Git checkpoint. End it by launching the app through its normal entry point, exercising the new interaction, running the focused physics check, and checkpointing the working result. Keep all earlier presets available. If Git needs initialization, scope the initial commit to the application files.
- **Control cost on the actual Mac.** Start with roughly 2,000 triangles or fewer per preset where accuracy allows. Measure time per physics step and simulated time advanced per wall-clock second during sustained playback on the M4 Air. Treat mesh size as a starting estimate. Bending accuracy and contact stability decide the usable resolution. Reconsider MPM only if a required scenario repeatedly loses mesh quality before reaching the deformation of interest.
- **Interrupt stalled work.** After two consecutive implementation turns without a demonstrable user-visible improvement, pause before a third. Use the existing local Codex auditor to summarize recorded usage, identify the specific blocker, and name the smallest action that can restore visible progress. Reuse the last working checkpoint and keep the review brief.
- **End planning here.** The foundation, first interaction, analytical reference, and stopping conditions are decided. Approval and a switch to normal execution mode are the only prerequisites to starting A1. Later contact details can be settled against the running examples. Verification supports claims about the numerical model. Real-material or ballistic predictions would require independent experimental validation.

**Recommended first implementation task for Codex in normal execution mode:** Complete **A1 only**. Deliver the launchable bar-impact window, demonstrate the stiffness change against the predicted wave-arrival change, and checkpoint that working application.
