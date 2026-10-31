//
//  AutoFillIdentity.swift
//  passKit
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import AuthenticationServices
import SwiftyUserDefaults

/// A credential identity offered as a QuickType suggestion. Identities picked by hand in the AutoFill
/// extension are saved, so that they survive rebuilding the suggestions after a sync.
public struct AutoFillIdentity: Codable, Equatable, DefaultsSerializable {
    public enum Kind: String, Codable {
        case password
        case oneTimeCode
    }

    public let kind: Kind
    public let serviceIdentifier: String
    public let isURL: Bool
    /// The user name for a password, the label for a one-time code.
    public let user: String
    /// The path of the password file.
    public let recordIdentifier: String

    public init(kind: Kind, serviceIdentifier: ASCredentialServiceIdentifier, user: String, recordIdentifier: String) {
        self.kind = kind
        self.serviceIdentifier = serviceIdentifier.identifier
        self.isURL = serviceIdentifier.type == .URL
        self.user = user
        self.recordIdentifier = recordIdentifier
    }

    /// Derive a password identity from a password path containing a domain, e.g., `github.com/user.gpg`.
    public init?(passwordPath: String) {
        let components = (passwordPath as NSString).deletingPathExtension.split(separator: "/").map(String.init)
        // Prefer the innermost domain, e.g., "work.example.com" in "example.com/work.example.com/me".
        guard let index = components.lastIndex(where: { Self.domain(in: $0) != nil }), let host = Self.domain(in: components[index]) else {
            return nil
        }
        let user = components[(index + 1)...].joined(separator: "/")
        self.init(
            kind: .password,
            serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
            user: user.isEmpty ? host : user,
            recordIdentifier: passwordPath
        )
    }

    public var credentialServiceIdentifier: ASCredentialServiceIdentifier {
        ASCredentialServiceIdentifier(identifier: serviceIdentifier, type: isURL ? .URL : .domain)
    }

    public var passwordCredentialIdentity: ASPasswordCredentialIdentity? {
        guard kind == .password else {
            return nil
        }
        return ASPasswordCredentialIdentity(serviceIdentifier: credentialServiceIdentifier, user: user, recordIdentifier: recordIdentifier)
    }

    @available(iOS 18.0, *)
    public var credentialIdentity: any ASCredentialIdentity {
        switch kind {
        case .password:
            return ASPasswordCredentialIdentity(serviceIdentifier: credentialServiceIdentifier, user: user, recordIdentifier: recordIdentifier)
        case .oneTimeCode:
            return ASOneTimeCodeCredentialIdentity(serviceIdentifier: credentialServiceIdentifier, label: user, recordIdentifier: recordIdentifier)
        }
    }

    /// All identities to offer for the given password paths: one per path containing a domain plus the saved
    /// ones. Saved identities of passwords that do not exist anymore are dropped.
    public static func identities(forPasswordPaths paths: [String], saved: [Self]) -> (all: [Self], saved: [Self]) {
        let existingPaths = Set(paths)
        let saved = saved.filter { existingPaths.contains($0.recordIdentifier) }
        let derived = paths.compactMap(Self.init(passwordPath:))
        return (derived + saved.filter { !derived.contains($0) }, saved)
    }

    static func domain(in component: String) -> String? {
        let host = component.lowercased()
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else {
            return nil
        }
        guard labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
            return nil
        }
        return host
    }
}

public extension ASCredentialServiceIdentifier {
    /// The host of the website or app asking for credentials. Depending on the caller, iOS passes either a bare
    /// domain like `github.com` or a URL, which may lack a scheme.
    var host: String? {
        switch type {
        case .domain:
            return identifier
        case .URL:
            return URL(string: identifier)?.host ?? URL(string: "https://\(identifier)")?.host
        @unknown default:
            return nil
        }
    }
}

public extension PasswordStore {
    /// Replace the QuickType suggestions with the identities derived from the password paths and the saved ones.
    func updateCredentialIdentities() {
        let paths = fetchPasswordEntityCoreData(withDir: false).map(\.path)
        let (identities, saved) = AutoFillIdentity.identities(forPasswordPaths: paths, saved: Defaults.savedAutoFillIdentities)
        Defaults.savedAutoFillIdentities = saved
        Self.storeCredentialIdentities(identities, replacingAll: true)
    }

    /// Remember an identity picked by hand and add it to the QuickType suggestions.
    func saveCredentialIdentity(_ identity: AutoFillIdentity) {
        Defaults.savedAutoFillIdentities.removeAll {
            $0.kind == identity.kind && $0.serviceIdentifier == identity.serviceIdentifier && $0.recordIdentifier == identity.recordIdentifier
        }
        Defaults.savedAutoFillIdentities.append(identity)
        Self.storeCredentialIdentities([identity], replacingAll: false)
    }

    private static func storeCredentialIdentities(_ identities: [AutoFillIdentity], replacingAll: Bool) {
        let store = ASCredentialIdentityStore.shared
        store.getState { state in
            guard state.isEnabled else {
                return
            }
            // One-time codes can only be suggested from iOS 18 on.
            if #available(iOS 18.0, *) {
                let credentialIdentities = identities.map(\.credentialIdentity)
                if replacingAll {
                    store.replaceCredentialIdentities(credentialIdentities)
                } else {
                    store.saveCredentialIdentities(credentialIdentities)
                }
            } else {
                let credentialIdentities = identities.compactMap(\.passwordCredentialIdentity)
                if replacingAll {
                    store.replaceCredentialIdentities(with: credentialIdentities)
                } else {
                    store.saveCredentialIdentities(credentialIdentities)
                }
            }
        }
    }
}
