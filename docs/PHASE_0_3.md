# Version 0.3 · Permanent deformation after impact

Launch Impact Lab with `./launch.command`. In **Plasticity impact**, select **Elastic**, run to completion, and pin the reference. Switch to **Elastoplastic** and run again. **Compare** aligns length change and mean accumulated plastic strain by simulated time. Select **Plastic strain** above the specimen to see where it yielded. The diagnostics also show peak strain, out-of-plane stress, plastic dissipation, stored hardening energy, and energy imbalance.

Both responses use the same finite-strain Hencky elasticity. The elastoplastic response adds a rate-independent J2 yield surface with linear isotropic hardening. Each triangle stores its inverse plastic metric and accumulated equivalent plastic strain. The radial return uses the full three-dimensional Kirchhoff stress, including the out-of-plane component under plane strain, and returns first Piola stress for the reference-mesh FEM forces. The solver commits material history with the accepted timestep. The energy balance counts stored hardening energy and irreversible plastic dissipation separately. [Simo, 1992](https://doi.org/10.1016/0045-7825(92)90123-2)

Residual length is the mean distance between the two end-face centroids over the final six nominal wave transit times. The specimen must be clear of the wall throughout that window. Undamped elastic waves continue to oscillate after separation, so a single final frame can differ from this mean. Scene files store settings for replay from the initial state. The original impact presets retain their neo-Hookean elastic response.

## Verification

Run `swift run --disable-sandbox -c release ImpactCheck --plasticity` for the material point, coupon, and impact checks. Omit `--plasticity` for the full regression suite.

For the default 300 mm bar at 1.30 m/s, mean unloaded length was 300.03 mm with elastic response and 293.32 mm with elastoplastic response. The plastic bar reached 2.50% mean and 6.61% peak accumulated plastic strain. It dissipated 7.19 J/m of out-of-plane depth. Peak energy imbalance stayed below 0.16% in both runs. The permanent shortening changed by 0.13% with a smaller timestep and 0.78% with a finer mesh at the same timestep. These checks verify the numerical model for the reference case. Material calibration and experimental validation are outside this milestone.

## Future UX improvements

- Give each specimen more room to move independently and support larger starting gaps.
- Expand the usable speed range as the solver and contact checks support it.
- Allow longer runs and direct dragging of specimens on the canvas.
