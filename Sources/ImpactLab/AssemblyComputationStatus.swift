import Darwin
import ImpactPhysics
import SwiftUI

struct AssemblyProcessSample: Sendable {
    let time: Double
    let cpu: Double?
    let resident, peakResident: UInt64?

    init() {
        time = ProcessInfo.processInfo.systemUptime
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
            peakResident = UInt64(usage.ru_maxrss)
        } else {
            cpu = nil
            peakResident = nil
        }
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        resident = result == KERN_SUCCESS ? info.resident_size : nil
    }

    func utilization(since earlier: Self) -> Double? {
        guard let cpu, let previous = earlier.cpu, time > earlier.time else { return nil }
        return 100 * (cpu - previous) / (time - earlier.time)
    }
}

struct AssemblyComputation: Sendable {
    enum State: String, Sendable {
        case calculating = "Calculating"
        case paused = "Calculation paused"
        case completed = "Calculation complete"
        case failed = "Calculation stopped"
    }

    let state: State
    let time, duration, dt, elapsed: Double
    let work: AssemblyWork
    let elements, frames: Int
    let solverBytes, replayBytes: Int
    let process: AssemblyProcessSample
    let cpuUtilization: Double?

    var fraction: Double { state == .completed ? 1 : min(1, time / duration) }
}

struct AssemblyComputationStatus: View {
    let experiment: AssemblyExperiment
    @State private var details = false

    var body: some View {
        if let run = experiment.computation {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(run.state.rawValue).fontWeight(.semibold)
                    if experiment.solving {
                        ProgressView(value: run.fraction)
                            .accessibilityLabel("Calculation progress")
                            .accessibilityValue(run.fraction.formatted(.percent.precision(.fractionLength(1))))
                            .frame(minWidth: 40, maxWidth: 180)
                        Text(run.fraction.formatted(.percent.precision(.fractionLength(1))))
                    }
                    Text("\(replayTime(run.time)) / \(replayTime(run.duration))")
                    Spacer(minLength: 4)
                    if experiment.solving {
                        Button(experiment.cancelling ? "Cancelling…" : "Cancel Calculation") {
                            experiment.cancelCalculation()
                        }.disabled(experiment.cancelling)
                    }
                    Button("Compute Details", systemImage: "gauge.with.dots.needle.33percent") { details = true }
                        .labelStyle(.iconOnly)
                        .popover(isPresented: $details) { breakdown(run) }
                }
                Text("\(run.work.steps.formatted()) steps · \(run.elapsed, specifier: "%.2f") s elapsed · CPU \(cpu(run)) · RAM \(memory(run.process.resident))")
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .font(.caption)
            .controlSize(.small)
        }
    }

    private func cpu(_ run: AssemblyComputation) -> String {
        guard let value = run.cpuUtilization else { return "—" }
        return String(format: "%.0f%%", value)
    }

    private func memory(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        return String(format: "%.1f MiB", Double(bytes) / 1_048_576)
    }

    private func breakdown(_ run: AssemblyComputation) -> some View {
        let preparation = run.work.parallelSteps > 0
            ? [("Position and FEM updates · 2 CPU lanes", run.work.parallelPreparation)]
            : [("Position update", run.work.drift), ("Element update and force assembly", run.work.fem)]
        let stages = preparation + [
            ("Fracture and topology", run.work.fracture),
            ("Contact search and forces", run.work.contact),
            ("Links, velocity update and acceptance", run.work.integration),
            ("Trace and replay recording", run.work.output)
        ]
        return VStack(alignment: .leading, spacing: 9) {
            Text("Calculation details").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow { Text("Triangles"); Text(run.elements.formatted()) }
                GridRow { Text("Numerical timestep"); Text(replayTime(run.dt)) }
                GridRow {
                    Text("Wall time per accepted step")
                    if run.work.steps > 0 {
                        Text("\(run.elapsed * 1e6 / Double(run.work.steps), specifier: "%.1f") µs")
                    } else { Text("—") }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(stages, id: \.0) { label, time in
                    GridRow { Text(label); Text("\(Double(time) / 1e9, specifier: "%.3f") s") }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow { Text("Process peak resident memory"); Text(memory(run.process.peakResident)) }
                GridRow { Text("Solver state payload"); Text(memory(UInt64(run.solverBytes))) }
                GridRow {
                    Text("Replay payload · \(run.frames.formatted()) frames")
                    Text(memory(UInt64(run.replayBytes)))
                }
            }.monospacedDigit()
            Text("CPU is the app process average over the latest measurement interval. 100% is one fully used logical core. RAM is current process resident memory. Payloads count solver state and replay fields. Shared mesh data, allocator overhead and contact workspaces are included only in process RAM.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption).padding(14).frame(width: 365)
    }
}
