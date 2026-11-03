import SwiftUI
import WidgetKit

// The YOU watch-face complication: how many apps you've logged today and your best streak.
// It reads what the YOU watch app last saved (see Snapshot.swift); tapping it opens the app.

nonisolated struct YOUEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

nonisolated struct YOUProvider: TimelineProvider {
    func placeholder(in context: Context) -> YOUEntry {
        YOUEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (YOUEntry) -> Void) {
        completion(YOUEntry(date: .now, snapshot: context.isPreview ? .sample : Snapshot.load()?.asOf(.now)))
    }

    // Now, and again at midnight when the day's count starts over. The app refreshes it whenever it loads.
    func getTimeline(in context: Context, completion: @escaping (Timeline<YOUEntry>) -> Void) {
        let saved = Snapshot.load()
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        completion(Timeline(entries: [
            YOUEntry(date: now, snapshot: saved?.asOf(now)),
            YOUEntry(date: midnight, snapshot: saved?.asOf(midnight)),
        ], policy: .after(midnight.addingTimeInterval(60))))
    }
}

struct YOUComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: YOUEntry

    var body: some View {
        content.containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        if let s = entry.snapshot {
            let fraction = Double(s.logged) / Double(max(s.connected, 1))
            switch family {
            case .accessoryCircular:
                Gauge(value: fraction) {
                    Text("YOU")
                } currentValueLabel: {
                    Text("\(s.logged)/\(s.connected)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryCorner:
                Text("\(s.logged)/\(s.connected)")
                    .widgetLabel { Gauge(value: fraction) { Text("YOU") } }
            case .accessoryInline:
                Text("YOU \(s.logged)/\(s.connected)" + (s.bestStreak.map { " · 🔥\($0.streak)" } ?? ""))
            default:
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("YOU").font(.headline)
                        Spacer()
                        Text("\(s.logged) of \(s.connected) today").font(.caption)
                    }
                    if let best = s.bestStreak {
                        Text("🔥 \(best.streak) days · \(best.kind.uppercased())").font(.caption)
                    } else {
                        Text("Log something to start a streak").font(.caption)
                    }
                    HStack(spacing: 5) {
                        ForEach(s.apps, id: \.kind) { app in
                            Circle()
                                .fill(app.logged ? Self.color(app.kind) : Color.gray.opacity(0.35))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        } else {
            // No data shared with the complication: a launcher for the app.
            switch family {
            case .accessoryInline:
                Text("Open YOU")
            case .accessoryCorner:
                Image(systemName: "circle.grid.3x3.fill").widgetLabel("YOU")
            default:
                VStack(spacing: 2) {
                    Image(systemName: "circle.grid.3x3.fill")
                    Text("YOU").font(.caption.bold())
                }
            }
        }
    }

    // The six apps' colours, as on the home screen.
    static func color(_ kind: String) -> Color {
        switch kind {
        case "body": return Color(red: 0.561, green: 0.827, blue: 1.0)
        case "money": return Color(red: 0.561, green: 0.890, blue: 0.690)
        case "gym": return Color(red: 1.0, green: 0.608, blue: 0.608)
        case "meal": return Color(red: 0.788, green: 0.655, blue: 1.0)
        case "write": return Color(red: 1.0, green: 0.851, blue: 0.541)
        case "sleep": return Color(red: 0.604, green: 0.659, blue: 1.0)
        default: return Color(red: 1.0, green: 0.722, blue: 0.420)
        }
    }
}

@main
struct YOUComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YOUComplication", provider: YOUProvider()) { entry in
            YOUComplicationView(entry: entry)
        }
        .configurationDisplayName("YOU")
        .description("How many of your apps you've logged today, and your best streak.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
