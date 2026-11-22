# Version 0.4 · Integrated Layered Impact

**Layered impact** opens by default. Press **Run** to launch a deformable striker into a two-layer specimen. The shipped run lasts about 68.8 ms. A reflected pulse opens the seam in tension. The detached backing then strikes a rigid stop, rebounds, and compresses the failed seam. Disable **Rigid backstop** under **Initial conditions** to let the layers drift freely. An **Intact** bond supplies a control with the same initial cohesive stiffness and no damage.

Edit the three region lengths, their elastic constants and densities, the striker and shared layer heights, the gap, closing speed, specimen drift, and optional stop clearance. The striker and facing use the plane-strain J₂ material model, with a shared choice of elastic or elastoplastic response and separate material scales. The backing uses neo-Hookean elasticity. The seam controls set peak tensile traction relative to the softer layer’s Young’s modulus and the final opening. Together they determine `Gc = ½ × peak traction × final opening`.

Pause or single-step to inspect the computed geometry. Switch the color field between axial strain and accumulated plastic strain. The seam color shows local loss of tensile stiffness. Diagnostics show seam force, contact and stored energy, plastic and fracture dissipation, and energy balance. **Pin reference** and **Compare** overlay mean seam opening, fracture dissipation per area, or plastic dissipation at matched simulated times. Scene files save the experiment settings for deterministic replay.

## Scientific limits

This preset uses collinear impact with lateral guides. The guides enforce zero transverse displacement and do no work. Conservation checks use longitudinal momentum, including the stop impulse when enabled. The contact pairs are striker–facing, facing–backing along the predefined seam, and backing–stop. The fixed-normal seam resists compression after full tensile failure through its matched nodes. Contact is frictionless and uses finite penalty stiffness. The integrated seam has a compression stiffness floor to limit interpenetration even for weak tensile bonds. The model does not resolve off-axis motion, sliding interfaces, arbitrary body pairings, mixed-mode fracture, spontaneous cracks, spall, fragmentation, melting, or three-dimensional response. These material parameters are illustrative. The full Cartesian product of editor settings has not been validated.

## Verification

Run `swift run --disable-sandbox -c release ImpactCheck --layered-impact` for the integrated checks, or omit `--layered-impact` for the full suite. The focused check measures impact timing, overlap, longitudinal momentum, total energy, and cohesive work. It tests the stopped, free, and intact specimens, plus two settings near the limits of the material and bond ranges. It also checks that failed links carry compression during reclosure and recover no tensile capacity.

| Shipped separating case | Measured result |
|---|---:|
| Strike → full failure → stop → failed-seam reclosure | 4.621 → 12.829 → 24.141 → 40.017 ms |
| Peak energy imbalance relative to initial kinetic energy | 0.108% |
| Peak longitudinal momentum residual after accounting for stop impulse | 5.1 × 10⁻¹⁵ of initial momentum |
| Peak relative overlap for striker and seam contacts | 2.72% of local resolution |
| Integrated interface work / model fracture energy | 1.17004 / 1.17000 J/m² |
| Final mean opening, with stop / free | 10.87 / 45.21 mm |
| Plastic dissipation, separating / intact with stop | 0.607 / 1.345 J/m |

At half the timestep, failure and reclosure shifted by 0.28% and 0.74%. Doubling mesh resolution along both axes at the same smaller step shifted them by 0.63% and 1.67%. Final opening varied by up to 3.87%. Plastic dissipation varied by 7.26% with time refinement and 10.69% with mesh refinement. Treat the plastic-energy readings as more resolution-sensitive than the event timing or fracture budget.
