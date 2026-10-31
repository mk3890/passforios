//
//  GitRepositoryTest.swift
//  pass
//
//  Created by Mingshen Sun on 1/26/25.
//  Copyright © 2025 Bob Sun. All rights reserved.
//

import XCTest
@testable import passKit

final class GitRepositoryTest: XCTestCase {
    private var bareRepositoryURL: URL!
    private var workingRepositoryURL: URL!
    private var otherWorkingRepositoryURL: URL!
    private var repository: GitRepository!
    private let fileManager = FileManager.default
    private let options = GitRemoteOptions()
    private let signature = GitSignature(name: "name", email: "email@email.com")
    private let checkoutProgressBlock: CheckoutProgressHandler = { _, _, _ in
    }

    private let transferProgressBlock: TransferProgressHandler = { _ in
    }

    private let pushProgressBlock: PushProgressHandler = { _, _ in
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        bareRepositoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        workingRepositoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        otherWorkingRepositoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(
            at: bareRepositoryURL,
            withIntermediateDirectories: true
        )

        try GitRepository.initializeBareRepository(at: bareRepositoryURL)

        repository = try clone(to: workingRepositoryURL)
    }

    func testSetup() {
        let dotGitFileURL = workingRepositoryURL.appendingPathComponent(".git")
        XCTAssertTrue(fileManager.fileExists(atPath: dotGitFileURL.path))
    }

    func testCommitHeadUnborn() throws {
        _ = try repository.commit(name: "name", email: "email@email.com", message: "message")
    }

    func testCommit() throws {
        try ["file1", "file2"].forEach { filename in
            try commitFile(filename, content: "change1", in: repository, at: workingRepositoryURL)
        }
        XCTAssertEqual(try repository.getRecentCommits(count: 1).first?.parentOIDs.count, 1)
    }

    func testPush() throws {
        try testCommit()
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
    }

    func testGetRecentCommits() throws {
        _ = try repository.commit(name: "name", email: "email@email.com", message: "message1")
        let commit = try repository.getRecentCommits(count: 1)
        XCTAssertEqual(commit.first?.message, "message1")
        XCTAssertEqual(commit.first?.author?.name, "name")
        XCTAssertEqual(commit.first?.author?.email, "email@email.com")
    }

    func testGetLocalCommits() throws {
        try ["file1", "file2"].forEach { filename in
            try commitFile(filename, content: "change", in: repository, at: workingRepositoryURL)
        }
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
        try ["file3", "file4"].forEach { filename in
            try commitFile(filename, content: "change", in: repository, at: workingRepositoryURL)
        }
        let commits = try repository.getLocalCommits()
        XCTAssertEqual(commits.map(\.message), ["message: file4", "message: file3"])
    }

    func testGetLocalCommitsWithoutRemoteBranch() throws {
        try ["file1", "file2"].forEach { filename in
            try commitFile(filename, content: "change", in: repository, at: workingRepositoryURL)
        }
        XCTAssertEqual(try repository.getLocalCommits().count, 2)
    }

    func testNumberOfCommits() throws {
        XCTAssertEqual(repository.numberOfCommits(), 0)
        try ["file1", "file2"].forEach { filename in
            try commitFile(filename, content: "change", in: repository, at: workingRepositoryURL)
        }
        XCTAssertEqual(repository.numberOfCommits(), 2)
    }

    func testCheckoutAndChangeBranch() throws {
        _ = try repository.commit(name: "name", email: "email@email.com", message: "message")
        try repository.createBranch(named: "feature-branch")
        try repository.push(branch: "feature-branch", options: options)

        try repository.checkoutAndChangeBranch(branchName: "feature-branch", progressBlock: checkoutProgressBlock)
    }

    func testCheckoutRemoteBranch() throws {
        try commitFile("file1", content: "change", in: repository, at: workingRepositoryURL)
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
        try repository.createBranch(named: "feature-branch")
        try repository.push(branch: "feature-branch", options: options)
        let otherRepository = try clone(to: otherWorkingRepositoryURL)

        try otherRepository.checkoutAndChangeBranch(branchName: "feature-branch", progressBlock: checkoutProgressBlock)

        XCTAssertTrue(fileManager.fileExists(atPath: otherWorkingRepositoryURL.appendingPathComponent("file1").path))
        XCTAssertThrowsError(try otherRepository.checkoutAndChangeBranch(branchName: "missing", progressBlock: checkoutProgressBlock)) {
            XCTAssertEqual($0 as? AppError, .repositoryRemoteBranchNotFound(branchName: "origin/missing"))
        }
    }

    func testPullFromEmptyRemote() throws {
        try repository.pull(options: options, signature: signature, transferProgressBlock: transferProgressBlock)
        XCTAssertEqual(repository.numberOfCommits(), 0)
    }

    func testPullFastForward() throws {
        let otherRepository = try clone(to: otherWorkingRepositoryURL)
        try commitFile("file1", content: "change", in: repository, at: workingRepositoryURL)
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)

        try otherRepository.pull(options: options, signature: signature, transferProgressBlock: transferProgressBlock)

