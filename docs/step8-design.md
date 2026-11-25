# Layered target plan, step 8: design notes

Written 25 November 2026 as a read-only design audit of `main` at `d17e841` (after PR 8). Step 8 of the "Impact Lab Layered Target Plan" reads: "Allow fracture on supported bodies, and raise the 150 m/s cap behind a run-time warning, first in a test-only path to find where the mesh actually fails." No pull request was open when this was written, so nothing here overlaps open work.

Nothing was built or run. This cloud machine has no Swift, and the code needs Apple's `simd` and CoreGraphics. Every number below is read from the code, worked by hand or in a short Python script (formulas copied from the code), or taken from a cited source. No solver file was changed.

Revised the same day after Joey's answers to the three questions: step 8's fracture half targets clamped bodies, the main high-speed check is plate-on-plate impact against LASL shock data, and the fracture check now is the clamped cantilever, with the notched three-point bend as a follow-up. See "Decisions" at the end.

How claims are marked:

- **[code]** read directly from the Swift source on `main`, with file and line.
- **[calc]** a hand or scripted calculation done for this note.
- **[source]** checked against the linked page during this audit.
- **[recall]** from memory of the literature, not checked against a source during this audit. Treat these as leads to confirm.

---

## Summary

| Part | Conclusion |
|---|---|
| 1. Fracture on clamped bodies | The block is one validation line, and it is there for a real reason: when a crack splits a node on a clamped edge, the new copy of that node is not on the clamp list, so part of the clamped edge would silently come free. The smallest safe change is to remove that line for clamps only and carry the clamp over to every copy of a held node after each split, about five lines in `AssemblySimulation.swift`. Fixed (rigid) supports stay unbreakable. Bodies **resting on** a fixed support are allowed to fracture and the crack test runs on them every step, but **no recorded run has shown a crack there yet**: both PR 4 runs inserted 0 cracks. A one-run Mac check is proposed to confirm it. |
| 2. Above 150 m/s | The cap is not one physics threshold. **Strain-rate hardening in steel already matters at ordinary impact speeds** (about +17% flow stress at 50 m/s, +19 to +24% at 150 m/s), while 6061-T6 is nearly rate-insensitive. The **pressure–volume** model is within about 1% of shock data at 150 m/s and drifts to 5% near 450 m/s (steel) and 600 m/s (aluminium beyond its existing offset). **Adiabatic heating** gives 30–60 K local rises at 150 m/s, and over 10% softening from roughly 220–300 m/s (steel) and 340–450 m/s (aluminium). **Element distortion** did not stop copper at 150 m/s; scaling that result suggests steel is safe to about 220 m/s and aluminium to about 340 m/s, but this must be measured. |
| 3. Benchmarks | High speed, main check: **symmetric plate-on-plate impact against LASL shock data (Marsh 1980)**, reusing `PlateImpact.swift`; predicted plateau 1.13, 3.94 and 8.35 GPa at 150, 500 and 1,000 m/s for 2024 aluminium. High speed, trend only: the Taylor test, labelled **plane strain, not a round-bar match**. Fracture, now: the **clamped cantilever**, first crack at the root near 1.5 kN/m, which tests the Part 1 fix directly. Fracture, follow-up: the notched three-point bend (ASTM E399 SE(B)), 9.58 kN/m peak; it needs a narrower notch than the editor allows today. |

The first version flagged two places where the spec and the code disagreed, and Joey has decided both: the fracture work targets clamps, and the Taylor test is kept only as a plane-strain trend check because the code cannot model a round bar.

---

## Part 1. Why fracture is blocked on supported or held bodies

### What the code does today

**The block itself.** `AssemblyPart.supportConflict` [code, `Sources/ImpactPhysics/AssemblyScene.swift` line 188]:

```swift
if fracture != nil { return "Supports cannot be combined with fracture yet (crack insertion would move the held nodes)." }
```

`isValid` requires `supportConflict == nil` [code, same file line 204], so any scene with a support and fracture on the same body is refused, both in the editor and when a scene file is loaded.

**What a support is.** `Support` has five cases [code, line 129]: `.fixed` (a rigid body that never deforms) and four clamps (`clampLeft`, `clampRight`, `clampBottom`, `clampTop`), where only the nodes on one edge are held.

