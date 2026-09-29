import SwiftUI
import WidgetKit
import AscentCore
import AscentUI
import AscentWidgetsUI

@main
struct AscentWidgetBundle: WidgetBundle {
    init() { AscentFonts.register() }

    var body: some Widget {
        AscentWidget()
        LiveSessionActivity()
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary
    let privacyLock: Bool
    let accent: AccentTheme
}

/// Reads the on-device log from the App Group and recomputes everything. Nothing is cached or synced.
struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, summary: .placeholder, privacyLock: false, accent: AccentTheme(hex: ""))
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let now = Date.now
        // Refresh every 30 minutes and right after midnight, when "this week" / "today" roll over.
        var dates = (0..<8).map { now.addingTimeInterval(Double($0) * 1800) }
        if let midnight = Day.calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) {
            dates.append(midnight)
        }
        let entries = dates.sorted().map { entry(at: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func entry(at date: Date) -> SummaryEntry {
        let db = LogFile.load() ?? Seed.empty()
        return SummaryEntry(date: date, summary: WidgetSummary.compute(db, now: date),
                            privacyLock: SharedAccent.privacyLock, accent: SharedAccent.current)
    }
}

struct AscentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AscentSummary", provider: SummaryProvider()) { entry in
            AscentWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ascent")
        .description("This week at a glance. With the Face ID lock on, a locked iPhone shows only counts and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AscentWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SummaryEntry

    var body: some View {
        let kind: AscentWidgetKind = switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        case .accessoryCircular: .circular
        case .accessoryRectangular: .rectangular
        default: .inline
        }
        let isHome = kind == .small || kind == .medium || kind == .large
        AscentWidgetView(kind: kind, summary: entry.summary, privacyLock: entry.privacyLock, accent: entry.accent)
            .widgetURL(URL(string: isHome ? "ascent://today" : "ascent://log"))
            .containerBackground(for: .widget) {
                if isHome { Palette.paper } else { Color.clear }
            }
    }
}
