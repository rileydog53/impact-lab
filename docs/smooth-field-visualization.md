# Smooth field display (prototype, branch viz-smooth-fields)

Display only. No solver, constitutive or production physics code changed; legacy replay is untouched. The Smooth toggle in the app (default on) switches between the interpolated display and the raw per-element colours; the calculation is identical either way. The legend and provenance line say "interpolated display" when it is on.

## Pieces
- `ImpactPhysics/SmoothField.swift`: `ScalarFieldOnTriangles` (points, triangles, one value per triangle, optional discontinuity groups) is the renderer's generic input. `Body.scalarField(...)` adapts FEM; an MPM or other adapter only has to produce the same shape. `recoveredCorners()` does area-weighted nodal averaging. Corner values are convex combinations of neighbouring element values, so the display never exceeds the solver's own range and a uniform field is exact. Bonded material interfaces are cut so a real stress jump is not smeared.
- `FieldColormap`: viridis (sequential) and ColorBrewer RdBu reversed (diverging, negative blue, zero lightest).
- `ImpactPhysics/FieldRaster.swift`: per-pixel interpolation and colour mapping into a CGImage; the app draws it, then the optional mesh overlay on top. Mesh off is the clean mode.
- `ImpactLab/SmoothFieldLegend.swift`: continuous colour bar with end values and units.
- Gate: `ImpactCheck --smooth-field [PNG]` (checks listed in the file; writes docs/smooth-field-demo.png, smooth on top, per-element below, same data).

## Adopted versus built
Adopted: viridis (CC0), ColorBrewer RdBu (Apache 2.0), the standard cell-to-point averaging used by ParaView/Gmsh-style viewers. Built: the small adapter, rasterizer and legend, because none of those tools can be linked into a Swift app view. Not done, named for later: Zienkiewicz-Zhu superconvergent patch recovery (more accurate than averaging), and cuts at failed cohesive faces.

## Known honest limits
Averaging lowers sharp peaks (the demo frame's single hottest triangle is smeared over its neighbours), so exact peak readings still come from the per-element values and the Measurements. Fields with no per-element data (crack separation) still draw as before. Per-frame cost is a CPU raster of each body; not yet profiled on large meshes.
