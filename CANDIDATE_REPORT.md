# Candidate build 2026-11-24 (branch candidate-2026-11-24)

Composition: PR 2 branch (claude/project-thread-sielwg, 4 fixes + crash fix) + viz-smooth-fields (smooth display, ParaView/PNG export) + regression suite (separate target, not in app) + docs index. All merges conflict-free. Solver physics files untouched: the smooth/export merge only adds 4 new files in ImpactPhysics. Geometry mesher left out. Baseline tag lab-baseline-2026-11-24 untouched.

Run on this build (release, all exit 0): legacy replay (identical on 11 scenes, bit-for-bit), default suite, --smooth-field, --results-export, --workshop-improvements, --assembly, --assembly-replay, --assembly-study, --experiment-library, --metal-profiles, --fracture, --scenario-library, --scene-documents (one run only, so the earlier unseeded-fuzz crash is not proven gone), --plasticity, --contact-handoff, --layered-impact, --supports-gravity, --lab-examples, --run-cost, --materials, and the regression suite (0 failures). Numerical verification only; no criterion loosened.

Not run: the app's own native smoke tests (--assembly-smoke etc.); nothing inspected on screen.
