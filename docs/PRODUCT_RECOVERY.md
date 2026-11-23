# Impact Lab — Six-Phase Product Recovery and Expansion

**Project:** shopping(noVOL) / Impact Lab\
**Starting checkpoint:** `15e8a6d` on `main`\
**Execution environment:** Native Swift/macOS, Apple M4 MacBook Air, 16 GB unified memory\
**Primary developer:** GPT-6.2 SOL High

## Governing requirements

- Preserve the existing numerical solver, scientific regression tests, saved experiments, and reference releases.
- Deliver one coherent, increasingly usable application. These six phases do not have to become six separate version releases.
- Do not mistake implemented code, smoke tests, or release notes for a successful user experience.
- Prefer general mechanical terminology: body, striker, receiver, support, material, interface, fragment.
- Every displayed physical event must originate from calculated solver state. Visual interpolation and rendering effects must be distinguishable from physical results.
- Do not invent scientific validity, material calibration, performance gains, or numerical convergence.
- Work directly in the existing repository. Inspect current functionality before replacing or duplicating it.

---

# CARD 1 — Make the Application Usable

**Priority:** Critical\
**Primary goal:** Make the graphical interface understandable, responsive, and capable of manipulating experiments without fighting the software.

### Problem

The application technically supports graphical editing and computed experiments, but basic operations are difficult or inaccessible. Users cannot reliably inspect their current configuration, understand which controls are available, or see the consequences of edits.

### Implementation scope

**Canvas and navigation**
- Implement reliable cursor-centered zoom using scroll wheel and trackpad gestures.
- Add smooth panning, Fit Assembly, Reset View, and Zoom to Selection.
- Show the complete experiment clearly before simulation.
- Maintain a consistent camera and coordinate system between editing and playback.
- Provide sufficient visual detail to distinguish adjacent objects, boundaries, cavities, and layers.

**Object inspection and editing**
- Clicking an object selects it and identifies its name, material, dimensions, position, orientation, velocity, and constraints.
- Provide direct manipulation for moving, rotating, and resizing selected geometry.
- Synchronize numeric property controls and graphical handles.
- Make edits visibly update the assembly before running.
- Support undo and redo for meaningful editing operations.

**Interface clarity**
- Organize controls around geometry, materials, motion, constraints, mesh, and simulation.
- Remove misleading controls or explain why a feature is unavailable for the selected object.
- Make the active experiment and unsaved changes obvious.
- Replace unexplained numerical labels with clear terms, units, and tooltips.
- Preserve the distinction between editing an assembly and inspecting a computed run.

### Acceptance criteria

- A user can open the application, locate an object, zoom into it, select it, change its angle and size, and see the result immediately.
- The camera remains usable with multiple objects, distant bodies, and small features.
- All visible editing controls either work or explicitly identify a genuine limitation.
- Save, reopen, and undo preserve the expected assembly state.
- The developer demonstrates the workflow in the real native application.

**Deliverable:** A functional, navigable experiment editor.

---

# CARD 2 — Build a Genuine Assembly Workshop

**Priority:** Critical\
**Dependency:** Basic camera and editing functionality from Card 1

**Primary goal:** Let the user construct arbitrary supported mechanical arrangements rather than rely on a narrow selection of predefined demonstrations.

### Problem

The experiment library contains editable presets, but the application does not yet provide the construction freedom expected of a general-purpose mechanical sandbox.

### Implementation scope

**Assembly construction**
- Add bodies from a clear geometry palette.
- Support rectangular plates, blocks, circular or appropriately approximated bodies, hollow structures, and layered configurations where the solver supports them.
- Allow independent placement, rotation, dimensions, and material assignment.
- Support adding, duplicating, deleting, grouping, and reordering bodies.
- Provide snapping, alignment, spacing, and numeric positioning tools.
- Enable explicit construction of gaps, cavities, and multi-body arrangements.

**Connections and boundaries**
- Expose supported bonded interfaces, supports, constraints, and breakable connections.
- Distinguish permanent bonds from failure-capable interfaces.
- Clearly identify supported versus unsupported fracture configurations.
- Permit deformable or constrained supports with understandable boundary conditions.

**Mesh generation**
- Generate meshes from the authored geometry.
- Provide per-body refinement controls.
- Preview mesh topology before simulation.
- Identify invalid geometry, problematic element shapes, or incompatible interfaces.
- Keep authoring geometry separate from numerical mesh representation.

**Preset integration**
- Retain the existing experiment library as editable starting configurations.
- Loading a preset must produce ordinary editable assembly objects.
- Presets must use the same physics and editing workflow as manually constructed assemblies.
- Avoid bespoke behavior that only works inside a preset.

### Acceptance criteria

- Starting with an empty canvas, the user can construct a multi-body assembly with several independently positioned deformable components.
- The user can adjust thicknesses, gaps, orientations, and materials directly.
- The assembly can be meshed, saved, reopened, calculated, and inspected.
- The system clearly identifies unsupported operations instead of silently disabling features.
- Construction does not require editing source code or hidden configuration files.

