# Version 0.2 experiment sandbox

Use the Version 0.2 card in [PLAN.md](../PLAN.md). Start from the five v0.1B presets and keep the existing solver and diagnostics in the same app.

| Slice | Implementation and acceptance |
| --- | --- |
| 0.2A Configuration | Add editing for supported dimensions, per-body elastic materials, initial positions, and velocities. Validate each configuration before restarting. All five presets must still select, edit, run, and reset through the normal app. |
| 0.2B Persistence and comparison | Save the scene definition as versioned local JSON. Compare two runs of the same preset over their shared simulated-time range. An edited puck-and-strip scene must reopen with the same configuration, reproduce its trace, and compare with the original at the same simulated times even when their solver timesteps differ. |
| 0.2C Bonded materials | Add one bar with a shared column of nodes at the interface and two element materials. Launch an axial pulse and compare reflected and transmitted stress amplitudes against the one-dimensional impedance prediction. Include higher, lower, and matched impedance. |

Keep dimensions, clearance, and velocities within the supported contact envelope. Check separation, overlap, and energy balance after edits. Keep comparison samples on a common time grid. Measure the bonded-bar waves at small amplitude before signals from the free ends reach the probes.

Stop when the native edit, save, reopen, and compare workflow, the five preset regressions, and the bonded-bar checks all pass. Keep plasticity in the next phase.
