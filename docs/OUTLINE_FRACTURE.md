# Fracture on drawn (outline) bodies

Added 2026-11-25. This is the milestone's "one checked case" before the editor lets an outline body crack. Run it with `ImpactCheck --outline-fracture` (about 30 minutes on the M4), or `--outline-fracture quick` (cases B and C only, with B over its first 100 µs, in CI). The code is in `Sources/ImpactCheck/OutlineFracture.swift`.

**Status: numerical verification, not physical validation. This is a solver behaviour change and needs Joseph's approval before it ships.**

## What changes

Outline bodies are meshed by the quality Delaunay mesher, so their triangles do not line up in rows the way a block's do. Until now fracture was switched off on them, because the crack model had only been checked on block meshes. Cracks open along element edges, and the crack model itself does not change. Three things change:

- Outline bodies may use fracture (`AssemblyScene.swift`, `AssemblyAdvisories.swift`, `SceneDocument.swift`).
- The block-only `meshPattern` setting is refused on an outline.
- Turning a block into an outline keeps its fracture settings, apart from the block mesh pattern (`BodyOutline.swift`).

The editor's help texts say so. Scenes without an outline body that cracks are untouched.

## Checks (criteria written before the first run)

| Case | Result | Criterion |
|---|---|---|
| B. Plate with a rectangular hole (2102 generated elements), clamped at the bottom, struck by a steel ball at 20 m/s. Fracture on but too strong to crack, against fracture off at the same step and contact stiffness | largest node difference exactly 0 (over 400 µs; the quick version stops at 100 µs, after contact starts at about 10 µs) | exact match |
| C. The same plate at 41 MPa (glass-like) | 1172 crack faces, 569 pieces; energy error 0.28%; every crack face joins two nodes that started at the same point | cracks open, energy error under 2%, cracks only along element edges |
| A. Fixed-guided bend rig of `--bend-rig` with an outline beam (160 × 20 mm, mesh size 2.5 mm, 2810 elements), 4.5 MPa, 100 J/m² | first crack at the clamp end on the top (tension) face, at 53.5 ms; grip force 4137 N/m, +10.3% against σh²/3L = 3750 N/m | at an end on its tension face, within 20% |

For comparison, the block beam on its x4 mesh cracked at +8.4%, and on x6 at +0.9% (`TEST_MACHINE.md`).

**Case A was changed before any result existed.** It first used a 1.67 mm mesh and 70 ms of loading. The generated mesh at that size needs a step of about 0.011 µs, and the run hit its 45-minute limit at 37.5 ms, before any crack. It now uses a 2.5 mm mesh, the 8 elements through the depth that the bending advisory asks for, and 40 ms of loading after a 10 ms ramp.

The app's geometry smoke test (`ImpactLab --geometry-smoke`, 21 checks) still passes. Its convert check now expects fracture to survive conversion without the block mesh pattern.

## Limits

- Crack paths follow the generated mesh's edges. On an unstructured mesh they zigzag at the scale of the mesh, so a crack's length and the fracture energy it releases depend on the mesh. This check covers the first crack load and the bookkeeping, not crack path or crack length.
- Case C's glass plate breaks into many pieces at 20 m/s. That is reported, not compared with anything.
