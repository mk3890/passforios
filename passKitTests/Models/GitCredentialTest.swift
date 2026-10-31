//
//  GitCredentialTest.swift
//  passKitTests
//
//  Created by Danny Moesch on 29.08.20.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

import XCTest

import SwiftyUserDefaults
@testable import passKit

final class GitCredentialTest: XCTestCase {
    private static let defaultsID = "SharedDefaultsForGitCredentialTest"

    private let keyStore = DictBasedKeychain()

    override func setUp() {
        super.setUp()

        keyStore.add(string: "password", for: Globals.gitPassword)
        keyStore.add(string: "passphrase", for: Globals.gitSSHPrivateKeyPassphrase)

        UserDefaults().removePersistentDomain(forName: Self.defaultsID)
        passKit.Defaults = DefaultsAdapter(defaults: UserDefaults(suiteName: Self.defaultsID)!, keyStore: DefaultsKeys())
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: Self.defaultsID)

        super.tearDown()
    }

    func testDelete() {
        let password = GitCredential.from(authenticationMethod: .password, userName: "user", keyStore: keyStore)
        password.delete()
        XCTAssertFalse(keyStore.contains(key: Globals.gitPassword))
        XCTAssertTrue(keyStore.contains(key: Globals.gitSSHPrivateKeyPassphrase))

        let key = GitCredential.from(authenticationMethod: .key, userName: "user", keyStore: keyStore)
        key.delete()
        XCTAssertFalse(keyStore.contains(key: Globals.gitPassword))
        XCTAssertFalse(keyStore.contains(key: Globals.gitSSHPrivateKeyPassphrase))
    }

    func testPasswordCredential() {
        let password = GitCredential.from(authenticationMethod: .password, userName: "user", keyStore: keyStore)
        let expectation = expectation(description: "Password is requested.")
        expectation.assertForOverFulfill = true
        expectation.expectedFulfillmentCount = 3
        let options = password.getCredentialOptions { _, _ in
            expectation.fulfill()
            return "otherPassword"
        }

        // The saved password is tried first.
        XCTAssertEqual(options.credential(false), .password(userName: "user", password: "password"))
        (2 ... 4).forEach { _ in
            XCTAssertEqual(options.credential(false), .password(userName: "user", password: "otherPassword"))
        }
        XCTAssertNil(options.credential(false))
        wait(for: [expectation], timeout: 0)
    }

    func testUsernameDoesNotCountAsAttempt() {
        let key = GitCredential.from(authenticationMethod: .key, userName: "user", keyStore: keyStore)
        let options = key.getCredentialOptions()

        XCTAssertEqual(options.credential(true), .username("user"))
        XCTAssertEqual(options.credential(true), .username("user"))
        XCTAssertNotNil(options.credential(false))
    }

    func testSSHKeyCredential() {
        keyStore.add(string: "privateKey", for: SSHKey.PRIVATE.getKeychainKey())
        let options = GitCredential.from(authenticationMethod: .key, userName: "user", keyStore: keyStore).getCredentialOptions()

        XCTAssertEqual(options.credential(false), .sshKey(userName: "user", privateKey: "privateKey", passphrase: "passphrase"))
        XCTAssertNil(options.credential(false))
    }

    func testCannotGetPassword() {
        let options = getCredentialOptions(authenticationMethod: .password)

        XCTAssertNotNil(options.credential(false))
        XCTAssertNil(options.credential(false))
    }

    func testSaveToKeyStore() {
        let options = getCredentialOptions(authenticationMethod: .key, password: "otherPassword")

        passKit.Defaults.isRememberGitCredentialPassphraseOn = true
        keyStore.removeAllContent()
        _ = options.credential(false)

        XCTAssertEqual(keyStore.get(for: Globals.gitSSHPrivateKeyPassphrase), "otherPassword")
    }

    func testHostKeyApprover() {
        let credential = GitCredential.from(authenticationMethod: .password, userName: "user", keyStore: keyStore)

        XCTAssertFalse(credential.getCredentialOptions().approveHostKey("host", "SHA256:new", nil))
        XCTAssertTrue(credential.getCredentialOptions(hostKeyApprover: { _, _, _ in true }).approveHostKey("host", "SHA256:new", nil))
    }

    private func getCredentialOptions(authenticationMethod: GitAuthenticationMethod, password: String? = nil) -> GitRemoteOptions {
        let credential = GitCredential.from(authenticationMethod: authenticationMethod, userName: "user", keyStore: keyStore)
        return credential.getCredentialOptions { _, _ in password }
    }
}