- A `.fixed` body is never calculated as a deforming body: `drift`, `assemble` and `kick` return early [code, `Physics.swift` lines 314, 327, 374]. Cracking it means nothing, so keeping fracture off there is correct, not a limitation. The advisory already says so [code, `AssemblyAdvisories.swift` line 64].
- A clamped body is an ordinary deforming body with a list of held node indices, `BodyStep.clamped` [code, `Physics.swift` line 290]. The list is built once at the start of the run from the reference mesh [code, `AssemblySimulation.swift` lines 412–414, `AssemblyScene.swift` `clampedNodes` line 283]. Held nodes are reset to their position after every drift and their velocity is zeroed after every kick [code, `Physics.swift` lines 315 and 381].

**Resting on a support: allowed, but not yet shown to crack.** Checked in the code, not assumed:

- `supportConflict` only looks at the body that has the support [code, `AssemblyScene.swift` line 188]. A free body with fracture sitting on a `.fixed` bench, or a beam on two fixed rollers, passes validation.
- The crack test runs on every body that has fracture, every step, with no check for supports or contact: `nextFractures[i]!.insert(position:piola:mesh:)` is called for each body with fracture [code, `AssemblySimulation.swift` lines 857–862]. It reads `trialPiola`, the stress after all of the step's forces, so the load from a fixed bench or roller is included. The only switch that turns it off is `insertionEnabled`, a test-only argument that defaults to true [code, same file lines 376 and 400].
- So the code path is there. But **a crack on a support has not been demonstrated.** The PR 4 check `ImpactCheck --fracture-guard` drops a fracturing block onto a `.fixed` bench [code, `Sources/ImpactCheck/FractureGuard.swift` line 14]. It requires only that the run finishes; it prints the number of cracks but does not require any [code, same file lines 38 and 90]. The PR 4 review runs on Joey's Mac reported 0 cracks for both the drop and the three-point-bend scene [record: PR 4 reviews].
- The likely reason is strength, not a block. The default crack strength is 3% of the body's E [code, `MaterialFractureSettings.strengthFraction` 0.030]. In the three-point-bend lab scene (`docs/lab-examples/three-point-bend.json`: E 10 MPa, bar 0.3 × 0.025 m, rollers 260 mm apart) that is 0.3 MPa, while the bending stress from the bar's own weight plus the 30 mm weight is of order 20 kPa [calc, rough].

**Proposed confirming check (Mac, one run, not done here).** Run the three-point-bend lab scene with fracture on and an absolute crack strength of 1e4 Pa (the bottom of `absoluteStrengthRange`). Expect the first crack at the bottom face near midspan. Make it pass or fail by requiring `insertedEdges > 0` and that the first cracked face lies in the middle third of the span. A second run at the default strength should still show 0 cracks, which confirms the strength explanation. Neither run touches the solver.

**Why the clamp case was blocked.** When a crack opens, `MaterialFracture.insert` duplicates nodes. It keeps every old node at its old index and appends the new copies at the end, returning `sources`, a map from each new node to the old node it came from [code, `MaterialFracture.swift` lines 354–365, `sources = Array(mesh.reference.indices)` then `sources.append(parent)`]. `BodyStep.splitNodes` rebuilds the body from that map [code, `Physics.swift` lines 340–371]. But nothing updates `clamped` [code, `AssemblySimulation.swift` line 866 is the only call]. So if a crack reaches a held node:

- the original copy (old index) stays held;
- the new copy is not in `clamped`, so from the next step it moves freely.

That is part of the clamped edge coming loose without anyone asking for it. The old message's wording, "would move the held nodes", describes this.

### Smallest safe change (proposal only, not made)

Three pieces, in this order.

1. **Carry the clamp over to new copies after each split** [`AssemblySimulation.swift`, right after the `splitNodes` call at line 866]:

   ```swift
   if !steps[i].clamped.isEmpty {
       let held = Set(steps[i].clamped)
       steps[i].clamped = split.sources.indices.filter { held.contains(split.sources[$0]) }
   }
   ```

   Because old nodes keep their index, the list only grows; every copy of a held node is held. This is safe with the existing rejected-step rollback, because the rollback restores the whole `BodyStep` (including `clamped`) from `beforeSplit` [code, the `defer` at line 849]. The copy's position is the parent's held position, since `splitNodes` takes positions from the parent [code, `Physics.swift` line 359] and `drift` already reset that parent. Its velocity is zeroed by the next `kick`.

2. **Relax the validation line for clamps only** [`AssemblyScene.swift` line 188]:

   ```swift
   if fracture != nil && support.isFixture { return "A fixed support is rigid and cannot fracture." }
   ```

   and in `fractureUnavailableReason` keep the `.fixed` message and drop the clamp one [`AssemblyAdvisories.swift` lines 62–66].

