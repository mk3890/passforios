//
//  GitCredential.swift
//  passKit
//
//  Created by Mingshen Sun on 30/4/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import SVProgressHUD

/// The credential handed to libgit2 when the remote asks for one.
public enum GitCredentialValue: Equatable {
    /// Only the user name, which SSH asks for first if the URL lacks one.
    case username(String)
    case password(userName: String, password: String)
    case sshKey(userName: String, privateKey: String, passphrase: String)
}

/// Decides whether to trust an SSH host key that is unknown or differs from the saved one, e.g., by asking the user.
/// Gets the host, the SHA-256 fingerprint of the presented key and the fingerprint saved before, if any.
public typealias GitHostKeyApprover = (_ host: String, _ fingerprint: String, _ savedFingerprint: String?) -> Bool

/// How to authenticate to the remote and which SSH host keys to trust when connecting to it.
public struct GitRemoteOptions {
    let credential: (_ usernameOnly: Bool) -> GitCredentialValue?
    let hostKeys: GitHostKeys
    let approveHostKey: GitHostKeyApprover

    public init(
        credential: @escaping (_ usernameOnly: Bool) -> GitCredentialValue? = { _ in nil },
        hostKeys: GitHostKeys = GitHostKeys(),
        approveHostKey: @escaping GitHostKeyApprover = { _, _, _ in false }
    ) {
        self.credential = credential
        self.hostKeys = hostKeys
        self.approveHostKey = approveHostKey
    }
}

public struct GitCredential {
    public typealias PasswordProvider = (String, String?) -> String?

    private let credentialType: CredentialType
    private let keyStore: KeyStore

    private enum CredentialType {
        case http(userName: String)
        case ssh(userName: String, privateKey: String)

        var requestPassphraseMessage: String {
            switch self {
            case .http:
                return "FillInGitAccountPassword.".localize()
            case .ssh:
                return "FillInSshKeyPassphrase.".localize()
            }
        }

        var keyStoreKey: String {
            switch self {
            case .http:
                return Globals.gitPassword
            case .ssh:
                return Globals.gitSSHPrivateKeyPassphrase
            }
        }

        var allowedAttempts: Int {
            switch self {
            case .http:
                return 4
            case .ssh:
                return 1
            }
        }

        var userName: String {
            switch self {
            case let .http(userName), let .ssh(userName, _):
                return userName
            }
        }

        func credential(password: String) -> GitCredentialValue {
            switch self {
            case let .http(userName):
                return .password(userName: userName, password: password)
            case let .ssh(userName, privateKey):
                return .sshKey(userName: userName, privateKey: privateKey, passphrase: password)
            }
        }
    }

    public static func from(authenticationMethod: GitAuthenticationMethod, userName: String, keyStore: KeyStore) -> Self {
        switch authenticationMethod {
        case .password:
            return Self(credentialType: .http(userName: userName), keyStore: keyStore)
        case .key:
            let privateKey: String = keyStore.get(for: SSHKey.PRIVATE.getKeychainKey()) ?? ""
            return Self(credentialType: .ssh(userName: userName, privateKey: privateKey), keyStore: keyStore)
        }
    }

    /// Options for one remote operation. Unknown SSH host keys are rejected unless the approver accepts them.
    public func getCredentialOptions(
        passwordProvider: @escaping PasswordProvider = { _, _ in nil },
        hostKeyApprover: @escaping GitHostKeyApprover = { _, _, _ in false }
    ) -> GitRemoteOptions {
        var attempts = 1
        let credential = { (usernameOnly: Bool) -> GitCredentialValue? in
            if usernameOnly {
                return .username(credentialType.userName)
            }
            if attempts > credentialType.allowedAttempts {
                return nil
            }
            guard let password = getPassword(attempts: attempts, passwordProvider: passwordProvider) else {
                return nil
            }
            attempts += 1
            return credentialType.credential(password: password)
        }
        return GitRemoteOptions(credential: credential, hostKeys: GitHostKeys(keyStore: keyStore), approveHostKey: hostKeyApprover)
    }

    public func delete() {
        keyStore.removeContent(for: credentialType.keyStoreKey)
    }

    private func getPassword(attempts: Int, passwordProvider: @escaping PasswordProvider) -> String? {
        let lastPassword: String? = keyStore.get(for: credentialType.keyStoreKey)
        if lastPassword == nil || attempts != 1 {
            guard let requestedPassword = passwordProvider(credentialType.requestPassphraseMessage, lastPassword) else {
                return nil
            }
            if Defaults.isRememberGitCredentialPassphraseOn {
                keyStore.add(string: requestedPassword, for: credentialType.keyStoreKey)
            }
            return requestedPassword
        }
        return lastPassword
    }
}
