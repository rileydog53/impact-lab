> COPY from project shared folder, 2026-11-24.

# Proposed architecture: user-defined material properties (23 November 2026)

**Status:** This is a planning proposal only. It is not approved and not implemented. Joseph approved planning, and implementation waits for his review. It doesn't touch the contact formulation, Card 5 or Card 6, and it doesn't open remeshing, XFEM or phase-field work.

## The problem in one paragraph

Today a material is defined by four numbers: E, ρ, ν and an optional provenance tag. Strength and toughness are then derived from E:

- **Yield stress** is `yieldFraction × E` (default 0.016).
- **Cohesive strength** is `strengthFraction × E` (default 0.03), unless the opt-in `tensileStrength` is set.

That works for the soft demo scenes. It's wrong for real materials. Aluminium would get a 2 GPa cohesive strength (the real value is about 310 MPa), which also collapses the timestep 43× (metal report, side finding). The fracture energy range is capped at 50 J/m², while ductile metals are in the kJ/m² range. The validator also forbids fracture on any provenance-tagged material, so a referenced metal can't be given a referenced strength.

## Design in five parts

### 1. One `MaterialModel` with absolute physical properties

| Group | Properties (SI units) | Required? |
|---|---|---|
| **Elastic** | E (Pa), ν, ρ (kg/m³) | yes. Same as today's `Material` |
| **Strength** | yield stress σy (Pa), hardening table (σ vs plastic strain) | optional. Absent means elastic |
| **Failure** | tensile strength (Pa), fracture energy (J/m²) | optional. Absent means no fracture |
| **Thermal (reserved)** | specific heat (J/kg·K), Taylor–Quinney fraction, reference temperature (K), conductivity (optional) | optional, unused at first |
| **Validity envelope** | strain-rate and temperature range the numbers are good for | optional, used only for warnings |

- **Every property is given in physical units,** never as a fraction of E.
- **Each property can carry its own provenance** (source, URL, evidence), so a material can mix "handbook E" with "user-guessed toughness" and the UI can show which is which.
- **Missing optional groups simply switch that physics off.**

### 2. Numerical settings kept apart from physics

Penalty scale, timestep scale, mesh pattern, and the cohesive "numerical strength cap" (if one is ever needed for timestep) belong in a separate `NumericalSettings` per part or per scene.

- **Why:** the contact studies showed these change the raw numbers but not the robust results. Mixing them into the material is what made "strengthFraction" look like physics.
- **Effect on the validator:** it then no longer needs to forbid fracture on referenced metals.

### 3. A per-element `MaterialState` with reserved slots

Each element already carries J2 history (plastic strain, back stress). The proposal is to collect that into one `MaterialState` struct with:

- the existing J2 fields, unchanged
- `temperature`, initialized to the reference temperature and not evolved in stage 1
- `damage`, from 0 to 1, initialized to 0 and not evolved in stage 1

This gives temperature-dependent or damage-dependent laws a place to live later, without another refactor of every element loop.

### 4. Constitutive behaviour behind one small protocol

```
protocol ConstitutiveLaw {
    func stress(strain increment, state, dt) -> (stress, newState)
    var maxSquaredWaveSpeed: Double   // for the timestep bound
}
```

The existing linear elastic and J2 code become two implementations of it. A future thermal-softening or damage law becomes a third, and the solver loop doesn't change. Only add this protocol if stage 2 needs it. If the switch statement stays small, keep the switch.

### 5. Scene file version 2 with exact migration

- **Version 2** writes the new absolute fields.
- **Version 1 files are read by converting fractions to absolutes:** σy = yieldFraction × E, tensile strength = strengthFraction × E. The converted scene therefore runs *the same arithmetic*.
- **Acceptance rule:** every existing ImpactCheck gate and saved scene replays **bit-identically** after migration. If it doesn't, the migration is wrong.

## Staged steps, each with its own acceptance check

| Stage | What changes | Accepted when |
|---|---|---|
| 1. Types + migration | Add `MaterialModel`, `NumericalSettings`, `MaterialState`, and scene v2 read/write. No physics change. | All existing ImpactCheck gates and the demo scenes replay bit-identically. |
| 2. Absolute strength in the solver | J2 reads σy in Pa, cohesive law reads tensile strength in Pa, energy range widened to cover metals. Drop the provenance/fracture validator restriction. | Stage 1 still identical for migrated scenes. A metal scene with real σy and tensile strength runs with a normal timestep (≈10 ns, not 0.23 ns). |
| 3. UI | Material editor fields in physical units, with per-property source labels. Presets come from the existing `MaterialProfile` entries. | Joseph can build and run an unfamiliar material pair by hand (his personal acceptance). |
| Later, only on request | Use `temperature` (adiabatic heating, thermal softening) or `damage`. | Separate approval. The slots exist but nothing evolves them before then. |

Stage 1 is mechanical and has a sharp pass/fail test. Stage 2 is the one that touches physics and needs the most care.

## What this deliberately doesn't do

- **No change to contact,** element formulation, remeshing, XFEM or phase-field.
- **No material database or online lookup.** Presets stay the handful already in `MaterialProfile`.
- **No temperature or damage evolution.** The slots are reserved only.

## Open questions for Joseph before stage 1

1. Should old scenes keep showing "fraction of E" in the UI, or show the converted pascal values? I'd suggest showing pascals.
2. For metals, should fracture energy default to "off" until he enters a value, rather than to a made-up default? I'd suggest off.
