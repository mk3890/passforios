//
//  AppKeychain.swift
//  passKit
//
//  Created by Danny Moesch on 25.06.19.
//  Copyright © 2019 Bob Sun. All rights reserved.
//

import KeychainAccess
import LocalAuthentication

public class AppKeychain: KeyStore {
    public static let shared = AppKeychain()

    private let keychain = Keychain(service: Globals.bundleIdentifier, accessGroup: Globals.groupIdentifier)
        .accessibility(.whenUnlockedThisDeviceOnly)
        .synchronizable(false)

    /// Authentication shared by all reads of protected items until `resetAuthentication` is called, so that users
    /// authenticate once per session instead of once per read.
    private var authenticationContext = LAContext()
    private let authenticationContextLock = NSLock()

    public var sessionAuthenticationContext: LAContext {
        authenticationContextLock.lock()
        defer { authenticationContextLock.unlock() }
        return authenticationContext
    }

    public func add(string: String?, for key: String) {
        keychain[key] = string
    }

    /// Store a secret, which can only be read after authenticating with Face ID, Touch ID or the device passcode.
    /// Without a device passcode, there is nothing to authenticate with, so the secret is stored like any other.
    public func addProtected(string: String?, for key: String) {
        try? keychain.remove(key)
        guard let string else {
            return
        }
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            add(string: string, for: key)
            return
        }
        try? keychain
            .accessibility(.whenPasscodeSetThisDeviceOnly, authenticationPolicy: .userPresence)
            .set(string, key: key)
    }

    public func contains(key: String) -> Bool {
        (try? keychain.contains(key)) ?? false
    }

    /// Read an item. Reading a protected item asks the user to authenticate, unless they already did in this session,
    /// so it must not happen on the main thread.
    public func get(for key: String) -> String? {
        try? keychain
            .authenticationContext(sessionAuthenticationContext)
            .authenticationPrompt("UnlockSavedPassphrase.".localize())
            .getString(key)
    }

    /// Read an item without ever asking the user to authenticate, i.e., protected items are not returned.
    public func getWithoutUserInteraction(for key: String) -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true
        return try? keychain.authenticationContext(context).getString(key)
    }

    /// Ask the user to authenticate again the next time a protected item is read.
    public func resetAuthentication() {
        authenticationContextLock.lock()
        defer { authenticationContextLock.unlock() }
        authenticationContext.invalidate()
        authenticationContext = LAContext()
    }

    /// Protect the secrets stored before protection was introduced, see `addProtected`.
    public func protectContent(withPrefix prefix: String) {
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return
        }
        keychain.allKeys()
            .filter { $0.hasPrefix(prefix) }
            // Protected items cannot be read without user interaction, so they are left alone.
            .forEach { key in
                if let string = getWithoutUserInteraction(for: key) {
                    addProtected(string: string, for: key)
                }
            }
    }

    public func removeContent(for key: String) {
        try? keychain.remove(key)
    }

    public func removeAllContent() {
        try? keychain.removeAll()
    }

    public func removeAllContent(withPrefix prefix: String) {
        keychain.allKeys()
            .filter { $0.hasPrefix(prefix) }
            .forEach { try? keychain.remove($0) }
    }

    public static func getPGPKeyPassphraseKey(keyID: String) -> String {
        Globals.pgpKeyPassphrase + "-" + keyID
    }
}
