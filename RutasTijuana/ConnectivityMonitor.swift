import Network
import Combine

final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "connectivity")

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--offline") {
            isConnected = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async { self?.isConnected = connected }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
