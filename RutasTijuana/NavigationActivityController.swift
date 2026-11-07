import ActivityKit
import Foundation

@MainActor final class NavigationActivityController {
    private static var cleaned = false
    static func clearPreviousSession() async {
        guard !cleaned else { return }
        cleaned = true
        for activity in Activity<NavigationAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    private var activity: Activity<NavigationAttributes>?
    private var lastState: NavigationAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    private var lastLocationCurrent: Bool?
    private var pending: Task<Void, Never>?
    func update(destination: String, instruction: String, meters: Int, status: String, locationCurrent: Bool) {
        let state = NavigationAttributes.ContentState(instruction: instruction, meters: max(0, meters / 10 * 10), status: status)
        let now = Date()
        guard state != lastState || locationCurrent != lastLocationCurrent || (locationCurrent && now.timeIntervalSince(lastUpdate) >= 30) else { return }
        lastState = state
        lastLocationCurrent = locationCurrent
        lastUpdate = now
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(locationCurrent ? 60 : 0))
        if let activity {
            pending?.cancel()
            pending = Task {
                guard !Task.isCancelled else { return }
                await activity.update(content)
            }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: NavigationAttributes(destination: destination), content: content, pushType: nil)
        }
    }
    func end(message: String) {
        pending?.cancel(); pending = nil
        guard let activity else { return }
        self.activity = nil; lastState = nil; lastLocationCurrent = nil
        Task {
            let state = NavigationAttributes.ContentState(instruction: message, meters: 0, status: "")
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
