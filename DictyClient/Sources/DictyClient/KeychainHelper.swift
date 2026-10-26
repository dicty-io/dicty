import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

import Security
import LocalAuthentication

// MARK: - Secrets Manager
struct SecretsManager {
    static func saveSecret(_ value: String, forKey key: String) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: "_sec_\(key)")
            UserDefaults.standard.removeObject(forKey: key)
            KeychainHelper.standard.deleteSilently(service: "DictyClient", account: key)
            return
        }
        
        // Primary, reliable storage in user preferences (eliminates macOS Keychain ACL password prompts across releases)
        UserDefaults.standard.set(value, forKey: "_sec_\(key)")
        
        // Clean up legacy keychain item silently so macOS never prompts for it
        KeychainHelper.standard.deleteSilently(service: "DictyClient", account: key)
    }
    
    static func readSecret(forKey key: String) -> String? {
        // 1. Check primary UserDefaults _sec_ store
        if let val = UserDefaults.standard.string(forKey: "_sec_\(key)"), !val.isEmpty {
            return val
        }
        
        // 2. Check un-prefixed store
        if let val = UserDefaults.standard.string(forKey: key), !val.isEmpty {
            return val
        }
        
        // 3. Fallback: silent non-interactive keychain read (never prompts for login password).
        // Only once per key per launch: unset keys otherwise cost two blocking Keychain queries
        // on every view appearance (e.g. ~17 reads each time the API Keys page opens).
        if keychainMisses.contains(key) { return nil }
        if let data = KeychainHelper.standard.readSilently(service: "DictyClient", account: key),
           let value = String(data: data, encoding: .utf8), !value.isEmpty {
            // Migrate to UserDefaults so keychain is never touched again
            UserDefaults.standard.set(value, forKey: "_sec_\(key)")
            KeychainHelper.standard.deleteSilently(service: "DictyClient", account: key)
            return value
        }
        keychainMisses.insert(key)
        return nil
    }
    
    nonisolated(unsafe) private static var keychainMisses = Set<String>()
}

struct KeychainHelper {
    static let standard = KeychainHelper()
    
    private func createSilentContext() -> LAContext {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        return ctx
    }
    
    /// Silent non-interactive read: immediately returns nil without prompting the user if UI would be required
    func readSilently(service: String, account: String) -> Data? {
        let authContext = createSilentContext()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationContext: authContext
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return data
        }
        
        // Fallback with strictly disabled UI prompt
        let legacyQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: authContext
        ]
        var legacyRef: AnyObject?
        if SecItemCopyMatching(legacyQuery as CFDictionary, &legacyRef) == errSecSuccess,
           let legacyData = legacyRef as? Data {
            return legacyData
        }
        
        return nil
    }
    
    /// Silently delete keychain entry without any user prompts
    func deleteSilently(service: String, account: String) {
        let authContext = createSilentContext()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationContext: authContext
        ]
        SecItemDelete(query as CFDictionary)
        
        let legacyQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseAuthenticationContext: authContext
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }
}
