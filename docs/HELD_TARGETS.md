# Fracture on held bodies (layered target plan, step 8, first part)

Added 2026-11-25. This follows `step8-design.md` Part 1 and Joseph's decisions recorded there. Run with `ImpactCheck --clamped-fracture` (about 20 minutes). The code is in `Sources/ImpactCheck/ClampedFracture.swift`.

**Status: numerical verification of the bookkeeping, not physical validation.**

## What changed

- **A clamped body can now use fracture.** When a crack splits a node on the clamped edge, every copy of that node stays held (`BodyStep.splitNodes`, `Physics.swift`: five lines). Before this, the new copy was not on the held list, so part of the clamped edge would have come loose without anyone asking for it. That is why the combination was blocked.
- **A fixed support still cannot fracture.** It is rigid and never calculated as a deforming body. The editor now offers only clamps when fracture is on, and turning a body into a fixed support switches its fracture off.
- With no clamped fracturing body in a scene the new lines never run, so every older scene replays bit for bit (`--legacy-replay check`).

## Checks (criteria written before each first run)

| Check | Result | Criterion |
|---|---|---|
| Glass cantilever (100 × 12 mm, clamped left), struck near its tip at 20 m/s | 177 crack faces, 11 of them touching the clamped edge; held nodes went from 7 to 18 as cracks split them, and none ever moved (largest movement or speed exactly 0); energy error 0.19% | cracks, energy under 2%, held nodes never move: pass |
| Control at 5 m/s: fracture on but too strong to crack, against fracture off, same time step and contact stiffness | largest node difference exactly 0 | exact match: pass |
| Three-point-bend lab example resting on fixed rollers, crack strength 1e4 Pa | first crack at 5.44 ms at midspan (x = 0) on the bottom face (y = −11.5 mm of ±12.5) | cracks, first crack in the middle third of the span: pass |
| Same at the default strength (3% of E, 0.3 MPa) | no crack in 300 ms | no crack: pass |

**The control was amended after its first run.** That run compared fracture on and fracture off at different time steps: with fracture on the solver uses a smaller, conservative step and twice the contact stiffness (see `FractureGuard.swift`). The two runs differed by 41 µm. The control now matches the step and the contact stiffness, as the fracture guard's own control does, and still requires an exact match. It also uses a 5 m/s strike with a 200 MPa strength, so the control never cracks and runs in reasonable time.

**Resting bodies.** The code always ran the crack test on a body resting on a fixed support. The three-point-bend run is the first recorded run that shows such a crack. It confirms that the earlier zero-crack runs came from the default strength (about ten times the bending stress there), not from a block.

## Not done yet (next part of step 8)

- The design's clamped-cantilever benchmark: a slowly rising tip load, first crack at the root near 1.5 kN/m by beam theory, on two meshes. The app has no applied load or moving grip for that loading yet. The cantilever above tests the clamp bookkeeping, not the crack load.
- The notched three-point bend (ASTM E399) and the narrower notch it needs.
- Speeds above 150 m/s: see [`SPEED_LIMIT.md`](SPEED_LIMIT.md).
