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

The same showcases are listed under **New / Examples**, and the app opens on the notched acrylic beam. The older test setups made of a simplified soft material are no longer shown in the app. They still run in the automatic checks.

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

## Building your own experiment

Add bodies with the **+** menu in the workshop, or draw your own shape. Every new body starts as **aluminium**; benches and rollers start as **steel**. Pick a body to change it in the panel on the right.

### Choosing a material

Under **Material**, click **Choose a material** and pick one by name. The Library has metals that bend for good (steel, stainless steel, aluminium, copper, titanium, brass) and materials that spring back (carbon fibre, window glass, epoxy, polycarbonate, safety-glass plastic, rubber, oak). Each one's numbers come from published sources, listed under its **Source** link.

To try something that isn't in the list, click **Type my own numbers instead**. The settings, in plain words:

| Setting | What it means | For scale |
|---|---|---|
| **Stiffness** (Young's modulus) | How hard it is to bend or squash a little | rubber 0.003 · wood 12 · aluminium 69 · steel 200 GPa |
| **Weight per size** (density) | How heavy it is for its size | water 1000 · aluminium 2700 · steel 7850 kg/m³ |
| **Squish sideways** (Poisson ratio) | How much it bulges out the sides when you squash it | cork 0 · metals 0.3 · rubber about 0.5 |
| **Bends for good at** (yield strength) | The push at which a metal stops springing back and stays bent | copper 69 · aluminium 276 · titanium 890 MPa |
| **Takes after a big bend** | How much harder it is to bend further once it's bent a lot (12%) | a little above "bends for good at" |

"How it behaves" picks **Springs back** (elastic, like glass or rubber) or **Metal: bends for good** (J2 plasticity, the standard model for metals).

### Cracking

Tick **Can crack** to let a body break. Two numbers control it:

- **Crack starts at** (cohesive strength): how hard you have to pull before a crack begins. Glass 41, aluminium 310, steel 475 MPa.
- **Crack resistance** (fracture energy): how much energy it takes to make the crack grow. Glass 7, epoxy 150, aluminium 11,000, steel 89,000 J/m². Lower means a crack, once started, runs through easily.

Setting crack resistance very low does not make a body crack the moment it's touched. A crack only starts when the pull reaches **Crack starts at**. To make something crack easily, lower that number too.

Round bodies can't crack, and neither can fixed supports. The app says so next to the body.

### Making sure they actually hit

Above **Run length** the app works out when the bodies will first touch, from their starting speeds, and how long the run goes on after that. If the run would end before anything touches, it says so and offers a button that makes the run long enough. Gravity and springs are not counted in that estimate.

Speeds are in metres per second. A minus sign means moving left (or down).

### Why some runs are slow

The app calculates in tiny time steps, and one step has to be shorter than the time sound takes to cross the smallest triangle of the stiffest body. A steel or aluminium body on a fine mesh makes every step very short, so the whole scene takes many steps, even while nothing is touching yet. To speed things up, start the bodies closer together, use a coarser mesh where detail isn't needed, or shorten the run.

### If a run stops with "pushed into each other"

The app stops a run when two bodies sink into each other further than it can trust (more than a tenth of a triangle edge), rather than show a wrong result. The message names the two bodies. This mostly happens when one body is far softer or far more coarsely meshed than the one it hits. Using real materials for both, or a finer mesh on the body being hit, usually fixes it.

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
