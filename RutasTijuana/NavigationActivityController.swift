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
    private var pending: Task<Void, Never>?
    func update(destination: String, instruction: String, meters: Int, status: String) {
        let state = NavigationAttributes.ContentState(instruction: instruction, meters: max(0, meters / 10 * 10), status: status)
        guard state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
        if let activity {
            pending?.cancel()
            pending = Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: NavigationAttributes(destination: destination), content: content, pushType: nil)
        }
    }
    func end(message: String) {
        pending?.cancel(); pending = nil
        guard let activity else { return }
        self.activity = nil; lastState = nil
        Task {
            let state = NavigationAttributes.ContentState(instruction: message, meters: 0, status: "")
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
