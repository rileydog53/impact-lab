# Candidate build 2026-11-24 (branch candidate-2026-11-24)

Composition: PR 2 branch (claude/project-thread-sielwg, 4 fixes + crash fix) + viz-smooth-fields (smooth display, ParaView/PNG export) + regression suite (separate target, not in app) + docs index. All merges conflict-free. Solver physics files untouched: the smooth/export merge only adds 4 new files in ImpactPhysics. Geometry mesher left out. Baseline tag lab-baseline-2026-11-24 untouched.

Run on this build (release, all exit 0): legacy replay (identical on 11 scenes, bit-for-bit), default suite, --smooth-field, --results-export, --workshop-improvements, --assembly, --assembly-replay, --assembly-study, --experiment-library, --metal-profiles, --fracture, --scenario-library, --scene-documents (one run only, so the earlier unseeded-fuzz crash is not proven gone), --plasticity, --contact-handoff, --layered-impact, --supports-gravity, --lab-examples, --run-cost, --materials, and the regression suite (0 failures). Numerical verification only; no criterion loosened.

Not run: the app's own native smoke tests (--assembly-smoke etc.); nothing inspected on screen.

## Visual-fix round (branch candidate-visual-fixes)
Display and app-shell only; no solver or physics file touched. Legacy replay identical on 11 scenes (bit for bit).
1. Smooth view now uses Zienkiewicz-Zhu superconvergent patch recovery (per-node least-squares plane through neighbouring element values, clamped to the patch's own range, area-weighted fallback at poorly conditioned nodes). New check: exact for a linear field at interior nodes. Diamond shapes are reduced but not gone on a coarse mesh: they reflect the mesh, and a finer mesh is the real cure. Still labelled "interpolated display".
2. PNG colour bar: max label is right-aligned to the bar end.
3. Cancelling a Save or export dialog is silent.
4. `--assembly-inspect <file>`: Cocoa treated the bare file path as a document to open and suppressed the window. Fixed by registering NSTreatUnknownArgumentsAsOpen=NO.
5. Remembered folder: the PNG and ParaView export dialogs did not use it at all (only Open/Save did). Now they do. Seen on screen: with a remembered folder set, the dialog opens there.
6. Steel striker uncoloured in plastic-strain view is intended (elastic, no plastic field); the legend now says so.
Screenshots: candidate-logs/visual-fixes/.
