import Foundation


struct SootSpace: Identifiable {
  let id: String
  let name: String
}

struct FileUploadProgress {
  let progress: Double
  let ETA: String
  let totalBytesUploaded: Double
}

import SwiftUI
import FirebaseAuth

protocol NetworkProtocol {
}

class Network: NetworkProtocol {

  var cacheManager: CacheManagerProtocol

  init(cacheManager: CacheManagerProtocol) {
    self.cacheManager = cacheManager
  }

//  private(set) lazy var apollo: ApolloClient = {
//    let client = URLSessionClient()
//    let cache = InMemoryNormalizedCache()
//    let store = ApolloStore(cache: cache)
//    let provider = NetworkInterceptorProvider(client: client, store: store, cacheManager: cacheManager)
//    let url = URL(string: "https://api.treachery.luke")! // TODO: ACTUAL URL GOES HERE
//    let transport = RequestChainNetworkTransport(interceptorProvider: provider, endpointURL: url)
//
//    return ApolloClient(networkTransport: transport, store: store)
//  }()
}

extension Task where Failure == Error {
  /// Performs an async task in a sync context.
  ///
  /// - Note: This function blocks the thread until the given operation is finished. The caller is responsible for managing multithreading.
  static func synchronous(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Success) {
    let semaphore = DispatchSemaphore(value: 0)

    Task(priority: priority) {
      defer { semaphore.signal() }
      return try await operation()
    }

    semaphore.wait()
  }
}
