import ActivityKit
import Foundation

struct NavigationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var instruction: String
        var meters: Int
        var status: String
    }
    var destination: String
}
