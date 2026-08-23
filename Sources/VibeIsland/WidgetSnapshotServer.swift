import Foundation
import Network
import VibeIslandShared
import WidgetKit

/// Serves a minimal read-only snapshot on the IPv4 loopback interface. This
/// lets the sandboxed widget read live state without an App Group entitlement,
/// which would require every shared build to use the same Developer Team.
final class WidgetSnapshotServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vibecoding.vibeisland.widget-snapshot")
    private var listener: NWListener?
    private var responseBody = (try? JSONEncoder().encode(WidgetStatusSnapshot.placeholder))
        ?? Data("{}".utf8)
    private var lastSnapshot = WidgetStatusSnapshot.placeholder
    private var isStopping = false

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            isStopping = true
            listener?.cancel()
            listener = nil
        }
    }

    func update(_ snapshot: WidgetStatusSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        queue.async { [weak self] in
            guard let self, snapshot != lastSnapshot else { return }
            lastSnapshot = snapshot
            responseBody = data
            WidgetCenter.shared.reloadTimelines(ofKind: VibeIslandWidgetConstants.kind)
        }
    }

    private func startOnQueue() {
        guard listener == nil, !isStopping,
              let port = NWEndpoint.Port(rawValue: VibeIslandWidgetConstants.loopbackPort) else { return }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)

        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                if case .failed = state {
                    listener.cancel()
                    if self.listener === listener { self.listener = nil }
                    guard !self.isStopping else { return }
                    self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.startOnQueue()
                    }
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            guard !isStopping else { return }
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startOnQueue()
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] _, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(responseBody.count)\r\nConnection: close\r\n\r\n"
            var response = Data(header.utf8)
            response.append(responseBody)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
