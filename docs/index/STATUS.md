# Status table of findings

Tags: **verified** = reproduced by a run or read from code/git by an agent (still numerical verification only, never physical validation); **recorded** = from an earlier evidence file, not re-run now; **agent-reported** = an agent's claim not independently checked; **hypothesis** = plausible explanation, untested; **accepted** = Joseph's personal acceptance. Sources: PLAN.md (P), Google Doc sections (GD), docs/ files, and Mac-only research notes (see WHERE_THINGS_LIVE.md). Spot-checked by me against the source text: the beam table, contact table, Card 6/7 numbers, MPM table, and Doc sections 19, 23, 24. Figures from PLAN.md for Cards 5-7 were copied as written and not re-run.

| # | Finding | Tag | Source |
|---|---|---|---|
| 1 | Card 6 (usable app, consolidated recovery build) accepted by Joseph 2026-11-24 06:49 UTC; application experience only | accepted | GD s24 |
| 2 | Beam bending: coarse triangle meshes are too stiff. First-mode period error vs Euler-Bernoulli: 2 rows -23.4%, 4 rows -7.4%, 8 rows -1.4%, 16 rows +0.26% (L/h = 20, elastic, nu = 0). About 8 rows needed for under 5% | verified (single runs, numerical only) | research/beam-verification/RESULTS.md; GD 2026-11-24 entry |
| 3 | Beam: 16-row small positive error caused by lumped-mass effect and Timoshenko correction | hypothesis | same |
| 4 | Contact: momentum transfer, rebound, deformation and energy converge and do not depend on the penalty stiffness (x1 to x8), mesh layout or timestep, for a soft elastic bend | verified | GD s17; CONTACT_GATE_REPORT |
| 5 | Raw peak contact force is a numerical artifact (grows about with the square root of penalty); never report it | verified | same |
| 6 | Windowed-average force and pulse impulse are the robust measures. Spread 0.4-0.9% metal, 1.5% soft | verified | docs/CONTACT_REPORTING.md; METAL_CONTACT_REPORT |
| 7 | Remaining mesh sensitivity of bending sag comes from CST bulk elements, not contact | hypothesis | CONTACT_GATE_REPORT |
| 8 | Low-speed metal rebound (1.45 m/s) depends on penalty (0.137 / 0.059 / 0.080 m/s); spread criterion of 5% stays OPEN on purpose | verified, unresolved | CONTACT_REPORTING.md |
| 9 | Fracture timestep: default strength gives dt 0.228 ns vs 10 ns without fracture (43.9x more steps); real Al strength is still 7-8x | verified | CONTACT_REPORTING.md |
| 10 | Card 5: parallel FEM 1.61x faster on M1 for mixed copper/steel fixture, identical fingerprint `62e6f0187b862a50` | recorded (PLAN.md) | P |
| 11 | Card 7 scenarios: wave speeds within 0.5-0.8% of bar theory; copper vs 304 hardening; bonded-layer reflection within 0.008 of 1D impedance prediction; interface crack at G꜀ 3.5 J/m² | recorded (PLAN.md) | P |
| 12 | Card 6 exercises: plastic work converged to about 0.2% under mesh refinement; local peak strain mesh-sensitive | recorded; quantitative within the model | P |
| 13 | Plastic dissipation reported as yield stress times strain, so it undercounts true plastic work for hardening metals (reported/true at 12% strain: A36 0.71, 304 0.47, 6061-T6 0.87, Cu 0.41); "Recoverable" label is misleading | verified (code reading) | research/design-notes/01 |
| 14 | Real metals store roughly 5-15% of plastic work, rest becomes heat | hypothesis | design-notes/01 |
| 15 | MPM prototype agrees with FEM where both apply (elastic rebound 0.3%, plastic work 0.6% at 50 m/s) | recorded | docs/MPM_PROTOTYPE.md |
| 16 | MPM cost ratio "4 to 25x" is unsupported: FEM ran parallel, MPM single-thread, contact thresholds differed | verified (code reading) | GD s26.11 |
| 17 | MPM beyond 150 m/s runs but the physics is not credible (no failure, rate, thermal or equation-of-state model) | recorded | MPM_PROTOTYPE.md |
| 18 | Per-step 2% energy gate runs only when fracture is on; gravitational energy not shown in Measurements | verified | GD s26 |
| 19 | Crack energy converged within 2%, crack arrival time not converged (8% and 29%) | recorded | design-notes/04 |
| 20 | Toughness values for A36 and 304 are literature-sourced experimental values, **not validated**; hardening beyond yield illustrative | agent-reported / illustrative | GD s21.5; PLAN.md |
| 21 | Material starting values (E, density, yield) are preliminary candidates; source check not recorded as done | agent-reported | PLAN.md |
| 22 | Scene JSON files: 19 built-in scenes reopen identically; every example runs with energy drift at most 0.104% | recorded | PLAN.md |
| 23 | Main and research trees: four lines of work are one linear chain (as of that note) | verified (git) | design-notes/02 |
| 24 | Known gaps: no metal failure criterion, no rate/temperature effects, crack paths mesh-dependent, parallelism limited to two lanes, no systematic code-to-GUI audit | stated in PLAN.md | P |
| 25 | Beam result is thin: single runs; no thick beams, nu other than 0, static loads or contact | stated limit | RESULTS.md |

**Possible staleness.** design-notes/04 says PR 1 was an unmerged draft; git now shows it merged into `main` (commit `f867f64`). Treat the note as written before the merge.
