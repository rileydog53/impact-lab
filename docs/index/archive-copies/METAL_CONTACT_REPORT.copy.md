> COPY from project shared folder, 2026-11-24.

# Metal repeat of the contact gate (23 November 2026)

**Status:** Research finding from solver runs on the M4 in this session. Not an approved decision. No repository code was changed. The section 17 conclusions stay pending until Joseph reviews this.

## Question

Does the soft-fixture conclusion still hold with stiff metals? The soft conclusion was that impulse, rebound, deformation and averaged force are robust, and that the raw peak is a penalty artifact. This repeat also checks whether the averaged force depends on the averaging window, and keeps both absolute and mesh-relative penetration.

## Short answer

**Mostly yes.** With metal, the early contact pulse, the deformation and the conservation behave just as they did in the soft case. Two things are not robust:

- **Raw peak force.** It's still a penalty artifact.
- **Final rebound speed in this low-speed case.** It's not robust because the metal run ends in a chain of small late re-contacts, and the order of those re-contacts shifts with mesh and penalty. At 10 m/s the rebound is robust.

**The averaged force depends on the window.** No single window, 1 ms included, is universally right. A window stops depending on penalty and mesh once it is about 10 element wave-transit times (h/c) long. Even then, the value still falls as the window widens, so the window must always be stated. The quantity that needs no window at all is the **impulse of each contact pulse**, and it's the most robust number in both materials.

## Three different kinds of "trust"

| Kind | What it means | Status here |
|---|---|---|
| **Numerical verification** | The computer solves the model's own equations consistently: results don't hinge on mesh, timestep or penalty, and energy and momentum are conserved. | **Done** for the quantities marked robust below, in this fixture only. |
| **Physical validation** | The model matches a real experiment. | **Not done.** There are no experimental data. The 1-D impedance estimate is a plausibility check only. |
| **Personal acceptance** | Joseph decides the program is good enough for his own use. | **Joseph's call.** Nothing here decides it. |

## What I ran

**Fixture.** This is the same notched elastic bend as the soft gate, with insertion disabled, built through the existing `AssemblySimulation`.

- **Materials.** The specimen is Al 6061 (E 68.9 GPa, ρ 2700, ν 0.33). The striker, supports and receiver are structural steel (E 200 GPa, ρ 7850, ν 0.30). These are the same numbers as the `MaterialProfile` entries, with the provenance tag removed because the scene validator rejects fracture settings on tagged materials.
- **Gaps.** Striker and support gaps are 0.1 mm, so the short metal episode isn't spent in free flight.
- **Duration.** 0.8 ms at 1.45 m/s, which covers the full contact sequence.

**Matrix (23 runs, all completed, no solver failures).**

- Penalty ×1, ×2 and ×4 at refinements ×2, ×3 and ×4, aligned.
- Penalty ×8 at ×3.
- Refinement ×5 at penalty ×2.
- Staggered layout at ×2, ×3 and ×4.
- Half timestep at ×3 (penalty ×1, ×2 and ×4).
- Penalty ×1 and ×4 at 10 m/s.

**Infrastructure.** I reused the scratch `ContactGate` path plus one scratch file, `MetalGate.swift`. It adds an independent geometric overlap measure in µm alongside the solver's own edge-relative value.

**One workaround.** Staggered meshes only exist through fracture settings. With the default fracture settings the metal timestep collapses to 0.23 ns (see side finding), so the staggered runs used weakened cohesive settings that never activate. Aligned runs used no fracture at all. Aligned and staggered agree on every robust quantity, so the workaround didn't change the answer.

## Results (×3 to ×5, every penalty, both layouts, 13 runs)

| Quantity | Range | Spread | Verdict |
|---|---|---|---|
| Raw peak force | 1.02–3.33 MN/m | 228% | **Artifact.** Rises with penalty, falls with refinement, no limit. |
| First-pulse impulse (0–100 µs) | 6.45–6.51 N·s/m | 0.86% | **Robust** |
| Impulse to 250 µs (first three pulses) | 10.48–10.52 N·s/m | 0.38% | **Robust** |
| Peak bending sag under the striker | 49.5–50.0 µm | 1.0% | **Robust**, converging (49.4 → 49.8 → 50.0 → 50.0 µm) |
| Peak of 10 µs-averaged force | 481–487 kN/m | 1.3% | Robust, **for that window** |
| Final striker rebound speed | 0.059–0.252 m/s | 328% | **Not robust** at 1.45 m/s (see below) |
| Absolute overlap | 0.13–0.38 µm | — | Tiny. ≤ 0.014% of an edge |
| Energy error | ≤ 0.0103% | | |
| Momentum error | ~1e−13 | | |
| Half timestep | impulse changes 0.2–0.3% | | Timestep is not the cause |

**At 10 m/s** (penalty ×1 vs ×4, ×3 mesh):

| Quantity | Penalty ×1 | Penalty ×4 |
|---|---|---|
| Impulse (N·s/m) | 113.89 | 113.63 |
| Rebound coefficient | 0.350 | 0.347 |
| Sag (mm) | 0.4285 | 0.4289 |

That is robust. **Early plausibility:** the force plateau over 0.3–2 µs is 310–487 kN/m, against a 1-D flat-impact impedance estimate of about 442 kN/m.

