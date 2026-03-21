import ActivityKit
import Flutter
import Foundation

final class LiveActivityManager {
  static let shared = LiveActivityManager()

  private init() {}

  func handle(method: String, arguments: Any?, result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(nil)
      return
    }

    switch method {
    case "startOrUpdate":
      guard let payload = arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Missing Live Activity payload.",
            details: nil
          )
        )
        return
      }
      startOrUpdate(with: payload, result: result)
    case "endAll":
      endAll(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 16.1, *)
  private func startOrUpdate(with payload: [String: Any], result: @escaping FlutterResult) {
    guard
      let requestId = payload["requestId"] as? String,
      let trackNum = payload["trackNum"] as? String,
      let title = payload["title"] as? String,
      let body = payload["body"] as? String,
      let status = payload["status"] as? String,
      let role = payload["role"] as? String,
      let pickupAddress = payload["pickupAddress"] as? String,
      let deliveryAddress = payload["deliveryAddress"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_args",
          message: "Missing required Live Activity fields.",
          details: nil
        )
      )
      return
    }

    let etaText = (payload["etaText"] as? String) ?? ""
    let state = GoVIPDeliveryAttributes.ContentState(
      title: title,
      body: body,
      status: status,
      role: role,
      etaText: etaText,
      updatedAt: Date()
    )
    let attributes = GoVIPDeliveryAttributes(
      requestId: requestId,
      trackNumber: trackNum,
      pickupAddress: pickupAddress,
      deliveryAddress: deliveryAddress
    )

    Task {
      do {
        if let existing = Activity<GoVIPDeliveryAttributes>.activities.first(
          where: { $0.attributes.requestId == requestId }
        ) {
          try await Self.update(activity: existing, state: state)
        } else {
          for activity in Activity<GoVIPDeliveryAttributes>.activities {
            try await Self.end(activity: activity, state: state)
          }
          _ = try Self.start(attributes: attributes, state: state)
        }
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "live_activity_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  @available(iOS 16.1, *)
  private func endAll(result: @escaping FlutterResult) {
    Task {
      let finalState = GoVIPDeliveryAttributes.ContentState(
        title: "Livraison terminee",
        body: "",
        status: "delivered",
        role: "sender",
        etaText: "",
        updatedAt: Date()
      )
      for activity in Activity<GoVIPDeliveryAttributes>.activities {
        try? await Self.end(activity: activity, state: finalState)
      }
      result(nil)
    }
  }

  @available(iOS 16.1, *)
  private static func start(
    attributes: GoVIPDeliveryAttributes,
    state: GoVIPDeliveryAttributes.ContentState
  ) throws -> Activity<GoVIPDeliveryAttributes> {
    if #available(iOS 16.2, *) {
      return try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state, staleDate: staleDate),
        pushType: nil
      )
    }
    return try Activity.request(
      attributes: attributes,
      contentState: state,
      pushType: nil
    )
  }

  @available(iOS 16.1, *)
  private static func update(
    activity: Activity<GoVIPDeliveryAttributes>,
    state: GoVIPDeliveryAttributes.ContentState
  ) async throws {
    if #available(iOS 16.2, *) {
      await activity.update(ActivityContent(state: state, staleDate: staleDate))
      return
    }
    await activity.update(using: state)
  }

  @available(iOS 16.1, *)
  private static func end(
    activity: Activity<GoVIPDeliveryAttributes>,
    state: GoVIPDeliveryAttributes.ContentState
  ) async throws {
    if #available(iOS 16.2, *) {
      await activity.end(
        ActivityContent(state: state, staleDate: nil),
        dismissalPolicy: .immediate
      )
      return
    }
    await activity.end(using: state, dismissalPolicy: .immediate)
  }

  @available(iOS 16.2, *)
  private static var staleDate: Date {
    Date().addingTimeInterval(30 * 60)
  }
}
