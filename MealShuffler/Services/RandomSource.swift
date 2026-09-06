import Foundation

/// Source of randomness for plan generation.
///
/// Injected rather than reached for globally so tests can pin the sequence: the generator
/// samples from a distribution, and an assertion about that sampling is only meaningful if
/// the draw is reproducible.
protocol RandomSource: AnyObject {
    /// Uniform value in `[0, 1)`.
    func nextUniform() -> Double
}

final class SystemRandomSource: RandomSource {
    func nextUniform() -> Double { Double.random(in: 0..<1) }
}

/// Deterministic SplitMix64. Same seed, same sequence, on every platform and run.
final class SeededRandomSource: RandomSource {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    func nextUniform() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        // Top 53 bits scaled into [0, 1), matching Double's significand width.
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
