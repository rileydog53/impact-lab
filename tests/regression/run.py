#!/usr/bin/env python3
"""Impact Lab regression runner (standard library only, no network).

1. builds and runs the ImpactRegression harness (raw measurements from the unmodified solver);
2. compares each measurement with an analytic reference (reference_calculator.py or the closed
   forms below) inside a stated tolerance -> PASS / FAIL;
3. compares every measurement with tests/regression/baseline.json (drift check) -> PASS / FAIL;
4. writes report.md, results.json and the usability probe output to --out (default: system temp, never tracked).

Numerical verification only. Passing does not validate any material or accept any threshold for Joseph.
Usage:  python3 tests/regression/run.py [--out DIR] [--skip-build] [--reuse DIR] [--record-baseline]
Exit status 1 if any check FAILS.
"""
import json, math, os, subprocess, sys, tempfile, argparse
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import reference_calculator as ref

G = 9.80665
# Scene values copied from docs/lab-examples (the harness reads the same JSON through the app's reader).
CANT = dict(E=1e7, rho=1000.0, L=0.15, h=0.025, nu=0.0)
SPRING_K = 2000.0

def cantilever_static_sag():
    """Timoshenko cantilever under uniform self-weight w = rho g h (per metre depth): w L^4/(8EI) + w L^2/(2 kappa G A)."""
    E, rho, L, h = CANT["E"], CANT["rho"], CANT["L"], CANT["h"]
    w = rho * G * h; I = h**3 / 12; Gm = E / 2; kappa = 5 / 6
    return w * L**4 / (8 * E * I) + w * L**2 / (2 * kappa * Gm * h)

def cantilever_period():
    w = ref.beam_first_frequency(CANT["E"], CANT["rho"], CANT["L"], CANT["h"], bc="clamped-free", timoshenko=True)
    return 2 * math.pi / w

