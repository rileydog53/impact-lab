# Version 0.5 · Off-axis impact

Launch `./launch.command` and run **Off-axis impact**. The striker hits the facing layer off-center. The backing can detach, translate and rotate, then hit a separate deformable receiver. The clocks under the viewport mark the first striker–facing contact, complete bond failure, and first backing–receiver contact. They report solver events and can occur in a different order or be absent in an edited scene.

Open **Initial conditions** to change the clearances, offsets, initial striker and receiver angles, initial velocity components, and duration (75–220 ms). The striker velocities are relative to the initially co-moving specimen layers. Receiver velocities are in the lab frame. Each body has dimensional and material controls. The striker and facing can use the elastic or J2 elastoplastic material, and the backing and receiver are elastic. Open **Seam settings** for the strength and critical link extension. Use quarter-speed playback or **+1 ms** to inspect contact, and pin a reference to compare backing rotation, receiver X velocity or plastic dissipation on a common time grid.

## Numerical model

The four bodies use the existing explicit plane-strain triangular FEM. Normal-only penalty contact evaluates all six pairs of exterior boundaries, including the layer pair during and after failure. The facing and backing start 1.5 mm apart with prescribed tensile links between matching reference nodes. A link follows the existing bilinear cohesive law in chord extension. It is slack in compression, where the body contact solver carries the load. Link forces act along the chord and the irreversible damage law carries no force after full failure. Reported seam tension is a sum of link force magnitudes, and extension measures the original pairs even after they break.

The links model a thin bridging bond. There is no independent shear law or general mixed-mode delamination criterion. The four prescribed meshes and one prescribed interface are the supported assembly. Contact is discrete, frictionless, and lacks continuous collision detection and self-contact. Local contact strain and penetration depend on mesh size. Finer meshes are especially important for interpreting local peaks. Test results support the cases below. Bulk crack growth, fragmentation, spall, melting, and three-dimensional effects are outside the formulation.

## Verification on the release preset

Run `swift run --disable-sandbox -c release ImpactCheck --off-axis` for the focused checks or omit `--off-axis` for all numerical regressions.

| Measurement | Result |
|---|---|
| Events over a 110 ms run | First strike 5.232 ms, all links failed 12.723 ms, backing hit receiver 35.273 ms |
| Backing motion from failure to receiver contact | 14.12 mm center-of-mass travel, 22.31° additional rotation, and 0.95 mm sampled clearance from the facing during flight |
| Receiver response | No pre-contact velocity change above the numerical tolerance. Maximum change 0.533 m/s and peak element axial strain about 6.50% |
| Peak conservation residuals | Linear momentum 4.92 × 10⁻¹⁵ and angular momentum 4.73 × 10⁻¹⁵, normalized by striker momentum and striker momentum times layer height, respectively. Angular momentum is evaluated about the global origin. Peak energy error 0.009% of initial kinetic energy |
| Penalty and fracture | Peak penetration 1.26% of the contacted edge length. Stored energy, contact penalty, hardening, plastic dissipation, and fracture dissipation are included. Cohesive work and dissipation both 0.97500 J/m² at full failure, matching the specified Gc |
| Time and mesh sensitivity | Halving the timestep changed the main measurements by at most 0.22%. Doubling mesh divisions in both directions at the same smaller timestep changed them by at most 4.27%. Peak receiver element strain rose from 6.47% to 7.45% |
| Controls | Reflecting the geometry reversed the backing rotation with the same event times to the reported precision. Shifting the receiver clear removed its impulse. The intact control carried bond load and reached the receiver later, at 50.697 ms |

The native app smoke check also exercises edit, pause, single-step, millisecond-step, full playback, the plastic and seam-damage fields, exact replay after saving and reopening, and a comparison with a receiver moved farther away. The `--inspect-ms 38` launcher argument pauses at a computed frame for visual review. Click **Run** to resume.
