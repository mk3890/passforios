//
//  CredentialProvider.swift
//  passAutoFillExtension
//
//  Created by Sun, Mingshen on 1/2/21.
//  Copyright © 2021 Bob Sun. All rights reserved.
//

import AuthenticationServices
import passKit

class CredentialProvider {
    private let viewController: UIViewController
    private let extensionContext: ASCredentialProviderExtensionContext
    private let afterDecryption: (Password) -> Void

    var identifier: ASCredentialServiceIdentifier?

    init(viewController: UIViewController, extensionContext: ASCredentialProviderExtensionContext, afterDecryption: @escaping (Password) -> Void) {
        self.viewController = viewController
        self.extensionContext = extensionContext
        self.afterDecryption = afterDecryption
    }

    func credentials(for identity: ASPasswordCredentialIdentity) {
        guard let recordIdentifier = identity.recordIdentifier else {
            cancel(with: .credentialIdentityNotFound)
            return
        }

        decryptPassword(in: viewController, with: recordIdentifier) { password in
            self.extensionContext.completeRequest(withSelectedCredential: .from(password))
            self.afterDecryption(password)
        }
    }

    /// Decrypt without showing any UI. Whenever that is not possible, e.g., because the PGP key
    /// passphrase is not saved, let iOS fall back to `prepareInterfaceToProvideCredential`.
    func credentialsWithoutUserInteraction(for identity: ASPasswordCredentialIdentity) {
        guard let recordIdentifier = identity.recordIdentifier,
              PasswordStore.shared.fetchPasswordEntity(with: recordIdentifier) != nil else {
            cancel(with: .credentialIdentityNotFound)
            return
        }
        guard !Defaults.isYubiKeyEnabled else {
            cancel(with: .userInteractionRequired)
            return
        }
        DispatchQueue.global(qos: .userInteractive).async {
            let password = try? PasswordStore.shared.decrypt(path: recordIdentifier) { keyID in
                AppKeychain.shared.get(for: AppKeychain.getPGPKeyPassphraseKey(keyID: keyID)) ?? ""
            }
            DispatchQueue.main.async {
                guard let password else {
                    self.cancel(with: .userInteractionRequired)
                    return
                }
                self.extensionContext.completeRequest(withSelectedCredential: .from(password))
                self.afterDecryption(password)
            }
        }
    }

    func persistAndProvideCredentials(with passwordPath: String) {
        decryptPassword(in: viewController, with: passwordPath) { password in
            if let identifier = self.identifier {
                PasswordStore.shared.saveCredentialIdentity(ASPasswordCredentialIdentity(
                    serviceIdentifier: identifier,
                    user: password.getUsernameForCompletion(),
                    recordIdentifier: passwordPath
                ))
            }
            self.extensionContext.completeRequest(withSelectedCredential: .from(password))
            self.afterDecryption(password)
        }
    }

    private func cancel(with code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}

extension ASCredentialServiceIdentifier {
    /// The host of the website or app asking for credentials. Depending on the caller, iOS passes
    /// either a bare domain like `github.com` or a URL, which may lack a scheme.
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

extension ASPasswordCredential {
    static func from(_ password: Password) -> ASPasswordCredential {
        ASPasswordCredential(user: password.getUsernameForCompletion(), password: password.password)
    }
}