3. **Update the words that say it is impossible**: `AssemblyEditor.swift` lines 216 and 1119, the `support` description in `docs/scene-format.schema.json` line 118, and `docs/SCENE_FORMAT.md` line 67.

**Why this is the smallest safe one.** It touches no element, contact or crack formula. With no clamped fracturing body in a scene, the new lines never run, so every existing scene replays bit-identically. That should be confirmed with `--legacy-replay check` on the Mac, as for every earlier step.

**What it does not fix, and the risks to test.**

- **The clamp corner is a stress singularity.** In plane strain the stress at the end of a clamped edge grows as the mesh is refined [recall: Williams 1952, "Stress singularities resulting from various boundary conditions in angular corners of plates in extension"]. With a strength-based crack test the first crack there will start earlier on finer meshes. This is real physics for a glued clamp, but the result is mesh-dependent, so the check below needs two meshes.
- **The support reaction.** `supportReaction` sums the forces on `clamped` [code, `Physics.swift` line 386]. After the change it includes the copies, which is what you want; before, the reported reaction would have missed them.
- **The energy guard.** Held nodes do no work, so the PR 4 energy rule is unchanged. Not checked by running.
- **Gravity moment.** `initialHeightMoments` is computed once at the start [code, `AssemblySimulation.swift` line 422]. Node splits conserve mass and position, so this should be unaffected, as for free bodies. Not checked by running.

---

## Part 2. Physics that stops being trustworthy above about 150 m/s

### What the model is today

- **Elastic:** compressible neo-Hookean, volumetric term λ·ln J [code, `Physics.swift` line 941].
- **Plastic:** rate-independent J2 (von Mises) plasticity with Hencky-type pressure −K·ln J / J [code, `Physics.swift` line 967; `J2Plasticity.swift`]. Hardening follows the reference profile's table and is flat after the last point at 12% strain [code, `MaterialProfile.swift` lines 130 and 46–55].
- **No strain-rate term, no equation of state beyond ln J, no temperature.** The temperature channel is reserved and empty [code, `MaterialState.swift` lines 26–27].
- **Triangles (three-node) in a Lagrangian mesh, no remeshing and no element deletion.** A run stops with "An element inverted" [code, `AssemblySimulation.swift` lines 795, 810].
- **The cap:** `AssemblyPart.velocityRange = -150.0...150.0` [code, `AssemblyScene.swift` line 140], checked in `isValid` (line 207) and in scene loading [code, `SceneDocument.swift` lines 596–597].

Materials used below are the app's own reference profiles [code, `MaterialProfile.swift` lines 136 and 150]: A36-like steel (E 200 GPa, ν 0.30, ρ 7850, yield 250 MPa, 440 MPa at 12%) and 6061-T6 (E 68.9 GPa, ν 0.33, ρ 2700, yield 276 MPa, 345 MPa at 12%).

