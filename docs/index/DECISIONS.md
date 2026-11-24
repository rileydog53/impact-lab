# Decision record: approved versus not approved

Source of truth is the Google Doc (sections 6, 19, 23, 24) and Joseph's own words. Agent recommendations are never decisions. The Google Doc was only read, not edited, for this index.

## Approved by Joseph

| When | Decision | Doc ref |
|---|---|---|
| 2026-11-24 00:52 UTC | 1. Common boundary approach (shared scene, units, measurement and result records); no multi-engine protocol until a second engine needs it | s19 |
| same | 2. Standalone reference calculator, convergence protocol, and design notes for loads, scene v2, material state (independent of the production solver) | s19 |
| same | 3. Beam-bending verification before more constitutive physics | s19 |
| same | 4. Compressible fluids stay on the research horizon; literature and scoping only, no implementation | s19 |
| same | 5. Investigate and document the plastic-work convention before any thermal work | s19 |
| same | 6. Resolve the main-versus-research source tree question before integrating new capabilities | s19 |
| 2026-11-24 | Contact reporting correction (reporting only; contact law unchanged) | s17c |
| 2026-11-24 | Materials architecture: approved **in principle only**, not implemented | s17c |
| 2026-11-24 03:09 UTC | Recovery direction with adjustments: one consolidated build; control explanations, runtime estimates; fixed supports and gravity first; spring anchors, edit-a-copy, preload; configurable run-time warnings (estimate above 30 s, confirm above 2 min, warn above 10 min); keep safeguards and legacy compatibility; non-violent examples | s23 |
| 2026-11-24 06:49 UTC | **Card 6 accepted** for the consolidated build, application experience only, not scientific validation | s24 |
| 2026-11-24 | Merge of PR 1 (the accepted build) into main, per project instructions; the merge exists on `main` | project instructions; git |
| Standing | D-001 keep FEM as production while evaluating others; D-002 MPM stays a research prototype; D-003 cohesive separation continues as research only (not a validated predictor) | s6 |
| Standing (2026-11-24) | Direction: matter and state first, methods interchangeable, adopt existing open-source work within licence; never discard FEM | memory / project instructions |

## Not approved (proposals awaiting Joseph)

| Item | Where |
|---|---|
| P-001 local crack remeshing; P-002 XFEM, phase-field, SPH, ALE or hybrid replacement | s6 |
| Next milestone: fracture verification as a first-class capability (s25.5), and options in 25.6 (integration path, geometry instead, P1 UI batch, housekeeping) | s25 |
| Architecture reassessment D1-D9: adopt concept layering; plastic-work convention (keep stored-as-cold-work vs heat fraction beta); thermal variable (internal energy vs temperature); whether the beam result satisfies decision 3; order of fracture vs heating demo; UI-only "honest continuous picture" batch; slow thermal horizon; installing external reference tools (Taichi, FEniCSx, Gmsh as separate programs); MPM stays cross-check | s26.11 |
| Roadmap in s18 and its questions D1-D8 (D2 and D8 partly overtaken by later approvals) | s18.8 |
| Scene v2, material-state slot and ledger channel; relabelling "Plastic dissipation" / "Recoverable" | design-notes/01, 03; s26 |
| Loads/boundary design (fixed supports by elimination or stiff penalty; gravity default) | design-notes/03 (note: supports and gravity were later built and approved under s23) |
| Experimental tensile-fracture integration (material-separation branch): held out on purpose | s23, s24 |
| Materials architecture implementation (absolute physical properties, tensile strength in Pa, fracture energy in J/m²) | MATERIAL_PROPERTIES_ARCHITECTURE |

## Not decisions at all
Contact gate, metal contact, Opus research return (s12-14), and design notes are **research findings or agent assessments**, even where phrased firmly.

*Noted ambiguity:* PLAN.md in the older research tree calls its Phase 0 architecture "Agreed" without naming who agreed; treat as historical.
