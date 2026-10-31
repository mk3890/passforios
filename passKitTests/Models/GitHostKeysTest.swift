//
//  GitHostKeysTest.swift
//  passKitTests
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

final class GitHostKeysTest: XCTestCase {
    private let keyStore = DictBasedKeychain()
    private lazy var hostKeys = GitHostKeys(keyStore: keyStore)

    func testFingerprintFormat() throws {
        let digest = try XCTUnwrap(Data(base64Encoded: "+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU="))

        XCTAssertEqual(GitHostKeys.fingerprint(sha256: digest), "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU")
    }

    func testUnknownKeyIsTrustedWhenApproved() throws {
        var requests: [String?] = []

        try hostKeys.verify(host: "github.com", fingerprint: "SHA256:first", approve: { _, _, saved in
            requests.append(saved)
            return true
        })
        // A trusted key is accepted without asking again.
        try hostKeys.verify(host: "GitHub.com", fingerprint: "SHA256:first", approve: { _, _, _ in
            XCTFail("Trusted key must not be approved again.")
            return false
        })

        XCTAssertEqual(requests, [nil])
        XCTAssertEqual(hostKeys.fingerprint(for: "github.com"), "SHA256:first")
    }

    func testUnknownKeyIsRejected() {
        XCTAssertThrowsError(try hostKeys.verify(host: "github.com", fingerprint: "SHA256:first", approve: { _, _, _ in false })) {
            XCTAssertEqual($0 as? AppError, .gitHostKeyNotTrusted(host: "github.com"))
        }
        XCTAssertNil(hostKeys.fingerprint(for: "github.com"))
    }

    func testChangedKeyIsRejected() throws {
        try hostKeys.verify(host: "github.com", fingerprint: "SHA256:first", approve: { _, _, _ in true })

        XCTAssertThrowsError(try hostKeys.verify(host: "github.com", fingerprint: "SHA256:second", approve: { host, fingerprint, saved in
            XCTAssertEqual(host, "github.com")
            XCTAssertEqual(fingerprint, "SHA256:second")
            XCTAssertEqual(saved, "SHA256:first")
            return false
        })) {
            XCTAssertEqual($0 as? AppError, .gitHostKeyChanged(host: "github.com"))
        }
        XCTAssertEqual(hostKeys.fingerprint(for: "github.com"), "SHA256:first")
    }

    func testChangedKeyIsTrustedWhenApproved() throws {
        try hostKeys.verify(host: "github.com", fingerprint: "SHA256:first", approve: { _, _, _ in true })
        try hostKeys.verify(host: "github.com", fingerprint: "SHA256:second", approve: { _, _, _ in true })

        XCTAssertEqual(hostKeys.fingerprint(for: "github.com"), "SHA256:second")
    }

    func testKeysArePerHost() throws {
        try hostKeys.verify(host: "github.com", fingerprint: "SHA256:first", approve: { _, _, _ in true })

        XCTAssertNil(hostKeys.fingerprint(for: "gitlab.com"))
    }
}
