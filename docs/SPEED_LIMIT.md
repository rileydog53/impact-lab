# Speeds above 150 m/s: test-only sweep (layered target plan, step 8, first part)

Added 2026-11-25. Run with `ImpactCheck --speed-limit` (about 12 minutes). The code is in `Sources/ImpactCheck/SpeedLimit.swift`. Background and the planned benchmarks are in [`step8-design.md`](step8-design.md).

**Status: numerical robustness only.** This sweep measures where runs stop being numerically clean. It says nothing about whether the physics is right at those speeds. The model has no strain-rate hardening, no heating and no shock equation of state, and `step8-design.md` Part 2 explains what each of those gaps costs. **The app's cap is unchanged at 150 m/s.**

## How it runs

Each scene is saved with its striker at rest, so it passes the scene rules. The solver's test-only initial-velocity hook then gives the striker its speed, so the app's limit plays no part. Duration is scaled so the striker travels the same distance as in the saved scene, with a floor of 0.15 ms.

Criteria fixed before the first run:

- A run **holds** if it reaches its end with no rejected step.
- Its energy error must be at most 0.5% (2% for the fracture scene).
- Peak contact overlap must be at most 2% of an edge (the step-probe bounds in `PHASE_0_8.md`).
- The supported cap is the highest speed at which every scene holds, at that speed and every lower one.

## Result (2026-11-25)

| Scene | 150 | 200 | 300 | 400 | 500 | 700 | 1000 m/s |
|---|---|---|---|---|---|---|---|
| Metal plate impact (steel ball on aluminium, plastic) | holds 1.07% | holds 1.28% | holds 1.54% | overlap 2.67% | 3.72% | 5.06% | 7.69% |
| Same, bulk viscosity on | holds 1.02% | holds 1.19% | holds 1.41% | overlap 2.55% | 3.23% | 4.88% | stopped by viscosity guard |
| Laminated glass on aluminium (fracture, bulk viscosity on) | stopped by viscosity guard at 4.5 µs | stopped | stopped | stopped | stopped | stopped | stopped |
| Same, bulk viscosity off (reported, not gated) | holds 1.57% | overlap 2.40% | 5.26% | 4.50% | 5.21% | 6.10% | energy guard stop |

Percentages are peak contact overlap as a share of an edge. Energy error stayed under 0.04% in every run that reached its end. No element inverted in any run.

**By the criteria written beforehand, no speed qualifies.** The laminated glass scene, with bulk viscosity on as saved, stops at 150 m/s. Its soft PVB layer (sound speed about 0.5 km/s) makes the viscous term need a shorter step than the run uses. The run then stops with a plain message, as step 4 designed it to, instead of running on. That is a stop, not a wrong answer. It does mean that this preset cannot run at 150 m/s today, even below the cap.

What the sweep shows:

- **Metal on metal stays clean to 300 m/s.** Above that, contact overlap passes the 2% bound because the striker travels further per time step (the step is fixed at the start). Energy stays balanced, and no element inverts up to 1000 m/s on this mesh.
- **Soft layers with bulk viscosity on stop first.** Two fixes would let them run: a time step that shrinks when the viscous term asks for it, or a viscosity bound per material. Both are solver changes, so neither is made here.
- **Fracture without viscosity stays clean to 150 m/s.** At 200 m/s and above, contact between the many glass fragments overlaps by more than 2%.

## Decision needed before the cap moves

Raising the cap is a product decision. It is left for after the plate-impact check against the LASL shock data (`step8-design.md`, Part 3). A recommendation goes with the step 8 pull request.
