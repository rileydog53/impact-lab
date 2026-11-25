# Headless runner

Runs any saved assembly scene without the app and writes machine-readable results.

    swift build -c release --product ImpactCheck
    .build/release/ImpactCheck run docs/scene-examples/linked-chain.json --out runs/chain --timeout 600

Outputs in the `--out` folder:

- `manifest.json`: scene SHA-256, git commit, solver settings (method, duration, mesh, dt, sample interval, gravity, bulk viscosity), every body's material values and recorded literature source, step and frame counts, replay fingerprint, final energy ledger, events, wall time, outcome.
- `energy.csv`: energy ledger per recorded frame, J per metre of depth, full precision.
- `gauges.csv`, `contacts.csv`, `links.csv`: written only when the scene has gauges, contacts or connections. Units are in the column names.
- `fields.pvd` and `vtk/frame_NNNNN.vtu`: only with `--vtk`. One ParaView file per recorded frame with the raw calculated fields: point data `displacement_m` (from t = 0) and `velocity_m_per_s`; cell data `von_mises_stress_Pa`, `mean_pressure_Pa` (positive in compression), `max_principal_stress_Pa`, `min_principal_stress_Pa`, `equivalent_plastic_strain_dimensionless`, `damage_dimensionless`, `body_index`. Nothing is smoothed. Open `fields.pvd` in ParaView. Checked in CI by `tests/vtk/check_vtk.py`. Not exported yet: stress tensor components and plastic-work density (the replay frames do not hold them).

Exit status: 0 finished, 2 scene rejected or solver guard stopped the run (the manifest says why), 3 timeout, 64 usage error.

It uses the same code path as the legacy-replay gate (`AssemblyScene` document reader, `AssemblyRun`, `AssemblyReplay`, `replayFingerprint`), so its fingerprint can be checked against `docs/legacy-replay-baseline.txt`. Verified 2026-11-25 on three scenes (linked-chain, metal-plate-impact, brittle-tile-fracture): steps and fingerprints identical to the baseline. It changes no physics.

Known gaps: the CSV columns are chosen here, not shared with the app's "Export CSV…" panel (that code lives in the SwiftUI target); the app's ParaView export (`ResultsExport.write`, which also writes nodal averages) is separate from `--vtk`; only assembly scenes are supported, not the older single-preset `SceneConfiguration` files.

Linux: not attempted. Blockers seen while reading: `CryptoKit` (swap for swift-crypto), `simd` throughout the physics, and the CClipper2 C++ build would need checking.
