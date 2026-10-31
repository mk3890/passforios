//
//  PasscodeLockTest.swift
//  passKitTests
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

final class PasscodeLockTest: XCTestCase {
    private let passcodeKey = Globals.bundleIdentifier + "passcode"

    private var keyStore = DictBasedKeychain()
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private lazy var passcodeLock = PasscodeLock(keyStore: keyStore) { [unowned self] in self.now }

    func testCheckPasscode() {
        XCTAssertFalse(passcodeLock.hasPasscode)

        passcodeLock.save(passcode: "1234")

        XCTAssertTrue(passcodeLock.hasPasscode)
        XCTAssertTrue(passcodeLock.check(passcode: "1234"))
        XCTAssertFalse(passcodeLock.check(passcode: "4321"))
    }

    func testPasscodeIsStoredHashed() throws {
        passcodeLock.save(passcode: "1234")
        let storedPasscode = try XCTUnwrap(keyStore.get(for: passcodeKey))

        XCTAssertFalse(storedPasscode.contains("1234"))
        XCTAssertTrue(storedPasscode.hasPrefix("sha256:"))
    }

    func testSaltDiffersBetweenSaves() throws {
        passcodeLock.save(passcode: "1234")
        let firstPasscode = try XCTUnwrap(keyStore.get(for: passcodeKey))
        passcodeLock.save(passcode: "1234")

        XCTAssertNotEqual(keyStore.get(for: passcodeKey), firstPasscode)
    }

    func testPlainTextPasscodeIsMigrated() throws {
        keyStore.add(string: "1234", for: passcodeKey)

        XCTAssertTrue(passcodeLock.check(passcode: "1234"))
        XCTAssertTrue(try XCTUnwrap(keyStore.get(for: passcodeKey)).hasPrefix("sha256:"))
        XCTAssertTrue(passcodeLock.check(passcode: "1234"))
    }

    func testLockoutAfterFailedAttempts() {
        passcodeLock.save(passcode: "1234")

        (1 ..< PasscodeLock.freeAttempts).forEach { _ in XCTAssertFalse(passcodeLock.check(passcode: "0000")) }
        XCTAssertEqual(passcodeLock.lockoutRemaining, 0)

        XCTAssertFalse(passcodeLock.check(passcode: "0000"))
        XCTAssertEqual(passcodeLock.lockoutRemaining, 30)
        // Even the right passcode is rejected while locked out.
        XCTAssertFalse(passcodeLock.check(passcode: "1234"))

        now += 10
        XCTAssertEqual(passcodeLock.lockoutRemaining, 20)
        now += 20
        XCTAssertEqual(passcodeLock.lockoutRemaining, 0)
        XCTAssertTrue(passcodeLock.check(passcode: "1234"))

        // A successful attempt resets the failed ones.
        XCTAssertFalse(passcodeLock.check(passcode: "0000"))
        XCTAssertEqual(passcodeLock.lockoutRemaining, 0)
    }

    func testLockoutGrowsWithFailedAttempts() {
        passcodeLock.save(passcode: "1234")
        var lockouts: [TimeInterval] = []

        (0 ..< PasscodeLock.freeAttempts + PasscodeLock.lockoutDurations.count + 1).forEach { _ in
            XCTAssertFalse(passcodeLock.check(passcode: "0000"))
            lockouts.append(passcodeLock.lockoutRemaining)
            now += passcodeLock.lockoutRemaining
        }

        XCTAssertEqual(lockouts, Array(repeating: 0, count: PasscodeLock.freeAttempts - 1) + PasscodeLock.lockoutDurations + [3600, 3600])
    }

    func testLockoutIsLimitedWhenClockIsSetBack() {
        passcodeLock.save(passcode: "1234")
        (0 ..< PasscodeLock.freeAttempts).forEach { _ in XCTAssertFalse(passcodeLock.check(passcode: "0000")) }

        now -= 24 * 60 * 60

        XCTAssertEqual(passcodeLock.lockoutRemaining, PasscodeLock.lockoutDurations.last)
    }

    func testAuthenticationResetsLockout() {
        passcodeLock.save(passcode: "1234")
        (0 ..< PasscodeLock.freeAttempts).forEach { _ in XCTAssertFalse(passcodeLock.check(passcode: "0000")) }

        passcodeLock.didAuthenticate()

        XCTAssertEqual(passcodeLock.lockoutRemaining, 0)
        XCTAssertTrue(passcodeLock.check(passcode: "1234"))
    }

    func testDelete() {
        passcodeLock.save(passcode: "1234")
        XCTAssertFalse(passcodeLock.check(passcode: "0000"))

        passcodeLock.delete()

        XCTAssertFalse(passcodeLock.hasPasscode)
        XCTAssertFalse(passcodeLock.check(passcode: "1234"))
    }
}
