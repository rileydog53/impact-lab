# Experimental tensile fracture and separation

These runs record checkpoint `fc188ee` and its original cohesive frame. The symmetric-frame results and current interpretation are in [Tensile crack propagation and fragment motion](TENSILE_PROPAGATION.md).

Impact Lab can now initiate cohesive cracks in a custom elastic material at an explicit tensile traction in pascals. The [bend coupon scene](scene-examples/tensile-separation.json) shows the coupon deforming, losing cohesion, separating, and making contact with a deformable receiver. Its material and fracture parameters are illustrative.

## Open the experiment

Build and open the branch with `./launch.command`. In **Assembly**, open `docs/scene-examples/tensile-separation.json` and click **Calculate**. Use **Maximum principal stress** near 5.8 ms, then **Interface damage** near 12 ms. The **Events** menu selects first failure, first detachment, or the first recorded contact on a newly exposed face. **Measurements** shows the energy history. The scene uses a 30 kPa tensile threshold and fracture energy of 7 J/m². Both are visible in the selected coupon’s **Material** inspector.

## Model and conventions

- The optional `fracture.tensileStrength` parameter applies to the tensile component of nominal face traction, $t_n=\mathbf n\cdot\mathbf P\mathbf N$. Here $\mathbf P$ is recovered first Piola stress, $\mathbf N$ is the reference face normal, and $\mathbf n$ is the current face normal. The threshold uses force per unit reference area. The app’s principal-stress field displays the Cauchy stress, a separate quantity. Compression or shear alone cannot trigger this mode on a face.
- Before insertion, shared nodes carry bulk elastic stress. Insertion separates the node sectors where the mesh allows it and seeds the existing cohesive law with the full resolved traction. Keeping the tangential traction preserves its pre-insertion value. The seed matches the recovered face traction. Stresses on the two adjacent triangles may differ.
- The existing irreversible traction–separation law softens the face and accounts for recoverable cohesive energy and fracture dissipation separately. In proportional pure opening, if the seed traction is $T_s$, the traction falls to zero over $2G_c/T_s$ of physical opening. The integral is $G_c$ per unit reference area. Equivalent opening includes seeded shear in mixed loading. This mode uses one toughness and supplies no independently calibrated mixed-mode law. The displayed damage is the maximum progress of neighboring cohesive faces. Bulk elastic parameters remain fixed as cohesion across the face declines.
- Splitting keeps every triangle and transfers lumped mass and half-step momentum to the new node sectors. A surface becomes fully failed when both cohesion integration points reach their final opening. Connected groups of triangles then form separate pieces, which can move, rebound, and make contact. Geometric triangle contact handles sibling interaction. Failed faces also enter contact with other bodies through the existing fragment surfaces.

Scenes without `tensileStrength` use their original initiation rule. The opt-in requires a custom elastic material, so the scoped verification leaves the Hencky–J2 flow update and the existing legacy fracture behavior intact. The method follows the extrinsic cohesive-element approach of inserting interfaces as the material loads. [Ortiz and Pandolfi, 1999](https://re.public.polimi.it/handle/11311/546544)

## Numerical evidence on Apple M4

```sh
swift build -c release
.build/release/ImpactCheck --tensile-separation
```

A two-triangle patch opened at a 20 kPa threshold in two orientations. A 19.98 kPa normal traction, compression, pure shear and shear combined with subcritical tension left it intact. The seed traction error was $5.12\times10^{-16}$ relative to strength. Integrated opening work was 0.14000002 J/m against 0.14000000 J/m prescribed. Unloading preserved damage and matched the cohesive potential gradient within $6.84\times10^{-8}$ N/m. The assembled weak-loading control finished with one piece and zero fracture work.

| Bend case, 115 ms window | Step (µs) | Insert (ms) | First failure (ms) | First detach (ms) | Final pieces | Dissipation (J/m) | Peak energy error | Peak overlap |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ×3, native | 0.869 | 5.046 | 6.272 | 20.578 | 2 | 0.919202 | 0.32306% | 1.3085% |
| ×3, common step | 0.435 | 5.046 | 6.272 | 24.018 | 3 | 0.878238 | 0.06641% | 1.3095% |
| ×4 coupon, common step | 0.435 | 5.025 | 5.996 | 13.887 | 6 | 0.839019 | 0.15484% | 1.8137% |

Every bend retained all triangles and conserved total coupon mass within $10^{-12}$ kg/m. Across the cases, the largest insertion mass and kinetic changes were $1.78\times10^{-15}$ kg/m and $4.44\times10^{-16}$ J/m. Peak whole-assembly linear and angular momentum residuals were $9.15\times10^{-14}$ N·s/m and $2.12\times10^{-15}$ N·s. Fracture dissipation increased monotonically and covered $G_c$ times the total fully failed reference length. Contributions from partially damaged faces account for additional dissipation.

In the native ×3 case, a fragment began contact with the receiver at 67.130 ms after detachment. The post-detachment scalar normal impulse at the receiver was 0.023891 N·s/m. The ×4 case recorded a receiver contact on a newly exposed crack face at 72.755 ms. Its aggregate post-detachment scalar normal impulse was 0.580711 N·s/m. The scalar sums describe accumulated contact load. They differ from the vector change in receiver momentum.

The onset time moves by 0.021 ms at the matched step, while the first detachment shifts by 10.131 ms and the final piece count goes from three to six. Dissipation changes by about 4.5% in each refinement comparison. Crack paths, fragment count, and later receiver interaction are therefore qualitative for this fixture. Mesh robustness is the next numerical priority. A controlled opening specimen with comparable crack advance across orientations would help separate mesh path bias from the sensitivity of secondary contact. Physical calibration still requires measured tensile initiation and fracture work for the material and loading conditions of interest.

## Native evidence

The screenshots and three-state comparison show the nominal ×3 run. The receiver-contact frame at 67.141 ms records an active normal load of 96.09 N/m. [Evidence index](audit-evidence/tensile-separation/README.md)
