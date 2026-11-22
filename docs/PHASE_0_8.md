# Version 0.8 experimental fracture

The assembly solver now starts fracture-enabled bodies on shared FEM nodes. It creates cohesive interfaces and splits vertex connectivity when a face meets the opening or shear criterion. This checkpoint delivers on-demand fracture in the assembly editor. The orientation and secondary-contact studies failed the release gates, so results remain experimental.

## Numerical model

- Constant-strain triangles provide one first Piola stress on each side. The mean resolved traction sets the insertion criterion and initializes the new interface in its current frame. A split requires at least one endpoint to separate into distinct groups of incident triangles. This limits isolated interior nucleation.
- The topology change transfers position and half-step velocity to the new nodes, reallocates lumped mass by incident element, and preserves element state and material attachments. The final half kick uses forces on the new connectivity. The traction-separation law uses zero physical gap at insertion, a finite seed traction, irreversible softening, and equal opening and shear toughness.
- Contact uses the actual new boundary nodes. Each matching node-to-edge feature can retain paired closure while other surfaces on the same fragments collide. The matching feature changes representation only when both its paired closure and its ordinary contact are unloaded. Fully failed interfaces still determine when a sibling gets its own collision domain. That can expose overlap that accumulated inside a previously connected body.
- Candidate paths still follow mesh edges and pay fracture energy per unit of actual edge length. Staggering the block mesh changes the available directions, and both patterns retain horizontal rows. The model has no compressive shear initiation, general same-piece self-contact, or edge-only collision detection. All calculations remain 2D plane strain.

