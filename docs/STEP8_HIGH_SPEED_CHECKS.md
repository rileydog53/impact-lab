# Plate impact and Taylor trend at or below 150 m/s (layered target plan, step 8, second part)

Added 2026-11-25. These are the high-speed benchmarks of [`step8-design.md`](step8-design.md) Part 3, run **only at or below the app's 150 m/s cap**, as verification. Joseph's direction (2026-11-25): the cap does not move, and higher speeds are recorded as notes for later (see [`SPEED_LIMIT.md`](SPEED_LIMIT.md)).

**Status: numerical verification, not physical validation.** Test only, no solver change.

## Plate-on-plate impact (`ImpactCheck --plate-impact`, about 15 s)

The code is in `Sources/ImpactCheck/PlateLASL.swift`.

**Setup.** Equal plates of a 2024-like aluminium: a 54 mm striker hits a 108 mm target, both 216 mm tall.

**Material.**

- K is matched to the LASL fit: ρ0 c0² = 79.06 GPa (ρ0 2785, c0 5328 m/s).
- E is 73.1 GPa, so ν is 0.346.
- Y is 345 MPa, perfectly plastic.
- Bulk viscosity is on.

**Measurement.** Measured 12 µs after contact, before any release wave reaches the centre band:

- **σxx:** the force across each cut in the centre band.
- **Mean pressure:** the solver's pressure field.

**References.**

- **A. Elastic-perfectly-plastic wave theory in uniaxial strain, with the run's own constants.** Below the Hugoniot elastic limit (HEL, 732 MPa here) a single elastic wave carries σxx = ρ c_L u. Above it, an elastic precursor at the HEL runs ahead of a plastic wave at the bulk speed c_B.
- **B. The LASL shock fit for 2024 aluminium** (Marsh 1980): P = ρ0 (c0 + s u) u, with s = 1.338.

Criteria were written before the first run. At 50 m/s, σxx within 2% of the elastic value. At 100 and 150 m/s, σxx and mean pressure within 3% of reference A. The x4 and x6 meshes within 1%. The gap to LASL is reported only.

| Impact speed | σxx (x4) vs theory A | Mean pressure vs K εxx | Plastic front speed vs c_B 5328 | σxx vs LASL fit |
|---|---|---|---|---|
| 50 m/s (elastic) | 448.8 MPa, +0.18% | +0.24% | (no plastic wave) | +20% |
| 100 m/s | 869.0 MPa, +0.14% | +0.85% | 5309 m/s | +16% |
| 150 m/s | 1244.0 MPa, +0.43% | +1.30% | 5166 m/s | +9.7% |

- **Meshes:** x6 against x4 agree within 0.26%.
- **Energy error:** at most 0.035%.

**What the LASL gap means.** The model reproduces its own wave theory to under 0.5%. It does not match the LASL fit at these speeds, and that is expected [calc, standard shock physics].

The LASL fit describes the hydrodynamic part of strong shocks, where strength is a small share of the stress. At 150 m/s the elastic limit alone is about 60% of the stress. Below a few GPa, the material's strength sets the longitudinal stress, not the fitted Hugoniot.

The two quantities bracket the fit:

- **Mean pressure** sits about 10% below it, because the fast elastic precursor carries part of the load at lower compression.
- **Longitudinal stress** sits about 10% above it, because of strength.

So the LASL fit cannot test this code below the cap. A test against it needs speeds of roughly 500 m/s and above, where the hydrodynamic part dominates. That stays a note for later, as decided.

## Taylor-style trend check (`ImpactCheck --taylor-trend`, about 20 s)

**Label: plane strain, not comparable with round-bar Taylor test results.**

The code is in `Sources/ImpactCheck/TaylorTrend.swift`. A slab 25.4 mm long and 7.62 mm thick hits a rigid wall end-on.

Criteria were written before the first run. Every run must reach its end, and the final length must fall strictly as the speed rises. Joseph dropped the 25% band, so the deviation from the 1D estimate Lf/L0 = exp(−ρv²/2Y) [recall: Taylor 1948; Wilkins and Guinan 1973] is recorded, not gated.

| Material, speed | Lf/L0 (x6) | 1D estimate, initial yield | 1D estimate, flow stress at 12% strain |
|---|---|---|---|
| Annealed copper, 100 m/s | 0.853 | 0.524 | 0.820 (+4%) |
| Annealed copper, 130 m/s | 0.768 | 0.336 | 0.716 (+7%) |
| Annealed copper, 146 m/s | 0.717 | 0.253 | 0.656 (+9%) |
| 6061-T6, 100 m/s | 0.968 | 0.952 (+2%) | 0.962 (+1%) |
| 6061-T6, 125 m/s | 0.952 | 0.926 (+3%) | 0.941 (+1%) |
| 6061-T6, 150 m/s | 0.933 | 0.896 (+4%) | 0.916 (+2%) |

- Final length falls steadily with speed for both materials on both meshes.
- x6 against x4 agree within 1.1% (copper) and 0.06% (6061).

The annealed copper hardens a lot (69 to 225 MPa over the curve). The 1D formula with its initial yield therefore badly overpredicts the shortening. With the hardened flow stress it comes within 4 to 9%.

## Not done here

- The clamped-cantilever crack-load benchmark (first crack near 1.5 kN/m). It needs a moving platen or loading nose. The moving grip in PR 17 is the first part of that.
- The notched three-point bend.
- Any check above 150 m/s.
