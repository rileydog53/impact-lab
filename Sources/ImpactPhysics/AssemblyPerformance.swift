import Dispatch

package struct AssemblyWork: Sendable {
    package var steps = 0
    package var fem: UInt64 = 0
    package var drift: UInt64 = 0
    package var fracture: UInt64 = 0
    package var contact: UInt64 = 0
    package var integration: UInt64 = 0
    package var output: UInt64 = 0
    package var kernel = ElementKernelTiming()
    package var parallelPreparation: UInt64 = 0
    package var parallelSteps = 0
    var last: UInt64 = 0

    mutating func start() { last = Self.now }
    mutating func end(_ phase: WritableKeyPath<Self, UInt64>) {
        let time = Self.now
        self[keyPath: phase] += time - last
        last = time
    }

    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }
}

// The production kernel specializes with no per-element timing branches.
protocol ElementKernelClock {
    func mark() -> UInt64
    mutating func record(started: UInt64, kinematicsEnd: UInt64, constitutiveEnd: UInt64)
}

struct UnmeasuredElementKernel: ElementKernelClock {
    func mark() -> UInt64 { 0 }
    mutating func record(started: UInt64, kinematicsEnd: UInt64, constitutiveEnd: UInt64) {}
}

package struct ElementKernelTiming: Sendable, ElementKernelClock {
    package var kinematics: UInt64 = 0
    package var constitutive: UInt64 = 0
    package var scatter: UInt64 = 0
    package var elements = 0

    func mark() -> UInt64 { AssemblyWork.now }

    mutating func record(started: UInt64, kinematicsEnd: UInt64, constitutiveEnd: UInt64) {
        let end = mark()
        kinematics += kinematicsEnd - started
        constitutive += constitutiveEnd - kinematicsEnd
        scatter += end - constitutiveEnd
        elements += 1
    }
}

package struct AssemblyStatePayload: Sendable {
    package var elasticElements = 0
    package var plasticElements = 0
    package var tractionElements = 0
    package var bytes = 0
}

extension BodyStep {
    var statePayload: AssemblyStatePayload {
        let n = body.position.count
        let elements = strain.count
        let stored = history?.current.count ?? 0
        let plastic = history?.plasticCount ?? 0
        let traction = trialPiola.count
        // Nominal live/trial numerical buffer payload before sharing or capacity,
        // excluding immutable mesh data, contact/topology and retained replay.
        let bytes = 8 * n * MemoryLayout<Point>.stride
            + 2 * elements * MemoryLayout<Double>.stride
            + 2 * stored * MemoryLayout<J2History>.stride
            + traction * MemoryLayout<ElementPiola>.stride
        return AssemblyStatePayload(elasticElements: elements - plastic, plasticElements: plastic,
                                    tractionElements: traction, bytes: bytes)
    }
}
