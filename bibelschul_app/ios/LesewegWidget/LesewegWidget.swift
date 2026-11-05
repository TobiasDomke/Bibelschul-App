import ActivityKit
import SwiftUI
import WidgetKit

/// What the app last wrote for the widget (see NativeBridge.swift / native_bridge.dart).
struct ReadingEntry: TimelineEntry {
  let date: Date
  let title: String
  let passage: String
  let detail: String
  let progress: Double
  let done: Bool

  static let placeholder = ReadingEntry(
    date: .now, title: "Heute", passage: "1. Mose 1–3", detail: "Tag 1 / 365", progress: 0.12, done: false)
}

private func localDay(_ date: Date) -> String {
  let f = DateFormatter()
  f.calendar = Calendar(identifier: .gregorian)
  f.locale = Locale(identifier: "en_US_POSIX")
  f.dateFormat = "yyyy-MM-dd"
  return f.string(from: date)
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> ReadingEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
    completion(context.isPreview ? .placeholder : load(at: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
    // One entry now and one shortly after midnight, when "read today" resets
    // and tomorrow's passage becomes today's.
    let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400 + 60)
    completion(Timeline(entries: [load(at: .now), load(at: midnight)], policy: .after(midnight)))
  }

  private func load(at date: Date) -> ReadingEntry {
    guard let data = UserDefaults(suiteName: lesewegAppGroup)?.dictionary(forKey: lesewegWidgetKey) else {
      return ReadingEntry(date: date, title: "Leseweg", passage: "", detail: "", progress: 0, done: false)
    }
    let savedDay = data["date"] as? String ?? ""
    let isSameDay = savedDay == localDay(date)
    let next = !isSameDay && savedDay < localDay(date)
    return ReadingEntry(
      date: date,
      title: next ? (data["todayTitle"] as? String ?? "") : (data["title"] as? String ?? ""),
      passage: next ? (data["nextPassage"] as? String ?? "") : (data["passage"] as? String ?? ""),
      detail: next ? (data["nextDetail"] as? String ?? "") : (data["detail"] as? String ?? ""),
      progress: data["progress"] as? Double ?? 0,
      done: isSameDay && (data["done"] as? Bool ?? false))
  }
}

private let green = Color(red: 0x17 / 255, green: 0x4e / 255, blue: 0x43 / 255)
private let sage = Color(red: 0xad / 255, green: 0xcc / 255, blue: 0xaf / 255)

struct LesewegWidgetView: View {
  @Environment(\.widgetFamily) var family
  var entry: ReadingEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      Gauge(value: entry.progress) {
        Image(systemName: entry.done ? "checkmark" : "book")
      }
      .gaugeStyle(.accessoryCircularCapacity)
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Label(entry.title, systemImage: entry.done ? "checkmark.circle" : "book")
          .font(.caption.weight(.semibold))
        Text(entry.passage).font(.headline).lineLimit(2)
      }
    case .accessoryInline:
      Text(entry.done ? entry.title : entry.passage)
    default:
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Image(systemName: entry.done ? "checkmark.circle.fill" : "book.fill")
          Text(entry.title).font(.caption.weight(.bold)).textCase(.uppercase)
        }
        .foregroundStyle(sage)
        Text(entry.passage)
          .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(family == .systemSmall ? 3 : 2)
        Spacer(minLength: 0)
        Text(entry.detail).font(.caption).foregroundStyle(sage)
        ProgressView(value: entry.progress).tint(sage)
      }
    }
  }
}

struct LesewegWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "LesewegWidget", provider: Provider()) { entry in
      LesewegWidgetView(entry: entry)
        .containerBackground(for: .widget) { green }
    }
    .configurationDisplayName("Leseweg")
    .description("Deine heutigen Kapitel und dein Fortschritt.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
  }
}

struct LesewegTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LesewegTimerAttributes.self) { context in
      HStack(spacing: 12) {
        Image(systemName: "book.fill").font(.title2).foregroundStyle(sage)
        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.title).font(.caption).foregroundStyle(sage)
          Text(context.attributes.passage).font(.headline).foregroundStyle(.white).lineLimit(1)
        }
        Spacer()
        Text(context.state.startedAt, style: .timer)
          .font(.title2.monospacedDigit().weight(.semibold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 110, alignment: .trailing)
      }
      .padding()
      .activityBackgroundTint(green)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "book.fill").foregroundStyle(sage)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 90)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.attributes.passage).lineLimit(1)
        }
      } compactLeading: {
        Image(systemName: "book.fill").foregroundStyle(sage)
      } compactTrailing: {
        Text(context.state.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 46)
      } minimal: {
        Image(systemName: "book.fill").foregroundStyle(sage)
      }
    }
  }
}

@main
struct LesewegWidgetBundle: WidgetBundle {
  var body: some Widget {
    LesewegWidget()
    LesewegTimerLiveActivity()
  }
}
