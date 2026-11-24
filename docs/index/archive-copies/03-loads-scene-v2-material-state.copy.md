> COPY made 2026-11-24 for preservation. Original: research/design-notes/03-loads-scene-v2-material-state.md on Joseph's Mac (untracked). The original wins if they differ.

# 3. Design notes: loads, scene v2, generic material state

Design only. No production code touched. Status key: **[verified]** read in code; **[hypothesis]** a proposal for Joseph to approve or change. Baseline for file references: `origin/main` (724e32b), which adds `SceneDocument.swift`.

## 0. What the code does today [verified]
- **No loads or constraints.** `SceneDocument.unsupported` rejects `gravity, bodyForce, load(s), force, pressure, fixed, clamped, constraint(s), temperature, strainRate…` with an explanatory message. Motion comes only from initial velocities, contact and connections. The only prescribed-motion precedent is `TensionLoad` (grips) inside `Physics.swift`, used by the tension coupon.
- **Versioning is a hard constant.** `AssemblyScene.assemblyVersion` is `private(set) var … = 1`; `validate()` requires `== 1`; `SceneDocument` fails on any other value; the JSON schema has `"assemblyVersion": {"const": 1}`.
- **Four concerns are mixed inside one `AssemblyPart`**: physical properties (`material`: E, ρ, ν, provenance), constitutive law (`plasticity`: response, yield fraction, hardening `table`; `fracture`: strength fraction relative to E, energy), numerical configuration (`refinement`, scene `meshResolution`, hidden step scale and penalty stiffness set at simulation init), and initial/evolving state (none in the scene; `J2History` and fracture seam state live only inside the running simulation).
- **State is hard-coded.** `J2History` = inverse plastic metric (3 doubles + zz) + `equivalentStrain`, double-buffered `current/next` per element (`Physics.swift`). Damage is a per-seam/face quantity in `MaterialFracture`/`CohesiveSeam`, exposed to replay as `damage: [Double]` in `AssemblyReplayBody`. No temperature anywhere.
- **Energy ledger** (`AssemblyEnergy`: kinetic, elastic, contact, connection, hardening, plastic, fracture, cohesive) has no external-work term; `relativeEnergyError` is measured against the initial kinetic energy.

## 1. Loads  [hypothesis]
Goal: let Joseph apply gravity, pressure/traction, point forces and prescribed motion without scripting.

Separate **loads** (forces) from **boundary conditions** (kinematic constraints). Both are new top-level arrays in scene v2, never fields inside parts.

```
loads: [ { id, kind: "gravity" | "bodyForce" | "traction" | "pressure" | "pointForce",
           target: { body: <part id>, selector: <see below> },
           magnitude | vector, unit-checked,
           curve: <amplitude curve id or constant> } ]
boundaryConditions: [ { id, kind: "fixed" | "prescribedVelocity" | "symmetry" | "roller",
                        target, curve } ]
curves: [ { id, points: [[t, value], …], interpolation: "linear" | "step" } ]
```
- **Targeting that survives remeshing:** select by geometry, not node indices: `{ edge: "left"|"right"|"top"|"bottom" }`, `{ region: box in body coordinates }`, or `{ bodyFraction: … }`. Mesh resolution is a numerical choice and must not change what a load means. (Existing code already resolves refinement per part, so a selector→nodes resolver at body creation fits.)
- **Energy accounting:** add `externalWork` to `AssemblyEnergy`; the balance becomes `kinetic+stored+dissipated−externalWork`. Prescribed motion work = reaction×displacement (precedent: grip reactions noted at `Physics.swift:349`). Without this term the existing 1% gates cannot be used for loaded scenes.
- **Time stepping:** explicit solver, so loads are evaluated at step start; ramps are required to avoid shock-loading artefacts; stable timestep is unchanged by loads but changes with stiff constraints (penalty vs elimination) — decide before implementing `fixed`.
- **Validation hooks:** gravity free-fall (exact), statically loaded bar (needs damping or a quasi-static ramp: flag as a numerical-method question), prescribed-velocity bar (reuses `TensionLoad` physics).
- **Open choices for Joseph:** (a) fixed support via elimination vs stiff penalty; (b) whether gravity defaults off.

## 2. Scene v2 (versioned, migration, legacy replay)  [hypothesis]
Principles: v1 files must open forever and reproduce identical results; v2 must be additive; unknown settings are still rejected.

