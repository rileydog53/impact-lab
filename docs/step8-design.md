# Layered target plan, step 8: design notes

Written 25 November 2026 as a read-only design audit of `main` at `d17e841` (after PR 8). Step 8 of the "Impact Lab Layered Target Plan" reads: "Allow fracture on supported bodies, and raise the 150 m/s cap behind a run-time warning, first in a test-only path to find where the mesh actually fails." No pull request was open when this was written, so nothing here overlaps open work.

Nothing was built or run. This cloud machine has no Swift, and the code needs Apple's `simd` and CoreGraphics. Every number below is read from the code, worked by hand or in a short Python script (formulas copied from the code), or taken from a cited source. No solver file was changed.

How claims are marked:

- **[code]** read directly from the Swift source on `main`, with file and line.
- **[calc]** a hand or scripted calculation done for this note.
- **[source]** checked against the linked page during this audit.
- **[recall]** from memory of the literature, not checked against a source during this audit. Treat these as leads to confirm.

---

## Summary

| Part | Conclusion |
|---|---|
| 1. Fracture on supported bodies | Only **clamped** bodies are blocked. A body **resting on** a fixed support (a bench, two rollers) can already have fracture; the PR 4 drop-on-bench check runs exactly that. The block is one validation line, and it is there for a real reason: when a crack splits a node on a clamped edge, the new copy of that node is not on the clamp list, so part of the clamped edge would silently come free. The smallest safe change is to remove that line for clamps only and carry the clamp over to every copy of a held node after each split, about five lines in `AssemblySimulation.swift`. Fixed (rigid) supports stay unbreakable. |
| 2. Above 150 m/s | The cap is not one physics threshold. **Strain-rate hardening in steel already matters at ordinary impact speeds** (about +17% flow stress at 50 m/s, +19 to +24% at 150 m/s), while 6061-T6 is nearly rate-insensitive. The **pressure–volume** model is within about 1% of shock data at 150 m/s and drifts to 5% near 450 m/s (steel) and 600 m/s (aluminium beyond its existing offset). **Adiabatic heating** gives 30–60 K local rises at 150 m/s, and over 10% softening from roughly 220–300 m/s (steel) and 340–450 m/s (aluminium). **Element distortion** did not stop copper at 150 m/s; scaling that result suggests steel is safe to about 220 m/s and aluminium to about 340 m/s, but this must be measured. |
| 3. Benchmarks | Fracture: the ASTM E399 single-edge notched three-point bend, with a worked prediction (9.58 kN per metre of depth for the beam proposed). It needs a narrow notch the app does not have yet, and it does not exercise clamps, so a clamped cantilever check is added as an option. High speed: the Taylor test as asked, with published test conditions, **but the code is plane strain and a Taylor test is a cylinder**, so it cannot be compared number for number. A symmetric plate impact against published shock data fits the code exactly and is offered as the alternative. Both choices are Joey's. |

Two places where the spec and the code disagree are flagged, not substituted: "resting on a support" is already allowed (the real block is clamps), and the Taylor cylinder is axisymmetric while the code is plane strain. See "Questions for Joey" at the end.

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

**Resting on a support is already allowed.** `supportConflict` only looks at the body that has the support. A free body with fracture sitting on a `.fixed` bench, or a beam on two fixed rollers, passes validation. The PR 4 check `ImpactCheck --fracture-guard` drops a fracturing block onto a `.fixed` bench [code, `Sources/ImpactCheck/FractureGuard.swift` line 14], and that check was reported passing on Joey's Mac before PR 4 merged. The supplied scene `docs/scene-examples/notched-beam-fracture.json` is a fracturing beam on two support bodies (those are free elastic bodies in that file, not `.fixed`).

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

