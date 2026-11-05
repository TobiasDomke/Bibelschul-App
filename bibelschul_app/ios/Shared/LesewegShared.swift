import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// App group shared by the app and the widget extension.
let lesewegAppGroup = "group.de.bibelschulapp.leseweg"
let lesewegWidgetKey = "widget"

#if canImport(ActivityKit)
/// Lock-screen / Dynamic Island timer while a reading session is timed.
@available(iOS 16.1, *)
struct LesewegTimerAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// The timer counts up from this instant (earlier paused segments included).
    var startedAt: Date
  }

  var title: String
  var passage: String
}
#endif
