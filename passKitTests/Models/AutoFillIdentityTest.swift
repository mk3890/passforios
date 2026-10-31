//
//  AutoFillIdentityTest.swift
//  passKitTests
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import AuthenticationServices
import XCTest

@testable import passKit

final class AutoFillIdentityTest: XCTestCase {
    func testIdentityFromPasswordNamedAfterDomain() throws {
        let identity = try XCTUnwrap(AutoFillIdentity(passwordPath: "GitHub.com.gpg"))

        XCTAssertEqual(identity.kind, .password)
        XCTAssertEqual(identity.serviceIdentifier, "github.com")
        XCTAssertFalse(identity.isURL)
        XCTAssertEqual(identity.user, "github.com")
        XCTAssertEqual(identity.recordIdentifier, "GitHub.com.gpg")
    }

    func testIdentityFromPasswordInDomainDirectory() throws {
        let identity = try XCTUnwrap(AutoFillIdentity(passwordPath: "web/amazon.co.uk/me/work.gpg"))

        XCTAssertEqual(identity.serviceIdentifier, "amazon.co.uk")
        XCTAssertEqual(identity.user, "me/work")
        XCTAssertEqual(identity.recordIdentifier, "web/amazon.co.uk/me/work.gpg")
    }

    func testIdentityPrefersInnermostDomain() throws {
        let identity = try XCTUnwrap(AutoFillIdentity(passwordPath: "example.com/mail.example.com/me.gpg"))

        XCTAssertEqual(identity.serviceIdentifier, "mail.example.com")
        XCTAssertEqual(identity.user, "me")
    }

    func testNoIdentityFromPasswordWithoutDomain() {
        [
            "github.gpg",
            "email/gmail.gpg",
            "keys/id_rsa.pub.gpg",
            "versions/release1.2.gpg",
            "dots/a..com.gpg",
            "dots/.com.gpg",
            "short/example.c.gpg",
        ].forEach { XCTAssertNil(AutoFillIdentity(passwordPath: $0), $0) }
    }

    func testIdentitiesForPasswordPaths() {
        let saved = [
            identity(.password, "https://example.org/login", user: "me", path: "logins/example.gpg"),
            identity(.oneTimeCode, "example.org", user: "example", path: "logins/example.gpg"),
            identity(.password, "gone.com", user: "me", path: "gone.com.gpg"),
        ]
        let paths = ["github.com/me.gpg", "logins/example.gpg", "notes.gpg"]

        let (all, kept) = AutoFillIdentity.identities(forPasswordPaths: paths, saved: saved)

        XCTAssertEqual(kept, Array(saved.prefix(2)))
        XCTAssertEqual(all, [identity(.password, "github.com", user: "me", path: "github.com/me.gpg")] + kept)
    }

    func testIdentitiesDoNotDuplicateSavedDerivedIdentity() {
        let derived = identity(.password, "github.com", user: "me", path: "github.com/me.gpg")

        let (all, kept) = AutoFillIdentity.identities(forPasswordPaths: [derived.recordIdentifier], saved: [derived])

        XCTAssertEqual(all, [derived])
        XCTAssertEqual(kept, [derived])
    }

    func testCodable() throws {
        let identities = [
            identity(.password, "https://example.org/login", user: "me", path: "example.gpg"),
            identity(.oneTimeCode, "example.org", user: "example", path: "example.gpg"),
        ]

        let decoded = try JSONDecoder().decode([AutoFillIdentity].self, from: JSONEncoder().encode(identities))

        XCTAssertEqual(decoded, identities)
    }

    func testPasswordCredentialIdentity() throws {
        let passwordIdentity = try XCTUnwrap(identity(.password, "https://example.org/login", user: "me", path: "example.gpg").passwordCredentialIdentity)

        XCTAssertEqual(passwordIdentity.serviceIdentifier.identifier, "https://example.org/login")
        XCTAssertEqual(passwordIdentity.serviceIdentifier.type, .URL)
        XCTAssertEqual(passwordIdentity.user, "me")
        XCTAssertEqual(passwordIdentity.recordIdentifier, "example.gpg")
        XCTAssertNil(identity(.oneTimeCode, "example.org", user: "example", path: "example.gpg").passwordCredentialIdentity)
    }

    func testOneTimeCodeCredentialIdentity() throws {
        guard #available(iOS 18.0, *) else {
            throw XCTSkip("One-time code identities require iOS 18.")
        }
        let credentialIdentity = identity(.oneTimeCode, "example.org", user: "example", path: "example.gpg").credentialIdentity
        let oneTimeCodeIdentity = try XCTUnwrap(credentialIdentity as? ASOneTimeCodeCredentialIdentity)

        XCTAssertEqual(oneTimeCodeIdentity.serviceIdentifier.identifier, "example.org")
        XCTAssertEqual(oneTimeCodeIdentity.serviceIdentifier.type, .domain)
        XCTAssertEqual(oneTimeCodeIdentity.label, "example")
        XCTAssertEqual(oneTimeCodeIdentity.recordIdentifier, "example.gpg")
    }

    func testServiceIdentifierHost() {
        XCTAssertEqual(ASCredentialServiceIdentifier(identifier: "github.com", type: .domain).host, "github.com")
        XCTAssertEqual(ASCredentialServiceIdentifier(identifier: "https://github.com/login", type: .URL).host, "github.com")
        XCTAssertEqual(ASCredentialServiceIdentifier(identifier: "github.com/login", type: .URL).host, "github.com")
    }

    private func identity(_ kind: AutoFillIdentity.Kind, _ serviceIdentifier: String, user: String, path: String) -> AutoFillIdentity {
        let type: ASCredentialServiceIdentifier.IdentifierType = serviceIdentifier.contains("/") ? .URL : .domain
        return AutoFillIdentity(
            kind: kind,
            serviceIdentifier: ASCredentialServiceIdentifier(identifier: serviceIdentifier, type: type),
            user: user,
            recordIdentifier: path
        )
    }
}
