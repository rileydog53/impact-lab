> COPY made 2026-11-24 for preservation. Original: research/beam-verification/CONVERGENCE_PROTOCOL.md on Joseph's Mac (untracked). The original wins if they differ.

# Convergence-study protocol (draft for Joseph's review; not a decision)

## 1. Verification versus validation versus acceptance
- **Numerical verification**: does the code solve its equations correctly? Compared against closed-form solutions or finer-mesh/finer-step solutions of the same model. Output: an error number with a stated tolerance.
- **Physical validation**: does the model describe real material behaviour? Needs measured data and stated uncertainty. Verification never implies validation.
- **Acceptance**: Joseph's own decision that a result is good enough. Agents report, they do not accept.
- Every report row carries one label: verified / agent-reported / hypothesis, and says which of the three kinds of claim it is.

## 2. What to vary (one factor at a time, others at baseline)
1. Spatial resolution: elements through the smallest thickness (2, 4, 8, 16), cells kept near-square so aspect ratio does not change.
2. Mesh pattern: alternating vs staggered diagonals (isolates directional bias).
3. Time step: scale by 1, 1/2, 1/4 of the stable step (isolates time error from space error).
4. Amplitude: halve and double (isolates nonlinearity; elastic small-strain cases should not change).
5. Geometry ratios: L/h of 10, 20, 40 (thick-beam effects, locking).
6. Poisson ratio: 0, 0.3, near 0.45 (incompressible locking in CSTs).
7. Contact penalty/gap (only for contact cases): a separate study using the same structure.

## 3. Common physical window
Compare every resolution over the same physical quantity and the same physical time interval, never the same step count. Examples: first 3 vibration periods (period from zero crossings); peak load within a fixed window around first contact; energy at a fixed time. State the window in seconds, the quantity, and how peaks/crossings are interpolated, before running.

## 4. Metrics and acceptance language
- Reference error: |measured - analytic| / analytic, for cases with a closed form.
- Self-convergence: change between successive refinements, |q_k - q_(k-1)| / |q_k|, for cases without one.
- Observed order: p = log(e_(k-1)/e_k)/log(2) from three levels; report it, do not assume it.
- Proposed language: "Verified to within X% of the reference on meshes with N rows (single run, window W)" or "Not converged: change of Y% on the last refinement." Default tolerance 5% (matches PLAN A3) unless Joseph sets another per quantity. Never write "validated" or "accurate" without the test name and tolerance.
- Always report energy balance and any solver stop reason with each run.

## 5. Procedure
1. Fix the analytic reference (`reference_calculator.py`) and tolerance before running.
2. Run the coarse-to-fine ladder; stop at the first level where both reference error and last-refinement change are within tolerance, plus one more level as a check.
3. Check cost (wall time, triangles) on the actual M4 Air; run only while no heavy solver job is active (check `ps`); bound each run.
4. Keep raw output text files and the exact commit hash; keep scratch out of tracked files.
5. Report: result table, what passed, what is untested, label per row.

## 6. Reference problem map (agent-reported; Google Doc section 18 not read, check against it)
| Problem | Closed form | Quantity |
|---|---|---|
| Beam bending | Euler-Bernoulli (+Timoshenko correction), cantilever tip deflection | period, deflection |
| Ring ovalization | thin-ring in-plane mode n=2 | period |
| Hertz line contact | a = sqrt(4 F R*/(pi E*)), p0 = 2F/(pi a) | contact width, peak pressure |
| Sod shock | exact Riemann solution | rho, u, p profiles at t |
| Gas spring | p V^gamma = const | force-displacement, frequency |
| Thermal conduction | erf half-space, Fourier slab | temperature profile |
Only the beam has been run against the solver so far; the others have calculator functions with internal self-tests only. The solver may not support some of these physics (gas, thermal) at all.
