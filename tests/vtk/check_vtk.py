#!/usr/bin/env python3
"""Check the raw-field VTK files written by `ImpactCheck run SCENE --out DIR --vtk`.

    python3 tests/vtk/check_vtk.py DIR

Standard library only. Exits 1 on the first problem class found, printing every problem.

Checks:
  - fields.pvd and every .vtu parse as XML and are VTK files of the right type
  - one .vtu per recorded frame: the count matches manifest.json "frames" and the pvd timesteps match the
    time column of energy.csv exactly (same text), in increasing order
  - each .vtu has the expected point and cell fields, with the right number of components and values,
    all finite; triangles only (type 5), offsets 3, 6, 9, ..., connectivity inside the point range
  - the first frame's displacement is exactly zero (displacement is measured from t = 0)
It does not judge the physics values themselves.
"""
import csv
import json
import math
import os
import sys
import xml.etree.ElementTree as ET

POINT_FIELDS = {"displacement_m": 3, "velocity_m_per_s": 3}
CELL_FIELDS = {
    "von_mises_stress_Pa": 1,
    "mean_pressure_Pa": 1,
    "max_principal_stress_Pa": 1,
    "min_principal_stress_Pa": 1,
    "equivalent_plastic_strain_dimensionless": 1,
    "damage_dimensionless": 1,
    "body_index": 1,
}

problems = []


def fail(msg):
    problems.append(msg)


def values(array, name, where):
    text = (array.text or "").split()
    out = []
    for token in text:
        try:
            v = float(token)
        except ValueError:
            fail(f"{where}: {name} has a value that is not a number: {token!r}")
            return []
        if not math.isfinite(v):
            fail(f"{where}: {name} has a non-finite value {token}")
            return []
        out.append(v)
    return out


def arrays(parent):
    return {a.get("Name"): a for a in parent.findall("DataArray")} if parent is not None else {}


def check_vtu(path, label):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        fail(f"{label}: not valid XML ({e})")
        return None
    if root.tag != "VTKFile" or root.get("type") != "UnstructuredGrid":
        fail(f"{label}: not a VTK UnstructuredGrid file")
        return None
    pieces = root.findall("./UnstructuredGrid/Piece")
    if len(pieces) != 1:
        fail(f"{label}: expected one Piece, found {len(pieces)}")
        return None
    piece = pieces[0]
    n_points = int(piece.get("NumberOfPoints", "-1"))
    n_cells = int(piece.get("NumberOfCells", "-1"))
    if n_points <= 0 or n_cells <= 0:
        fail(f"{label}: empty grid ({n_points} points, {n_cells} cells)")
        return None

    time_arrays = arrays(root.find("./UnstructuredGrid/FieldData"))
    if "TimeValue" not in time_arrays:
        fail(f"{label}: no TimeValue field data")

    point_arrays = arrays(piece.find("PointData"))
    cell_arrays = arrays(piece.find("CellData"))
    result = {}
    for fields, found, count, kind in ((POINT_FIELDS, point_arrays, n_points, "point"),
                                       (CELL_FIELDS, cell_arrays, n_cells, "cell")):
        missing = sorted(set(fields) - set(found))
        if missing:
            fail(f"{label}: missing {kind} fields {missing}")
        for name, comps in fields.items():
            a = found.get(name)
            if a is None:
                continue
            if int(a.get("NumberOfComponents", "1")) != comps:
                fail(f"{label}: {name} should have {comps} components")
            v = values(a, name, label)
            if len(v) != comps * count:
                fail(f"{label}: {name} has {len(v)} values, expected {comps * count}")
            result[name] = v
    extra_points = sorted(set(point_arrays) - set(POINT_FIELDS))
    if extra_points:
        fail(f"{label}: unexpected point fields {extra_points} (point data must be displacement and velocity only)")

    pts = arrays(piece.find("Points"))
    if len(pts) != 1:
        fail(f"{label}: expected one Points array")
    else:
        p = values(next(iter(pts.values())), "Points", label)
        if len(p) != 3 * n_points:
            fail(f"{label}: Points has {len(p)} values, expected {3 * n_points}")

    cells = arrays(piece.find("Cells"))
    for name in ("connectivity", "offsets", "types"):
        if name not in cells:
            fail(f"{label}: Cells has no {name}")
            return result
    conn = values(cells["connectivity"], "connectivity", label)
    offs = values(cells["offsets"], "offsets", label)
    types = values(cells["types"], "types", label)
    if len(conn) != 3 * n_cells or any(c < 0 or c >= n_points or c != int(c) for c in conn):
        fail(f"{label}: connectivity wrong length or outside the point range")
    if offs != [3.0 * (i + 1) for i in range(n_cells)]:
        fail(f"{label}: offsets are not 3, 6, 9, ...")
    if len(types) != n_cells or any(t != 5 for t in types):
        fail(f"{label}: cell types are not all triangles (5)")
    return result


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check_vtk.py RUN_DIR")
    run = sys.argv[1]
    manifest = json.load(open(os.path.join(run, "manifest.json")))
    print(f"run outcome: {manifest.get('outcome')}, frames: {manifest.get('frames')}")

    try:
        pvd = ET.parse(os.path.join(run, "fields.pvd")).getroot()
    except (OSError, ET.ParseError) as e:
        sys.exit(f"FAIL fields.pvd unreadable: {e}")
    if pvd.tag != "VTKFile" or pvd.get("type") != "Collection":
        sys.exit("FAIL fields.pvd is not a VTK Collection")
    datasets = pvd.findall("./Collection/DataSet")
    if len(datasets) != manifest.get("frames"):
        fail(f"fields.pvd lists {len(datasets)} files, manifest has {manifest.get('frames')} frames")

    with open(os.path.join(run, "energy.csv")) as f:
        times = [row["time_s"] for row in csv.DictReader(f)]
    steps = [d.get("timestep") for d in datasets]
    if steps != times:
        fail("fields.pvd timesteps do not match energy.csv times exactly")
    if any(float(b) <= float(a) for a, b in zip(steps, steps[1:])):
        fail("fields.pvd timesteps are not increasing")

    listed = set()
    for i, d in enumerate(datasets):
        rel = d.get("file")
        listed.add(rel)
        path = os.path.join(run, rel)
        if not os.path.isfile(path):
            fail(f"{rel}: listed in fields.pvd but missing")
            continue
        fields = check_vtu(path, rel)
        if i == 0 and fields and any(v != 0 for v in fields.get("displacement_m", [])):
            fail(f"{rel}: first-frame displacement is not exactly zero")
        if fields and i == len(datasets) - 1:
            for name in ("von_mises_stress_Pa", "equivalent_plastic_strain_dimensionless", "damage_dimensionless"):
                v = fields.get(name, [])
                if v:
                    print(f"last frame {name}: min {min(v):.6g}, max {max(v):.6g}")
            u = fields.get("displacement_m", [])
            if u:
                print(f"last frame largest displacement component: {max(abs(x) for x in u):.6g} m")
    on_disk = {os.path.join("vtk", n) for n in os.listdir(os.path.join(run, "vtk")) if n.endswith(".vtu")}
    if on_disk != listed:
        fail(f"vtk/ holds {len(on_disk)} .vtu files, fields.pvd lists {len(listed)}")

    if problems:
        for p in problems[:50]:
            print("FAIL", p)
        print(f"{len(problems)} problem(s)")
        sys.exit(1)
    print(f"OK: {len(datasets)} frames, every file valid XML with the expected fields")


if __name__ == "__main__":
    main()
