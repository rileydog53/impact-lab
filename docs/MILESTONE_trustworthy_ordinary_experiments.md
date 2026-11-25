# Milestone: trustworthy ordinary experiments

Status: proposed 25 November 2026, awaiting Joseph's acceptance. Scope: ordinary, non-violent materials testing on the existing 2-D plane-strain FEM. This milestone verifies numerics against published theory. It is not experimental validation. Engineering record section 27 (independent review) sets the cautions below.

## Goal

Turn Impact Lab from an impact tool into a small virtual materials-testing laboratory whose force, displacement and energy numbers can be read, checked and exported, and say plainly how far each one can be trusted.

## What exists (checked in source, 25 Nov 2026)

- **Clamps and reactions.** Clamped edges reset held nodes each step and zero their velocity (`Physics.swift`, `drift`/`kick`); `supportReaction` gives the clamp force and is recorded per step (`AssemblySimulation.supportReaction`). Zero displacement only; no moving boundary.
- **Moving grips.** Only in the older preset engine, tied to the cohesive-seam study (`CohesiveSeam.Grip`, `Motion`; `guidePositions`, `guideVelocitiesAndWork` in `Physics.swift`). They prescribe displacement and already account grip work, but are not available to Assembly scenes.
- **Load ramp.** `TensionCoupon.swift` ramps a force (cosine over 24 wave transits), not a displacement.
- **Gauges, measurements, CSV.** Gauges exist (`AssemblyInstrumentation.swift`); Measurements and CSV export exist in the app.
- **Not present:** displacement-controlled grips in Assembly, engineering stress-strain output, 0.2%-offset yield extraction.

## Deliverables

1. **Virtual test machine (centrepiece).** A displacement-controlled grip or platen boundary condition for Assembly scenes: prescribed position and velocity on a node set, smooth ramp, reaction force and grip work recorded. Reports force-displacement and engineering stress-strain from the gauge section. First experiments: uniaxial tension coupon and compression block (steel, aluminium), and the existing three-point bend driven by displacement.
2. **Energy ledger you can read.** Residual scaled by release work or grip work (independent of the potential-energy zero), retained 40 mm drop regression, matched uncracked control, negative control that must still be rejected (section 27.7).
3. **Geometry advisories.** Per-body notes on elements through the bending section and run cost, labelled "global response only". Fracture on drawn shapes stays off until one checked case passes.
4. **Honest measurement.** Relabel energy categories to what the solver holds (stored hardening, modelled dissipation); tag each reported quantity verified, agent-reported or hypothesis; units in CSV; no temperatures; fix the fracture smoke test (stale expectation, add timeout).

## Pass criteria (numerical verification only)

| Check | Reference | Pass |
|---|---|---|
| Elastic slope in tension and compression | Input E (plane-strain modulus stated) | within 2% |
| 0.2%-offset yield (J2 metal) | Input yield | within 2%, offset method written down |
| Reaction force vs gauge force | Section force balance | within 2% in quasi-static regime |
| Grip work vs ledger | Strain energy + dissipation + kinetic | residual within 0.5% of grip work |
| Rate independence | Halve loading speed | slope and yield change under 2% (confirms quasi-static) |
| Mesh refinement | Two refinements | reported with predeclared tolerance; not tuned |
| Bend, displacement-controlled | Euler-Bernoulli / Timoshenko beam | cantilever sag 1.2180 mm within 3%, roller sag 1.0885 mm within 2% (existing gates) |
| Drop energy | mgh scale | 0.5% budget, denominator declared in advance |

Reference literature: ASTM E8/E8M (tension), E9 (compression), E111 (modulus), Timoshenko beam theory, section 27 benchmarks. Material values stay literature-based and illustrative; agreement with theory is not experimental validation, and plane strain is not a round bar.

## Needs Joseph's typed yes

Any change to the solver path: the new grip boundary condition (it must leave every existing scene bit-identical, behind a flag, with replay fingerprints unchanged), a changed energy-guard threshold, and fracture on drawn shapes. Labels, advisories, reports, tests and docs do not.

## Out of scope

Temperature, heating or heat fraction; rate or temperature dependent hardening; raising the 150 m/s cap; MPM or any new solver; remeshing, XFEM, phase field; tensile-separation branch; notched/SENB bend; PVB rate fix; the 1.45 m/s rebound fix; linking Gmsh, MFEM or other libraries (reference runs only); headless runner (separate thread). No armor, weapon or injury applications.

## Cloud CI vs local

Cloud CI (GitHub macOS runners): all ImpactCheck gates, refinement studies, fingerprint equality against main, negative controls. Local Air: visual checks of the test-machine view and one app smoke test only.

## Order

Ledger and measurement relabels first (no solver change), then grips behind a flag with legacy-fingerprint check, then tension/compression/bend gates, then the report.
