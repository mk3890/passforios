//
//  NewPasswordEntry.swift
//  passKit
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import Foundation

/// A password to save for a website or app, e.g., when AutoFill offers to save one after signing up or changing it.
public struct NewPasswordEntry: Equatable {
    public let host: String?
    public let username: String
    public let password: String

    public init(host: String?, username: String, password: String) {
        self.host = host
        self.username = username
        self.password = password
    }

    /// The name proposed for the entry, following the common `domain/username` layout of pass stores, e.g.,
    /// "github.com/mkelly".
    public var suggestedName: String {
        let site = host.map { $0.lowercased().hasPrefix("www.") ? String($0.lowercased().dropFirst(4)) : $0.lowercased() } ?? ""
        // A slash in the user name would create another directory.
        let user = username.trimmed.replacingOccurrences(of: "/", with: "-")
        return [site, user].filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// The content of a new password file: the password on the first line, then the user name and the website.
    public var plainText: String {
        var lines = [password]
        if !username.isEmpty {
            lines.append("\(Constants.LOGIN_KEYWORD): \(username)")
        }
        if let host {
            lines.append("\(Constants.URL_KEYWORD): https://\(host)")
        }
        return lines.joined(separator: "\n")
    }

    /// The content of an existing password file with its password replaced, keeping all other lines, e.g., the user
    /// name or the secret for one-time passwords.
    public func plainText(replacingPasswordIn existingPlainText: String) -> String {
        let lines = existingPlainText.splitByNewline()
        guard let firstLine = lines.first, !firstLine.isEmpty else {
            return ([password] + lines.dropFirst()).joined(separator: "\n")
        }
        // Some entries have no password, but start with a one-time password field.
        if let key = Parser.getKeyValuePair(from: firstLine).key, Constants.isOtpKeyword(key) {
            return ([password] + lines).joined(separator: "\n")
        }
        return ([password] + lines.dropFirst()).joined(separator: "\n")
    }

    /// The path of the password file for a name, or nil if the name cannot be used, e.g., because it is empty, absolute
    /// or contains ".." to point outside of the store.
    public static func path(forName name: String) -> String? {
        let name = name.trimmed
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return name + ".gpg"
    }
}
