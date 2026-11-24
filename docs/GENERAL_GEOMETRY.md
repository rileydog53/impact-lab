# General geometry editing: design and mesh prototype

Status, 2026-11-24: design proposal plus a bounded prototype on branch `claude/project-thread-184oy5`. Nothing here is approved, and nothing is wired into the app or the production solver. The architecture reassessment (Google Doc section 26) is separate; this design is meant to stay useful whichever numerical methods are chosen there.

## 1. Problem

Today a body is one of three hard-coded shapes (block, enclosure, round body), each with its own structured mesh builder in `AssemblyScene.swift`. A V-notch and bonded layers are special options of the block. Sizes are limited to 25–300 mm (`AssemblyPart.sizeRange`), scenes to 8 bodies (`AssemblyScene.maximumParts`), and the mesh is a fixed pattern of about 9 mm cells divided by an integer refinement. None of these limits is physics: a 5 mm strip and a 1 m bench are ordinary laboratory objects. They exist because each shape needed its own mesh code.

## 2. Proposal in one paragraph

Describe every body by its **outline**: a polygon region with an outer boundary, any number of holes, and optional interior lines (bonded interfaces, gauge lines). A notch, slot, window or enclosure is just geometry. The outline is stored in the scene file, in the body's own frame, independent of any solver. Each numerical method turns the outline into what it needs: FEM asks a general mesher for triangles, MPM fills it with particles, visualization draws the true outline. Mesh quality is checked automatically and reported; resolution guidance is advisory and never blocks a run. Scenes saved before this change keep their exact meshes and results.

## 3. Editor model

| Action | What the person does | Stored as |
|---|---|---|
| Insert a primitive | Rectangle, ellipse, regular polygon, wedge, as today | Polygon vertices (primitive kept as a label for re-editing) |
| Draw an outline | Click points on the canvas, or type coordinates in mm | Outer ring |
| Cut | Draw any shape over a body and choose Cut: notches, holes, slots | Boolean difference (holes or a changed outer ring) |
| Join | Merge two overlapping outlines into one body | Boolean union |
| Edit vertices | Drag, insert on an edge, delete, type exact values; snap to grid and angles | Vertex list |
| Round or chamfer a corner | Select a corner, give a radius | New vertices (arcs, see 4) |
| Split into materials | Draw an interior line across the body, assign a material on each side | Interior line plus region materials |
| Tag edges | Select boundary edges for a clamp, support or load | Named edge set |
| Mesh size | One target edge length per body, optional finer size near chosen points or edges | `meshSize`, size hints |

Everything is reversible on the canvas and in Undo. Invalid outlines (self-crossing edges, a hole outside the body) are explained in words, as the prototype's validator already does, and only those block Calculate.

## 4. Geometry representation (solver independent)

Prototype type `PolygonRegion` (in `Sources/ImpactGeometry/Geometry.swift`):

- `outer`: points in metres, body frame. Orientation is normalized internally (outer counter-clockwise, holes clockwise, so material is always on the left).
- `holes`: rings strictly inside, disjoint, not nested.
- `interiorLines`: polylines the mesh must follow without cutting the body.

Placement (centre, angle), velocity, material and supports stay on the body as they are today. Recommended additions for the production version, not in the prototype: circular arcs as an edge type (resampled at mesh time to a chord tolerance tied to the mesh size, so a hole gets rounder as the mesh is refined instead of staying a fixed 32-gon), named edge sets, and region materials. In the scene file this becomes one optional object per body, for example `"outline": {"outer": [[x, y], ...], "holes": [...], "interiorLines": [...], "meshSize": 0.003}`, added to `docs/scene-format.schema.json`.

How each method uses it:
- **FEM**: `Mesher.generate(MeshRequest)` returns triangles, boundary edges and interface edges (section 5).
- **MPM**: seed particles on a lattice and keep those where `PolygonRegion.contains(point)` is true, weighted by cell area.
- **Visualization**: draw the true outline over any field, so smooth displays are not clipped to triangle facets.

## 5. Mesher and how it plugs into the existing FEM

Prototype: `Sources/ImpactGeometry/Mesher.swift`, about 650 lines, no dependencies. Method, all published and cited in the code:
- Bowyer–Watson Delaunay insertion (Bowyer 1981, Watson 1981).
- Ruppert's Delaunay refinement (J. Algorithms 1995): split boundary pieces until they are Delaunay edges, then insert circumcentres of triangles that are too large or too skinny, splitting any boundary piece a new point would encroach.
- Shewchuk's 2002 refinements: concentric-shell splitting near corners, and leaving alone skinny triangles that a sharp input corner makes unavoidable, so the algorithm always terminates.
- Exact predicates: all coordinates are snapped to an integer grid (2²¹ steps across the body, 0.05 µm for a 100 mm body), which makes the orientation test exact in ordinary arithmetic and the in-circle test exact with Shewchuk's error-free expansion arithmetic (1997). Points on the boundary are mapped back exactly onto the original edges, so mesh area equals polygon area to rounding error.

