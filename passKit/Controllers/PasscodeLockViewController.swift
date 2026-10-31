//
//  PasscodeLockViewController.swift
//  passKit
//
//  Created by Yishi Lin on 10/04/2018.
//  Copyright © 2018 Yishi Lin. All rights reserved.
//
//  Inspired by SwiftPasscodeLock created by Yanko Dimitrov.
//

import LocalAuthentication
import UIKit

open class PasscodeLockViewController: UIViewController, UITextFieldDelegate {
    open var dismissCompletionCallback: (() -> Void)?
    open var successCallback: (() -> Void)?
    open var cancelCallback: (() -> Void)?

    weak var passcodeTextField: UITextField?
    weak var biometryAuthButton: UIButton?
    open weak var cancelButton: UIButton?

    var isCancellable = false

    private var lockoutTimer: Timer?

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()

    private let passwordStore = PasswordStore.shared

    override open func loadView() {
        super.loadView()

        let passcodeTextField = UITextField()
        passcodeTextField.borderStyle = UITextField.BorderStyle.roundedRect
        passcodeTextField.placeholder = "EnterPasscode".localize()
        passcodeTextField.isSecureTextEntry = true
        passcodeTextField.clearButtonMode = UITextField.ViewMode.whileEditing
        passcodeTextField.delegate = self
        // Unlock on return only, so that every guess counts as an attempt.
        passcodeTextField.returnKeyType = .done
        passcodeTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passcodeTextField)
        self.passcodeTextField = passcodeTextField

        view.backgroundColor = Colors.systemBackground
        passcodeTextField.backgroundColor = Colors.secondarySystemBackground
        passcodeTextField.textColor = Colors.secondaryLabel

        let biometryAuthButton = UIButton(type: .custom)
        biometryAuthButton.setTitle("", for: .normal)
        biometryAuthButton.setTitleColor(Colors.systemBlue, for: .normal)
        biometryAuthButton.addTarget(self, action: #selector(bioButtonPressedAction), for: .touchUpInside)
        biometryAuthButton.isHidden = true
        biometryAuthButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(biometryAuthButton)
        self.biometryAuthButton = biometryAuthButton

        let myContext = LAContext()
        var authError: NSError?
        if myContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            if myContext.biometryType == .faceID {
                biometryAuthButton.setTitle("FaceId".localize(), for: .normal)
            } else {
                biometryAuthButton.setTitle("TouchId".localize(), for: .normal)
            }
            biometryAuthButton.titleLabel?.font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
            biometryAuthButton.isHidden = false
        }