How speed turns into strain rate, pressure and strain [calc, rough]: for a body about 25 mm long, the average strain rate is about v/L, so 2,000 /s at 50 m/s and 6,000 /s at 150 m/s; near the contact face it is several times higher. A symmetric impact gives particle speed v/2 and pressure ρ·Us·(v/2). Peak plastic strain grows with ρv²/σ (Taylor's damage number, [recall]).

### The four effects

| Effect | Steel (A36-like) | Aluminium (6061-T6) |
|---|---|---|
| Strain-rate hardening (Johnson–Cook) | Already matters below 150 m/s: about +17% at 50 m/s, +19 to +24% at 150 m/s | Small at any speed in reach: about +2% at 150 m/s |
| Pressure–volume (Mie–Grüneisen) | Within 1% at 150 m/s; −5% near 450 m/s; −13% at 1,000 m/s | Already 13% soft at all speeds (a modulus issue, below); the high-speed part adds −1% at 150, −4% at 500, −8% at 1,000 m/s |
| Adiabatic heating | 30–60 K local at 150 m/s (2–4% softening); over 10% from about 220–300 m/s | Similar local rise at 150 m/s; over 10% from about 340–450 m/s |
| Element distortion | Probably fine to about 220 m/s; must be measured | Probably fine to about 340 m/s; must be measured |

The detail and the sources for each row follow.

#### Strain-rate hardening (Johnson–Cook)

Johnson–Cook writes flow stress as σ = (A + B·εⁿ)(1 + C·ln ε̇*)(1 − T*ᵐ), with ε̇* = ε̇ / 1.0 s⁻¹ [source: Johnson and Cook 1983, "A constitutive model and data for metals subjected to large strains, high strain rates and high temperatures", 7th Int. Symp. on Ballistics, text at [archive.org](https://ia800406.us.archive.org/4/items/AConstitutiveModelAndDataForMetals/A%20constitutive%20model%20and%20data%20for%20metals_text.pdf); read from an OCR copy, so digits should be checked against the scan]. The rate constants in its Table 1:

| Material | C | Source |
|---|---|---|
| 1006 steel | 0.022 | [source, JC 1983 Table 1] |
| 4340 steel | 0.014 | [source, JC 1983 Table 1] |
| 2024-T351 aluminium | 0.015 | [source, JC 1983 Table 1] |
| 7039 aluminium | 0.010 | [source, JC 1983 Table 1] |
| OFHC copper | 0.025 | [source, JC 1983 Table 1; same values in [Banerjee 2005, Table 4](https://arxiv.org/pdf/cond-mat/0512466)] |
| 6061-T6 aluminium | about 0.002 | [recall: the widely used 6061-T6 set A 324 MPa, B 114 MPa, n 0.42, C 0.002, m 1.34; not confirmed this audit] |

The factor 1 + C·ln ε̇* with C = 0.022 [calc]:

| Speed | Average rate | Steel factor (1006, C 0.022) | 6061-T6 factor (C 0.002) |
|---|---|---|---|
| 50 m/s | 2,000 /s | 1.17 (1.22 near the contact) | 1.015 |
| 150 m/s | 6,000 /s | 1.19 (1.24) | 1.017 |
| 500 m/s | 20,000 /s | 1.22 (1.27) | 1.020 |

So for steel the effect is **not** a high-speed effect. A 5% rise needs only about 10 /s, which is well under 1 m/s for a 25 mm body [calc: ln ε̇ = 0.05/0.022]. Every steel impact the app runs today is already about 15–25% too soft in flow stress. Raising the cap does not create this error; it is there now. 6061-T6 is nearly rate-insensitive, but the other aluminium alloys in the same table (2024, 7039) behave more like steel, so the warning should not say "aluminium is fine".

The rate dependence is also known to steepen above about 10³–10⁴ /s, beyond what the log term captures [source: Lesuer 1999, LLNL UCRL-ID-13469, [UNT digital library](https://digital.library.unt.edu/ark:/67531/metadc623770/m2/1/high_res_d/11977.pdf), which names the JC model's behaviour above about 10³ /s as its "major concern"; OCR copy].

**Warning text:** "Strength does not rise with loading rate in this model. For steels this already makes impacts tens of percent too soft at any speed; above 150 m/s the gap grows. Treat deformation and dent depth in steel as an upper bound."

#### Pressure–volume behaviour (Mie–Grüneisen)

Shock data is usually given as a straight line, shock speed Us = c₀ + s·uₚ, with uₚ the particle speed; Mie–Grüneisen builds the pressure model around it [source: Banerjee 2005 eq. 3, [arXiv](https://arxiv.org/pdf/cond-mat/0512466), which also notes the fit is good below a compression of 1.3].

Reference fits:

- **2024 aluminium:** ρ₀ 2.785 g/cm³, c₀ 5.328 km/s, s 1.338, Γ 2.00 [source: Marsh (ed.), LASL Shock Hugoniot Data, 1980, Table II impedance standards, [copy](https://ancient.hydro.nsc.ru/chem/biblio/lasl_shock.pdf); third-party copy, columns misaligned in the extracted text].
- **6061 aluminium:** c₀ 5.35 km/s, s 1.34 [recall; LASL lists 6061 on p. 182, not read].
- **Steel (304 stainless used as a stand-in for A36):** c₀ 4.57 km/s, s 1.49 [recall; LASL lists 304 on p. 212, not read]. Pure iron is not a good stand-in because of its phase change near 13 GPa [recall].

The app's pressure at the same compression is −K·ln J / J. Expanding both for small compression η = 1 − J [calc]: the app gives K(η + 1.5η²), the shock fit gives ρ₀c₀²(η + 2sη²). So the app is right at small compression and gets softer as compression grows, because its effective s is about 0.75 against the measured 1.3–1.5.

Symmetric impact, same material, pressure at the Hugoniot's own compression [calc, script copies the code's formula]:

| Speed | Steel shock fit | App | Gap | 6061 shock fit | App | Gap |
|---|---|---|---|---|---|---|
| 50 m/s | 0.90 GPa | 0.91 | +0.8% | 0.36 | 0.32 | −13.1% |
| 150 m/s | 2.76 | 2.74 | −0.8% | 1.10 | 0.95 | −14.0% |
| 500 m/s | 9.70 | 9.11 | −6.1% | 3.84 | 3.18 | −17.2% |
| 1,000 m/s | 20.9 | 18.2 | −12.9% | 8.13 | 6.39 | −21.4% |

Two separate findings:

1. **The high-speed error is small at 150 m/s.** It reaches 5% beyond the low-speed value near 450 m/s for steel and near 600 m/s for aluminium. The thermal (Γ) part of Mie–Grüneisen only matters off the shock curve, on release from high pressure, so it is smaller still at these speeds [recall].
2. **6061-T6 is about 13% too soft in compression at every speed, today.** The app derives the bulk modulus from E 68.9 GPa and ν 0.33, giving K 67.5 GPa and a bulk sound speed of 5,002 m/s. Shock data implies ρ₀c₀² ≈ 77 GPa (5,350 m/s) [calc]. The profile marks ν as "estimated" [code, `MaterialProfile.swift` line 154]. This is a material-data issue below the cap, not a step 8 issue; it is flagged here because it would show in any high-speed benchmark. Steel's bulk sound speed (4,608 m/s) matches its shock c₀ (4,570 m/s) within 1%.

**Warning text:** "Pressure under strong compression uses a simple elastic law. It is close to measured shock data up to a few hundred m/s, and too soft above about 450 m/s in steel and 600 m/s in aluminium (5% or more)."

#### Adiabatic heating

At impact rates there is no time for heat to leave, so most plastic work becomes a local temperature rise: ΔT = β·σ·εₚ / (ρ·cₚ). β ≈ 0.9 is the usual assumption [source: Banerjee 2005, "assumed to be 0.9 in all our simulations", citing Taylor and Quinney 1934, [arXiv](https://arxiv.org/pdf/cond-mat/0512466)]. Measured β depends on strain, and for 2024-T3 not on rate between 10⁻³ and 10⁴ /s [source: Hodowany, Ravichandran, Rosakis and Rosakis 2000, Experimental Mechanics 40(2) 113–123, [abstract](https://authors.library.caltech.edu/55288)]. Heating softens through the JC term (1 − T*ᵐ), T* = (T − 298)/(T_melt − 298).

Constants: steel cₚ 452 J/kg·K, T_melt 1811 K, m 1.00 (1006 steel) [source, JC 1983 Table 1]; 6061 cₚ 896 J/kg·K, T_melt 925 K, m 1.34 [recall]. Flow stress taken as the profile's 12% value [code].

| Plastic strain | Steel ΔT | Steel softening | 6061 ΔT | 6061 softening |
|---|---|---|---|---|
| 0.3 | 33 K | 2.2% | 39 K | 2.4% |
| 0.5 | 56 K | 3.7% | 64 K | 4.7% |
| 1.0 | 112 K | 7.4% | 128 K | 11.9% |
| 1.7 | 187 K | 12.4% | 216 K | 23.9% |

[calc]

Turning strain into speed: the repo's own FEM run of copper at 150 m/s reached 168% peak plastic strain, and 27% at 50 m/s [code/record: `docs/MPM_PROTOTYPE.md` table]. Scaling by ρv²/σ (12% flow stress) [calc, rough]: copper at 150 m/s has 0.89; steel reaches that at about 223 m/s and 6061 at about 337 m/s. At 150 m/s steel sits at 0.40 and 6061 at 0.18, between the two copper runs, so local peaks of roughly 30–90% strain, 30–60 K, 2–5% softening. Over 10% local softening needs strain above about 1.3 (steel) or 1.0 (6061), so from roughly 220–300 m/s for steel and 340–450 m/s for aluminium. These speed ranges are estimates from one geometry and should be replaced by the test-only sweep proposed under "One warning, proposed shape".

Heating and rate hardening push in opposite directions, and the app has neither, so the two errors partly cancel in steel at moderate speeds [recall]. Heating also drives adiabatic shear bands in steels; a model without heating cannot form them, and if it did they would be one element wide and mesh-dependent [recall].

**Warning text:** "Plastic work does not heat the material in this model. Above about 200 m/s in steel and 350 m/s in aluminium, real metal near the impact softens by 10% or more and can form narrow shear bands that this model cannot show."

#### Element distortion

The mesh is three-node triangles that follow the material, with no remeshing and no deletion. Large local strain flattens triangles: the time step shrinks with the smallest triangle height, so runs get slower, and when a triangle turns inside out the run stops [code, `AssemblySimulation.swift` lines 795, 810]. Plane-strain triangles under volume-preserving plasticity can also lock (come out too stiff), which is step 6's test [record: plan doc step 6].

The only measured point: FEM copper at 150 m/s, 168% peak plastic strain, energy error 0.03%, mesh did not fail [record: `docs/MPM_PROTOTYPE.md`]. Scaled as above, steel and 6061 should reach the same severity at about 223 and 337 m/s. Where the mesh actually fails is unknown and depends on geometry and refinement; this is exactly the measurement step 8 says to make in a test-only path.

**Warning text:** "Above 150 m/s the mesh may distort badly near the impact. If the run stops with an inverted element, or the time step shrinks sharply, the result near the contact is not reliable; try a finer mesh and compare."

### One warning, proposed shape

A single advisory in the existing `AssemblyAdvisories.swift` style (never blocking) whenever any body's speed is over 150 m/s, with one line per effect above, the steel line first when a steel profile is used. Keep the app cap at 150 m/s until the test-only sweep below has run; then raise it to the measured limit with this warning shown. Suggested test-only path: an `ImpactCheck --speed-sweep` that builds scenes directly (bypassing `velocityRange` the way `MPMComparison.swift` lines 158–161 guard against it today) at 150, 200, 300, 450, 600 m/s for steel and 6061 on two meshes, and records time-step shrink, energy error, peak plastic strain and the speed of the first inverted element. Proposal only.

---

## Part 3. Benchmarks

Chosen by Joey: plate impact is the main high-speed check, Taylor is a loose trend check, the clamped cantilever is the fracture check now, and the notched three-point bend follows later.

### High speed, main check: symmetric plate-on-plate impact against LASL shock data

**Why this one.** A flat plate hitting an equal plate is one-dimensional strain in its middle, which a plane-strain code represents exactly, and the repo already has the setup (`Sources/ImpactCheck/PlateImpact.swift`, used by the step 4 and 5 checks). Until the release waves from the edges arrive, the pressure in the middle of the contact sits on a flat plateau whose value follows from the shock fit alone.

**Reference.** Published Hugoniot data, Marsh (ed.), LASL Shock Hugoniot Data, 1980 [source, Table II impedance standards, [copy](https://ancient.hydro.nsc.ru/chem/biblio/lasl_shock.pdf)]. For 2024 aluminium: ρ₀ 2.785 g/cm³, c₀ 5.328 km/s, s 1.338. For a symmetric impact at speed v, the particle speed is v/2 and the plateau pressure is P = ρ₀·(c₀ + s·v/2)·(v/2) [calc, standard jump condition]:

| Impact speed | Particle speed | Plateau pressure (2024 Al, LASL fit) |
|---|---|---|
| 150 m/s | 75 m/s | 1.13 GPa |
| 300 m/s | 150 m/s | 2.31 GPa |
| 500 m/s | 250 m/s | 3.94 GPa |
| 1,000 m/s | 500 m/s | 8.35 GPa |

[calc from the source fit]

For steel and 6061 the LASL pages were not read this audit; the fits in Part 2 (304 stainless c₀ 4.57, s 1.49; 6061 c₀ 5.35, s 1.34) are [recall] and should be checked against LASL pp. 212 and 182 before they set a pass value. The 2024 row is the one confirmed number set, so the first run should use a 2024-like aluminium profile (E and ν set so that K matches ρ₀c₀², about 79 GPa).

**What to measure.** The plateau pressure at the middle of the contact, averaged over the flat part of the pressure history before edge release arrives, plus the shock speed from the arrival time at two depths. Run at 150, 300, 500 and 1,000 m/s, elastic-plastic, on two meshes.

**Pass criteria to fix before the first run** (suggested): within 2% of the fit at 150 m/s; the gap at higher speed reported, not failed, because Part 2 predicts it (about −1% at 150, −4% at 500 and −8% at 1,000 m/s for an aluminium whose bulk modulus matches c₀); the two meshes agree within 1%. The measured gap then becomes the number in the pressure–volume line of the warning. This check does not test rate hardening or heating, which the code does not have yet.

### High speed, trend check only: Taylor impact (plane strain, not a round-bar match)

**Label for the check and its output:** "Taylor-style trend check, plane strain. Not comparable with round-bar Taylor test results."

**What it is:** a flat-ended cylinder hits a rigid wall; its final length and mushroomed face width test strength at high rate [source: Taylor 1948, Proc. R. Soc. London A 194, 289–299, cited in the [LS-DYNA verification manual VM-027](https://ansyshelp.ansys.com/public/views/secured/corp/v261/en/lsdyna_vm/vm-lsdyna-solve-027.html)].

**Published test conditions** [source: Banerjee, "Validation of the material point method and plasticity with Taylor impact tests", Tables 1–2, [arXiv](https://arxiv.org/pdf/1201.2476)]:

- OFHC copper: L₀ 25.4 mm, D₀ 7.62 mm at 130, 146 and 190 m/s (Johnson and Cook 1983); 23.47 mm at 210 m/s (Wilkins and Guinan 1973).
- 6061-T6: L₀ 23.47 mm, D₀ 7.62 mm at 373 and 603 m/s; L₀ 46.94 mm at 275 and 484 m/s (Wilkins and Guinan 1973). Also 30 × 6 mm at 200 and 358 m/s (Gust 1982).
- 4340 steel (Rc 30): 25.4 × 7.62 mm at 208 m/s, 12.7 mm at 282 m/s, 8.1 mm at 343 m/s (Johnson and Cook 1983). This row was read from a summary of the paper, not verbatim.
- The copper 190 m/s case is the one used by both LS-DYNA (VM-027) and Ansys (VM-EXD-MECH-003, 2D axisymmetric) [source].

**Reference numbers not yet confirmed.** The experimental final lengths and face diameters are printed only in figures in the papers above, which this audit could not read. They need to be taken from Johnson and Cook 1983 Fig. 9–10 or Wilkins and Guinan 1973 (J. Appl. Phys. 44, 1200) [recall for the Wilkins–Guinan citation].

**Why it is only a trend check.** Impact Lab is 2D plane strain, so it models an infinitely deep slab hitting a wall, not a round bar. A slab's face can only spread sideways in one direction, so it shortens differently from a cylinder of the same material and speed. The published cylinder lengths cannot be pass or fail values for this code, and an axisymmetric mode would be needed for a real match.

**What it can check.** The direction and rough size of trends: final length falls as speed rises and as yield strength falls, steadily, with no jump where the mesh starts to fail; and the slab's final length sits in the same broad range as the 1D Taylor estimate from ρv²/σ [recall: Taylor 1948; Wilkins and Guinan 1973]. Suggested runs: a 25.4 mm long, 7.62 mm thick slab at 130, 146 and 190 m/s in a copper profile, and 6061 at 200, 275 and 373 m/s. Suggested pass: final length decreases monotonically with speed and stays within about 25% of the 1D estimate. That tolerance is a guess, not a published number.

### Fracture, now: clamped cantilever

**Why this one.** It exercises exactly the Part 1 change: a crack that starts at a clamped edge splits clamped nodes, and the copies must stay held.

**Setup.** Reuse the clamped beam of `Sources/ImpactCheck/SupportsGravity.swift` [code, line 115, `.clampLeft`], with fracture on and a tip load that rises slowly. Suggested case: length L 200 mm, depth h 20 mm, the illustrative material from the follow-up below (E 1.0 GPa, ν 0.2, strength 4.5 MPa, fracture energy 100 J/m²), so the cohesive length is 5.1 mm; the finer mesh needs at least three elements across it [recall: Turon et al. 2007].

**Reference.** Beam theory per metre of depth: root bending stress σ = 6PL/h² [recall, textbook beam theory]. The first crack should start at the top fibre at the root when σ reaches the strength, at P ≈ **1.5 kN/m** [calc: 4.5e6 × 0.02² / (6 × 0.2)]. The clamp corner is a stress singularity [recall: Williams 1952], so on finer meshes the first crack will start somewhat earlier; the check should report the first-crack load on two meshes rather than require an exact match.

**Pass criteria** (suggested):

- every copy of every clamped node stays at zero displacement for the whole run, including after cracks reach the clamped edge;
- the support reaction balances the tip load within 1% while the beam is still uncracked;
- the first crack starts at the root, on the tension face;
- the first-crack load is at or below 1.5 kN/m and moves toward it on the coarser mesh, not away;
- `--legacy-replay check` is unchanged, since no saved scene has a clamped fracturing body.

### Fracture, follow-up: notched three-point bend (ASTM E399 SE(B))

**The textbook result** [source: ASTM E399-12, Annex A3, [copy](https://sites.utexas.edu/taleff/files/2019/10/astm_e399_12.pdf)]: span S = 4W (A3.1.1); K = P·S / (B·W^{3/2}) · f(a/W) (Eq. A3.1, plain-sided specimen); "for a/W = 0.500, f(a/W) = 2.66" (Note A3.1); the expression is accurate within 1% for 0.2 ≤ a/W ≤ 1 with S/W = 4 (Note A3.2); test crack size 0.45W to 0.55W (7.2.1).

f(a/W) = 3√(a/W)·[1.99 − (a/W)(1 − a/W)(2.15 − 3.93(a/W) + 2.7(a/W)²)] / [2(1 + 2a/W)(1 − a/W)^{3/2}]. The equation was garbled in the extracted text, so the coefficients are [recall], but they reproduce the standard's own check value, f(0.5) = 2.663 [calc]. f(0.45) = 2.285, f(0.55) = 3.142 [calc].

**Proposed case** [calc]: a 2D beam, W 100 mm, crack a 50 mm, span 400 mm, on two `.fixed` rollers, loaded slowly from the top centre. Illustrative material chosen so the cohesive zone is resolved: E 1.0 GPa, ν 0.2, strength σₜ 4.5 MPa, fracture energy G 100 J/m².

- K_Ic = √(E'·G) = 0.323 MPa√m, with E' = E/(1 − ν²) in plane strain.
- Characteristic length l_ch = E'G/σₜ² = 5.1 mm. Ligament 50 mm ≈ 10 l_ch.
- Predicted peak load per metre of depth: P = K·W^{3/2} / (S·f) = **9.58 kN/m**.
- Total fracture work to break the ligament: G × 50 mm = **5.0 J/m**.

**Criteria to fix before the first run** (suggested): crack starts at the notch tip; peak load below the LEFM value and moving toward it on a larger beam (cohesive cracks at modest W/l_ch give lower peaks than LEFM, which is the large-size limit [recall: Bažant and Planas 1998, "Fracture and Size Effect in Concrete and Other Quasibrittle Materials"]); fracture work within 10% of 5.0 J/m; kinetic energy under 1% of stored energy at peak load (quasi-static); two meshes with at least 3 elements across l_ch on the finer one [recall: cohesive zones need about 3 or more elements, Turon et al. 2007].

**What it needs first.** Joey noted that the geometry editor can already cut notches. It can, but only a V-notch whose width is at least 12% of the block's length [code, `AssemblyScene.swift` lines 49–51, `widthFraction` 0.12 to 0.36], and whose depth is at most 45% of the height (`depthFraction` up to 0.45). On a 400 mm beam the narrowest notch is 48 mm wide, which is a blunt notch, not a crack, and the E399 formula does not apply to it. The depth limit is fine, since E399 accepts a/W from 0.45. So the cheap addition is a narrower width limit, or a separate thin-slot option, for blocks; outline bodies are not an alternative yet because they cannot fracture [code, `AssemblyAdvisories.swift` line 54]. This is a small geometry change, not a solver change, and it fits Joey's "cheap to add later".

**It does not test the Part 1 change.** The rollers are separate `.fixed` bodies, which already pass validation.

---

## Decisions (Joey, 25 November 2026)

1. **Supported or held:** the fracture half targets clamped (fixed-edge) bodies. Rigid `.fixed` supports stay unbreakable. That bodies resting on supports already crack was to be confirmed in the code: the code path is confirmed, a crack is not yet shown, and a Mac check is proposed in Part 1.
2. **High-speed benchmark:** plate-on-plate impact against LASL shock data (Marsh 1980) is the main check. The Taylor test stays only as a loose trend check, labelled plane strain, not a round-bar match.
3. **Fracture benchmark:** the clamped cantilever now, because it tests the clamp fix. The notched three-point bend is a follow-up.

## What this audit did not do

- Nothing was built or run; no Swift on this machine.
- No solver or app file was changed. Only this file was added.
- Not read: LASL pages for 6061 and 304, the Taylor test figures, and the full Hodowany 2000 paper. Those values are marked [recall].
- The speed thresholds for heating and distortion are rough scalings of one repo result, not measurements.
