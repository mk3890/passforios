//
//  CredentialProviderViewController.swift
//  passAutoFillExtension
//
//  Created by Yishi Lin on 2018/9/24.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import AuthenticationServices
import passKit

class CredentialProviderViewController: ASCredentialProviderViewController {
    private lazy var passcodelock: PasscodeExtensionDisplay = { [unowned self] in
        PasscodeExtensionDisplay(extensionContext: extensionContext)
    }()

    private lazy var passwordsViewController: PasswordsViewController = (children.first as! UINavigationController).viewControllers.first as! PasswordsViewController

    private lazy var credentialProvider: CredentialProvider = { [unowned self] in
        CredentialProvider(viewController: self, extensionContext: extensionContext, afterDecryption: NotificationCenterDispatcher.showOTPNotification)
    }()

    private lazy var passwordsTableEntries = PasswordStore.shared.fetchPasswordEntityCoreData(withDir: false)
        .map(PasswordTableEntry.init)

    override func viewDidLoad() {
        super.viewDidLoad()
        passwordsViewController.dataSource = PasswordsTableDataSource(entries: passwordsTableEntries)
        passwordsViewController.selectionDelegate = self
        passwordsViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        prepareCredentialList(for: serviceIdentifiers, type: .password)
    }

    @available(iOS 18.0, *)
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        prepareCredentialList(for: serviceIdentifiers, type: .oneTimeCode)
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        provideCredentialWithoutUserInteraction(for: credentialIdentity.recordIdentifier, type: .password)
    }

    @available(iOS 17.0, *)
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        guard let type = Self.credentialType(of: credentialRequest) else {
            cancelRequest(with: .credentialIdentityNotFound)
            return
        }
        provideCredentialWithoutUserInteraction(for: credentialRequest.credentialIdentity.recordIdentifier, type: type)
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        prepareInterfaceToProvideCredential(for: credentialIdentity.serviceIdentifier, recordIdentifier: credentialIdentity.recordIdentifier, type: .password)
    }

    @available(iOS 17.0, *)
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        guard let type = Self.credentialType(of: credentialRequest) else {
            cancelRequest(with: .credentialIdentityNotFound)
            return
        }
        let identity = credentialRequest.credentialIdentity
        prepareInterfaceToProvideCredential(for: identity.serviceIdentifier, recordIdentifier: identity.recordIdentifier, type: type)
    }

    @available(iOS 26.2, *)
    override func performWithoutUserInteractionIfPossible(savePasswordRequest _: ASSavePasswordRequest) {
        // Every saved password becomes a commit in the store, so users always confirm it and choose its name.
        cancelRequest(with: .userInteractionRequired)
    }

    @available(iOS 26.2, *)
    override func prepareInterface(for savePasswordRequest: ASSavePasswordRequest) {
        passcodelock.presentPasscodeLockIfNeeded(self) {
            self.view.isHidden = true
        } after: { [unowned self] in
            view.isHidden = false
            showSavePassword(for: savePasswordRequest)
        }
    }

    @available(iOS 26.2, *)
    private func showSavePassword(for request: ASSavePasswordRequest) {
        let serviceIdentifier = request.serviceIdentifier
        let password = request.credential.password
        let entry = NewPasswordEntry(host: serviceIdentifier.host, username: request.credential.user, password: password)
        let savePasswordViewController = SavePasswordViewController(entry: entry) { [unowned self] name, username in
            let entry = NewPasswordEntry(host: serviceIdentifier.host, username: username, password: password)
            credentialProvider.save(entry, as: name, for: serviceIdentifier) { [unowned self] in
                extensionContext.completeSavePasswordRequest(completionHandler: nil)
            }
        } cancel: { [unowned self] in
            cancelRequest(with: .userCanceled)
        }
        (children.first as? UINavigationController)?.setViewControllers([savePasswordViewController], animated: false)
    }

    private func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier], type: CredentialProvider.CredentialType) {
        passcodelock.presentPasscodeLockIfNeeded(self) {
            self.view.isHidden = true
        } after: { [unowned self] in
            view.isHidden = false
            credentialProvider.credentialType = type
            showPasswordsWithSuggestion(for: serviceIdentifiers)
        }
    }

    private func provideCredentialWithoutUserInteraction(for recordIdentifier: String?, type: CredentialProvider.CredentialType) {
        guard !PasscodeLock.shared.hasPasscode, Defaults.isRememberPGPPassphraseOn else {
            cancelRequest(with: .userInteractionRequired)
            return
        }
        credentialProvider.credentialType = type
        credentialProvider.credentialsWithoutUserInteraction(for: recordIdentifier)
    }

    private func prepareInterfaceToProvideCredential(for serviceIdentifier: ASCredentialServiceIdentifier, recordIdentifier: String?, type: CredentialProvider.CredentialType) {
        passcodelock.presentPasscodeLockIfNeeded(self) {
            self.view.isHidden = true
        } after: { [unowned self] in
            // Keep the list visible, so that it is possible to pick another password or cancel
            // if decryption fails.
            view.isHidden = false
            credentialProvider.credentialType = type
            // The password may have been renamed or deleted since the suggestion was saved.
            if let recordIdentifier, PasswordStore.shared.fetchPasswordEntity(with: recordIdentifier) != nil {
                credentialProvider.identifier = serviceIdentifier
                credentialProvider.credentials(for: recordIdentifier)
            } else {
                showPasswordsWithSuggestion(for: [serviceIdentifier])
            }
        }
    }

    private func showPasswordsWithSuggestion(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let identifier = serviceIdentifiers.first { $0.host != nil } ?? serviceIdentifiers.first
        credentialProvider.identifier = identifier
        passwordsViewController.navigationItem.prompt = identifier?.host
        passwordsViewController.showPasswordsWithSuggestion(matching: identifier?.host ?? "")
    }

    @available(iOS 17.0, *)
    private static func credentialType(of credentialRequest: any ASCredentialRequest) -> CredentialProvider.CredentialType? {
        if credentialRequest.credentialIdentity is ASPasswordCredentialIdentity {
            return .password
        }
        if #available(iOS 18.0, *), credentialRequest.credentialIdentity is ASOneTimeCodeCredentialIdentity {
            return .oneTimeCode
        }
        return nil
    }

    private func cancelRequest(with code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }

    @objc
    private func cancel(_: AnyObject?) {
        extensionContext.cancelRequest(withError: NSError(domain: "PassExtension", code: 0))
    }
}

extension CredentialProviderViewController: PasswordSelectionDelegate {
    func selected(password: PasswordTableEntry) {
        credentialProvider.persistAndProvideCredentials(with: password.passwordEntity.path)
    }
}
