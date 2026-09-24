import SwiftUI

/// A day's dinner, drawn like a slot-machine reel.
///
/// Shuffle is the app's name and its signature action, and it used to be a spinner followed
/// by a list that had silently changed. Now each day's reel spins through dishes and settles
/// on its dinner, one day after another, each with a small tap under the thumb -- the moment
/// the week is drawn is something you see and feel. With Reduce Motion on, it simply changes.
struct SlotReel: View {
    let symbol: String
    /// Changes whenever this reel should spin.
    let spin: Int
    /// How long after the first reel this one settles, so the week lands left to right.
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var face: String?
    @State private var rolling: Task<Void, Never>?

    static let faces = ["🍕", "🌮", "🐟", "🍝", "🥗", "🍛", "🍲", "🥘", "🍗", "🍜", "🥙", "🍔", "🥣", "🍤", "🌯", "🥞"]

    var body: some View {
        ZStack {
            Text(face ?? symbol)
                .id(face ?? symbol)
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(insertion: .move(edge: .top), removal: .move(edge: .bottom)))
        }
        .clipped()
        .onChange(of: spin) { _, _ in roll() }
        .onDisappear { rolling?.cancel() }
        .accessibilityHidden(true)
    }

    private func roll() {
        rolling?.cancel()
        guard !reduceMotion else { return }
        rolling = Task { @MainActor in
            let steps = 6 + Int((delay / 0.08).rounded())
            for step in 0..<steps {
                var next = Self.faces.randomElement() ?? symbol
                // A repeated face would not move, and a reel that stalls reads as broken.
                if next == face { next = Self.faces[((Self.faces.firstIndex(of: next) ?? 0) + 1) % Self.faces.count] }
                withAnimation(.linear(duration: 0.06)) { face = next }
                // Slows towards the end, like a reel settling.
                try? await Task.sleep(for: .milliseconds(50 + step * 7))
                if Task.isCancelled { return }
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { face = nil }
            Haptics.land()
        }
    }
}