        XCTAssertEqual(try content(of: "file1", at: otherWorkingRepositoryURL), "change")
        XCTAssertEqual(try otherRepository.getRecentCommits(count: 1).first?.message, "message: file1")
        XCTAssertEqual(try otherRepository.getLocalCommits().count, 0)
    }

    func testPullMerge() throws {
        try commitFile("file1", content: "change", in: repository, at: workingRepositoryURL)
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
        let otherRepository = try clone(to: otherWorkingRepositoryURL)
        try commitFile("file2", content: "change", in: repository, at: workingRepositoryURL)
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
        try commitFile("file3", content: "change", in: otherRepository, at: otherWorkingRepositoryURL)

        try otherRepository.pull(options: options, signature: signature, transferProgressBlock: transferProgressBlock)

        let mergeCommit = try XCTUnwrap(otherRepository.getRecentCommits(count: 1).first)
        XCTAssertEqual(mergeCommit.parentOIDs.count, 2)
        XCTAssertEqual(mergeCommit.message, "Merge remote-tracking branch 'origin/master'")
        try ["file1", "file2", "file3"].forEach { filename in
            XCTAssertEqual(try content(of: filename, at: otherWorkingRepositoryURL), "change")
        }
        // The merged changes can be pushed.
        try otherRepository.push(options: options, transferProgressBlock: pushProgressBlock)
        XCTAssertEqual(try otherRepository.getLocalCommits().count, 0)
    }

    func testPullMergeConflict() throws {
        try commitFile("file", content: "original", in: repository, at: workingRepositoryURL)
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
        let otherRepository = try clone(to: otherWorkingRepositoryURL)
        try commitFile("file", content: "remote", in: repository, at: workingRepositoryURL)
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
        try commitFile("file", content: "local", in: otherRepository, at: otherWorkingRepositoryURL)

        XCTAssertThrowsError(try otherRepository.pull(options: options, signature: signature, transferProgressBlock: transferProgressBlock)) {
            XCTAssertEqual($0 as? AppError, .gitMergeConflict(files: ["file"]))
        }
        // The working directory is left untouched.
        XCTAssertEqual(try content(of: "file", at: otherWorkingRepositoryURL), "local")
    }

    func testReset() throws {
        try commitFile("file1", content: "change", in: repository, at: workingRepositoryURL)
        try repository.push(options: options, transferProgressBlock: pushProgressBlock)
        try ["file2", "file3"].forEach { filename in
            try commitFile(filename, content: "change", in: repository, at: workingRepositoryURL)
        }

        try repository.reset()

        XCTAssertEqual(try repository.getLocalCommits().count, 0)
        XCTAssertEqual(try repository.getRecentCommits(count: 1).first?.message, "message: file1")
        XCTAssertFalse(fileManager.fileExists(atPath: workingRepositoryURL.appendingPathComponent("file2").path))
    }

    func testLastCommitDate() throws {
        let fileURL = workingRepositoryURL.appendingPathComponent("file")
        try "change".write(toFile: fileURL.path, atomically: true, encoding: .utf8)
        try repository.add(path: "file")
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try repository.commit(signature: GitSignature(name: "name", email: "email@email.com", time: time), message: "message")

        XCTAssertEqual(try repository.lastCommitDate(path: "file"), time)
    }

    func testRm() throws {
        try ["file1", "file2"].forEach { filename in
            try commitFile(filename, content: "change1", in: repository, at: workingRepositoryURL)
        }

        try repository.rm(path: "file1")
        let commit = try repository.commit(name: "name", email: "email@email.com", message: "message: remove file1")
        XCTAssertEqual(commit.message, "message: remove file1")
        XCTAssertFalse(fileManager.fileExists(atPath: workingRepositoryURL.appendingPathComponent("file1").path))
    }

    func testMv() throws {
        try ["file1", "file2"].forEach { filename in
            try commitFile(filename, content: "change1", in: repository, at: workingRepositoryURL)
        }

        try repository.mv(from: "file1", to: "file3")
        let commit = try repository.commit(name: "name", email: "email@email.com", message: "message: remove file1")
        XCTAssertEqual(commit.message, "message: remove file1")
        XCTAssertFalse(fileManager.fileExists(atPath: workingRepositoryURL.appendingPathComponent("file1").path))
        XCTAssertTrue(fileManager.fileExists(atPath: workingRepositoryURL.appendingPathComponent("file3").path))
    }

    func testSignatureValidation() {
        XCTAssertTrue(GitSignature.isValid(name: "name", email: "email@email.com"))
        XCTAssertFalse(GitSignature.isValid(name: "<name>", email: "email@email.com"))
        XCTAssertFalse(GitSignature.isValid(name: "", email: "email@email.com"))
    }

    override func tearDownWithError() throws {
        repository = nil
        try fileManager.removeItem(at: bareRepositoryURL)
        try fileManager.removeItem(at: workingRepositoryURL)
        try? fileManager.removeItem(at: otherWorkingRepositoryURL)
        super.tearDown()
    }

    private func clone(to url: URL) throws -> GitRepository {
        try GitRepository(from: bareRepositoryURL, to: url, branchName: "master", options: options, transferProgressBlock: transferProgressBlock, checkoutProgressBlock: checkoutProgressBlock)
    }

    private func commitFile(_ filename: String, content: String, in repository: GitRepository, at url: URL) throws {
        try content.write(toFile: url.appendingPathComponent(filename).path, atomically: true, encoding: .utf8)
        try repository.add(path: filename)
        _ = try repository.commit(name: "name", email: "email@email.com", message: "message: \(filename)")
    }

    private func content(of filename: String, at url: URL) throws -> String {
        try String(contentsOf: url.appendingPathComponent(filename), encoding: .utf8)
    }
}
