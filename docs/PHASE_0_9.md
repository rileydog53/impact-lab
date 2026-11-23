# Impact Lab 0.9

## Experiments in the native app

- **Bonded wave transmission.** Open **New / Examples → Load bonded wave example**. The striker sends a pulse into a two-material elastic specimen. Choose **Mean pressure** to see the wave and **Study → Single run** to plot the gauges on either side of the bond. Edit the second material's modulus or density to change its impedance. Set it equal to the first material for a matched control. The straight interface shares nodes and stays bonded.
- **Notched bending.** Load the bending example, select the specimen, and enable **V-notch on local bottom edge**. Set its offset, width, and depth. Place gauges on opposite sides of the notch before running. The gauge positions follow their material triangles as the mesh splits. A body can use a factor up to ×7 while the striker, supports, and receiver retain their own mesh settings.
- **Resolution and timestep studies.** Under **Study**, refine one body or the full assembly at a common timestep. **Timestep halving** runs the same geometry and mesh at nominal, half, and quarter step. The cases run independently on CPU cores. The chart and CSV use accepted solver states at about 0.25 ms intervals. The CSV includes each body's actual mesh factor, the timestep, gauge histories, contact measurements, fracture readings, and the energy ledger. Save the assembly JSON alongside the CSV to retain the geometry and materials.

Pressure is the negative mean of the three plane-strain Cauchy normal stresses. Positive values indicate compression. Gauge position and velocity use the triangle's interpolation, while stress and strain come from the containing element. Put gauges inside the material on the side of an interface you want to measure. The chart connects sampled values. The scalar normal load sums positive contributions from the contact quadrature, and its integral is a scalar measure. Peaks and impulse use every accepted step. Force peaks remain sensitive to contact compliance and mesh spacing.

## Experiment library

Open **Assembly → Experiments** to preview and load an inclined plate, separated plates, a three-layer bonded composite, a hollow sandwich, or independently angled panels. Choose free bodies or deformable end supports and set the starting mesh. Supports have mass and move under load. The composite shares nodes at two permanent elastic bonds. The hollow sandwich has a cavity and a common thickness for its faces and side walls.

Select a body to edit its position, angle, initial velocity, and mesh. Ordinary plate thickness is its local height. Composite thickness is its local width because the preset rotates the coupon 90°. The hollow panel's **Wall** setting changes both faces and side walls. **Material** offers four illustrative profiles as well as direct parameter edits. The profile values are numerical examples and have no real-material calibration.

Preset gauges follow proportional positions when the geometry is resized. **Study** records their histories along with contact loads and the energy ledger. Material fracture remains optional on supported homogeneous bodies. Treat coarse fracture previews as qualitative and run mesh and timestep comparisons for quantities of interest.

All ten preset and boundary combinations completed in the focused check with peak sampled energy residual below 0.07% and peak relative overlap at or below 0.51%. In the separated-plates fixture, the striker reached the front plate at 2.54 ms and the front plate contacted the receiver at 14.78 ms. The striker impulse through 20 ms changed 1.11% between ×2 and ×3 at a common 2.399 µs timestep. Changing only the rear panel angle from 9° to 4° shifted inter-panel contact from 20.87 to 25.87 ms in the coarse preview. Run `ImpactCheck --experiment-library` to reproduce these checks. The native library smoke test opened the sheet, loaded the supported composite, edited thickness and material, and advanced to contact.

## Measured checks

| Check | Result |
| --- | --- |
| Bonded wave, small-amplitude impedance control | Velocity reflection −0.3379 vs −0.3333 analytically. Transmission 0.6765 vs 0.6667. Peak sampled energy residual 0.0234%. |
| Bonded wave, common 3.867 µs step | Transmitted velocity over the early pulse window was 0.03473, 0.03489, and 0.03361 m/s at ×2, ×3, and ×4 on the specimen. The sampled velocity varied by about 4% across these meshes. |
| Bonded wave, three independent mesh cases | 1.101 s serial and 0.595 s parallel, or 1.85× faster. Serial and parallel runs agreed exactly on the compared sample times, gauge velocities, energy residuals, and scalar impulses. |
| Authored V-notch | The notch tip and area matched the specified geometry at ×1–×7. In the ×3 demonstration, insertion began at 4.950 ms and the solver reported three pieces at 30 ms. Peak sampled energy residual was 0.0105%. The two gauge histories remained available through insertion. |
| Selective refinement, 20 ms elastic five-body bend | At the same 0.740 µs step, changing the apparatus from ×5 to ×2 while keeping the specimen at ×5 reduced triangles from 9,300 to 3,756 and wall time from 4.797 s to 1.961 s. Striker impulse changed by +2.736%. |
| Self-contact, centered aligned ×5 at 0.225 µs | The 0.8 build from `1fd5e7f` took 27.997 s. The 0.9 build took 22.471 s, or 1.25× faster, with identical reported observables. Peak RSS rose from 14.91 to 15.83 MiB. Both runs used about one core. |
| Resource use | The complete study check took 13.698 s wall time and 14.112 CPU-seconds. Process peak RSS was 19.95 MiB and the OS reported zero process swaps. |

Measurements used the 16 GB M4 MacBook Air. Run `ImpactCheck --assembly-study` for the new experiment checks. The self-contact comparison used `ImpactCheck --fracture-convergence aligned 5 0.225`.

The default checker, contact handoff, and the full six-case fracture convergence check passed. Fixed-position contact-energy changes at splitting and detachment were zero in the two tested half-step handoff cases. At ×6→×7, notch-crack energy changed by 0.51% for the aligned mesh and 0.12% for the staggered mesh. Through-crack times changed by 8.28% and 29.18%, respectively.

Start the app with `./launch.command`. The native study smoke test exercised authoring through the assembly model, opened the rendered study sheet, ran a three-level mesh study, and exported CSV. The assembly and verified-presets smoke tests also passed.

## Numerical scope

The 0.8 solver already had extrinsic cohesive insertion, cached stress recovery, and a refitted self-contact BVH. Version 0.9 caches the shared-vertex stencil when it rebuilds contact candidates. The current step still checks the geometry of each candidate. Per-body refinement reduces the number of elements advanced at every step. The smallest stable timestep still controls the whole assembly.

The bonded-wave results apply to small-amplitude elastic motion in this fixture. Breakable assembly links remain a separate model from the bonded specimen. Within-body mesh-size fields, within-step parallelism, a new inter-body BVH, and changes to the constitutive laws remain open.

The established 0.8 fracture limits apply. Coarse ×1–×3 fracture runs are qualitative. The centered fixture showed useful fracture-energy convergence at fine meshes, with ×5 as a fixture-specific observation. Cracks follow mesh edges. Completion timing, secondary trajectories, and receiver impulses remain resolution-sensitive. The late production-step contact-energy drift in the archived aligned case remains open.
