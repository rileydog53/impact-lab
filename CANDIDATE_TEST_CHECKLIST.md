# Impact Lab candidate build: your test checklist (about 15 minutes)

One app. To open it, double-click **Impact Lab (test build)** on the Desktop or `launch.command` in this folder. Both open the shared test build without rebuilding (macOS may ask you to allow it the first time).

## What is new in this build
1. **The 4 small fixes (PR 2):** each body shows "fracture on / off / n/a" tags; small bodies are allowed (minimum follows mesh size); Open/Save remember your last folder; the spring panel explains starting length, rest length, preload and stiffness in plain words with a picture. Also a crash fix for enclosures.
2. **Smooth colours:** the stress/strain/etc. picture is now a continuous gradient instead of one flat colour per triangle. A **Smooth** checkbox switches back to the raw per-triangle colours. A continuous colour bar with units sits beside it.
3. **Export menu:** (a) results for ParaView (a free scientific viewer), (b) the current frame as a PNG picture.

## What to try
- [ ] **Build once, then open the app.** Open **New / Examples → Metal Impact Example** and press **Calculate**.
- [ ] **Smooth on versus off.** Drag the Replay slider. Tick and untick **Smooth**. The numbers do not change, only how the colours are drawn. Does the smooth view look more like a real material? Does it ever look wrong or misleading?
- [ ] **Show mesh** on and off while Smooth is on. Mesh off should be a clean picture.
- [ ] **Change the Field** (for example Plastic strain). Check the colour bar's end labels and units look sensible.
- [ ] **Export → Current frame as PNG.** Open the saved PNG. It should show the picture, the colour bar, units and a caption saying it is an interpolated display.
- [ ] **Export → ParaView.** Choose a folder; a message reports what was written. (Optional: if you have ParaView, open the `.pvd` file.)
- [ ] **Body tags and the 4 fixes.** Open the Enclosure Example: look for fracture on/off/n/a tags in the body list and the inspector; hover over an "n/a". Add a small body (try 12 mm). Open the spring example and read the spring panel.
- [ ] **Remembered folder.** Save a file into a folder, then press Open; it should start in that folder.
- [ ] **Anything confusing, ugly or slow.** Write it down; that is useful.

## Verified in code vs not yet seen on screen
See `CANDIDATE_REPORT.md` for the exact test results. In short: the calculation, the saved numbers, the colour mapping and the export files are checked by automated tests. **Nobody has looked at the smooth view, colour bar, Export menu, body tags or spring panel on a real screen**, so how they look and feel is exactly what you are testing.

Smooth colours are a display only. They average neighbouring triangles, so the single hottest spot looks lower than it is; exact peaks come from the Measurements, not the picture.
