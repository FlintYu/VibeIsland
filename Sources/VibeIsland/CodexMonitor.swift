import Combine
import Foundation

@MainActor
final class CodexMonitor: ObservableObject {
    /// Keep task discovery responsive without allowing overlapping app-server requests.
    /// `refresh()` already coalesces ticks while a request is in flight.
    static let refreshInterval: TimeInterval = 1
    static let clockInterval: TimeInterval = 15

    @Published private(set) var quota = QuotaSnapshot.placeholder
    @Published private(set) var tasks: [CodexTaskSnapshot] = []
    @Published private(set) var now = Date()
    @Published private(set) var isConnected = false
    @Published private(set) var errorMessage: String?

    private let client = CodexAppServerClient()
    private var clock: AnyCancellable?
    private var refreshTimer: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    var currentTask: CodexTaskSnapshot? {
        activeTasks.first ?? tasks.first
    }

    var activeTasks: [CodexTaskSnapshot] {
        tasks.filter(\.isActive)
    }

    func start() {
        // The UI only renders minute-level countdowns. Updating `now` every
        // second needlessly invalidates the entire SwiftUI hierarchy.
        clock = Timer.publish(every: Self.clockInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.now = date
            }

        refreshTimer = Timer.publish(every: Self.refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            do {
                let snapshot = try await client.fetch()
                if quota != snapshot.quota { quota = snapshot.quota }
                if tasks != snapshot.tasks { tasks = snapshot.tasks }
                if !isConnected { isConnected = true }
                if errorMessage != nil { errorMessage = nil }
            } catch {
                if isConnected { isConnected = false }
                let message = error.localizedDescription
                if errorMessage != message { errorMessage = message }
            }
        }
    }
}
