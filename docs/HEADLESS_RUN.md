# Headless runner

Runs any saved assembly scene without the app and writes machine-readable results.

    swift build -c release --product ImpactCheck
    .build/release/ImpactCheck run docs/scene-examples/linked-chain.json --out runs/chain --timeout 600

Outputs in the `--out` folder:

- `manifest.json`: scene SHA-256, git commit, solver settings (method, duration, mesh, dt, sample interval, gravity, bulk viscosity), every body's material values and recorded literature source, step and frame counts, replay fingerprint, final energy ledger, events, wall time, outcome.
- `energy.csv`: energy ledger per recorded frame, J per metre of depth, full precision.
- `gauges.csv`, `contacts.csv`, `links.csv`: written only when the scene has gauges, contacts or connections. Units are in the column names.

Exit status: 0 finished, 2 scene rejected or solver guard stopped the run (the manifest says why), 3 timeout, 64 usage error.

It uses the same code path as the legacy-replay gate (`AssemblyScene` document reader, `AssemblyRun`, `AssemblyReplay`, `replayFingerprint`), so its fingerprint can be checked against `docs/legacy-replay-baseline.txt`. Verified 2026-11-25 on three scenes (linked-chain, metal-plate-impact, brittle-tile-fracture): steps and fingerprints identical to the baseline. It changes no physics.

Known gaps: the CSV columns are chosen here, not shared with the app's "Export CSV…" panel (that code lives in the SwiftUI target); the ParaView export (`ResultsExport.write`) is not yet wired in; only assembly scenes are supported, not the older single-preset `SceneConfiguration` files.

Linux: not attempted. Blockers seen while reading: `CryptoKit` (swap for swift-crypto), `simd` throughout the physics, and the CClipper2 C++ build would need checking.
