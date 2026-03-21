import ActivityKit
import Foundation

struct GoVIPDeliveryAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var title: String
    var body: String
    var status: String
    var role: String
    var etaText: String
    var updatedAt: Date
  }

  var requestId: String
  var trackNumber: String
  var pickupAddress: String
  var deliveryAddress: String
}
