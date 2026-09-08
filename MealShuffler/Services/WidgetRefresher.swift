import Foundation
import WidgetKit

/// Tells the home-screen widget that the data underneath it moved.
///
/// The widget runs in its own process and only re-reads state when WidgetKit gives it a
/// timeline pass. Nothing did that, so a reshuffled Tuesday kept showing the meal it
/// replaced until the timeline happened to expire -- on the widget the app itself calls its
/// highest-value surface.
protocol WidgetRefreshing: Sendable {
    func reload()
}

struct WidgetKitRefresher: WidgetRefreshing {
    func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Records calls instead of making them, so tests can assert the app asks for a reload
/// without a WidgetKit host to answer.
final class RecordingWidgetRefresher: WidgetRefreshing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var reloadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func reload() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
}
