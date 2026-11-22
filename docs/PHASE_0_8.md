# Version 0.8 experimental fracture

The assembly solver now starts fracture-enabled bodies on shared FEM nodes. It creates cohesive interfaces and splits vertex connectivity when a face meets the opening or shear criterion. This checkpoint delivers on-demand fracture in the assembly editor. The orientation and secondary-contact studies failed the release gates, so results remain experimental.

## Numerical model

- Constant-strain triangles provide one first Piola stress on each side. The mean resolved traction sets the insertion criterion and initializes the new interface in its current frame. A split requires at least one endpoint to separate into distinct groups of incident triangles. This limits isolated interior nucleation.
- The topology change transfers position and half-step velocity to the new nodes, reallocates lumped mass by incident element, and preserves element state and material attachments. The final half kick uses forces on the new connectivity. The traction-separation law uses zero physical gap at insertion, a finite seed traction, irreversible softening, and equal opening and shear toughness.
- Contact uses the actual new boundary nodes. Matching crack faces retain their closure penalty until they clear. The ordinary fragment contact solver then handles sibling recontact. Geometry that overlaps elsewhere at that transition can generate an abrupt contact penalty. The existing energy guard rejects that step and preserves the last accepted state.
- Candidate paths still follow mesh edges and pay fracture energy per unit of actual edge length. Staggering the block mesh changes the available directions, and both patterns retain horizontal rows. The model has no compressive shear initiation, general same-piece self-contact, or edge-only collision detection. All calculations remain 2D plane strain.

[Pandolfi and Ortiz, adaptive cohesive insertion](https://arxiv.org/abs/cond-mat/0106318)

## Verification

**Insertion passes the controlled patches.** Axial stiffness was identical at 35,998.20 N/m per unit strain. The intact weak pulse reached its gauge at 3.771 ms in both runs. The largest observed insertion change on the standard assembly was 1.78e−15 kg/m in mass, 4.44e−16 N·s/m in linear momentum, and 2.22e−16 J/m in kinetic energy. Opening, sliding, and mixed-mode patches absorbed 0.14000002 J/m against 0.14000000 prescribed. Seeded traction matched the resolved mean to roundoff. The individual bulk tractions on the two sides of a face differed by up to one interface strength in the standard impact, so the patch result establishes continuity of the seed with the discrete mean.

**Crack consistency fails.** Both standard notched meshes missed the 10.5 mm crack-advance target. At extra fine, changing pattern shifted peak load by 13.69% and work at matched advance by 54.47%. Work is interpolated between the two measured advances that bracket the target. Fine-to-extra-fine staggered exit sets differed by 4.53 mm, above the 3.02 mm tolerance. Likely contributors include the edge-restricted path cost, the different tractions on adjacent elements, and spatial sensitivity of the striker contact load.

**Secondary interaction fails across the test matrix.** Actual receiver contact occurred in 7 of 12 unnotched runs, including 4 with a tagged new target face. Only extra-fine aligned passed every timestep, energy and penetration tolerance. The standard aligned run missed the receiver and had 3.64% work sensitivity to step halving. The extra-fine staggered run had 18.08% split-time sensitivity, 7.43% work sensitivity and 2.42% penetration. The fine staggered run rejected a step at 28.771 ms when sibling contact added 0.387 J/m of penalty energy in one step, with 7.06% trial penetration. Its half-step run completed on a different fracture trajectory. The verifier reports per-piece sampled clearance, contact episodes, and scalar normal impulse. Scalar impulse sums the positive penalty loads from both contact directions.

The extra-fine aligned app run is paused at 40.20 ms. It logged a newly exposed target-face receiver contact at 39.921 ms. The native smoke check also exercised construction from blank, save and deterministic replay, striker relocation, refinement, and the comparison sheet. The headless regression suite passed. A genuine 0.7 saved scene also reopened under the new solver.

## Reference and performance

| Standard aligned impact through 115 ms | 0.7 at `a410871` | 0.8 experimental |
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