**Deliverable:** A practical, general-purpose mechanical assembly workshop.

---

# CARD 3 — Make Materials and Physical Conditions Meaningful

**Priority:** High\
**Dependencies:** Functional property editing and assembly construction

**Primary goal:** Make physical inputs understandable, editable, and scientifically accountable.

### Problem

Existing material profiles are described with abstract labels such as "elastic stiff" or "yielding J2 solid." These expose constitutive behavior but are not intuitive material choices, and the user cannot easily determine whether an experiment contains enough initial energy or appropriate boundary conditions to produce meaningful motion.

### Implementation scope

**Material system**
- Provide a searchable material library with understandable descriptions.
- Include documented reference profiles where enough defensible material information exists, alongside explicitly labeled illustrative profiles.
- Show density, elastic modulus, Poisson's ratio, yield strength, hardening parameters, and fracture parameters where supported.
- Display units and source or calibration status.
- Allow duplication and editing of materials without changing the original reference.
- Distinguish elastic-only, plastic, and fracture-capable material models.

**Physical conditions**
- Provide clear controls for initial velocity and direction.
- Support appropriate fixed, constrained, freely moving, and elastically supported conditions.
- Expose supported applied loads and initial displacements.
- Show mass and relevant momentum or kinetic-energy values where applicable.
- Include an initial-condition preview with velocity vectors and constrained regions.
- Warn when an experiment is static, when bodies cannot interact during the configured time window, or when incompatible settings are chosen.

**Model limitations**
- State which material behaviors the current solver can represent.
- Do not label illustrative solver parameters as validated real-world material data.
- Do not promise unsupported thermal, high-pressure, extreme-rate, or complex fracture behavior.
- Preserve the ability to expand constitutive models later.

### Acceptance criteria

- The user can choose a material, inspect its physical parameters, modify it, and observe the change in a computed experiment.
- The user can set an initial velocity and clearly see its direction and magnitude before running.
- An experiment preview identifies its major constraints and motion conditions.
- Numerical material inputs use consistent units.
- Material profiles are honest about their source, assumptions, and validity.

**Deliverable:** An understandable, editable physical-input system.

---

# CARD 4 — Make the Calculated Physics Visible

**Priority:** Critical\
**Dependencies:** Usable canvas and working experiment configuration

**Primary goal:** Make it possible to observe, inspect, and explain the physics that the solver calculates.

### Problem

Scientifically meaningful calculations are of limited value if deformation, stress propagation, fracture, contact, and energy transfer are too small, too unclear, or too difficult to inspect.

### Implementation scope

**Simulation playback**
- Separate numerical solving from visual replay.
- Provide play, pause, step, restart, variable playback speed, and timeline scrubbing.
- Maintain reliable camera navigation during playback.
- Permit frame inspection without recalculating the experiment.
- Make it easy to jump to meaningful recorded events.

**Geometry and deformation**
- Render actual computed body geometry and deformation.
- Show opening cracks, detached fragments, and secondary contacts when supported and calculated.
- Distinguish intact bonds, damaged interfaces, and separated surfaces.
- Provide optional undeformed-geometry overlays.
- If displacement exaggeration is offered, label it prominently and retain access to true-scale rendering.

**Scientific fields**
- Display supported stress, strain, equivalent plastic strain, and damage fields.
- Include legible scales, units, color legends, and appropriate field ranges.
- Permit inspection of local values and changes over time.
- Visualize velocity vectors and contact interactions where numerical data is available.
- Clearly distinguish computed fields from interpolated display values.

**Instrumentation**
- Extend existing gauges into accessible virtual measurement tools.
- Display force, impulse, displacement, velocity, and energy histories as appropriate.
- Provide time-aligned plots and event markers.
- Show a conservation and energy-partition history.
- Preserve Study comparisons and CSV export.

### Acceptance criteria

- A user can visibly identify and inspect a meaningful calculated deformation or contact event.
- Zooming and panning work during replay.
- A user can select a time, inspect a field, and identify what the numerical data means.
- The application can distinguish actual physical separation from a visual rendering artifact.
- Comparison and gauge data correspond to recorded solver states.
- The developer demonstrates these interactions in the running application.

**Deliverable:** A scientifically informative simulation viewer.

---

# CARD 5 — Scale the Computational Engine

**Priority:** High\
**Dependencies:** Preserve numerical correctness and representative performance workloads

**Primary goal:** Make larger, adequately resolved simulations practical and expose the computer's actual computational behavior.

### Problem

The current solver generally executes an individual simulation on one CPU core. Fine meshes can become expensive, and the application does not adequately communicate progress, resource use, or why a simulation is slow.

### Implementation scope