[Pandolfi and Ortiz, adaptive cohesive insertion](https://arxiv.org/abs/cond-mat/0106318)

## Contact repair and remaining gates

At `923c8f8`, fragment pair 0/247 already had 0.3865 J/m of ordinary contact potential one step before the 28.771 ms rejection. The pair-wide switch had suppressed it. The feature-level repair allows nonmatching contacts to act while matching crack faces still carry closure. In the same fine staggered run, the pair now begins ordinary contact at 27.857 ms, accumulates 0.049962 N·s/m of scalar normal impulse, and reaches 115 ms. The total energy change at the former rejection was −4.3e−6 J/m. Peak energy imbalance was 0.033%, with momentum residuals of 3.64e−14 N·s/m and 1.26e−15 N·s. Peak penetration was 4.83%, above the 2% gate.

The repeated two-pattern, three-resolution study still fails. Receiver contact occurred in 7 of 12 runs and tagged new-face contact occurred in 3. The aligned extra-fine half-step run rejected 15.94% trial overlap at 28.906 ms when its fourth fragment acquired a collision domain. The insertion count stayed at 122 while the spent-face count increased from 23 to 24. Trying collision domains from the moment of node insertion moved the problem earlier. In that trial the same extra-fine run rejected a 0.0631 J/m one-step contact-energy increase at 13.408 ms. The fine staggered case also rejected a step. The trial was reverted. Moving the domain boundary in time is insufficient when already-overlapping surface features enter the contact search.

The notched-bend work discrepancy survives the contact repair. At extra fine, work at matched advance was 0.7634 J/m for aligned and 0.3476 J/m for staggered. The adjacent measured work intervals were disjoint, so interpolation cannot explain the 54.47% difference. Away from the notch-connected crack, fully spent faces accounted for 0.1560 J/m of the difference and partially damaged faces for 0.2482 J/m. Together they explain about 97% of the difference. Work in the spent notch-connected crack differed by only 0.0033 J/m. Peak striker load differed by 13.69% and occurred before measurable fracture dissipation in both patterns. The next controlled bend should isolate the mesh dependence of the loading response before changing the fracture criterion.

The nominal production step remains 2.218 µs for the standard case. A paired standard-case probe measured 0.551 s and 7.38 MiB at `923c8f8`, and 0.558 s and 7.33 MiB with the repair. `ImpactCheck --sibling-contact`, `--fracture`, `--assembly`, and the native assembly smoke passed. The scientific study still exits nonzero.

### Contact at detachment

`ImpactCheck --sliding-contact-patch` exercises a two-triangle patch through node splitting, compressed detachment, opening, and sliding recontact. Paired closure energy stayed constant through detachment and its relative force change was 2.55e−9 across the two load samples. Handoff on the open seam transferred zero penalty energy. Recontact reached 0.10% penetration and fracture work was 0.140000 J/m.

`ImpactCheck --detachment-contact` still exits nonzero. It traces features by element corner and compares collision domains at the same trial positions. In the aligned extra-fine half-step case, both features had negative local gaps for over 3.7 ms before the fourth domain activated at 28.905691 ms. Two proper edge crossings were already present at the preceding accepted positions. At activation the 15.941% matching hit stayed on paired closure. A distinct ordinary hit at 2.312% would introduce 0.008482 J/m and about 250 N/m of normal force, with unchanged paired closure energy at the same positions. The guard rejected the step before those forces could act. An already overlapping feature entering the search explains the jump. The FEM indices were stable at this event, the ordinary hit appeared once, and the ordinary penalty has no stored history to reset.

The smallest next contact change to test is local self-contact on already inserted surfaces that still share a collision domain. Swept node–edge crossing checks should start before domain separation, and the 2D patch should verify edge crossings and the transition from paired closure as the surfaces slip. Keep the shared-node FEM, cohesive law, production timestep, and penetration gate. Run the damage-disabled notched-bend control once the contact gate passes. [Continuous collision detection for deforming meshes with changing topology](https://pmc.ncbi.nlm.nih.gov/articles/PMC4500942/)

## Verification at the original experimental checkpoint

**Insertion passes the controlled patches.** Axial stiffness was identical at 35,998.20 N/m per unit strain. The intact weak pulse reached its gauge at 3.771 ms in both runs. The largest observed insertion change on the standard assembly was 1.78e−15 kg/m in mass, 4.44e−16 N·s/m in linear momentum, and 2.22e−16 J/m in kinetic energy. Opening, sliding, and mixed-mode patches absorbed 0.14000002 J/m against 0.14000000 prescribed. Seeded traction matched the resolved mean to roundoff. The individual bulk tractions on the two sides of a face differed by up to one interface strength in the standard impact, so the patch result establishes continuity of the seed with the discrete mean.

**Crack consistency fails.** Both standard notched meshes missed the 10.5 mm crack-advance target. At extra fine, changing pattern shifted peak load by 13.69% and work at matched advance by 54.47%. Work is interpolated between the two measured advances that bracket the target. Fine-to-extra-fine staggered exit sets differed by 4.53 mm, above the 3.02 mm tolerance. Likely contributors include the edge-restricted path cost, the different tractions on adjacent elements, and spatial sensitivity of the striker contact load.

**Secondary interaction fails across the test matrix.** Actual receiver contact occurred in 7 of 12 unnotched runs, including 4 with a tagged new target face. Only extra-fine aligned passed every timestep, energy and penetration tolerance. The standard aligned run missed the receiver and had 3.64% work sensitivity to step halving. The extra-fine staggered run had 18.08% split-time sensitivity, 7.43% work sensitivity and 2.42% penetration. The fine staggered run rejected a step at 28.771 ms when sibling contact added 0.387 J/m of penalty energy in one step, with 7.06% trial penetration. Its half-step run completed on a different fracture trajectory. The verifier reports per-piece sampled clearance, contact episodes, and scalar normal impulse. Scalar impulse sums the positive penalty loads from both contact directions.

The extra-fine aligned app run is paused at 40.20 ms. It logged a newly exposed target-face receiver contact at 39.921 ms. The native smoke check also exercised construction from blank, save and deterministic replay, striker relocation, refinement, and the comparison sheet. The headless regression suite passed. A genuine 0.7 saved scene also reopened under the new solver.

## Reference and performance

| Standard aligned impact through 115 ms | 0.7 at `a410871` | 0.8 at `923c8f8` |
| --- | ---: | ---: |
| Specimen nodes, start → end | 324 → 324 | 76 → 92 |
| Nominal timestep | 2.218 µs | 2.218 µs |
| Instrumented wall time | 0.831 s | 0.572 s |
| Peak process RSS, first probe | 7.00 MiB | 7.38 MiB |
| Largest tested step below 0.5% energy error and 2% penetration | 2.218 µs | 8.874 µs |
| Standard split and receiver outcome | 11.931 ms, four pieces, new-face hit | 31.289 ms, two pieces, miss |

The step probes covered 2.218, 4.437, 8.874 and 17.748 µs. Both solvers reached 115 ms at 4.437 µs, with energy error of 0.512% in 0.7 and 0.080% in 0.8. Both rejected 17.748 µs. These probes measure one impact with different fracture trajectories. The production step still uses the conservative bound for future node splits and contact.

The signed 0.7 app and original checker are preserved locally in `.build/reference-0.7/`. To rebuild the original app on a Mac, check out `a410871` in a separate directory and run its `launch.command`.

Run the default release `ImpactCheck` for regressions. Use `ImpactCheck --fracture-study` for the complete two-pattern, three-resolution study, which exits nonzero on a failed gate. Use `--notched-bend`, `--fracture-case staggered 2`, or `--fracture-stability` for isolated reproductions. Keep fracture work in 2D until a controlled crack-path test and contact handoff both meet their tolerances.