# (experiment, quantity, reference function(value lookup) -> number or None, mode, tolerance, provenance)
# mode "rel": |m/r - 1| <= tol ; "abs": |m - r| <= tol ; "max": m <= tol ; "info": no pass/fail on its own.
# provenance: "existing" = same criterion as an existing ImpactCheck gate; "new" = introduced here, recorded in
# tests/regression/README.md with the rationale; nothing here loosens an existing acceptance criterion.
CHECKS = [
    ("block_on_bench", "mean_reaction_over_weight_second_half", lambda m: 1.0, "info", None, "FINDING: example says time-averaged reaction equals weight; over t > T/2 it differs by the block's net momentum change (see impulse_residual_relative_second_half)"),
    ("block_on_bench", "impulse_residual_relative_second_half", None, "max", 0.02, "new"),
    ("block_on_bench", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("block_on_bench", "energy_drift_relative", None, "max", 0.01, "new"),
    ("drop_test", "free_fall_max_position_error", None, "max", 1e-6, "existing (free-fall case 1: 1e-6 of g t^2/2; here absolute metres)"),
    ("drop_test", "ke_before_contact_over_mgh", lambda m: 1.0, "rel", 0.01, "new (stated in the example's description)"),
    ("drop_test", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("drop_test", "rebound_height_over_drop", None, "info", None, "illustrative only"),
    ("cantilever_sag", "mean_tip_sag", lambda m: cantilever_static_sag(), "rel", 0.05, "existing (--supports-gravity case 3: 5%)"),
    ("cantilever_sag", "first_period", lambda m: cantilever_period(), "rel", 0.05, "new (Timoshenko-corrected first mode, reference_calculator)"),
    ("cantilever_sag", "peak_tip_sag_over_mean", lambda m: 2.0, "rel", 0.10, "new (suddenly applied load, undamped)"),
    ("cantilever_sag", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("bar_vibration_x2", "first_period", lambda m: cantilever_period(), "info", None, "convergence trend only (coarse mesh)"),
    ("bar_vibration_x4", "first_period", lambda m: cantilever_period(), "rel", 0.05, "new (Timoshenko-corrected first mode, reference_calculator)"),
    ("bar_vibration_x4", "mean_tip_sag", lambda m: cantilever_static_sag(), "rel", 0.05, "existing (5%)"),
    ("bar_vibration_x4", "trough_count", None, "min", 5, "new (enough periods timed)"),
    ("outline_cantilever_3mm", "mean_tip_sag", lambda m: cantilever_static_sag(), "rel", 0.05, "new (outline body, generated mesh; same 5% as cantilever_sag)"),
    ("outline_cantilever_3mm", "first_period", lambda m: cantilever_period(), "rel", 0.05, "new (outline body, generated mesh; Timoshenko-corrected first mode)"),
    ("outline_cantilever_3mm", "mean_tip_sag", lambda m: m["cantilever_sag/mean_tip_sag"], "rel", 0.03, "new (agreement with the structured-mesh cantilever_sag result)"),
    ("outline_cantilever_3mm", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("outline_cantilever_2p25mm", "mean_tip_sag", lambda m: cantilever_static_sag(), "rel", 0.05, "new (outline body, generated mesh; same 5% as cantilever_sag)"),
    ("outline_cantilever_2p25mm", "first_period", lambda m: cantilever_period(), "rel", 0.05, "new (outline body, generated mesh; Timoshenko-corrected first mode)"),
    ("outline_cantilever_2p25mm", "mean_tip_sag", lambda m: m["cantilever_sag/mean_tip_sag"], "rel", 0.03, "new (agreement with the structured-mesh cantilever_sag result)"),
    ("outline_cantilever_2p25mm", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("three_point_bend", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("three_point_bend", "energy_drift_relative", None, "max", 0.05, "new"),
    ("hanging_springs", "unloaded_period", lambda m: 2 * math.pi * math.sqrt(m["hanging_springs/block_mass"] / SPRING_K), "rel", 0.03, "new"),
    ("hanging_springs", "unloaded_mean_drop", lambda m: m["hanging_springs/block_mass"] * G / SPRING_K, "rel", 0.03, "new"),
    ("hanging_springs", "unloaded_peak_drop", lambda m: 2 * m["hanging_springs/block_mass"] * G / SPRING_K, "rel", 0.05, "new"),
    ("hanging_springs", "preloaded_peak_speed", None, "max", 1e-3, "existing (--lab-examples: below 1e-3 m/s)"),
    ("hanging_springs", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("stack_on_support", "mean_reaction_over_total_weight_second_half", lambda m: 1.0, "rel", 0.01, "existing criterion (bench reaction vs weight, 1%)"),
    ("stack_on_support", "upper_block_lateral_drift", None, "max", 1e-5, "existing criterion (lateral drift on frictionless bench, 0.01 mm)"),
    ("stack_on_support", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("stack_on_support", "impulse_residual_relative_second_half", None, "max", 0.02, "new"),
    ("stack_offset", "mean_reaction_over_total_weight_second_half", None, "info", None, "4 mm off-centre upper block; informational"),
    ("stack_offset", "upper_block_lateral_drift", None, "info", None, "4 mm off-centre upper block; informational"),
    ("stack_offset", "impulse_residual_relative", None, "max", 0.02, "new"),
    ("stack_offset", "energy_drift_relative", None, "max", 0.01, "new"),
    ("stack_on_support", "energy_drift_relative", None, "max", 0.01, "new"),
    ("determinism", "max_abs_position_difference_two_runs", None, "max", 0.0, "new (bit-for-bit repeatability)"),
    ("layered_two_region", "energy_drift_relative", None, "max", 0.005, "new (layered target plan step 2: energy error under 0.5%)"),
    ("layered_bond_pull", "fracture_energy_over_gc_length", lambda m: 1.0, "rel", 0.02, "new (plan step 3: dissipation = bond toughness × bond length)"),
    ("layered_bond_pull", "failed_faces_off_bond", None, "max", 0, "new (the bar separates only along the weaker bond)"),
    ("layered_bond_pull", "bond_crack_length", lambda m: 0.03, "rel", 1e-9, "new (the whole 30 mm bond fails)"),
]
# Always-on rule: every harness run must finish.
NEVER_BASELINE = {"wall_seconds"}
BASELINE_REL_TOL = 1e-6   # drift check; same machine/toolchain should reproduce exactly, this absorbs cross-Mac float differences

def build_and_run(out, skip_build):
    exe = os.path.join(ROOT, ".build-regression", "release", "ImpactRegression")
    if not skip_build:
        r = subprocess.run(["swift", "build", "-c", "release", "--scratch-path", ".build-regression", "--product", "ImpactRegression"],
                           cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:]); sys.exit(2)
    with open(os.path.join(out, "harness.log"), "w") as log:
        r = subprocess.run([exe, "--out", out], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if r.returncode != 0:
        print("harness failed; see", os.path.join(out, "harness.log")); sys.exit(2)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "impactlab-regression"))
    ap.add_argument("--skip-build", action="store_true")
    ap.add_argument("--reuse", help="compare an existing harness output directory instead of running")
    ap.add_argument("--record-baseline", action="store_true")
    a = ap.parse_args()
    out = a.reuse or a.out
    os.makedirs(out, exist_ok=True)
    if not a.reuse:
        build_and_run(out, a.skip_build)
    ms = json.load(open(os.path.join(out, "measurements.json")))
    val = {f'{m["experiment"]}/{m["quantity"]}': m["value"] for m in ms}
    rows, failures = [], 0

    for exp, q, rf, mode, tol, prov in CHECKS:
        key = f"{exp}/{q}"
        if key not in val or val[key] is None or (isinstance(val[key], float) and math.isnan(val[key])):
            rows.append((key, None, None, None, tol, "FAIL", prov + " — not measured")); failures += 1; continue
        m = val[key]; r = rf(val) if rf else None
        if mode == "rel":
            err = m / r - 1; ok = abs(err) <= tol
        elif mode == "max":
            err = m; ok = m <= tol
        elif mode == "min":
            err = m; ok = m >= tol
        else:
            err = (m / r - 1) if r else None; ok = True
        status = "INFO" if mode == "info" else ("PASS" if ok else "FAIL")
        failures += status == "FAIL"
        rows.append((key, m, r, err, tol, status, prov))

    for m in ms:   # a run that failed to finish is always a failure
        if m["quantity"] == "run_failed":
            rows.append((f'{m["experiment"]}/run_failed', 1, None, None, None, "FAIL", "scene did not run to completion")); failures += 1

    base_path = os.path.join(HERE, "baseline.json")
    drift_rows = []
    if a.record_baseline:
        json.dump({k: v for k, v in sorted(val.items()) if k.split("/")[1] not in NEVER_BASELINE and v == v},
                  open(base_path, "w"), indent=1, sort_keys=True)
        print("baseline recorded to", base_path)
    elif os.path.exists(base_path):
        base = json.load(open(base_path))
        for k, b in sorted(base.items()):
            m = val.get(k)
            if m is None: drift_rows.append((k, b, None, "FAIL")); failures += 1; continue
            scale = max(abs(b), 1e-12)
            # tiny absolute values (round-off level) compared absolutely
            ok = abs(m - b) <= BASELINE_REL_TOL * scale or abs(m - b) <= 1e-12
            if not ok: failures += 1
            if not ok: drift_rows.append((k, b, m, "FAIL"))
        for k in val:
            if k not in base and k.split("/")[1] not in NEVER_BASELINE:
                drift_rows.append((k, None, val[k], "NEW (not in baseline)"))

    probes = json.load(open(os.path.join(out, "usability.json")))
    with open(os.path.join(out, "report.md"), "w") as f:
        f.write("# Impact Lab regression report\n\nNumerical verification only. Tolerances are stated, not accepted by Joseph.\n\n")
        f.write("| check | measured | reference | error | tolerance | status | provenance |\n|---|---|---|---|---|---|---|\n")
        for k, m, r, e, t, s, p in rows:
            fmt = lambda x: "" if x is None else f"{x:.6g}"
            f.write(f"| {k} | {fmt(m)} | {fmt(r)} | {fmt(e)} | {fmt(t)} | {s} | {p} |\n")
        f.write(f"\n## Baseline drift (relative tolerance {BASELINE_REL_TOL:g})\n\n")
        f.write("none\n" if not drift_rows else "\n".join(f"- {k}: baseline {b}, now {m} — {s}" for k, b, m, s in drift_rows) + "\n")
        f.write("\n## Usability probes (verbatim messages)\n\n")
        for p in probes:
            f.write(f"- **{p['name']}** (expect: {p['expectation']}): {'ACCEPTED' if p['accepted'] else 'rejected'}\n")
            for msg in p["messages"]: f.write(f"    - {msg}\n")
    json.dump({"rows": rows, "drift": drift_rows, "failures": failures}, open(os.path.join(out, "results.json"), "w"), indent=1)
    print(open(os.path.join(out, "report.md")).read())
    print(f"{failures} failure(s). Report: {os.path.join(out, 'report.md')}")
    sys.exit(1 if failures else 0)

if __name__ == "__main__":
    main()