The output follows the existing FEM's conventions exactly: counter-clockwise triangles, boundary edges listed in the direction of their triangle (the gauge locator and contact code rely on this). The adapter is three lines using the existing `Mesh(reference:triangles:boundary:)` initializer, shown in `Sources/MeshCheck/main.swift`. Production integration (not done, needs approval) would be: an optional `outline` on `AssemblyPart`; `makeBody` calls the mesher only when it is present; clamps use tagged edges instead of bounding-box sides; region materials become `elementMaterials`; interior lines become `interfaceLines`.

Not yet compatible: fracture. The verified crack model inserts cracks along element edges and was verified on the structured aligned/staggered patterns, so crack paths on generated meshes need their own verification (it belongs after the fracture verification in section 25.5) and fracture should stay unavailable on outline bodies until then.

## 6. Quality checks

`MeshQuality` (`Quality.swift`) measures, for any triangle mesh: minimum and maximum angle, counts below 20° and 30°, worst circumradius-to-shortest-edge ratio, Bank's shape measure (1 = equilateral), shortest and longest edge, **smallest altitude** (with a lumped-mass explicit solver the stable time step scales with it, so it predicts run cost), area, boundary length, inverted triangles, edge-sharing errors, and the Euler characteristic (which must equal 1 minus the number of holes).

Blocking: invalid outline, inverted triangles, topology errors, mesher internal error. Everything else is reported, not enforced.

## 7. Resolution guidance (advisory only)

`ResolutionAdvice` gives plain-language notes, each with a location, and never blocks a run:
- estimated triangle count at the chosen size;
- narrowest wall or ligament and how many elements span it (fewer than about 3 linear triangles across a section makes bending too stiff, a rule of thumb, labelled as such);
- re-entrant corners, where linear-elastic stress is mathematically singular (Williams 1952), so peak stress there keeps rising with refinement and should be read a short distance away or the corner rounded;
- very sharp corners, where some triangles cannot reach the requested quality.

Production should add the run-cost estimate from the existing `AssemblyCost` model (triangle count and smallest altitude give steps and time), and point to the existing **Study → Mesh refinement** for convergence. The fixed size and body-count caps would then be replaced by these estimates. That is a decision for Joseph (section 10).

## 8. Legacy scene compatibility

- A body without an `outline` keeps today's shape code and structured mesh, bit for bit. Existing replay fingerprints and the legacy-replay gates must stay unchanged; the prototype does not touch `ImpactPhysics`.
- "Convert to outline" would work on a copy (the existing Edit a Copy pattern). The prototype already has the conversions: `Shapes.notchedBlock` (the legacy V-notch geometry), `Shapes.enclosure`, `Shapes.layeredBlock`, `Shapes.ellipse`. A converted body gets a different mesh, so its results will differ slightly; the app should say so and offer to pin the original for comparison.
- The legacy shapes remain as quick-insert primitives.
- Older app versions reject files with an `outline` field (the scene reader rejects unknown settings), which is a safe, explained failure.
- Resolution meaning changes: the legacy label "≈9 mm" is the side of a square cell cut into two right triangles, whose long edge is about 12.7 mm. A generated mesh with a 10 mm target edge length is considerably finer (see 9). The production label should state the target edge length explicitly.

## 9. Prototype evidence (numerical verification only, not physical validation)

Run `swift run -c release MeshCheck [--svg DIR]` (about 3 s on the M4 Air). Results from this branch:

| Check | Result |
|---|---|
| 11 shapes: block, enclosure, legacy V-notch as a polygon, 64-sided round, L-bracket, plate with round hole and slot, 8° slit, 10° wedge, 5 × 1 mm strip, 1000 × 20 mm bench, block with two bonded interfaces | All meshed in ≤ 0.011 s. Area and boundary length equal the polygon to ≤ 1e-12 relative, Euler characteristic correct, no inverted triangles, no topology errors, no edge longer than requested. Minimum angle ≥ 25° on every shape without sharp corners (25.1°–30.0°). |
| Sharp corners | 8° slit (sharp on the void side): minimum angle 18.6°, 1 triangle left. 10° wedge tip (sharp in the material): 8.9° minimum, 8 triangles left at the tip, as Shewchuk's rule intends; both reported in the mesher's notes. |
| Invalid outlines (bow-tie, hole outside, hole crossing the edge, two points, repeated point, interior line leaving the body) | Each rejected with a plain-language reason, no crash. |
| Determinism | Same input gives a bit-identical mesh, also across separate runs; scaling the plate by 1/1000 gives identical topology. |
| Refinement, plate with holes | h = 6, 3, 1.5, 0.75 mm: 1,035 / 3,876 / 15,345 / 60,466 triangles (≈ 4× per halving), minimum angle ≥ 25.0°, 60k triangles in 0.11 s. |
| FEM patch test (the same construction as `ImpactCheck` `patchCheck`) on 4 generated meshes, including holes and notches | Rigid translation and rotation residuals ≤ 6e-12, uniform-deformation residual ≤ 2e-13 of the boundary force. Lumped mass equals density × area to 1e-15. |
| 500 × 50 mm elastic bar (ν = 0) hitting the rigid wall, existing solver | 1D theory: contact 31.62 ms. Structured legacy mesh (500 triangles): 31.73 ms (+0.3%), energy error 1.2e-3. Generated mesh, 10 mm target (1,301 triangles): 31.63 ms (+0.0%), energy error 4.9e-4. Both conserve momentum against the wall impulse to 1e-15. |
| Plate with a hole and a slot hitting the wall, 20 ms | Stable, peak energy error 2.0e-4, momentum balance 2e-15. |

