//
//  ContentViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import SwiftUI
import FirebaseAuth


enum ContentViewModelState {
  case notAuthenticated
  case authenticated

  var isAuthenticated: Bool {
    switch self {
      case .authenticated: return true
      default: return false
    }
  }

  var bodyText: String {
    switch self {
      case .notAuthenticated: return "Not Authenticated"
      case .authenticated: return "Authenticated"
    }
  }
}

class ContentViewModel: ObservableObject {
  
  @Published var state: ContentViewModelState = .notAuthenticated
  
  var email: String = ""
  var password: String = ""

  var firebaseManager: FirebaseManager
  var cacheManager: CacheManagerProtocol


  init(firebaseManager: FirebaseManager, cacheManager: CacheManagerProtocol) {
    self.firebaseManager = firebaseManager
    self.cacheManager = cacheManager
  }

  func authenticate() {
    firebaseManager.signIn(email: self.email, password: self.password) { [weak self] result in
      switch result {
        case .success(let success):
          self?.state = .authenticated
        case .failure(let failure):
          self?.state = .notAuthenticated
      }
    }
  }

  func copyToClipboard() {
    let pasteboard = UIPasteboard.general
    if let token = cacheManager.fetchVerificationToken() {
      pasteboard.string = token
    }
  }

}
