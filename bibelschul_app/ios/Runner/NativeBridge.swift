import ActivityKit
import Flutter
import Foundation
import WidgetKit

/// Handles the "leseweg/native" channel (lib/services/native_bridge.dart):
/// home-screen widget data and the lock-screen timer.
enum NativeBridge {
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "LesewegNative") else { return }
    let channel = FlutterMethodChannel(name: "leseweg/native", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "updateWidget":
        if let args = call.arguments as? [String: Any] {
          UserDefaults(suiteName: lesewegAppGroup)?.set(args, forKey: lesewegWidgetKey)
          WidgetCenter.shared.reloadAllTimelines()
        }
        result(nil)
      case "startTimer":
        if #available(iOS 16.2, *), let args = call.arguments as? [String: Any] {
          startTimer(args)
        }
        result(nil)
      case "stopTimer":
        if #available(iOS 16.2, *) { stopTimers() }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(iOS 16.2, *)
  private static func startTimer(_ args: [String: Any]) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
      let ms = args["startedAt"] as? NSNumber
    else { return }
    let state = LesewegTimerAttributes.ContentState(startedAt: Date(timeIntervalSince1970: ms.doubleValue / 1000))
    let attributes = LesewegTimerAttributes(
      title: args["title"] as? String ?? "Leseweg", passage: args["passage"] as? String ?? "")
    Task {
      // Only one timer at a time: replace a running one (for example after reopening the app).
      for activity in Activity<LesewegTimerAttributes>.activities {
        let sameStart = abs(activity.content.state.startedAt.timeIntervalSince(state.startedAt)) < 3
        if sameStart && activity.attributes.passage == attributes.passage { return }
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
    }
  }

  @available(iOS 16.2, *)
  private static func stopTimers() {
    Task {
      for activity in Activity<LesewegTimerAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }
}
