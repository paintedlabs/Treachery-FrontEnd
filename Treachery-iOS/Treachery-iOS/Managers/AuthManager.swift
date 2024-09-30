//
//  AuthManager.swift
//  SootUploader
//
//  Created by Luke Solomon on 8/1/24.
//

import Foundation
import FirebaseAuth

protocol AuthManagerService {
  func login(email: String, password: String, completion: @escaping (Result<Bool, Error>) -> ())
  func login()
  func logout()
  func isUserLoggedIn() -> Bool
}

class AuthManager: AuthManagerService, ObservableObject {
  @Published var isAuthenticated = false
  private let cacheManager: CacheManagerProtocol
  private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?

  init(cacheManager: CacheManagerProtocol) {
    self.cacheManager = cacheManager
    self.authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] (_, user) in
      if let _ = user {
        self?.isAuthenticated = true
      } else {
        self?.isAuthenticated = false
      }
    }
  }

  deinit {
    if let handle = authStateDidChangeListenerHandle {
      Auth.auth().removeStateDidChangeListener(handle)
    }
  }

  //MARK: - Login
  func login(email: String, password: String, completion: @escaping (Result<Bool, Error>) -> ()) {
    Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
      if let error = error {
        completion(.failure(error))
        self.isAuthenticated = false
        return
      }
      
      guard let authResult = authResult else {
        let error = NSError(domain: "com.sootuploader", code: 0, userInfo: nil)
        completion(.failure(error))
        return
      }

      authResult.user.getIDToken { [weak self] token, error in
        if let error = error {
          completion(.failure(error))
          return
        }

        if let token = token {
          self?.cacheManager.saveVerificationToken(verificationToken: token)
          self?.login()
        }
      }
    }
  }

  func login() {
    if let _ = cacheManager.fetchVerificationToken() {
      self.isAuthenticated = true
    } else {
      self.isAuthenticated = false
    }
  }

  func logout() {
    cacheManager.deleteVerificationToken()
    self.isAuthenticated = false
    do {
      try Auth.auth().signOut()
    } catch (let error){
      print("Error signing out: \(error.localizedDescription)")
    }
  }

  func isUserLoggedIn() -> Bool {
    return isAuthenticated
//    if Auth.auth().currentUser != nil {
//      if let _ = cacheManager.fetchVerificationToken() {
//        return true
//      } else {
//        return false
//      }
//    } else {
//      return false
//    }
  }
}

// Mock AuthManagerService for preview
class MockAuthManagerService: AuthManagerService, ObservableObject {
  var isAuthenticated = false

  func login(email: String, password: String, completion: @escaping (Result<Bool, Error>) -> ()) {
    isAuthenticated = true
    completion(.success(true))
  }

  func login() {
    isAuthenticated = true
  }

  func logout() {
    isAuthenticated = false
  }

  func isUserLoggedIn() -> Bool {
    return isAuthenticated
  }
}
