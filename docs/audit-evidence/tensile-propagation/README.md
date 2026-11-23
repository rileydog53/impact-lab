# Native evidence for tensile propagation

- [Native triptych](native-triptych.png) shows the aligned ×4 coupon at setup, 12 ms and 85 ms.
- [Same-time mesh comparison](native-mesh-comparison.png) shows the aligned ×3 and ×4 coupons at 12 and 30 ms.
- [Uncropped native window captures](native/) preserve field names, values, time readouts, and the fragment measurements.
- [Sampled histories](histories.csv) and [run summaries](run-summary.csv) contain the measured results. Gauge entries are blank for the original runs because the equivalent material-point gauge was introduced for the symmetric-frame runs.

The images are from the native SwiftUI Assembly view. A temporary capture harness set the same 0.4346 µs step cap as the matched solver runs, advanced the existing solver and saved the window. The comparison panels crop those window captures and add captions from the measured histories. The triptych ends at 85 ms, after separation and a receiver interaction in that run. Numerical summaries use the full interval to 115 ms.

[Methods, measurements and limitations](../../TENSILE_PROPAGATION.md)
