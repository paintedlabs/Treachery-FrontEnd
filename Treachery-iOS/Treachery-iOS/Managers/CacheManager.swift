//
//  CacheManager.swift
//  SootUploader
//
//  Created by Luke Solomon on 8/1/24.
//

import Foundation
import KeychainSwift

protocol CacheManagerProtocol {
  func fetchVerificationToken() -> String?
  func saveVerificationToken(verificationToken: String)
  func deleteVerificationToken()
}

class CacheManager: CacheManagerProtocol {
  private let keychain: KeychainSwift
  private static var verificationTokenKey = "VerificationTokenKey"

  // Initialize with dependency injection
  init(keychain: KeychainSwift = KeychainSwift()) {
    self.keychain = keychain
  }

  func fetchVerificationToken() -> String? {
    return keychain.get(Self.verificationTokenKey)
  }

  func saveVerificationToken(verificationToken: String) {
    keychain.set(verificationToken, forKey: Self.verificationTokenKey)
  }

  func deleteVerificationToken() {
      keychain.delete(Self.verificationTokenKey)
  }
}

class MockCacheManager: CacheManagerProtocol {
  var token:String? = "FakeBearerToken"

  func fetchVerificationToken() -> String? {
    return token
  }

  func saveVerificationToken(verificationToken: String)  {
    self.token = verificationToken
  }

  func deleteVerificationToken() {
    self.token = nil
  }
}
