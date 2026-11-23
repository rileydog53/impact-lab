# Impact Lab — your acceptance checklist (about 20 minutes)

Card 6 ends with you trying the app yourself. Open it with `launch.command`, work through these steps, and tick each one only if it worked and made sense to you. Note anything confusing. That is useful feedback too.

## 1. Build something from scratch (about 6 min)
- [ ] Click **New / Examples → Blank Assembly**.
- [ ] Use **Add Body** to add a **Rectangular Plate** and a **Round Body**.
- [ ] Select the round body. In the inspector, set **X velocity** to `-40` so it moves toward the plate. A white arrow appears.
- [ ] Select the plate. Open **Material → Material Library…**, pick **6061-T6 Aluminum**, read its evidence note, and press **Assign to Body**.
- [ ] Press **Calculate**. Watch the progress bar, then drag the **Replay time** slider and press **Play**.
- [ ] Press **Pin**, then **Reset Run**. Change the plate to **Annealed Copper** and press **Calculate** again.
- [ ] Press **Compare** and set **Field → Plastic strain**. Copper should show permanent bending spread over a wider area.
- [ ] Press **Save**, then **Open** the file again. The plate should still say aluminum or copper.

## 2. Change a ready-made experiment (about 4 min)
- [ ] **New / Examples → Metal Impact Example** → **Calculate** → **Pin** → **Reset Run**.
- [ ] Change the specimen's **Local height**. In the Material Library, use **Duplicate and Edit** to raise the first flow-stress number, then press **Save Profile** and **Assign to Body**.
- [ ] Press **Calculate**, then **Compare**. Both runs appear side by side with their numbers.

## 3. Check how trustworthy a number is (about 3 min)
- [ ] Press **Study → Mesh refinement → Run study**, then set **Signal** to **Plastic dissipation**.
- [ ] The three lines should nearly overlap. Nearly overlapping means the number does not depend on mesh size. Try **Export CSV…**.

## 4. Push the computer (about 4 min)
- [ ] Open **Enclosure Example** and set **Simulation settings → Assembly mesh** to **×4**. Press **Calculate**.
- [ ] While it runs, zoom and pan the canvas and open the **ⓘ** details. Press **Cancel Calculation**, then **Resume Calculation**.
- [ ] The app should stay responsive. It finishes in about 3 minutes and uses less than 300 MB of memory.

## 5. Ready-made scenarios (about 3 min)
- [ ] Click **Scenarios**, choose **Strain hardening**, and press **Run A and B**. Read the results table and the takeaway.
- [ ] Hover over the locked **Brittle versus ductile** entry to see why it is not available yet.

## What to expect, honestly
- **Trust the numbers** in the elastic wave-speed and bonded-layer scenarios, and for the energy totals in any run. All of these are checked against theory.
- **Trust the trends** for metal comparisons: which metal dents more, and which absorbs more energy. The exact values depend on mesh size and on illustrative hardening curves.
- **Treat as illustration:** crack paths, and anything after a metal starts to harden beyond its listed yield value.
- **Not available yet:** bodies fixed to the ground (all bodies are free, and supports are separate blocks), metal fracture, and speed- or temperature-dependent metals.

If every box is ticked, tell Claude "Card 6 accepted". Otherwise, describe what went wrong.
