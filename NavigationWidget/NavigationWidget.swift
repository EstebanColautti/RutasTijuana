import WidgetKit
import SwiftUI
import ActivityKit

@main struct NavigationWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label(context.attributes.destination, systemImage: "figure.walk")
                Text(context.state.instruction).font(.headline)
                Text("\(context.state.meters) m")
                if context.isStale { Text("Abre la app para actualizar") }
                else if !context.state.status.isEmpty { Text(context.state.status).font(.caption) }
            }
            .padding().privacySensitive()
            .activityBackgroundTint(.black.opacity(0.85)).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "figure.walk") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.meters) m").privacySensitive() }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "Abre la app para actualizar" : context.state.instruction).privacySensitive()
                }
            } compactLeading: { Image(systemName: "figure.walk") }
              compactTrailing: { Text("\(context.state.meters)m").privacySensitive() }
              minimal: { Image(systemName: "figure.walk") }
        }
    }
}
