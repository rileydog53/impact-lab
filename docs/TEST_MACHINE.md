# Virtual test machine: moving grips (milestone "trustworthy ordinary experiments")

Added 2026-11-25. This is deliverable 1 of `docs/MILESTONE_trustworthy_ordinary_experiments.md` (on branch `claude/milestone-ordinary-experiments` until it merges). Run with `ImpactCheck --test-machine` (about 4 minutes). The code is in `Sources/ImpactCheck/TestMachine.swift`.

**Status: numerical verification against the input material law and continuum theory, not experimental validation.** The model is 2-D plane strain, so a coupon here is a wide plate with no out-of-plane strain, not a round bar.

## What it is

A body can now have a `grip` on one straight edge (`left`, `right`, `bottom` or `top`). Every node on that edge moves together at a set velocity, like the crosshead of a materials-testing machine. The velocity rises from zero over `ramp` seconds along half a cosine, then stays constant. A clamp, if the body has one, must be on the opposite edge.

The solver records:

- the force the grip exerts (`gripReaction`), including the inertia of the gripped nodes;
- how far the grip has moved (`gripDisplacement`);
- the work the grip has done (`energies.gripWork`).

The work enters the energy ledger, so the ledger total stays at the starting energy. The fracture guard's energy scale includes the largest grip work so far, the same way it already includes gravitational release.

Solver change: `Physics.swift` (`GripState`, and grip lines in `drift`, `kick` and `splitNodes`), `AssemblySimulation.swift` and `EnergyAcceptance.swift`. With no grip in a scene none of those lines run, and every saved scene replays bit for bit (`--legacy-replay check`, 11 scenes, run 2026-11-25).

Scene file: `"grip": { "edge": "right", "velocity": [0.4, 0], "ramp": 0.0002 }`. See [`SCENE_FORMAT.md`](SCENE_FORMAT.md) and the schema. The app's editor does not show grips yet. Scenes with a grip load and run from a file.

## Theory used

Uniaxial stress in plane strain (σyy = 0, εzz = 0):

- The elastic slope is the plane-strain modulus E' = E / (1 − ν²).
- Yield starts above the input yield stress Y, at Y / √(1 − ν + ν²), because the out-of-plane stress σzz = ν σxx adds to the von Mises stress.
- The reference for the 0.2%-offset yield is an independent small-strain calculation of one material point under these conditions, using the input E, ν and flow curve. It is written in the check without solver code.

## Checks (criteria written before the first run)

The coupons are:

- **Tension:** 120 × 15 mm, left edge clamped, right edge gripped and pulled.
- **Compression:** 24 × 120 mm, bottom clamped, top gripped and pushed.

The grip reaches 1% overall strain over 150 longitudinal wave transits, with a 10-transit ramp. That is about 0.4 m/s and 3 ms. The gauge marks are the node lines nearest a quarter of the length either side of the middle.

| Run | Slope vs E' | 0.2%-offset yield vs reference | Grip vs section and clamp force | Ledger residual |
|---|---|---|---|---|
| Steel tension, x4 | −0.89% | −0.30% (287.6 MPa) | within 0.48% | 2e-9 of grip work |
| Steel compression, x4 | −0.69% | +0.35% (289.5 MPa) | within 0.64% | 4e-9 |
| 6061-T6 tension, x4 | −0.36% | −0.58% (318.0 MPa) | within 0.25% | 3e-10 |
| 6061-T6 compression, x4 | +0.35% | +0.64% (321.9 MPa) | within 0.19% | 6e-10 |
| Criterion | within 2% | within 2% | within 2% | within 0.5% |

The references are:

- **Steel (A36-like profile, E 200 GPa, ν 0.30, Y 250 MPa):** E' 219.8 GPa, first yield 281.3 MPa, offset-yield reference 288.5 MPa.
- **6061-T6 profile (E 68.9 GPa, ν 0.33, Y 276 MPa):** E' 77.3 GPa, first yield 312.7 MPa, offset-yield reference 319.8 MPa.

**Half speed** (300 transits) changes the slope by at most 0.76% (steel) and the yield by at most 0.07%. Criterion: under 2%. At half speed the steel slope comes within 0.15% of E', so most of the −0.9% at full speed is leftover wave ringing, not stiffness.

