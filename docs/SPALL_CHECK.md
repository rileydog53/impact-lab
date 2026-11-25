# Spall check against the 1D wave picture (layered target plan, step 5)

Added 2026-11-25. Gate: `ImpactCheck --spall` (about 2 minutes on the M4 Air). Code: `Sources/ImpactCheck/Spall.swift`, plate setup shared with the bulk viscosity check in `PlateImpact.swift`.

**Status: numerical verification against a hand calculation.** Not physical validation: the plates are elastic on purpose and the crack strength is a test value set from the prediction, not a measured spall strength.

## Prediction

Steel reference profile, elastic (E 200 GPa, ρ 7850 kg/m³, ν 0.30, so c = 5856 m/s), impact at 50 m/s, so σ = ρcv/2 = 1.149 GPa. Striker δ = 27 mm, ×4 mesh (2.25 mm cells). Standard plate-impact wave theory (Meyers 1994; Antoun et al. 2003), worked in `layered-steps-4-6-design.md`:

- **Equal plates** (T = δ): the release waves meet at the impact face at 2δ/c = 9.221 µs. A contact cannot carry tension, so the plates separate there. No spall. The striker is left at rest and the target leaves at v.
- **Target twice as thick** (T = 2δ): the release waves meet in the middle of the target at 3δ/c = 13.831 µs, with a tension of ρcv/2 there.

The 1D picture only holds where no wave from the plates' top and bottom edges has arrived: at time t, |y| < H/2 − c·t.

## Criteria fixed before the first run

All with bulk viscosity on.

1. Equal plates, both able to crack at 0.5 ρcv/2: no crack anywhere up to 4δ/c. Contact opens within 5% of 2δ/c. Afterwards the striker's centre band moves at under 5% of v and the target's within 5% of v.
2. T = 2δ, crack strength 0.5 ρcv/2: no crack before 0.9 · 3δ/c. First crack within 5% of 3δ/c and within two element widths of the mid-plane.
3. Negative control, T = 2δ, crack strength 1.3 ρcv/2: no crack up to 5δ/c.

## First run (plates 8δ = 216 mm tall): three criteria not met

| | Result | As first specified |
|---|---|---|
| 1. Equal plates, cracks | first crack at 9.52 µs, 1 mm from the impact face, **25 mm in from the top and bottom edges** (y = ±83 mm); none in the 1D zone | not met |
| 1. Equal plates, separation | whole face clear at 9.85 µs (+6.8%); the edges were the last to let go | not met |
| 1. Equal plates, momentum swap | striker 1.7 m/s, target 48.3 m/s | met |
| 2. T = 2δ, time | first crack 13.97 µs (+1.0%) | met |
| 2. T = 2δ, place | that first crack was again at y = −83 mm, 25 mm from the edge and 5.6 mm off the mid-plane; the first crack in the 1D zone was on the mid-plane | not met |
| 3. Negative control | no crack | met |

Every miss came from the same place: about 25 mm in from the plates' top and bottom edges, which is inside the 2D edge zone, where waves from the free edges have already arrived and the 1D picture does not apply. Hypothesis, not tested: the spot matches how far a shear wave from the plate corners travels by then (about 3.1 km/s × 9.5 µs ≈ 30 mm). These edge cracks are a 2D result of a finite plate. They are not checked against anything here.

## Amended gate (written after the first run; accepted by Joseph on 2026-11-25)

The same tolerances, judged only inside the 1D zone. Plates are 16δ = 432 mm tall, so that zone is wide (|y| < 135 mm at 3δ/c). "Contact opens" is measured on the centre band of the impact face, as the last moment its faces still touch. A crack face exactly two cells from the plane counts as "within two cells". Edge-zone cracks are still printed. The first run above is still run and printed every time, against its original wording.

| Case | Result | Criterion |
|---|---|---|
| 1. Equal plates | no crack in the 1D zone (edge-zone crack at 9.52 µs, 25 mm from the edges); centre band opened at 9.416 µs (+2.1%); striker 1.69 m/s, target 48.31 m/s | pass |
| 2. T = 2δ, 0.5 ρcv/2 | first crack in the 1D zone at 14.460 µs (+4.5%), on the mid-plane; 464 faces within 5% of that time, all within 2 cells of the mid-plane, spanning y = ±129 mm | pass |
| 3. Negative control, 1.3 ρcv/2 | no crack anywhere | pass |

## With bulk viscosity off (reported, not gated)

| Case | Result |
|---|---|
| 2. 0.5 ρcv/2 | false first crack at 10.40 µs (−25%), at the impact face in the edge zone; the 1D zone result is unchanged (14.460 µs on the mid-plane) |
| 3. 1.3 ρcv/2 | **cracks** on the mid-plane at 15.4 µs, across y = ±125 mm |

Without viscosity the ringing behind the release fronts pushes the tension past 1.3 ρcv/2, so a target 30% stronger than the 1D tension still spalls. With it on, it does not. That is the direct test of step 4 the design asked for.

## What this does not cover

Plastic plates (steel at 50 m/s yields in reality), real spall strengths, rate effects, and the edge zone. Energy error stayed under 0.002% in every run.
