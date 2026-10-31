//
//  PasswordAlertPresenter.swift
//  pass
//
//  Created by Danny Moesch on 23.08.20.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

import SVProgressHUD

protocol PasswordAlertPresenter {
    func present(message: String, lastPassword: String?) -> String?
    func approveHostKey(host: String, fingerprint: String, savedFingerprint: String?) -> Bool
}

extension PasswordAlertPresenter where Self: UIViewController {
    func present(message: String, lastPassword: String?) -> String? {
        let sem = DispatchSemaphore(value: 0)
        var password: String?

        DispatchQueue.main.async {
            SVProgressHUD.dismiss()
            let alert = UIAlertController(title: "Password".localize(), message: message, preferredStyle: .alert)
            alert.addTextField {
                $0.text = lastPassword ?? ""
                $0.isSecureTextEntry = true
            }
            alert.addAction(
                .ok { _ in
                    password = alert.textFields?.first?.text
                    sem.signal()
                }
            )
            alert.addAction(
                .cancel { _ in
                    password = nil
                    sem.signal()
                }
            )
            self.present(alert, animated: true)
        }

        _ = sem.wait(timeout: .distantFuture)
        return password
    }

    /// Ask whether to trust an SSH host key that is unknown or, if a fingerprint was saved, differs from the trusted one.
    func approveHostKey(host: String, fingerprint: String, savedFingerprint: String?) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var approved = false

        DispatchQueue.main.async {
            SVProgressHUD.dismiss()
            let alert: UIAlertController
            if let savedFingerprint {
                let message = String(format: "HostKeyChangedMessage.".localize(), host, savedFingerprint, fingerprint)
                alert = UIAlertController(title: "HostKeyChanged".localize(), message: message, preferredStyle: .alert)
            } else {
                let message = String(format: "UnknownHostKeyMessage.".localize(), host, fingerprint)
                alert = UIAlertController(title: "UnknownHostKey".localize(), message: message, preferredStyle: .alert)
            }
            alert.addAction(
                .cancel { _ in
                    sem.signal()
                }
            )
            alert.addAction(
                UIAlertAction(title: "TrustHostKey".localize(), style: savedFingerprint == nil ? .default : .destructive) { _ in
                    approved = true
                    sem.signal()
                }
            )
            self.present(alert, animated: true)
        }

        _ = sem.wait(timeout: .distantFuture)
        return approved
    }

    /// Ask whether to trust an unknown SSH host key, but reject a changed one, which can only be accepted when cloning.
    func approveUnknownHostKey(host: String, fingerprint: String, savedFingerprint: String?) -> Bool {
        savedFingerprint == nil && approveHostKey(host: host, fingerprint: fingerprint, savedFingerprint: nil)
    }
}
