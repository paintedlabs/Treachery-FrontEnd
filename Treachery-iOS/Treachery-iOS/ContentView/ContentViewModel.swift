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

  init(firebaseManager: FirebaseManager) {
    self.firebaseManager = firebaseManager
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

}
