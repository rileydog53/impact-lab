# Plate-in-enclosure benchmark results

Joseph's scene from his testing (docs/FEEDBACK.md), rebuilt from the description: the carbon-skinned panel
preset clamped at the bottom, a hollow 60×40 mm box (5 mm wall) and a 40×20 mm plate inside it, both moving
at 20 m/s toward the panel, fine mesh, 0.4 ms run. Headless runs on Joseph's Mac, Release build of commit 8bc1de6.

| Scene | Materials | Result | Steps | Time on the Mac |
|---|---|---|---|---|
| plate-in-enclosure-as-built.json | Old soft demo material for the box and plate (1–4 MPa stiffness) | Stopped early: "Artificial bulk viscosity needs a shorter step here" | 21,595 | a few seconds |
| plate-in-enclosure-real.json | Steel plate, aluminium box (Library) | Finished all 0.4 ms, no "pushed into each other" stop | 293,137 | 71 s |

Real-material run, in order: box touches the panel at 0.050 ms; panel glue line starts to give at 0.053 ms;
first crack in the panel at 0.077 ms; plate reaches the inside of the box at 0.300 ms; first crack in the box
at 0.335 ms. Energy at the end (J per metre of depth): moving 879, permanent bending 491, cracking 107,
spring 171, damping 83. Total 1742.

What this shows: with real materials, his scene runs to the end, bodies touch, bend for good and crack. The
soft demo material, not the contact method, is what stopped the as-built scene here. The 5 m/s variants were
not run yet.

## Second round (2026-11-26, Joseph's Mac, Release build of main after PR 38)

Quick checks first: --metal-profiles, --showcases, --scene-documents and the legacy replay check all passed.

### At 5 m/s

| Scene | Result |
|---|---|
| plate-in-enclosure-as-built-5ms.json (old soft material) | Stopped at first touch (0.2 ms): "Artificial bulk viscosity needs a shorter step here" |
| plate-in-enclosure-real-5ms.json (steel and aluminium) | Finished all 1.6 ms in 4 min; panel glue line starts to give at 0.25 ms, plate reaches the box at 0.95 ms |

### Speed test (real materials; 150 m/s is the app's top speed)

Plate-in-enclosure with real materials, run lasting until 0.35 ms after the touch:

| Speed (m/s) | Result | Permanent bending (J/m) | Cracking (J/m) | Time on the Mac |
|---|---|---|---|---|
| 5 | finished | 0 | 0.4 | 76 s |
| 10 | finished | 0.7 | 7.6 | 64 s |
| 30 | finished | 1,619 | 214 | 67 s |
| 75 | finished | 9,569 | 630 | 77 s |
| 150 | finished | 30,616 | 803 | 92 s |

Cascade showcase (docs/showcase/cascade.json, original spacing, run lasting 1 ms after the slug reaches the bar):

| Speed (m/s) | Result | Permanent bending (J/m) | Time on the Mac |
|---|---|---|---|
| 10 | finished | 132 | 23 s |
| 30 | finished | 1,187 | 11 s |
| 75 | finished | 6,721 | 7 s |
| 150 | finished | 26,308 | 7 s |

No run at any speed hit the "pushed into each other" stop or the smoothing stop. With real metals, the old ~5 m/s ceiling is gone.

Why the old material topped out near 5 m/s: the strong-smoothing term (quadratic bulk viscosity) grows with impact speed divided by
the material's sound speed √(E/ρ). That is about 5 km/s for steel, aluminium and glass, but only about 32 m/s for the old soft
material (1 MPa, 1000 kg/m³). So even a 5 m/s hit forced tiny steps, and the run stopped.

### Core-in-shell with a rubber pad (core-in-shell-rubber.json)

- **Strong smoothing on (as saved):** stopped at first touch (0.05 ms), for the same reason. Sound moves at only about 56 m/s in rubber (3 MPa, 930 kg/m³), so a 20 m/s hit is too fast for the smoothing.
- **Strong smoothing off:** finished all 0.4 ms in 47 s.
  - Events: box reaches the pad at 0.05 ms; pad reaches the panel at 0.10 ms; panel glue line starts to give at 0.11 ms; box cracks start to open at 0.15 ms; first panel face fails at 0.39 ms.
  - Energy at the end (J/m): moving 1,446 · spring 221 · cracking 40 · permanent bending 28.

The bodies bent and cracked, so the "slid around inside each other with nothing happening" failure did not show up here. Most of the energy
is still in motion at 0.4 ms, so a longer run would show more. Whether anything slides was not checked by eye: this was a headless run.

Open point: scenes with rubber and strong smoothing on stop on contact. The app could warn before the run. This is not changed yet.
