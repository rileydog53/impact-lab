> COPY from project shared folder, 2026-11-24.

# Contact verification gate, elastic bend fixture (23 November 2026)

**Status:** Research finding from solver runs executed on the M4 in this session. Not an approved decision. No production code was changed.

## Question

Can Impact Lab compute contact results that converge with mesh refinement, without the numerical contact stiffness (the "penalty") deciding the answer?

## Short answer

Yes for the quantities that matter physically in this regime. No for the raw peak force, which no one should report.

- **Momentum transfer, rebound, deformation and energy converge.** The penalty stiffness does not decide them. They also don't depend on the mesh layout or the timestep.
- **The raw instantaneous peak force is a numerical artifact.** It grows like the square root of the penalty and shrinks as the mesh is refined. It has no converged value.
- **Force averaged over a physically meaningful window converges.** A 1 ms average agrees within about 1% across all penalties and both layouts at ×4 and ×5 (1,170–1,181 N/m).
- **No physics correction is needed for this regime.** The smallest justified change is to how contact force is *reported and gated*, not to the contact law.

## What I ran

**Fixture.** This is PHASE_0_8's elastic, fracture-disabled notched bend, built exactly as in `compliantStrikerCheck` (`AssemblySimulation(..., notchDepth: 0.005, insertionEnabled: false)`). It's a soft specimen (E = 1 MPa, ν = 0.12) on two supports, struck at 1.45 m/s by a block (E = 3 MPa) 18 mm off the notch. Each run lasts 40 ms, which covers the whole contact episode and the striker's rebound.

**Matrix (32 runs, all completed, no failures).**

- Penalty ×1, ×2 and ×4 on aligned and staggered meshes at refinements ×2, ×3 and ×4.
- Penalty ×8 at ×3.
- Half timestep at ×3 for penalty ×2 and ×4.
- ×5 refinement at penalty ×2.
- The PHASE_0_8 soft pad (250 kPa, 4 mm) at ×2, ×3 and ×4.

**Reproduction first.** The existing command `ImpactCheck --compliant-striker` reproduced every PHASE_0_8 number exactly (`compliant-striker-repro.txt`).

**Isolation.** Everything ran in a scratch copy of `research/material-separation` at 47ccaad. I added one scratch-only file, `ContactGate.swift`, which records per-step histories. Nothing in the repository was edited.

## Measured results

| Quantity | Spread across penalty ×1 to ×8 (×3, aligned) | Aligned vs staggered | Half timestep | Trend with refinement |
|---|---|---|---|---|
| Raw peak force | 2,640 → 7,342 N/m (×2.8, ≈ √8) | up to 22% | < 0.02% | falls, no limit |
| Peak of 1 ms-averaged force | 1,183–1,188 N/m (0.4%) | ≤ 1.3% at ×3–×5 | < 0.4% | 1,217 → 1,183 → 1,175 → 1,175 (converged) |
| Total impulse to the striker | 4.95–5.00 N·s/m (0.9%) | ≤ 0.6% | < 0.3% | within 1% |
| Striker rebound speed | 0.636–0.650 m/s (2%) | ≤ 1.4% at ×3–×5 (3.3% at ×2) | < 0.3% | 0.624–0.655, no clear trend (±2%) |
| Peak bending sag under the striker | 8.72–8.77 mm (0.6%) | ≤ 1.3% | < 0.1% | 8.49 → 8.76 → 8.96 → 9.09 mm, still rising |
| Peak overlap | 0.59–1.84% of an edge | similar | none | ~0.05 mm in absolute terms, roughly constant |
| Energy error | ≤ 0.011% | | | |
| Momentum error | ≤ 8e−14 N·s/m | | | |

**Initial contact plateau.** The 0.1 ms average over the first 50 to 300 µs is about 880–915 N/m at ×3–×5 for every penalty. A textbook one-dimensional estimate for two flat elastic blocks colliding (speed times the combined wave impedance, over the 25 mm face) gives about 826 N/m. The 8–10% difference is consistent with 2D spreading, but this is a plausibility check, not a validation.

