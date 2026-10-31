//
//  PasswordTableEntry.swift
//  passKit
//
//  Created by Yishi Lin on 2020/2/23.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

import Foundation

public class PasswordTableEntry: NSObject {
    public let passwordEntity: PasswordEntity
    @objc public let title: String
    public let isDir: Bool
    public let isSynced: Bool
    public let categoryText: String

    public init(_ entity: PasswordEntity) {
        self.passwordEntity = entity
        self.title = entity.name
        self.isDir = entity.isDir
        self.isSynced = entity.isSynced
        self.categoryText = entity.dirText
    }

    public func matches(_ searchText: String) -> Bool {
        Self.match(nameWithCategory: passwordEntity.nameWithDir, searchText: searchText)
    }

    public static func match(nameWithCategory: String, searchText: String) -> Bool {
        let titleSplit = nameWithCategory.split { !($0.isLetter || $0.isNumber || $0 == ".") }
        for str in titleSplit {
            if str.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            if searchText.localizedCaseInsensitiveContains(str) {
                return true
            }
        }

        return false
    }

    /// Whether the password belongs to the website or app with the given host. Unlike `matches`, a name has to
    /// name the host's domain, not just appear somewhere in it, because suggestions are trusted more than search
    /// results. For example, "paypal.com" is not suggested on "paypal.com.example.org".
    public func matches(host: String) -> Bool {
        Self.match(nameWithCategory: passwordEntity.nameWithDir, host: host)
    }

    public static func match(nameWithCategory: String, host: String) -> Bool {
        let host = host.lowercased()
        let siteName = siteName(of: host)
        return nameWithCategory.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
            .contains { name in
                if name.contains(".") {
                    // A domain matches itself, its subdomains, and its parent domains.
                    return host == name || host.hasSuffix(".\(name)") || name.hasSuffix(".\(host)")
                }
                return name == siteName
            }
    }

    /// The label naming the site, e.g., "github" for "www.github.com" or "amazon" for "amazon.co.uk". Without a
    /// public suffix list, only the common second-level domains of two-letter country codes are recognized.
    static func siteName(of host: String) -> Substring? {
        var labels = host.split(separator: ".")
        guard labels.count > 1, let topLevelDomain = labels.popLast() else {
            return labels.first
        }
        let secondLevelDomains: Set<Substring> = ["ac", "co", "com", "edu", "gov", "ne", "net", "or", "org"]
        if topLevelDomain.count == 2, labels.count > 1, let label = labels.last, secondLevelDomains.contains(label) {
            labels.removeLast()
        }
        return labels.last
    }
}
