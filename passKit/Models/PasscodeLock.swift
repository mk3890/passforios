//
//  PasscodeLock.swift
//  passKit
//
//  Created by Yishi Lin on 28/1/2018.
//  Copyright © 2017 Yishi Lin. All rights reserved.
//

import CryptoKit
import Foundation

public class PasscodeLock {
    public static let shared = PasscodeLock()

    /// Number of failed attempts in a row before further attempts are delayed.
    static let freeAttempts = 5
    /// Delays after the first, second, ... failed attempt beyond the free ones.
    static let lockoutDurations: [TimeInterval] = [30, 60, 5 * 60, 15 * 60, 60 * 60]

    private static let hashPrefix = "sha256:"

    private let identifier = Globals.bundleIdentifier + "passcode"
    private let failedAttemptsIdentifier = Globals.bundleIdentifier + "passcode.failedAttempts"
    private let lockedUntilIdentifier = Globals.bundleIdentifier + "passcode.lockedUntil"

    private let keyStore: KeyStore
    private let now: () -> Date

    private var passcode: String? {
        keyStore.get(for: identifier)
    }

    private var failedAttempts: Int {
        keyStore.get(for: failedAttemptsIdentifier).flatMap(Int.init) ?? 0
    }

    /// Constructor used to migrate passcode from SharedDefaults to Keychain
    init(keyStore: KeyStore = AppKeychain.shared, now: @escaping () -> Date = Date.init) {
        self.keyStore = keyStore
        self.now = now
        if let passcode = Defaults.passcodeKey {
            save(passcode: passcode)
            Defaults.passcodeKey = nil
        }
    }

    public var hasPasscode: Bool {
        passcode != nil
    }

    /// Seconds until the next attempt is allowed, zero if it is allowed right away.
    public var lockoutRemaining: TimeInterval {
        guard let lockedUntil = keyStore.get(for: lockedUntilIdentifier).flatMap(TimeInterval.init) else {
            return 0
        }
        // Setting the clock back must not lock users out for longer than the longest delay.
        return min(max(0, lockedUntil - now().timeIntervalSince1970), Self.lockoutDurations.last!)
    }

    public func save(passcode: String) {
        let salt = Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) })
        keyStore.add(string: Self.hash(passcode, salt: salt), for: identifier)
        resetFailedAttempts()
    }

    /// Check the passcode, unless attempts are delayed after too many failed ones.
    public func check(passcode: String) -> Bool {
        guard lockoutRemaining == 0, let storedPasscode = self.passcode else {
            return false
        }
        guard Self.verify(passcode, against: storedPasscode) else {
            recordFailedAttempt()
            return false
        }
        if storedPasscode.hasPrefix(Self.hashPrefix) {
            resetFailedAttempts()
        } else {
            // Older versions stored the passcode in plain text.
            save(passcode: passcode)
        }
        return true
    }

    /// Reset the failed attempts after users proved their identity otherwise, e.g., with Face ID.
    public func didAuthenticate() {
        resetFailedAttempts()
    }

    public func delete() {
        keyStore.removeContent(for: identifier)
        resetFailedAttempts()
    }

    private func recordFailedAttempt() {
        let failedAttempts = failedAttempts + 1
        keyStore.add(string: String(failedAttempts), for: failedAttemptsIdentifier)
        guard failedAttempts >= Self.freeAttempts else {
            return
        }
        let index = min(failedAttempts - Self.freeAttempts, Self.lockoutDurations.count - 1)
        let lockedUntil = now().timeIntervalSince1970 + Self.lockoutDurations[index]
        keyStore.add(string: String(lockedUntil), for: lockedUntilIdentifier)
    }

    private func resetFailedAttempts() {
        keyStore.removeContent(for: failedAttemptsIdentifier)
        keyStore.removeContent(for: lockedUntilIdentifier)
    }

    static func hash(_ passcode: String, salt: Data) -> String {
        let digest = SHA256.hash(data: salt + Data(passcode.utf8))
        return hashPrefix + salt.base64EncodedString() + ":" + Data(digest).base64EncodedString()
    }

    static func verify(_ passcode: String, against storedPasscode: String) -> Bool {
        guard storedPasscode.hasPrefix(hashPrefix) else {
            return passcode == storedPasscode
        }
        let parts = storedPasscode.dropFirst(hashPrefix.count).split(separator: ":")
        guard parts.count == 2, let salt = Data(base64Encoded: String(parts[0])) else {
            return false
        }
        return hash(passcode, salt: salt) == storedPasscode
    }
}