**Performance instrumentation**
- Measure per-timestep computation cost.
- Profile bulk FEM calculations, contact detection, force assembly, fracture updates, and output recording.
- Report actual CPU usage, process memory, elapsed computation time, and numerical progress.
- Expose meaningful progress indicators during long calculations.
- Support cancellation and safe recovery from interrupted runs.

**Algorithmic improvements**
- Investigate unnecessary contact-pair checks and other measured hotspots.
- Reduce redundant geometry calculations, unnecessary allocations, and repeated computations.
- Retain existing numerical consistency through optimization.
- Evaluate data layout and memory-access efficiency where profiling supports changes.

**Hardware utilization**
- Retain and improve independent parallel experiment execution.
- Investigate multicore calculation within individual simulations when mesh size justifies it.
- Preserve deterministic or appropriately bounded numerical results.
- Evaluate GPU acceleration only where there is credible evidence of benefit.
- Avoid making thermal or memory assumptions without measurement.

**Resolution and scientific quality**
- Support larger meshes without arbitrary limits unsupported by actual resource measurements.
- Preserve per-body mesh resolution.
- Consider spatially graded meshes if justified and numerically verifiable.
- Distinguish coarse qualitative simulations from appropriately refined studies.
- Make convergence comparisons accessible through existing Study tools.

### Acceptance criteria

- Fine-mesh and multi-body performance is measured against the previous implementation.
- At least one meaningful optimization demonstrates a measurable benefit without invalidating the numerical results.
- Progress and resource consumption are visible during actual calculations.
- Long-running simulations can be managed without locking the entire application into an unusable state.
- Larger simulations remain reproducible and scientifically accountable.
- Any resource-related limits are justified by measurements.

**Deliverable:** A measured, scalable, and observable numerical engine.

---

# CARD 6 — Prove the Complete Product Works

**Priority:** Release-blocking\
**Dependencies:** The usable workflows from Cards 1–5

**Primary goal:** Demonstrate that Impact Lab satisfies its intended purpose as a scientific experimentation environment.

### Problem

Previous releases passed extensive numerical and smoke tests while still failing the user's first practical interaction with the application.

The final acceptance procedure must test the actual user experience, not merely individual subsystems.

### Implementation scope

**End-to-end manual verification**

Demonstrate these workflows in the actual macOS application:

**Experiment A — From a blank canvas**
- Create multiple bodies with different geometries.
- Assign editable materials.
- Define initial positions, velocities, and constraints.
- Select an appropriate mesh.
- Run the simulation.
- Inspect deformation, contact, and physical measurements.
- Save and reopen the experiment.

**Experiment B — From an existing preset**
- Load an experiment.
- Modify geometry and a material parameter.
- Run the original and modified configurations.
- Compare relevant physical measurements.
- Inspect both results visually.

**Experiment C — Scientific refinement**
- Choose a suitable reference problem.
- Run multiple mesh or timestep resolutions.
- Compare numerical observables.
- Identify which results are converged, uncertain, or qualitative.
- Export the results.

**Experiment D — Computational stress test**
- Construct a larger supported assembly.
- Run an adequately instrumented simulation.
- Observe CPU use, memory consumption, progress, and solver timing.
- Confirm that the program remains controllable.
- Preserve the numerical evidence and identify actual resource limitations.

**Usability review**
- Verify zoom, pan, selection, property editing, and playback.
- Investigate controls that do not visibly affect the configuration.
- Eliminate misleading labels and unexplained restrictions.
- Confirm that experiments are understandable without knowing their source code.
- Verify that presets are genuinely editable and not special-case demonstrations.

**Release evidence**
- Supply actual application screenshots or a brief recorded walkthrough.
- Document completed user actions, measured results, and remaining blockers.
- Identify any features that exist in code but are not accessible in the GUI.
- Run relevant numerical regression checks.
- Do not declare the product complete merely because a test suite passes.

### Acceptance criteria

- All four end-to-end experiments can be completed through the real application.
- The user can create, modify, run, observe, and compare meaningful physical configurations.
- The application remains understandable and controllable during computation and playback.
- Numerical limitations are visible rather than concealed.
- The user personally tests the result before the product milestone is accepted.

**Deliverable:** A demonstrably usable scientific impact laboratory.

---

## Execution rules

**Order:** Card 1 → Card 2 → Card 3 → Card 4 → Card 5 → Card 6, with overlapping implementation where sensible.

Card 6's real-user workflow checks should inform development throughout, not only at the end.

Each card must conclude with:
- Actual implemented functionality.
- A working native application demonstration.
- Relevant verification evidence.
- Known limitations.
- A clear pass/fail against the card's acceptance criteria.

Do not mark a card complete because its source code exists. Do not claim the user experience has been verified when only automated tests have run.

Keep the present numerical foundations intact. Avoid replacing scientifically defensible calculations with scripted outcomes or attractive but misleading animations.

**The project succeeds when the user can freely construct supported physical experiments, understand and control their inputs, run actual numerical physics, observe the consequences, and investigate the results.**