**Three separate contacts.** The striker strikes three times: around 4, 11 and 18 ms. All penalties trace the same averaged force and the same velocity history (figure 2).

## What this means in plain English

The contact spring works like a very stiff, very short spring between surface points. When two meshed surfaces first touch, the outermost nodes bounce off each other on that spring for a few microseconds. That brief rattle sets the "peak force". A stiffer spring makes a taller, shorter spike, but the area under the spike, which is the momentum it delivers, barely changes. So the striker slows, bends the beam and bounces back the same way whatever spring we choose. The spike is a property of the numerical method, not of the materials.

## What the evidence establishes

1. **Penalty contact is adequate in this regime.** For a soft elastic body under low-speed, frictionless, flat contact, Impact Lab transfers momentum and energy correctly and converges in rebound, impulse and deformation, independent of penalty stiffness (×1–×8), mesh layout and timestep. This is **verified by execution**.
2. **The 13.7% mesh-layout difference is a raw-peak artifact.** It's the node-scale rattle, so the PHASE_0_8 diagnosis is confirmed and extended. Raw peak force should never be quoted as a physical result. Also **verified**.
3. **The PHASE_0_8 soft pad is not a "physically compliant" version of this experiment.** It's a different physical system. The pad (250 kPa) is softer than the specimen (1 MPa). It cuts the first-contact plateau to about 310 N/m, changes the 8 ms impulse by about 7%, and leaves the striker still moving down when the pad's guard stops the run at about 14.7 ms ("striker pad collapsed"). Its tight mesh agreement shows the pad smooths the load. It doesn't show that hard contact is wrong. **Verified.**
4. **The remaining mesh sensitivity sits in the bulk elements, not in contact.** Bending sag still grows about 0.13–0.27 mm per refinement level at ×5. This is consistent with the known bending over-stiffness of constant-strain triangles. That's a **hypothesis**: it fits the data, but I didn't test an alternative element.

## What remains unreliable or untested

- **Raw peak contact force and anything derived from it**, such as a peak contact stress readout.
- **Regimes this fixture doesn't cover:** stiff metals (where the penalty length scale and the timestep interact differently), high speed, curved or Hertzian contact, sliding and friction, and contact between fracture fragments.
- **Late-time chatter.** There are 18 to 231 on/off contact episodes per run, increasing with penalty. It's energy-neutral here, but it's numerical noise.
- **The relative-overlap gate.** The 2% check is measured against the local edge length, so the default penalty breaks it on finer meshes (2.6% at ×4) even though the absolute overlap stays at about 0.05 mm. The gate, not the physics, becomes mesh-dependent.

## Smallest justified correction (proposal, not implemented)

**No change to the contact law.** Instead:

1. **Report contact force with a stated averaging window.** For example, use a window of at least one element wave-transit time (h/c), labelled as such. Show the raw peak only as a numerical diagnostic.
2. **Gate contact checks on impulse, rebound and averaged force.** Stop gating on raw peak, and express overlap in absolute length (or relative to the body size) as well as relative to edge length.

These are instrumentation and test changes in `ImpactCheck` and the readouts. They need your approval before they go into the repository.

## Recommended next material-physics capability (recommendation, not approved)

**Independently specified material properties behind an extensible material-state interface.** Strength and toughness would be given in pascals and J/m² rather than as fractions of E, and the interface would have room for later rate, temperature and damage state. The experimental package already has opt-in `tensileStrength`, so this is a short step from what exists. It also unlocks unfamiliar material combinations, the project's core goal.

**Before trusting stiff-metal contact,** run one cheap check: repeat this same gate with metal profiles. That's the regime where contact could still bite.

## Reproduce

```sh
# from the scratch copy (research/material-separation at 47ccaad + ContactGate.swift)
swift build -c release
.build/release/ImpactCheck --compliant-striker          # existing PHASE_0_8 controls
.build/release/ImpactCheck --contact-gate aligned 3 penalty 2 0.45 40 out.csv   # scratch-only
python3 analysis/analyze.py <dir>                       # figures + summary.csv
```
