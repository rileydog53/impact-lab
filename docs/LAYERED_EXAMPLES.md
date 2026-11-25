# Layered examples (layered target plan, step 7)

Added 2026-11-25. Three editable starting scenes of ordinary bonded laminates, each hit by a 20 mm steel ball at 20 m/s as in a ball-drop impact test. Files in `docs/layered-examples/`, also built into the app under **New / Examples ▸ Layered examples (laminates)**. Check: `ImpactCheck --layered-examples` (about 4 minutes).

**Status: numerical results, not physical validation.** Every material value is sourced in [`laminate-material-profiles.md`](laminate-material-profiles.md) (written by Duet, values checked here: the G = K²(1−ν²)/E conversions reproduce, and the metal layers reuse the app's own sourced profiles). Every toughness and bond value is experimental and carries its citation in the file, so the app shows its "Experimental, not validated" note next to it.

## The three scenes

| Scene | Layers (struck face first) | Thickness | What to watch |
|---|---|---|---|
| Sprayed-ceramic-coated steel plate | plasma-sprayed alumina / thermal-spray bond / A36 steel (plastic) | 1.8 + 16.2 mm | the coating cracks; whether the bond lets go |
| Laminated glass on aluminium | soda-lime glass / glass–PVB bond / PVB / epoxy / 6061-T6 (plastic) | 6 + 1.6 + 8.4 mm | the glass breaks up; interior cracks; the glass coming off the PVB |
| Carbon-fibre-skinned aluminium panel | carbon/epoxy fabric skin / epoxy / 6061-T6 (plastic), struck from the right | 2 + 10 mm | the skin coming off (delamination) |

The app is 2D (plane strain), so the "ball" is really a long steel rod seen end on and the plates are long strips. The plates float free (no support).

## What the check found (2026-11-25)

| Scene | Energy error | Crack faces | Delaminated | Pieces | Events, µs after the start (first contact at 25.0) |
|---|---|---|---|---|---|
| Coated steel | 0.37% | 14 (all in the coating) | none | 1 | first crack 25.82 |
| Laminated glass | 0.02% | 193 | 2.3 mm | 79 | first crack 25.31, interior crack 27.29, delamination 51.23 |
| Carbon skin | 0.002% | 57 (all on the bond) | whole 100 mm | 2 | first bond damage 32.5, delamination 74.0 |

The check requires each file to match the app's built-in copy, to save and reopen identically, to run to its end with energy error under 2%, and to show a first crack. The event times and counts are printed, not gated.

## Known gaps (say so when showing these)

- **Coating thickness.** The app's thinnest layer is 10% of the block, so the coating is 1.8 mm; real sprayed coatings are about 0.1–0.7 mm. Its density, Poisson ratio and 83 MPa strength are stand-ins from related coatings.
- **PVB is too soft.** 33 MPa is the shortest-load sourced value (3 s at 20 °C). At impact rates PVB is far stiffer; no measured high-rate modulus was found (one search, 2026-11-25), and the app has no rate-dependent polymer. PVB has no sourced toughness, so it never cracks. The glass–PVB bond strength is a guess capped at PVB's own tensile strength. Real laminated glass is glass/PVB/glass; a block holds at most three layers.
- **The carbon skin never cracks.** No crack toughness was found for the fabric, so only the bond and the aluminium can fail. The fabric is isotropic at its fibre-direction stiffness (single source), which overstates it off-axis. The epoxy toughness is for aluminium; the same round robin found about 208 J/m² on carbon-fibre substrates, so this bond may be too tough.
- **The whole carbon skin comes off.** Not checked against anything. The panel is free and thin, so it flexes; whether that is realistic for a supported panel is open.
- **Event names.** "Interior crack (spall-type)" is an operational label: the first crack face at least two element sizes from the outer boundary and not on a bond line (`InteriorCrackWatch` in `AssemblyReplay.swift`). It is not a check that the crack was opened by reflected-wave tension.

## Also in this step

- **New events** in the replay's Events menu and the timeline: first crack, first delamination and first interior crack for every body with fracture on. They are kept apart from the older events, which sit exactly on recorded frames and are part of the legacy replay fingerprint, so every older scene replays bit for bit as before.
- **Fix: saving a scene with fracture strength in Pa.** The complete form wrote both `strength` and `strengthFraction`, and the scene reader refuses a file with both, so such a scene could be saved but not reopened. A strength in Pa is now saved without the (ignored) fraction.
- **Schema:** `fracture.energy` now allows up to 1,000,000 J/m² when `strength` is in Pa and 50 J/m² otherwise, as the app does, and refuses `strength` with `strengthFraction`.
