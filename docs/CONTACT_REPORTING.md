# Contact reporting

Approved by Joseph on 24 November 2026 after the soft and metal contact verification gates (Google Doc sections 17 and 17b). The approval covers **reporting only**. The contact formulation (node-to-edge penalty, stiffness, timestep) did not change, and existing results replay identically.

## What is reported

| Quantity | Status | Where |
|---|---|---|
| **Pulse impulse** (N·s/m) | Headline. Window-free and the most robust measure (spread 0.4–0.9% metal, 1.5% soft across penalty ×1–×8 and mesh layout). | Study view, pulse CSV |
| Pulse start, end, duration, **mean force** = impulse ÷ duration | Reported with every pulse. | Study view, pulse CSV |
| **Windowed force** (trailing moving average) | Always reported together with its window. | Study CSV `load_avg_<window>` columns, pulse CSV |
| **Raw step peak** | Numerical diagnostic only. It scales roughly with √(penalty) and changes with mesh. | Labelled as such everywhere |
| **Overlap** | Shown both ways: % of the local edge, and absolute depth (µm or mm). | App metrics, study view, CSV |

## Pulse detection

The solver turns contact on and off many times inside one physical contact (node-scale chatter): 93–219 on/off episodes in a 0.8 ms metal run. To keep that chatter from being reported as separate physical events:

- **Merging.** Loaded spans separated by less than the **merge gap** count as one pulse. The number of solver episodes merged into each pulse is still reported.
- **Minor touches.** Pulses whose impulse is below **1%** of the largest pulse are counted separately as minor touches (count and total impulse), not listed as pulses.
- **Bookkeeping.** Every pulse impulse plus the minor impulse adds up to the pair's total impulse. ImpactCheck checks this.

## Windows and gaps

- **Basis.** Both the windows and the merge gap come from the **element wave-transit time** τ: characteristic element size √(2 × mean triangle area) divided by the longitudinal wave speed. For each contact pair, τ is the slower of its two bodies.
- **Common across cases.** Within a study, τ is the largest across all cases, so every case uses **the same physical windows**. Convergence comparisons are then made over common physical windows, never over mesh-dependent ones.
- **Merge gap** = 5 τ.
- **Windows** = 10 τ rounded up to a 1-2-5 value, plus half and double that. The three are reported together so the window dependence stays visible.

These multiples are **empirical guidelines from one fixture** (the notched elastic bend, soft and metal), not universal constants:

- The penalty and mesh spread of the averaged force fell to about 2.5% at 10 τ in both materials.
- Merging at 5 τ grouped the early pulses identically across penalties.

**The averaged value itself keeps falling as the window lengthens past the pulse.** A windowed force is only meaningful with its window stated and when the window is shorter than the pulse.

## Known open issue, kept on purpose

**Low-speed metal rebound** (steel striker on Al beam, 1.45 m/s, ×3) depends on penalty: 0.137, 0.059 and 0.080 m/s at ×1, ×2 and ×4. The first 250 µs (three pulses) agree within 0.4%. The later re-contacts differ. At 10 m/s the rebound agrees within 1%.

`ImpactCheck --contact-reporting` keeps this as:

- **An unresolved numerical sensitivity.** The criterion (≤ 5% spread) is reported as **OPEN** and is not relaxed. If it ever passes, the gate asks for review.
- **A regression benchmark.** The three rebound values must match the recorded reference to 1e-5 m/s. A change means the solver changed and must be explained.

## Fracture strength and timestep (verified)

With fracture settings, the cohesive strength is `strengthFraction × E`, and its stiffness enters the timestep bound. Measured on the Al beam at ×3 (`--contact-reporting`):

| strengthFraction | cohesive strength | dt | vs no fracture (10 ns) |
|---|---|---|---|
| 0.03 (default) | 2,067 MPa | 0.228 ns | 43.9× smaller |
| 0.015 | 1,034 MPa | 0.454 ns | 22.0× smaller |
| 0.0075 | 517 MPa | 0.902 ns | 11.1× smaller |
| 0.005 (minimum allowed) | 344 MPa | 1.34 ns | 7.5× smaller |

The timestep is inversely proportional to the cohesive strength. Real 6061-T6 tensile strength (about 310 MPa) is just below the allowed range, so even a realistic strength costs about 7–8× more steps than no fracture. This is evidence for the material-properties architecture proposal (approved in principle, not implemented).

## Verify

```sh
swift build -c release
.build/release/ImpactCheck --contact-reporting   # about 2 min
.build/release/ImpactCheck --assembly-study      # includes the pulse CSV check
```
