# Impact Lab user guide

A short guide to using the app: load a ready-made experiment, calculate it, watch it in slow motion, and read the labels that say what you are looking at.

Impact Lab is a 2D simulator. You see a flat slice of each object, as if it were very long and you were looking at its end. Everything that moves, bends or cracks on screen was worked out by the app's physics, step by step. Nothing is pre-animated.

## Opening the app

On the Mac, double-click `launch.command` in the Impact Lab folder. It builds the app and opens it. The first build takes a few minutes.

The window has two tabs at the top:

- **Assembly**: the main workshop. This guide is about this tab.
- **Verified presets**: an older set of fixed test cases, kept separate from the workshop.

## Loading a showcase

A showcase is a ready-made experiment with real materials, already set up so something interesting happens.

1. Click **Experiments** (the books icon) at the top of the Assembly tab.
2. On the left, under **Ready-made showcases**, pick one. The right side shows a picture of the setup, what to watch for, and its limits.
3. Click **Load showcase**.

Loading replaces whatever is in the workshop. If you have unsaved changes, the app asks whether to save them first.

The seven ready-made showcases:

- **Notched acrylic beam**: a steel ball hits an acrylic beam that has a V-notch. Watch whether a crack starts at the notch.
- **Glass arch**: a steel ball hits the top of a glass arch clamped at both feet. Watch where the first crack opens.
- **Aluminium L-bracket**: a steel ball lands on the arm of an aluminium bracket. Watch the inside corner, where it bends.
- **Laminated glass panel**: glass bonded to a plastic interlayer and aluminium, hit at 20 m/s. Watch for the first glass crack and the glass peeling off.
- **Dogbone tension test**: an aluminium test piece is pulled apart in the virtual test machine. Watch the narrow middle start to stretch permanently.
- **Perforated copper block**: a copper block with nine holes is crushed from above. Watch the holes squash.
- **First crack, slow motion**: a glass plate is hit by a steel ball. Made for trying slow motion on the moment the first crack appears.

Under **Controlled experiments** in the same window are simpler, adjustable setups. They load the same way, with **Load experiment**.

There are also three showcase files saved in the `docs/showcase` folder. To use one, click **Open** (or press Command-O), go to `docs/showcase`, and pick a `.json` file. The [showcase notes](showcase/README.md) describe what each one does.

## Calculating

After loading, the bodies sit still until you calculate.

1. Click **Calculate** (or press the space bar).
2. If the run looks long, the app first shows an estimate and asks before it starts. You can choose **Calculate Anyway** or **Cancel**.
3. While it works, a progress bar shows how far along it is, with an estimate of the time left. **Cancel Calculation** stops it and keeps what was done so far.

When it finishes, the result plays back like a video:

- **Play / Pause** (space bar) starts and stops the replay.
- The speed menu next to it sets replay speed. At **1×** the whole run plays in about five seconds.
- The slider scrubs through time. The arrow buttons step one frame back or forward, and the leftmost button jumps to the start.
- The **Events** menu lists key moments, such as first contact or **First crack**. Pick one to jump straight to it.
- The menu above the picture picks what the colors show, for example stress, permanent (plastic) strain or crack opening.

A finished run can't be edited directly. To change something and run again, click **Edit a Copy**. The app keeps your old result for comparing and gives you a fresh copy of the setup to change. **Reset Run** clears the result from the screen and goes back to the setup. Finished runs stay in the **History** menu for the session.

## Slow motion

The app already keeps extra frames around important moments. Right after each event, such as a first contact or a first crack, it saves a burst of closely spaced frames, so playback is smoother there.

For a closer look at one moment, use **Slow Down Here**:

1. Move the slider (or use **Events**) to the moment you care about.
2. Open the **Slow Down Here** menu next to the slider and pick how long a stretch to slow down. It offers three lengths, each a small slice of the run.
3. The app goes back to a saved point just before that moment and calculates that stretch again, this time keeping far more frames. A note says "Recalculating this stretch from a saved checkpoint…". You can cancel it.
4. When it's done, the slider covers only that short stretch, and a line above the controls says how many frames it kept.

These slow-motion frames are real calculations, not in-between pictures made up by the app. The app also checks them against the original run. Where the two share frames, the line should say they match. If it says they differ, treat that clip with caution.

To go back to the full run, click **Whole Run**. You return to the same moment in the full run.

## "Calculated" and "Illustration"

Next to the color scale, the app always says what kind of picture you are seeing.

- **Calculated** means the colors are exactly the numbers the physics produced. The objects are made of many small triangles, and each triangle gets one solid color from its own value. This is the raw result.
- **Illustration of calculated field** means the same numbers, blended smoothly between neighbouring triangles so the picture looks continuous. The blending is only for looks. It adds no new detail, and the brightest peaks can look a little lower than the raw values.

The **Smooth** checkbox switches between the two. Smooth is on when the app starts, so you'll see **Illustration of calculated field** at first. Turn **Smooth** off to see **Calculated**. The calculation itself is the same either way.

Pictures saved with **Export > Current frame as PNG** carry the same illustration note.

## What the results are and aren't

- Everything is 2D, so a round ball is really a long rod seen end on.
- Cracks can only run along the edges of the triangles.
- Material values come from published sources, but fracture toughness values are still experimental in this app.
- The results are careful numbers, not real lab measurements. Each showcase lists its own limits in the Experiments window.
