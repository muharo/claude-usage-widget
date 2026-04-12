import WidgetKit
import Foundation

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let isStale: Bool

    static let placeholder = UsageEntry(
        date: Date(),
        snapshot: .placeholder,
        isStale: false
    )
}
