> COPY made 2026-11-24 for preservation. Original: research/design-notes/01-plastic-work-accounting.md on Joseph's Mac (untracked). The original wins if they differ.

# 1. Plastic-work accounting convention in ImpactPhysics

Status key: **[verified]** read in code or computed here; **[agent-reported]** from another document, not rechecked; **[hypothesis]** my inference, untested.
Source read: `main` 2593315 (J2/energy files are identical on the later branches except where noted). No code was changed.

## Where it lives [verified]
| Piece | File | What it does |
|---|---|---|
| Per-point ledger | `Sources/ImpactPhysics/J2Plasticity.swift:119-122` | `J2Response` returns `elasticEnergy`, `hardeningEnergy`, `dissipation` per reference area. |
| Dissipation | same, line 122 | `dissipation = (yieldStress ?? 0) * alpha`, with `alpha` the accumulated equivalent plastic strain and `yieldStress` the **initial** flow stress (`table.points[0].stress` for tabulated metals, line 53). |
| Stored hardening | same, line 121; `MaterialProfile.swift:58-72` (`storedEnergy`) | `H(alpha) = ∫0..alpha (σ_flow(a) − σ_y0) da` for tables; `½·H·alpha²` for the linear model. |
| Summation | `Physics.swift:800-803` | `energy.hardening += area·hardeningEnergy`, `energy.dissipation += area·dissipation`. `ElementEnergy.total = elastic + hardening + dissipation` (line 217). |
| Public name | `Physics.swift:405`, `AssemblySimulation.swift:678,693`, `AssemblyEnergy.plastic` | Exposed as "Plastic dissipation" (UI: `ComparisonView`, `ReplayMeasurements`, `AssemblyStudyView`; CSV `plastic_dissipation_J_per_m`). |
| Recoverable / dissipated split | `AssemblyReplay.swift:40-44` | `recoverableEnergy = elastic + hardening + contact + connection + cohesive`; `dissipatedEnergy = plastic + fracture`. |
| Tests | `ImpactCheck/MetalProfiles.swift:33-37`, `Plasticity.swift:54-58` | Check that the piecewise integral matches `hardeningEnergy` and `dissipation == yield·alpha`, and that dissipation is nonnegative and monotone. |
| Same convention reused | `MPMPrototype.swift` (origin/main) | Calls the same `J2Model`, stores `hardening` and `dissipation` per particle. A change here changes both solvers. |

The code comment (`MaterialProfile.swift:58-59`) states the convention outright: the increase above initial yield is "stored", and initial yield × strain is dissipated.

## What it assumes [verified]
1. Total plastic work per reference volume is `W_p = ∫ σ_eq dα = σ_y0·α + H(α)`. The code reports the first term as dissipation and keeps the second as stored energy. So the energy ledger closes exactly (`elastic + hardening + dissipation`), which is why the 1% balance gates pass.
2. All hardening work is treated as stored (recoverable class) and none is heat. Equivalent to a Taylor–Quinney-style fraction of `β = σ_y0/σ_flow`, which falls with strain, not a material constant.
3. Stress measure: tabulated flow stresses are Kirchhoff (documented at `J2Plasticity.swift:84-85`); energies are per **reference** area, so `τ:D^p` per reference volume is consistent. Plane strain; units J/m (per metre of depth).
4. `alpha` is monotone nondecreasing, and `HardeningTable.isValid` requires nondecreasing stress, so `H ≥ 0` today. No softening, cyclic or kinematic hardening, so no Bauschinger energy.

## Does it match true plastic work for hardening materials? **No** [verified]
`dissipation` equals true plastic work only for perfectly plastic behaviour. For hardening materials it undercounts by exactly `H(α)`. Ratio reported/true for uniform strain, from the shipped tables (my calculation, trapezoid integral of the table):

| Profile | α = 2% | α = 6.2% | α = 12% |
|---|---|---|---|
| A36 steel | 0.95 | 0.82 | 0.71 |
| 304 stainless | 0.75 | 0.57 | 0.47 |
| 6061-T6 | 0.97 | 0.92 | 0.87 |
| Copper C11000 | 0.67 | 0.50 | 0.41 |

Consequences:
- **Naming** [verified]: PLAN.md and research PLAN.md quote "plastic work 1,180 J/m (copper) vs 1,229 J/m (304)" and the UI says "Plastic dissipation". These are yield×strain sums, not plastic work. The claim "similar plastic work" for copper vs 304 is therefore an artifact of the convention: stainless hardens much more, so its true work is higher relative to this figure. [hypothesis: the true-work gap for the actual impact cases is smaller than the uniform-strain table because mean α in the impact is below peak; it needs a run to quantify.]
- **"Recoverable" is misleading** [verified]: `recoverableEnergy` includes `hardening`, but nothing in the solver ever releases hardening energy back to kinetic or elastic energy (isotropic hardening, α never decreases). It is an accounting entry that stays on the books after unloading. [hypothesis, physical]: real metals store roughly 5–15% of plastic work as cold work; the rest is heat. Here the stored share is `H/W_p`, up to ~50–60% for copper and 304.
- Numerical verification is unaffected (energy still balances); this is a physical-interpretation issue.

## What must be settled before any thermomechanical implementation
Decisions only; no thermal implementation is proposed here.
1. **Define the ledger terms.** Introduce explicit `plasticWork` (= σ_eq·α̇ integrated), and from it two named parts: heat-generating (dissipated) and stored cold work. Decide whether stored fraction is a material constant (β) or derived. Today's split is neither.
2. **Rename or relabel** "Plastic dissipation" and the "plastic work" claims in docs and exports, or keep the old quantity under an honest name ("yield-level dissipation").
3. **Decide whether `hardening` energy stays in `recoverableEnergy`.** It should not be called recoverable unless a mechanism releases it.
4. **Closed forms stop working.** `storedEnergy(at: alpha)` and `σ_y0·α` assume flow stress depends on α alone. Once flow stress depends on temperature or rate, plastic work must be accumulated incrementally per step (`W_p += σ_eq·Δα`). This changes the model interface and the MPM prototype.
5. **Stress/volume consistency.** Heating per unit current mass or volume needs ρ0·c_p per reference volume with Kirchhoff stress; confirm that choice and that J≈1 in plastic flow is not assumed implicitly.
6. **Source for β and for tables.** Tables are marked illustrative (`evidence` strings, e.g. "Post-yield hardening is illustrative"). Thermal results are only as defensible as those inputs.
7. **Fracture heat.** Cohesive/material fracture dissipation (`fractureDissipation`) is a separate ledger line; decide whether it heats the process zone.
8. **Test plan** (numerical verification before physical validation): adiabatic uniaxial point test with analytic `ΔT = β·W_p/(ρ c_p)`, ledger closure to <1e-10, unchanged results when β/thermal are off, and convention flag so the old numbers remain reproducible.
9. **Joseph's decision needed**: whether to relabel existing reported numbers now, or only when thermal work starts.