### Why the final rebound isn't robust at 1.45 m/s

The metal striker hits, bounces, and re-contacts the vibrating beam several times (figure M1).

- **The first 250 µs are the same in every run:** three pulses with impulse within 0.4%.
- **After about 290 µs, small late re-contacts begin.** How many there are and when they happen depends on the mesh and the penalty, because the beam's high-frequency vibration decides whether the striker catches it.
- **The final speed is what's left after a sequence of nearly balanced kicks**, so small differences are amplified. Timestep halving barely changes it, which points to sensitivity to the surface discretization rather than a timestep error.
- **At 10 m/s the striker leaves cleanly** and the rebound agrees within 1%.

This is a statement about a chaotic multi-impact sequence. It's not evidence that the contact law is wrong.

## Averaging windows

Figure M2 shows how much the peak of the averaged force varies across penalty and layout as the window grows:

| Window (in element transit times h/c) | Metal spread | Soft spread |
|---|---|---|
| about 1 | 18% | 20% |
| about 5 | 4–7% | 4% |
| **about 10** | **2.5%** | **2.4%** |
| about 20 | 1.3% | 1.6% |

**The two materials collapse onto one curve when the window is measured in transit times, not milliseconds.** That's why 1 ms worked for the soft case: its h/c is about 91 µs, so 1 ms is about 11 transit times. For the metal, h/c ≈ 0.49 µs, so about 5 µs does the same job.

**But the averaged value itself keeps falling as the window grows:**

- Metal: 556 → 484 → 325 kN/m for 5, 10 and 20 µs.
- Soft: 1,185 → 970 N/m for 1 ms and 2 ms.

Once the window is longer than the pulse, it averages in the gaps between pulses. So a windowed force needs two bounds:

- **at least about 10 h/c**, so it doesn't depend on the mesh or the penalty
- **no longer than the pulse**, so it still measures the pulse

It must always be reported with its window. **Pulse impulse is the window-free alternative,** and it's the most robust quantity in both materials (0.86% metal, 1.5% soft).

## Penetration, absolute and mesh-relative

| Case | Absolute overlap | Relative to edge |
|---|---|---|
| Metal, 1.45 m/s | 0.13–0.38 µm | 0.005–0.014% |
| Metal, 10 m/s | 1.0–2.2 µm | about 0.07% |
| Soft | about 0.05 mm | 0.6–2.6% |

The penalty scales with E, so the penalty-to-body stiffness ratio is set by the fixed 0.4 mm length scale and the element size, not by the material. That's why the metal behaves like a scaled copy of the soft case. Both diagnostics are kept:

- **Absolute overlap** answers "is this geometrically negligible?"
- **Relative overlap** shows that the 2% edge-relative gate becomes mesh-dependent on fine soft meshes even while the absolute overlap stays put.

## Side finding: fracture settings make metal timesteps collapse

With the default fracture settings, cohesive strength is 0.03 × E. That's about 2 GPa for aluminium, against a real tensile strength of about 310 MPa. The cohesive stiffness enters the timestep bound, so dt drops from about 10 ns to 0.23 ns, about 43× more steps. That's a strong practical reason to specify strength in pascals rather than as a fraction of E (see the architecture proposal).

## What stays open

- **Beam-element convergence.** In the soft case, bending sag keeps rising with refinement: 8.49 → 8.76 → 8.96 → 9.09 mm. The constant-strain-triangle bending hypothesis is untested. The metal sag converges (about 0.1% between ×4 and ×5), but the metal beam is much stiffer and less deeply bent, so this doesn't close the question.
- **Physical validation.** No experiment has been compared.
- **Elasticity assumption.** The estimated contact stress is about 18 MPa at 1.45 m/s and about 122 MPa at 10 m/s, under the 276 MPa yield. I didn't check this against the computed stress field.
- **Untested here.** Curved or Hertzian contact, sliding and friction, fragment-to-fragment contact, and plastic metal.

## Recommended minimal reporting correction (proposal, not implemented)

**No change to the contact formulation.** I'm proposing reporting and gating changes only, in the readouts and `ImpactCheck`:

1. **Per-pulse summary.** Each contact pulse gets its impulse, duration and mean force (impulse ÷ duration). This is the headline contact number.
2. **Windowed force only with a stated window.** Default to about 10 h/c of the finer body, capped at the pulse duration, and label it, for example "force, 5 µs average".
3. **Raw peak shown only as a numerical diagnostic,** never as a result.
4. **Overlap in both forms:** absolute (µm or mm) and as a percentage of edge length.
5. **Final rebound with a caution** when there are several late re-contacts, for example "rebound depends on a multi-impact sequence".
6. **Gates.** Contact checks gate on pulse impulse, deformation and conservation, not on raw peak or a fixed-ms average.

## Reproduce

```sh
# scratch copy of research/material-separation at 47ccaad + ContactGate.swift + MetalGate.swift
swift build -c release
GATE_FRACTURE=none .build/release/ImpactCheck --metal-gate metal aligned 3 2 auto 1 0.8 1.45 out.csv
python3 analysis/windows.py ; python3 analysis/metal_plots.py
```