1. **Freeze v1.** Keep a `SceneV1` Codable struct that is never edited again, plus the existing normalize/validate rules for `assemblyVersion: 1`. The current `AssemblyScene` becomes the in-memory/runtime model (internally v2).
2. **Pure, tested migration** `v1 → v2`: in memory only; fills new sections (`loads: []`, `boundaryConditions: []`, `curves: []`, `materialState: nil`, `solver: defaults`). The migrated scene carries `migratedFrom: 1` for provenance. A v1 file is **never rewritten** unless the user saves, and saving offers "Save as v2" (v1 export kept for sharing while features used are all v1-representable).
3. **Legacy replay guarantee (acceptance test):** every shipped scene (`docs/scene-examples/*.json`, `docs/showcase/*.json`, Metal Impact Example) is run through both the v1 path and migrated-v2 path; results must match exactly (the repo already records "metal-plate-impact.json reproduces … 60,220 steps, 2,350 J/m plastic" as a precedent for exact reproduction). The hidden numerical defaults currently baked into init (step scale, penalty stiffness) are written into the v2 `solver` block with the **same values** so old scenes do not drift.
4. **Version handling in `SceneDocument`:** accept 1 and 2; `assemblyVersion` in a v1 file may not contain v2-only keys (error, with suggestion to set version 2); the `unsupported` map becomes version-aware (e.g. `gravity` is rejected in v1 but valid in v2). Schema becomes `oneOf` by version.
5. **v2 section layout (four-way separation):**
```
materials:   [ { id, name, properties: { density, young, poisson, (later: cp, conductivity) }, provenance } ]
constitutive:[ { id, model: "j2-tabulated" | "j2-linear" | "elastic" | …, version, parameters, uses: <material id> } ]
parts:       [ { id, geometry, material: <id>, constitutive: <id>, initialVelocity, initialState: {…}, refinement? } ]
solver:      { meshResolution, stepScale, contactStiffnessScale, duration, sampling }
loads / boundaryConditions / curves   (section 1)
```
   Physical properties, constitutive law + parameters, evolving state, and numerical configuration each get their own section. Today's `fracture.strengthFraction` (a fraction of E) mixes law and property; in v2 store absolute strength with units and convert on migration.
6. **Units:** every new quantity states SI units in the schema; no mixed mm/MPa fields.
7. **Replay/result files** carry the scene version and `constitutive model version`; replays of old results are read-only and need no migration.
8. **Risks:** the `private(set)` version and size cap (128 KB in `open`) both need to change; `Equatable` scenes compared in the UI will include new arrays; `bodyOrder`/`groups` organisation must remain outside solver semantics.

## 3. Generic material-state slot (temperature, damage)  [hypothesis]
Goal: add evolving per-point state without editing the solver loop each time.

- **Per-element state channels**, declared by the constitutive model: `StateChannel { name, unit, kind: scalar|sym2|vec2, initial, bounds, monotonic?, recorded: Bool }`. The model publishes a schema (`J2Tabulated`: `alpha`, `inversePlasticMetric`; `Cohesive`: `damage`, `maxOpening`; a thermal wrapper: `temperature`). Storage: structure-of-arrays, double buffered `current/next` exactly like today's `history`, so the explicit-step/rollback behaviour stays intact.
- **Interface sketch** (prose): `update(kinematics, stateIn, parameters, extras: {temperature?}) → (stress, stateOut, ledger)`, where `ledger = {elastic, stored, dissipated, heatSource}`. `extras` is how temperature reaches mechanics; the model never writes temperature directly.
- **Temperature is owned by the body, not the mechanical model.** Mechanics and heat are coupled by the integrator (operator split per step), so `temperature` is a channel on the body with its own update rule, initialised from `initialState` or a scene-level default, and consumed by models that declare they depend on it. Elements are constant-strain triangles (one point each), so element-centred temperature matches J2 history; conduction later needs nodal fields: keep that out of this slot.
- **Damage:** a bounded monotone scalar channel, 0…1, with a rule "never decreases" enforced by the channel descriptor and a check in tests. Today's cohesive seam state maps onto it per face; element-level continuum damage is a future model, not implied by this slot.
- **Replay:** `AssemblyReplayBody` gains `state: [name: [Double]]` for recorded channels; legacy fields (`plasticStrain`, `damage`) remain, populated from the same channels so old viewers keep working. Memory budget: the replay already caps by `fieldPayloadBytes`; recorded channels count toward it.
- **Provenance rule:** a channel is only available to a model that declares it and a material that has evidence for its parameters; the UI says "unavailable: no thermal properties" instead of silently using zeros. Matches the existing `unsupported` message style.
- **Dependencies:** the plastic-work ledger decision in note 1 (heat source needs an agreed `dissipated` definition) must come first; the J2 model change must keep the old convention available behind a flag so legacy scenes replay identically.

## 4. Suggested order (all gated on Joseph)
1. Settle note 1 ledger terms. 2. Base on origin/main (note 2). 3. Freeze v1 + migration + exact-replay tests (no new physics). 4. State-channel refactor with J2 mapped onto it, results bit-identical. 5. Loads/BCs with `externalWork`. 6. Only then thermal coupling.
