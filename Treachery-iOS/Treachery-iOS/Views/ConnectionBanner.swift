//
//  ConnectionBanner.swift
//  Treachery-iOS
//

import SwiftUI
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var delayTask: Task<Void, Never>?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .satisfied {
                    self.delayTask?.cancel()
                    self.isOffline = false
                } else {
                    // Small delay to avoid flicker on brief disconnects
                    self.delayTask?.cancel()
                    self.delayTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled {
                            self.isOffline = true
                        }
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }
}

struct ConnectionBanner: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        if networkMonitor.isOffline {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.orange)
                Text("Reconnecting...")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
            .overlay(
                Rectangle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }
}
