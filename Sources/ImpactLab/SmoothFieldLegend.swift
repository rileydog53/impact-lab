import ImpactPhysics
import SwiftUI

/// Continuous colour bar with ticks and units, for the smooth display.
struct SmoothFieldLegend: View {
    let field: AssemblyField
    let limit: Double

    var body: some View {
        let map: FieldColormap = field.signed ? .diverging : .sequential
        let stops = (0...16).map { i -> Color in
            let c = map.color(Double(i) / 16)
            return Color(red: c.x, green: c.y, blue: c.z)
        }
        let low = field.signed ? -limit : 0
        HStack(spacing: 6) {
            Text(field.display(low, limit: limit))
            VStack(spacing: 1) {
                LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                    .frame(width: 120, height: 8).clipShape(.capsule)
                if field.signed {
                    Text("0").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            Text(field.display(limit, limit: limit))
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Smooth color scale \(field.display(low, limit: limit)) to \(field.display(limit, limit: limit))")
        .help("Interpolated display of solver output (area-weighted averaging). Values beyond the scale use the end colors.")
    }
}
