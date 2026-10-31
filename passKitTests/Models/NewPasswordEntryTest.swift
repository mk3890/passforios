//
//  NewPasswordEntryTest.swift
//  passKitTests
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

final class NewPasswordEntryTest: XCTestCase {
    func testSuggestedName() {
        XCTAssertEqual(NewPasswordEntry(host: "github.com", username: "mkelly", password: "secret").suggestedName, "github.com/mkelly")
        XCTAssertEqual(NewPasswordEntry(host: "WWW.Example.org", username: "", password: "secret").suggestedName, "example.org")
        XCTAssertEqual(NewPasswordEntry(host: "example.org", username: " me/work ", password: "secret").suggestedName, "example.org/me-work")
        XCTAssertEqual(NewPasswordEntry(host: nil, username: "me", password: "secret").suggestedName, "me")
    }

    func testPlainText() {
        XCTAssertEqual(
            NewPasswordEntry(host: "github.com", username: "mkelly", password: "secret").plainText,
            "secret\nlogin: mkelly\nurl: https://github.com"
        )
        XCTAssertEqual(NewPasswordEntry(host: nil, username: "", password: "secret").plainText, "secret")
    }

    func testPlainTextIsParsedByPassword() {
        let plainText = NewPasswordEntry(host: "github.com", username: "mkelly", password: "secret").plainText
        let password = Password(name: "mkelly", path: "github.com/mkelly.gpg", plainText: plainText)

        XCTAssertEqual(password.password, "secret")
        XCTAssertEqual(password.getUsernameForCompletion(), "mkelly")
        XCTAssertEqual(password.urlString, "https://github.com")
    }

    func testReplacingPasswordKeepsOtherLines() {
        let entry = NewPasswordEntry(host: "github.com", username: "mkelly", password: "new")
        let existing = "old\nlogin: mkelly\notpauth://totp/GitHub:mkelly?secret=JBSWY3DPEHPK3PXP"

        XCTAssertEqual(entry.plainText(replacingPasswordIn: existing), "new\nlogin: mkelly\notpauth://totp/GitHub:mkelly?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(entry.plainText(replacingPasswordIn: "old"), "new")
        XCTAssertEqual(entry.plainText(replacingPasswordIn: ""), "new")
        XCTAssertEqual(entry.plainText(replacingPasswordIn: "\nlogin: mkelly"), "new\nlogin: mkelly")
    }

    func testReplacingPasswordKeepsLeadingOneTimePasswordField() {
        let entry = NewPasswordEntry(host: "github.com", username: "mkelly", password: "new")

        XCTAssertEqual(entry.plainText(replacingPasswordIn: "otp_secret: JBSWY3DPEHPK3PXP"), "new\notp_secret: JBSWY3DPEHPK3PXP")
    }

    func testPathForName() {
        XCTAssertEqual(NewPasswordEntry.path(forName: "github.com/mkelly"), "github.com/mkelly.gpg")
        XCTAssertEqual(NewPasswordEntry.path(forName: " github.com "), "github.com.gpg")
        [
            "",
            " ",
            "/github.com",
            "github.com/",
            "github.com//mkelly",
            "../github.com",
            "github.com/../../etc",
            "./github.com",
        ].forEach { XCTAssertNil(NewPasswordEntry.path(forName: $0), $0) }
    }
}
