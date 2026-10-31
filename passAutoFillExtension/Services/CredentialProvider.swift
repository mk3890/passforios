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
    enum CredentialType {
        case password
        case oneTimeCode
    }

    private let viewController: UIViewController
    private let extensionContext: ASCredentialProviderExtensionContext
    private let afterDecryption: (Password) -> Void

    var identifier: ASCredentialServiceIdentifier?
    var credentialType = CredentialType.password

    init(viewController: UIViewController, extensionContext: ASCredentialProviderExtensionContext, afterDecryption: @escaping (Password) -> Void) {
        self.viewController = viewController
        self.extensionContext = extensionContext
        self.afterDecryption = afterDecryption
    }

    func credentials(for recordIdentifier: String?) {
        guard let recordIdentifier else {
            cancel(with: .credentialIdentityNotFound)
            return
        }

        decryptPassword(in: viewController, with: recordIdentifier) { password in
            guard self.complete(with: password) else {
                self.alertMissingOneTimeCode()
                return
            }
            self.saveOneTimeCodeIdentity(for: password, at: recordIdentifier)
        }
    }

    /// Decrypt without showing any UI. Whenever that is not possible, e.g., because the PGP key
    /// passphrase is not saved, let iOS fall back to `prepareInterfaceToProvideCredential`.
    func credentialsWithoutUserInteraction(for recordIdentifier: String?) {
        guard let recordIdentifier, PasswordStore.shared.fetchPasswordEntity(with: recordIdentifier) != nil else {
            cancel(with: .credentialIdentityNotFound)
            return
        }
        guard !Defaults.isYubiKeyEnabled else {
            cancel(with: .userInteractionRequired)
            return
        }
        DispatchQueue.global(qos: .userInteractive).async {
            let password = try? PasswordStore.shared.decrypt(path: recordIdentifier) { keyID in
                AppKeychain.shared.getWithoutUserInteraction(for: AppKeychain.getPGPKeyPassphraseKey(keyID: keyID)) ?? ""
            }
            DispatchQueue.main.async {
                guard let password else {
                    self.cancel(with: .userInteractionRequired)
                    return
                }
                guard self.complete(with: password) else {
                    self.cancel(with: .credentialIdentityNotFound)
                    return
                }
                self.saveOneTimeCodeIdentity(for: password, at: recordIdentifier)
            }
        }
    }

    func persistAndProvideCredentials(with passwordPath: String) {
        decryptPassword(in: viewController, with: passwordPath) { password in
            guard self.complete(with: password) else {
                self.alertMissingOneTimeCode()
                return
            }
            if let identifier = self.identifier, self.credentialType == .password {
                PasswordStore.shared.saveCredentialIdentity(AutoFillIdentity(
                    kind: .password,
                    serviceIdentifier: identifier,
                    user: password.getUsernameForCompletion(),
                    recordIdentifier: passwordPath
                ))
            }
            self.saveOneTimeCodeIdentity(for: password, at: passwordPath)
        }
    }

    /// Complete the request with the password or its one-time code, depending on what was asked for.
    /// Returns false if a one-time code was asked for, but the password has none.
    private func complete(with password: Password) -> Bool {
        switch credentialType {
        case .password:
            extensionContext.completeRequest(withSelectedCredential: .from(password))
            afterDecryption(password)
            return true
        case .oneTimeCode:
            // Counter based codes are not supported, since filling one would have to update the password file.
            guard #available(iOS 18.0, *), password.otpType == .totp, let code = password.currentOtp else {
                return false
            }
            extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code))
            return true
        }
    }

    /// Suggest the one-time code of a password with TOTP whenever it is used for a website or app.
    private func saveOneTimeCodeIdentity(for password: Password, at passwordPath: String) {
        guard let identifier, password.otpType == .totp else {
            return
        }
        PasswordStore.shared.saveCredentialIdentity(AutoFillIdentity(
            kind: .oneTimeCode,
            serviceIdentifier: identifier,
            user: password.name,
            recordIdentifier: passwordPath
        ))
    }

    private func alertMissingOneTimeCode() {
        Utils.alert(title: "CannotFillOneTimeCode".localize(), message: "NoOneTimeCode.".localize(), controller: viewController)
    }

    private func cancel(with code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}

extension ASPasswordCredential {
    static func from(_ password: Password) -> ASPasswordCredential {
        ASPasswordCredential(user: password.getUsernameForCompletion(), password: password.password)
    }
}
