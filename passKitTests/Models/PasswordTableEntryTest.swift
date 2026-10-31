//
//  PasswordTableEntryTest.swift
//  passKitTests
//
//  Created by Yishi Lin on 2020/2/23.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

final class PasswordTableEntryTest: XCTestCase {
    func testMatchHost() {
        [
            ("github", "github.com"),
            ("GitHub", "www.github.com"),
            ("github.com", "github.com"),
            ("github.com", "www.github.com"),
            ("www.github.com", "github.com"),
            ("personal/github.com", "github.com"),
            ("github.com/personal", "github.com"),
            ("github (personal)", "github.com"),
            ("amazon", "www.amazon.co.uk"),
            ("amazon.co.uk", "www.amazon.co.uk"),
            ("my-bank", "login.my-bank.com"),
        ].forEach { name, host in
            XCTAssertTrue(PasswordTableEntry.match(nameWithCategory: name, host: host), "\(name) on \(host)")
        }
    }

    func testNoMatchHostOnLookalikeDomains() {
        [
            ("paypal.com", "paypal.com.example.org"),
            ("paypal", "paypal.com.example.org"),
            ("paypal", "paypal-login.com"),
            ("paypal.com", "notpaypal.com"),
            ("github", "xgithub.com"),
            ("bank", "mybank.com"),
            ("com", "github.com"),
            ("co", "example.co.uk"),
        ].forEach { name, host in
            XCTAssertFalse(PasswordTableEntry.match(nameWithCategory: name, host: host), "\(name) on \(host)")
        }
    }

    func testSiteName() {
        XCTAssertEqual(PasswordTableEntry.siteName(of: "github.com"), "github")
        XCTAssertEqual(PasswordTableEntry.siteName(of: "www.github.com"), "github")
        XCTAssertEqual(PasswordTableEntry.siteName(of: "www.amazon.co.uk"), "amazon")
        XCTAssertEqual(PasswordTableEntry.siteName(of: "example.de"), "example")
        XCTAssertEqual(PasswordTableEntry.siteName(of: "localhost"), "localhost")
    }

    func testExample() {
        let nameWithCategoryList = [
            "github",
            "github.com",
            "www.github.com",
            "personal/github",
            "personal/github.com",
            "personal/www.github.com",
            "github/personal",
            "github.com/personal",
            "www.github.com/personal",
            "github (personal)",
        ]
        let searchTextList1 = [
            "github.com",
            "www.github.com",
        ]
        let searchTextList2 = [
            "xx.com",
            "www.xx.com",
        ]

        for nameWithCategory in nameWithCategoryList {
            for searchText in searchTextList1 {
                XCTAssertTrue(PasswordTableEntry.match(nameWithCategory: nameWithCategory, searchText: searchText))
            }
            for searchText in searchTextList2 {
                XCTAssertFalse(PasswordTableEntry.match(nameWithCategory: nameWithCategory, searchText: searchText))
            }
        }
    }
}