Cost finding (verified on the bar): at the "same" 10 mm, the generated mesh had 2.6× the triangles and a 1.7× smaller time step (11.6 vs 19.7 µs), so about 4.4× the compute, because its edges are all at most 10 mm while the legacy cells have 14 mm diagonals. Matching legacy cost needs a target edge length around 1.3–1.4× the legacy cell size; this is a hypothesis to measure before choosing defaults.

Example meshes (mesher output, not simulation results): `docs/geometry/*.svg`.

## 10. What exists to adopt, and what was built

| Need | Existing option | License (checked 2026-11-24) | Recommendation |
|---|---|---|---|
| Quality triangle meshing | Triangle (Shewchuk) | Free for research and private use; commercial use only by arrangement with the author ([source](https://www.cs.cmu.edu/~quake/triangle.html)) | Gold-standard reference. Use as a separate program to cross-check our meshes if Joseph approves installing reference tools (decision D8). Do not link or ship. |
| | Gmsh | GPL (general knowledge, confirm) | Separate program only, for benchmarks and graded or quad meshes. Same D8 approval. |
| | CGAL 2D mesh generation | GPL or commercial (general knowledge) | Separate program only. |
| | Spade (Rust) | MIT or Apache-2.0 ([source](https://github.com/Stoeoef/spade)); has constrained Delaunay and Delaunay refinement | Permissive, good cross-check or replacement kernel; needs a Rust toolchain and a C bridge. |
| | JIGSAW | Custom licence, terms unclear ([source](https://github.com/dengwirda/jigsaw)) | Avoid until its LICENSE.md is read. |
| Constrained triangulation only | CDT (artem-ogre) | MPL-2.0, file-level copyleft, may be combined with other code if its files stay MPL ([source](https://github.com/artem-ogre/CDT)) | Usable through Swift's C++ interop. It does constrained or conforming triangulation, not quality refinement as far as I could tell, so refinement would still be ours. |
| | poly2tri (BSD-3), earcut (ISC) | Permissive (general knowledge) | Not suitable: no quality control, slivers are common. |
| Robust predicates | Shewchuk predicates.c | Public domain | We implemented the same published method for our integer grid; predicates.c could be vendored instead if wanted. |
| Polygon booleans and offsets (Cut, Join, rounding, thin-wall checks) | Clipper2 (Angus Johnson) | Boost Software License 1.0, permissive ([source](https://angusj.com/clipper2/Docs/Overview.htm)) | **Adopt** for the editor's Cut and Join tools, through Swift's C++ interop, with attribution. Not needed by the mesher prototype. |
| Benchmarks | Irons patch test; 1D bar impact (contact 2L/c); Kirsch plate-with-hole stress concentration (factor 3 for an infinite plate in tension) | Published | Patch test and bar impact are in MeshCheck. Kirsch is the natural next benchmark for holes, but needs slow (quasi-static) loading in our explicit solver. |

Built here: the Ruppert/Shewchuk mesher, exact grid predicates, quality metrics, advisory notes, outline validation and the MeshCheck gates. Reason for building rather than adopting the mesher: the only permissive option with quality refinement is Spade (Rust), and the method is small and well documented, so a dependency-free Swift version (about 1,100 lines for the whole geometry module) keeps the build unchanged and the licence clean, behind an interface (`MeshRequest` → `TriangleMesh`) that Spade, CDT or Triangle could replace later. Its weakness is that it has not yet been cross-checked against an independent mesher.

## 11. Decisions for Joseph (none taken)

1. Adopt the outline model (section 2) as the direction for geometry editing.
2. Replace the 25–300 mm size range and the 8-body limit with cost estimates and advisory notes.
3. Allow installing Triangle or Gmsh as separate reference programs for cross-checks (part of D8 in section 26.11).
4. Adopt Clipper2 (BSL-1.0) for Cut and Join.
5. Order of work relative to section 25.5 (fracture verification) and the architecture decisions.

## 12. Not done, and limits of the prototype

- No app or solver integration, no UI, no scene-file field (all need approval).
- Straight edges only: no arcs, no size grading or local refinement, no region materials, no named edge sets.
- No cross-check against Triangle, Gmsh or Spade (none installed).
- Fracture on generated meshes untested.
- The cost ratio in section 9 comes from one bar; defaults need a wider measurement.
- Timings are from one run on the M4 Air while other work was running.
