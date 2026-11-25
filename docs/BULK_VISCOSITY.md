# Artificial bulk viscosity (layered target plan, step 4)

Added 2026-11-24. Off by default. Scene key `bulkViscosity` (see `SCENE_FORMAT.md`), editor checkbox "Artificial bulk viscosity (shock smoothing)" in the assembly settings, code in `Sources/ImpactPhysics/BulkViscosity.swift` and the element loop of `Simulation.assembleElements` (`Physics.swift`).

**Status: numerical verification only.** Nothing here is physical validation.

## What it is

While an element is being compressed it carries an extra numerical pressure

    q = ρ · l · ( b1 · c · |ε̇v| + b2² · l · ε̇v² )        (ε̇v < 0 only)

ρ is the current density, c the element's elastic longitudinal wave speed, l = √(current area), ε̇v = ln(J_{n+1}/J_n)/Δt. The quadratic term is von Neumann and Richtmyer's (J. Appl. Phys. 21, 1950); the linear term damps ringing behind a front.

| Choice | Value | Where it comes from |
|---|---|---|
| Formula, b1 = 0.06, b2 = 1.2 (squared, so 1.44) | verified | Abaqus Analysis User's Guide, "Bulk viscosity" (read 2026-11-24 at abaqus.uclouvain.be) |
| Compression only, for both terms | verified | d3VIEW note on LS-DYNA `*CONTROL_BULK_VISCOSITY` ("a positive trace is ignored"). Abaqus applies its linear term always; we follow LS-DYNA so a body in tension is never damped |
| l = √area in 2D | verified | same d3VIEW note |
| LS-DYNA defaults Q1 = 1.5, Q2 = 0.06 | verified (in words) | same d3VIEW note; the LS-DYNA theory manual itself could not be fetched (over 10 MB) |
| Step factor √(1+ξ²) − ξ, ξ = b1 + b2² (l/c)\|ε̇v\| | standard damped central-difference result; ξ formula from the Abaqus page | the run starts with ξ = b1 (factor 0.942) and stops with a plain message if the quadratic part would ever need more than a fifth of the 0.8 safety margin (engineering choice) |

Energy: the work done against q is a running total, per element A · ½(q_n + q_{n+1}) · (J_n − J_{n+1}) each step (trapezoid, like the springs). It is the new `viscous` term of `AssemblyEnergy`, inside `total`, so the fracture energy guard sees it. It has its own line in Measurements ("Artificial bulk viscosity (numerical)"), in the energy panel, in study plots, and an extra CSV column only for scenes that turn it on.

The element stress stored for crack insertion includes q. q only adds hydrostatic compression and is zero in an expanding element, so it can only lower the tension a crack test sees, and keeping it in the stored stress keeps the forces rebuilt after a node split consistent.

## Checks (`ImpactCheck --bulk-viscosity`, about 2 s)

Steel and copper reference profiles, striker plate 27 mm, target 54 mm, both 216 mm tall, ×4 mesh (2.25 mm cells). Criteria were written into the check before its first run.

| Case | Viscosity off | Viscosity on | Criterion |
|---|---|---|---|
| Elastic steel, 50 m/s: wave speed between two target stations | 5765 m/s (−1.56% of c) | 5795 m/s (−1.05%) | within 5% of c = 5856 m/s (the existing bar tolerance): pass |
| Elastic steel: ringing inside the plate (station 1) | +17.1% above ρcv/2 | +13.8% | reported |
| Elastic steel: energy error | 0.103% | 0.042% (viscous term counted) | under 0.5%: pass |
| Elastic steel: energy taken by viscosity | 0 | 3.3% of the start | reported |
| Plastic copper, 100 m/s: front width (10–90%) | 3.33 elements | 3.80 elements | at most 6 elements: pass |
| Plastic copper: overshoot above plateau | +8.4% | +3.6% | at most 5%, and lower than off: pass |
| Plastic copper: plastic work / viscous energy | 10,749 / 0 J/m | 9,525 / 6,620 J/m | reported |

What this means:

- With the setting on, waves still travel at the right speed and the energy books still balance.
- It does what it is for at a plastic front: the overshoot behind the front halves and the front stays under four elements wide.
- It does little to the ringing of a purely elastic wave (17% to 14%), because the quadratic term is tiny at elastic strain rates. That ringing is the usual Gibbs-type overshoot of a sharp front on a finite mesh. The spall check (step 5) has a negative control that tests whether it causes false cracks.
- It is not free. In the copper run it took 2.5% of the starting energy and lowered the plastic work by 11%. That is why it is off by default and reported as its own numerical term, never mixed into plastic or fracture energy.

The largest centre-line pressure in the elastic runs (+34% off, +27% on) sits one cell from the contact face, about 2.6 µs after impact. That is the penalty contact spring, not the wave in the plate.

## Regression

With viscosity off: `--legacy-replay check` identical on all 11 scenes, default `ImpactCheck` suite, `--fracture-guard`, `--supports-gravity`, `--scene-documents` and `tests/regression/run.py` (0 failures, baseline unchanged) all pass.