**Fine against x4 mesh:** slope and yield agree within 0.08%. Criterion: 1%, declared before the run and not tuned.

**Grip work:** the solver's grip work and a separate force × displacement record agree to rounding, within 2e-14. The ledger residual above is then the gap between the grip work and kinetic + stored + dissipated energy.

**Brittle coupon with fracture on**, glass-like (41 MPa, 7.4 J/m²), pulled at 2 m/s:

- The first crack came at 79.6 µs, with the grip 60.6 µm along.
- At the end there were 196 crack faces and 75 pieces.
- The fracture guard accepted every step.
- Gripped nodes, including those made by splits, stayed on the prescribed path (largest difference 3.5e-18).
- The ledger residual was at most 1.01% of the largest grip work so far, under the guard's 2%.

**Scene files:** a valid grip loads. The opposite-edge rule, a fixed support, a body that starts moving, a speed over 10 m/s, an unknown edge and a missing ramp are each refused with an explanation.

## Displacement-driven bend and crack load (`ImpactCheck --bend-rig`, about 30 minutes; `--bend-rig quick`, about 10, in CI)

Added 2026-11-25. The code is in `Sources/ImpactCheck/BendRig.swift`.

**Setup.** A 160 × 20 mm beam (E 1 GPa, ν 0.2) is clamped on its left edge. A grip holds its right edge and moves it straight down. Both ends keep their slope, so it is a fixed-guided beam with end moments P L / 2.

**What is gated.** Following the review of PR 16, the check gates the **grip's force at the prescribed deflection** against Timoshenko beam theory, F = δ / (L³/(12 E′ I) + L/(κ G A)), in plane strain with κ = 5/6. A check on the deflection itself would be empty, because the machine prescribes it. The force-driven sags (cantilever 1.2180 mm, rollers 1.0885 mm) stay as separate regressions in `--supports-gravity`.

**Stiffness. The criterion was amended after the first run.** The first run failed the 3% criterion on the x4 mesh (12 elements through the depth): the beam came out +3.41% stiff. The probe mode (`--bend-rig probe`) split that number up:

| Mesh | Full crack deflection | A tenth of it |
|---|---|---|
| x4 | +3.41% | +2.75% |
| x5 | +2.59% | +1.93% |
| x6 | +2.10% | +1.44% |
| x7 | +1.84% | +1.18% |

- **About 0.66 points are membrane tension.** The grip also holds the beam's end at its length, so a 1.9 mm deflection stretches the beam (axial grip force 1.47 kN/m, against 15 N/m at a tenth of the deflection). Linear beam theory leaves that out.
- **The rest is the mesh.** Linear triangles are too stiff in bending. The error falls about as the square of the element size (fitted order 1.9) toward about +0.3% to +0.5% (extrapolated), which is what remains of the end conditions.

The amended criterion compares the **linear** response (a tenth of the deflection) with linear theory. The limit is still 3% on x4, and the check now also requires x6 to be closer to theory than x4. Result: +2.75% (x4) and +1.44% (x6). The full-deflection +3.41% is still printed.

**Crack load.** The crack strength is 4.5 MPa and the energy 100 J/m². The end moment gives a surface stress of 3 P L / h², so the first crack is predicted at P = σ h² / (3 L) = 3750 N/m. The criteria were written before the first run:

- the first crack is at an end, on that end's tension face;
- the load at first crack is within 20% on x4;
- the x6 result is reported.

| Mesh | First crack | Grip force at first crack | Deflection |
|---|---|---|---|
| x4 | grip end, bottom face, 78.3 ms | 4064 N/m (+8.4%) | 2.02 mm |
| x6 | clamp end, top face, 74.2 ms | 3784 N/m (+0.9%) | 1.91 mm |

The finer mesh cracks 6.9% earlier, as expected at the singular clamp and grip corners [recall: Williams 1952]. The two ends carry equal moments, so either may crack first. Every step was accepted.

## Not done yet

- A loading nose or platen in contact (three-point bend, tip-loaded cantilever). A first try with a gripped elastic nose on a cantilever chattered (contact force swinging ±15%) and was slow, so the crack-load benchmark moved to the fixed-guided rig above.
- Engineering stress-strain output and CSV columns in the app, and showing grips in the editor and the replay.
- The stress-strain results above come from the check, not from a run the app can export yet.