        let forgotPasscodeButton = UIButton(type: .custom)
        forgotPasscodeButton.setTitle("ForgotYourPasscode?".localize(), for: .normal)
        forgotPasscodeButton.titleLabel?.font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
        forgotPasscodeButton.setTitleColor(Colors.systemBlue, for: .normal)
        forgotPasscodeButton.addTarget(self, action: #selector(forgotPasscodeButtonPressedAction), for: .touchUpInside)
        // hide the forgotPasscodeButton if the native app is running
        forgotPasscodeButton.isHidden = isCancellable
        forgotPasscodeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(forgotPasscodeButton)

        let cancelButton = UIButton(type: .custom)
        cancelButton.setTitle("Cancel".localize(), for: .normal)
        cancelButton.setTitleColor(Colors.systemBlue, for: .normal)
        cancelButton.addTarget(self, action: #selector(passcodeLockDidCancel), for: .touchUpInside)
        cancelButton.isHidden = !isCancellable
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.contentHorizontalAlignment = UIControl.ContentHorizontalAlignment.left
        view.addSubview(cancelButton)
        self.cancelButton = cancelButton

        // Display the Pass icon in the middle of the screen
        let bundle = Bundle(for: Self.self)
        let appIcon = UIImage(named: "PasscodeLockViewIcon", in: bundle, compatibleWith: nil)
        let appIconSize = (appIcon?.size.height) ?? 0
        let appIconView = UIImageView(image: appIcon)
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        appIconView.layer.cornerRadius = appIconSize / 5
        appIconView.layer.masksToBounds = true
        view?.addSubview(appIconView)

        NSLayoutConstraint.activate(
            [
                passcodeTextField.widthAnchor.constraint(equalToConstant: 250),
                passcodeTextField.heightAnchor.constraint(equalToConstant: 40),
                passcodeTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                passcodeTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
                // above passocde
                appIconView.widthAnchor.constraint(equalToConstant: appIconSize),
                appIconView.heightAnchor.constraint(equalToConstant: appIconSize),
                appIconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                appIconView.bottomAnchor.constraint(equalTo: passcodeTextField.topAnchor, constant: -appIconSize),
                // below passcode
                biometryAuthButton.widthAnchor.constraint(equalToConstant: 250),
                biometryAuthButton.heightAnchor.constraint(equalToConstant: 40),
                biometryAuthButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                biometryAuthButton.topAnchor.constraint(equalTo: passcodeTextField.bottomAnchor),
                // cancel (top-left of the screen)
                cancelButton.widthAnchor.constraint(equalToConstant: 150),
                cancelButton.heightAnchor.constraint(equalToConstant: 40),
                cancelButton.topAnchor.constraint(equalTo: view.safeTopAnchor),
                cancelButton.leftAnchor.constraint(equalTo: view.safeLeftAnchor, constant: 20),
                // bottom of the screen
                forgotPasscodeButton.widthAnchor.constraint(equalToConstant: 250),
                forgotPasscodeButton.heightAnchor.constraint(equalToConstant: 40),
                forgotPasscodeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                forgotPasscodeButton.bottomAnchor.constraint(equalTo: view.safeBottomAnchor, constant: -40),
            ]
        )

        // dismiss keyboard when tapping anywhere
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        view.addGestureRecognizer(tap)
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateLockout()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let biometryAuthButton {
            bioButtonPressedAction(biometryAuthButton)
        }
    }

    private func dismissPasscodeLock(completionHandler: (() -> Void)? = nil) {
        lockoutTimer?.invalidate()

        // clean up the textfield
        DispatchQueue.main.async {
            self.passcodeTextField?.text = ""
        }

        completionHandler?()

        // pop
        if presentingViewController?.presentedViewController == self {
            // if presented as modal
            dismiss(animated: true) { [weak self] in
                self?.dismissCompletionCallback?()
            }
        } else {
            // if pushed in a navigation controller
            _ = navigationController?.popViewController(animated: true)
            dismissCompletionCallback?()
        }
    }

    // MARK: - PasscodeLockDelegate

    open func passcodeLockDidSucceed() {
        dismissPasscodeLock(completionHandler: successCallback)
    }

    @objc
    func passcodeLockDidCancel() {
        dismissPasscodeLock(completionHandler: cancelCallback)
    }

    @objc
    func bioButtonPressedAction(_: UIButton) {
        // Authenticating the session also unlocks the saved PGP key passphrases without asking again.
        let myContext = AppKeychain.shared.sessionAuthenticationContext
        let myLocalizedReasonString = "AuthenticationNeeded.".localize()
        var authError: NSError?
        if myContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            myContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: myLocalizedReasonString) { success, _ in
                if success {
                    DispatchQueue.main.async {
                        // user authenticated successfully, take appropriate action
                        PasscodeLock.shared.didAuthenticate()
                        self.passcodeLockDidSucceed()
                    }
                }
            }
        }
    }

    @objc
    func forgotPasscodeButtonPressedAction(_: UIButton) {
        let alert = UIAlertController(title: "ResetPass".localize(), message: "ResetPassExplanation.".localize(), preferredStyle: UIAlertController.Style.alert)
        alert.addAction(
            UIAlertAction(title: "ErasePasswordStoreData".localize(), style: UIAlertAction.Style.destructive) { [unowned self] _ in
                let myContext = LAContext()
                // If the device passcode is not set, reset the app.
                guard myContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
                    passwordStore.erase()
                    passcodeLockDidSucceed()
                    return
                }
                // If the device passcode is set, authentication is required.
                myContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "ErasePasswordStoreData".localize()) { success, error in
                    if success {
                        DispatchQueue.main.async {
                            // User authenticated successfully, take appropriate action
                            self.passwordStore.erase()
                            self.passcodeLockDidSucceed()
                        }
                    } else {
                        DispatchQueue.main.async {
                            Utils.alert(title: "Error".localize(), message: error?.localizedDescription ?? "", controller: self)
                        }
                    }
                }
            }
        )
        alert.addAction(UIAlertAction.dismiss())
        present(alert, animated: true, completion: nil)
    }

    override public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == passcodeTextField {
            if PasscodeLock.shared.check(passcode: textField.text ?? "") {
                passcodeLockDidSucceed()
            } else {
                passcodeTextField?.placeholder =
                    "TryAgain".localize()
                passcodeTextField?.text = ""
                passcodeTextField?.shake()
                updateLockout()
            }
        }
        textField.resignFirstResponder()
        return true
    }

    /// Disable the passcode field while attempts are delayed after too many failed ones.
    private func updateLockout() {
        lockoutTimer?.invalidate()
        let remaining = PasscodeLock.shared.lockoutRemaining
        guard remaining > 0 else {
            if passcodeTextField?.isEnabled == false {
                passcodeTextField?.isEnabled = true
                passcodeTextField?.placeholder = "EnterPasscode".localize()
            }
            return
        }
        passcodeTextField?.isEnabled = false
        passcodeTextField?.placeholder = "TryAgainIn(%@)".localize(Self.durationFormatter.string(from: remaining.rounded(.up)) ?? "")
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            self?.updateLockout()
        }
    }

    public func setCancellable(_ isCancellable: Bool) {
        self.isCancellable = isCancellable
        cancelButton?.isHidden = !isCancellable
    }
}
