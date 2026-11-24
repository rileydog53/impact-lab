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

## Results export (added on the same branch)
- `ImpactPhysics/ResultsExport.swift`: `ExportGrid` is the solver-neutral shape (points, triangles, point and cell arrays, time). `ResultsExport.grid(frame)` adapts FEM replay frames; `write(frames:to:name:)` writes `name.pvd` plus `name_0000.vtu`, ... (at most 60 frames, first and last always included). Hand-written ASCII XML, no library. Cell arrays are the raw solver values (von Mises, principal stresses, pressure in Pa; strain; plastic strain; damage; speed in m/s; body id). Point arrays are displacement and velocity as calculated, plus clearly named `*_nodal_average` arrays. Elastic bodies have no plastic/damage field and export zeros.
- Verified by reading, not memory: VTK_TRIANGLE = 5 and VTK_QUAD = 9 in Kitware's vtkCellType.h. The files were read back with VTK (via pyvista, whose PVDReader read all 12 time steps with correct times) and meshio (MIT); triangle cells, array names, and counts matched. NOT done: opening the files in the ParaView application itself, and the official VTK `vtkXMLPVDReader` (not present in the Python wheel), so the .pvd layout rests on the standard Collection/DataSet form plus the pyvista read.
- `ImpactPhysics/FieldSnapshot.swift`: PNG of a frame in the smooth view with colour bar, units and an honest caption. App: new Export menu (ParaView files, current frame PNG).
- Gate: `ImpactCheck --results-export DIR` (structure, cell type 5, offsets, array lengths, exact solver values in the last frame, PNG). It caught one real bug while being written (arrays missing for elastic bodies). Sample output: docs/export-demo/.
