//
//  Apollo + Intercepters.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/13/24.
//

import Foundation
//import Apollo
//
//class NetworkInterceptorProvider: DefaultInterceptorProvider {
//
//  var cacheManager: CacheManagerProtocol
//
//  init(client: URLSessionClient, store: ApolloStore, cacheManager: CacheManagerProtocol) {
//    self.cacheManager = cacheManager
//    super.init(client: client, store: store)
//  }
//
//  override func interceptors<Operation>(for operation: Operation) -> [ApolloInterceptor] where Operation : GraphQLOperation {
//    var interceptors = super.interceptors(for: operation)
//    interceptors.insert(CacheWriteInterceptor(), at: 0)
//    interceptors.insert(AuthorizationInterceptor(cacheManager: cacheManager), at: 1)
//    return interceptors
//  }
//
//}
//
//class AuthorizationInterceptor: ApolloInterceptor {
//
//  public var id: String = UUID().uuidString
//  var cacheManager: CacheManagerProtocol
//
//  init(cacheManager: CacheManagerProtocol) {
//    self.cacheManager = cacheManager
//  }
//
//  func interceptAsync<Operation>(
//    chain: RequestChain,
//    request: HTTPRequest<Operation>,
//    response: HTTPResponse<Operation>?,
//    completion: @escaping (Swift.Result<GraphQLResult<Operation.Data>, Swift.Error>) -> Swift.Void
//  ) where Operation : GraphQLOperation {
//
//    if let token = cacheManager.fetchVerificationToken() {
//      request.addHeader(name: "Authorization", value: "Bearer \(token)")
//    }
//
//    chain.proceedAsync(
//      request: request,
//      response: response,
//      interceptor: self,
//      completion: completion
//    )
//  }
//}
//
//class CacheWriteInterceptor: ApolloInterceptor {
//  var id: String = UUID().uuidString
//
//  func interceptAsync<Operation>(
//    chain: any Apollo.RequestChain,
//    request: Apollo.HTTPRequest<Operation>,
//    response: Apollo.HTTPResponse<Operation>?,
//    completion: @escaping (Swift.Result<GraphQLResult<Operation.Data>, Swift.Error>) -> Swift.Void
//  ) where Operation : GraphQLOperation {
//
//    request.cachePolicy = .fetchIgnoringCacheCompletely
//
//    chain.proceedAsync(
//      request: request,
//      response: response,
//      interceptor: self,
//      completion: completion
//    )
//  }
//
//}