Turning strain into speed: the repo's own FEM run of copper at 150 m/s reached 168% peak plastic strain, and 27% at 50 m/s [code/record: `docs/MPM_PROTOTYPE.md` table]. Scaling by ρv²/σ (12% flow stress) [calc, rough]: copper at 150 m/s has 0.89; steel reaches that at about 223 m/s and 6061 at about 337 m/s. At 150 m/s steel sits at 0.40 and 6061 at 0.18, between the two copper runs, so local peaks of roughly 30–90% strain, 30–60 K, 2–5% softening. Over 10% local softening needs strain above about 1.3 (steel) or 1.0 (6061), so from roughly 220–300 m/s for steel and 340–450 m/s for aluminium. These speed ranges are estimates from one geometry and should be replaced by the sweep in Part 3.

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

### Fracture: supported three-point bend (ASTM E399 SE(B))

**The textbook result** [source: ASTM E399-12, Annex A3, [copy](https://sites.utexas.edu/taleff/files/2019/10/astm_e399_12.pdf)]: span S = 4W (A3.1.1); K = P·S / (B·W^{3/2}) · f(a/W) (Eq. A3.1, plain-sided specimen); "for a/W = 0.500, f(a/W) = 2.66" (Note A3.1); the expression is accurate within 1% for 0.2 ≤ a/W ≤ 1 with S/W = 4 (Note A3.2); test crack size 0.45W to 0.55W (7.2.1).

f(a/W) = 3√(a/W)·[1.99 − (a/W)(1 − a/W)(2.15 − 3.93(a/W) + 2.7(a/W)²)] / [2(1 + 2a/W)(1 − a/W)^{3/2}]. The equation was garbled in the extracted text, so the coefficients are [recall], but they reproduce the standard's own check value, f(0.5) = 2.663 [calc]. f(0.45) = 2.285, f(0.55) = 3.142 [calc].

**Proposed case** [calc]: a 2D beam, W 100 mm, crack a 50 mm, span 400 mm, on two `.fixed` rollers, loaded slowly from the top centre. Illustrative material chosen so the cohesive zone is resolved: E 1.0 GPa, ν 0.2, strength σₜ 4.5 MPa, fracture energy G 100 J/m².

- K_Ic = √(E'·G) = 0.323 MPa√m, with E' = E/(1 − ν²) in plane strain.
- Characteristic length l_ch = E'G/σₜ² = 5.1 mm. Ligament 50 mm ≈ 10 l_ch.
- Predicted peak load per metre of depth: P = K·W^{3/2} / (S·f) = **9.58 kN/m**.
- Total fracture work to break the ligament: G × 50 mm = **5.0 J/m**.

**Criteria to fix before the first run** (suggested): crack starts at the notch tip; peak load below the LEFM value and moving toward it on a larger beam (cohesive cracks at modest W/l_ch give lower peaks than LEFM, which is the large-size limit [recall: Bažant and Planas 1998, "Fracture and Size Effect in Concrete and Other Quasibrittle Materials"]); fracture work within 10% of 5.0 J/m; kinetic energy under 1% of stored energy at peak load (quasi-static); two meshes with at least 3 elements across l_ch on the finer one [recall: cohesive zones need about 3 or more elements, Turon et al. 2007].

**Gaps to know about:**

- **The app has no narrow notch.** `Notch` is a V-notch whose width is at least 12% of the block's length [code, `AssemblyScene.swift` line 50]. On a 400 mm beam that is a 48 mm wide notch, which is a blunt notch, not a crack, and the formula does not apply. This benchmark needs either a narrow slot (a small geometry addition) or an outline body with a slot, and outline bodies cannot fracture yet [code, `AssemblyAdvisories.swift` line 54].
- **It does not test the Part 1 change.** The rollers are separate `.fixed` bodies, which already work.

**Optional second check that does test Part 1: clamped cantilever.** Reuse the clamped beam of `Sources/ImpactCheck/SupportsGravity.swift` (line 115, `.clampLeft`), with fracture on and a slow tip load. Beam theory per metre of depth: root bending stress σ = 6PL/h² [recall, textbook beam theory]. With the material above, L 200 mm and h 20 mm, the first crack should start at the root at P ≈ **1.5 kN/m** [calc], earlier on finer meshes because of the corner singularity. Pass criteria would be: every copy of every clamped node stays at zero displacement through the whole run; the support reaction balances the tip load; the crack starts at the root; legacy replay unchanged.

### High speed: Taylor impact test (as asked), with a caveat

**What it is:** a flat-ended cylinder hits a rigid wall; its final length and mushroomed face width test strength at high rate [source: Taylor 1948, Proc. R. Soc. London A 194, 289–299, cited in the [LS-DYNA verification manual VM-027](https://ansyshelp.ansys.com/public/views/secured/corp/v261/en/lsdyna_vm/vm-lsdyna-solve-027.html)].

**Published test conditions** [source: Banerjee, "Validation of the material point method and plasticity with Taylor impact tests", Tables 1–2, [arXiv](https://arxiv.org/pdf/1201.2476)]:

- OFHC copper: L₀ 25.4 mm, D₀ 7.62 mm at 130, 146 and 190 m/s (Johnson and Cook 1983); 23.47 mm at 210 m/s (Wilkins and Guinan 1973).
- 6061-T6: L₀ 23.47 mm, D₀ 7.62 mm at 373 and 603 m/s; L₀ 46.94 mm at 275 and 484 m/s (Wilkins and Guinan 1973). Also 30 × 6 mm at 200 and 358 m/s (Gust 1982).
- 4340 steel (Rc 30): 25.4 × 7.62 mm at 208 m/s, 12.7 mm at 282 m/s, 8.1 mm at 343 m/s (Johnson and Cook 1983). This row was read from a summary of the paper, not verbatim.
- The copper 190 m/s case is the one used by both LS-DYNA (VM-027) and Ansys (VM-EXD-MECH-003, 2D axisymmetric) [source].

**Reference numbers not yet confirmed.** The experimental final lengths and face diameters are printed only in figures in the papers above, which this audit could not read. They need to be taken from Johnson and Cook 1983 Fig. 9–10 or Wilkins and Guinan 1973 (J. Appl. Phys. 44, 1200) [recall for the Wilkins–Guinan citation].

**The caveat: plane strain is not a cylinder.** Impact Lab is 2D plane strain, so it models an infinitely deep slab, not a round bar. A slab's face can only spread sideways in one direction, so it shortens differently from a cylinder of the same material and speed. The cylinder numbers cannot be used as pass or fail values for this code. What can be compared is the 1D Taylor estimate of final length from yield strength (Taylor 1948; Wilkins and Guinan 1973), which depends mainly on ρv²/σ and length [recall], loosely and with a wide tolerance. Using the Taylor test properly would need an axisymmetric mode, which the solver does not have.

**Alternative that fits the code exactly: symmetric plate impact against shock data.** A flat plate hitting an equal plate is one-dimensional strain in its middle, which a plane-strain code represents exactly, and the repo already has this setup (`Sources/ImpactCheck/PlateImpact.swift`, used by the step 4 and 5 checks). The reference is published Hugoniot data: for 2024 aluminium (LASL standard above) the predicted plateau pressure is 1.13 GPa at 150 m/s, 3.94 GPa at 500 m/s and 8.35 GPa at 1,000 m/s [calc from the source fit]. Run elastic-plastic at 150, 300, 500 and 1,000 m/s, compare the plateau with the fit, and the gap measures exactly the pressure–volume error in Part 2. It would not test rate hardening or heating, which the code does not have yet anyway.

---

## Questions for Joey

1. **Supported or held?** Bodies resting on supports can already fracture. Should step 8's fracture half target clamped (held) bodies, as written above? Fixed supports would stay unbreakable.
2. **High-speed benchmark:** keep the Taylor test as asked, knowing the code can only compare with it loosely, or use the symmetric plate impact against shock data, which the code can match exactly? Both can be done; the choice changes what "pass" means.
3. **Fracture benchmark:** the three-point bend needs a narrow notch the app does not have. Add one as part of step 8, or use the clamped cantilever check for now?

## What this audit did not do

- Nothing was built or run; no Swift on this machine.
- No solver or app file was changed. Only this file was added.
- Not read: LASL pages for 6061 and 304, the Taylor test figures, and the full Hodowany 2000 paper. Those values are marked [recall].
- The speed thresholds for heating and distortion are rough scalings of one repo result, not measurements.
