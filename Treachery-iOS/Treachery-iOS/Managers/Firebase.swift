//
//  Firebase.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

struct FirebaseManager {
  static let shared = FirebaseManager()

  private init() {
    FirebaseApp.configure()
  }

  func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
    Auth.auth().signIn(withEmail: email, password: password) { (result, error) in
      if let error = error {
        completion(.failure(error))
      } else if let result = result {
        completion(.success(result.user))
      }
    }
  }

  func signUp(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
    Auth.auth().createUser(withEmail: email, password: password) { (result, error) in
      if let error = error {
        completion(.failure(error))
      } else if let result = result {
        completion(.success(result.user))
      }
    }
  }

  func signOut() {
    do {
      try Auth.auth().signOut()
    } catch {
      print(error)
    }
  }

//  func observeAuthChanges(completion: @escaping (AuthStateDidChangeListenerHandle, User?) -> Void) {
//    let handle = Auth.auth().addStateDidChangeListener { (auth, user) in
//      completion(handle, user)
//    }
//  }

  func removeAuthChangesObserver(handle: AuthStateDidChangeListenerHandle) {
    Auth.auth().removeStateDidChangeListener(handle)
  }

  func resetPassword(email: String, completion: @escaping (Error?) -> Void) {
    Auth.auth().sendPasswordReset(withEmail: email) { error in
      completion(error)
    }
  }

  func changePassword(newPassword: String, completion: @escaping (Error?) -> Void) {
    Auth.auth().currentUser?.updatePassword(to: newPassword) { error in
      completion(error)
    }
  }

//  func changeEmail(newEmail: String, completion: @escaping (Error?) -> Void) {
//    Auth.auth().currentUser?.updateEmail(to: newEmail) { error in
//      completion(error)
//    }
//  }

//  func deleteAccount(completion: @escaping (Error?) -> Void) {
//    Auth.auth().currentUser?.delete { error in
//      completion(error)
//    }
//  }

//  func reauthenticateUser(email: String, password: String, completion: @escaping (Error?) -> Void) {
//    let credential = EmailAuthProvider
//  }


}
