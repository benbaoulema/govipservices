import ActivityKit
import SwiftUI
import WidgetKit

struct GoVIPLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GoVIPDeliveryAttributes.self) { context in
      DeliveryLiveActivityView(context: context)
        .widgetURL(deepLinkURL(for: context))
        .activityBackgroundTint(Color(red: 15 / 255, green: 118 / 255, blue: 110 / 255))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label {
            Text(roleLabel(context.state.role))
              .font(.caption.weight(.semibold))
          } icon: {
            Image(systemName: "scooter")
          }
          .foregroundStyle(.white)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.attributes.trackNumber)
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
        }
        DynamicIslandExpandedRegion(.bottom) {
          DeliveryExpandedSummary(context: context)
        }
      } compactLeading: {
        Image(systemName: "scooter")
          .foregroundStyle(.white)
      } compactTrailing: {
        Text(shortStatus(context.state.status))
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white)
      } minimal: {
        Image(systemName: "shippingbox.fill")
          .foregroundStyle(.white)
      }
      .keylineTint(.white)
      .widgetURL(deepLinkURL(for: context))
    }
  }

  private func deepLinkURL(for context: ActivityViewContext<GoVIPDeliveryAttributes>) -> URL? {
    var components = URLComponents()
    components.scheme = "govipservices"
    components.host = "parcel-tracking"
    components.queryItems = [
      URLQueryItem(name: "requestId", value: context.attributes.requestId),
      URLQueryItem(name: "role", value: context.state.role),
    ]
    return components.url
  }

  private func roleLabel(_ role: String) -> String {
    role == "driver" ? "Livreur" : "Colis"
  }

  private func shortStatus(_ status: String) -> String {
    switch status {
    case "accepted":
      return "Route"
    case "en_route_to_pickup":
      return "Pickup"
    case "picked_up":
      return "Livr."
    default:
      return "Cours"
    }
  }
}

private struct DeliveryLiveActivityView: View {
  let context: ActivityViewContext<GoVIPDeliveryAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(context.state.title)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
          Text(context.state.body)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(2)
        }
        Spacer()
        if !context.state.etaText.isEmpty {
          Text(context.state.etaText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.18), in: Capsule())
            .foregroundStyle(.white)
        }
      }

      DeliveryExpandedSummary(context: context)
    }
    .padding(16)
  }
}

private struct DeliveryExpandedSummary: View {
  let context: ActivityViewContext<GoVIPDeliveryAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AddressRow(
        icon: "shippingbox.fill",
        label: "Retrait",
        value: context.attributes.pickupAddress
      )
      AddressRow(
        icon: "location.fill",
        label: "Livraison",
        value: context.attributes.deliveryAddress
      )
    }
  }
}

private struct AddressRow: View {
  let icon: String
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.caption.weight(.bold))
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: 16, height: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white.opacity(0.72))
        Text(value.isEmpty ? "-" : value)
          .font(.caption)
          .foregroundStyle(.white)
          .lineLimit(1)
      }
    }
  }
}
