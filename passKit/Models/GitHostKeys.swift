//
//  GitHostKeys.swift
//  passKit
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import Foundation

/// The SSH host keys users trusted, identified by their SHA-256 fingerprints. A server presenting another key than
/// the trusted one may be an attacker intercepting the connection, so the user has to approve it first.
public struct GitHostKeys {
    private let keyStore: KeyStore

    public init(keyStore: KeyStore = AppKeychain.shared) {
        self.keyStore = keyStore
    }

    public func fingerprint(for host: String) -> String? {
        keyStore.get(for: Self.keyStoreKey(for: host))
    }

    /// Accept the trusted key of the host. Ask the approver about an unknown or changed key and trust it if approved.
    func verify(host: String, fingerprint: String, approve: GitHostKeyApprover) throws {
        let savedFingerprint = self.fingerprint(for: host)
        if savedFingerprint == fingerprint {
            return
        }
        guard approve(host, fingerprint, savedFingerprint) else {
            throw savedFingerprint == nil ? AppError.gitHostKeyNotTrusted(host: host) : AppError.gitHostKeyChanged(host: host)
        }
        keyStore.add(string: fingerprint, for: Self.keyStoreKey(for: host))
    }

    /// Format a SHA-256 hash of a host key like OpenSSH does, e.g., `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`.
    static func fingerprint(sha256 digest: Data) -> String {
        "SHA256:" + digest.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private static func keyStoreKey(for host: String) -> String {
        Globals.gitSSHHostKey + "-" + host.lowercased()
    }
}
