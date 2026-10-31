//
//  GitRepository.swift
//  pass
//
//  Created by Mingshen Sun on 1/25/25.
//  Copyright © 2025 Bob Sun. All rights reserved.
//

@_implementationOnly import Clibgit2
import CryptoKit
import Foundation

public struct GitTransferProgress {
    public let receivedObjects: Int
    public let totalObjects: Int
}

public typealias TransferProgressHandler = (GitTransferProgress) -> Void
public typealias CheckoutProgressHandler = (_ path: String, _ completedSteps: Int, _ totalSteps: Int) -> Void
public typealias PushProgressHandler = (_ current: Int, _ total: Int) -> Void

public struct GitSignature {
    public let name: String
    public let email: String
    public let time: Date

    public init(name: String, email: String, time: Date = Date()) {
        self.name = name
        self.email = email
        self.time = time
    }
}

public extension GitSignature {
    /// Whether git accepts the name and email, which must not be empty or contain angle brackets, for example.
    static func isValid(name: String, email: String) -> Bool {
        Git.initialize()
        var signature: UnsafeMutablePointer<git_signature>?
        defer { git_signature_free(signature) }
        return git_signature_now(&signature, name, email) == 0
    }
}

public struct GitCommit {
    public let oid: String
    public let message: String?
    public let author: GitSignature?
    public let commitDate: Date
    let parentOIDs: [String]
}

/// An error reported by libgit2.
public struct GitError: LocalizedError {
    public let code: Int32
    public let message: String

    public var errorDescription: String? {
        message
    }
}

public class GitRepository {
    private let repository: OpaquePointer
    var branchName: String = "master"

    public init(with localDir: URL) throws {
        Git.initialize()
        guard FileManager.default.fileExists(atPath: localDir.path) else {
            throw AppError.repositoryNotSet
        }
        var repository: OpaquePointer?
        try Git.check(git_repository_open(&repository, localDir.path))
        self.repository = repository!
        if let currentBranchName {
            self.branchName = currentBranchName
        }
    }

    public init(
        from remoteURL: URL,
        to workingDir: URL,
        branchName: String,
        options: GitRemoteOptions,
        transferProgressBlock: @escaping TransferProgressHandler,
        checkoutProgressBlock: @escaping CheckoutProgressHandler
    ) throws {
        Git.initialize()
        let callbacks = RemoteCallbacks(options: options, transferProgress: transferProgressBlock)
        let checkoutProgress = CheckoutProgress(checkoutProgressBlock)
        var cloneOptions = git_clone_options()
        git_clone_options_init(&cloneOptions, UInt32(GIT_CLONE_OPTIONS_VERSION))
        var repository: OpaquePointer?
        try withExtendedLifetime((callbacks, checkoutProgress)) {
            cloneOptions.fetch_opts.callbacks = callbacks.rawCallbacks
            checkoutProgress.configure(&cloneOptions.checkout_opts)
            let url = remoteURL.isFileURL ? remoteURL.path : remoteURL.absoluteString
            try callbacks.check(git_clone(&repository, url, workingDir.path, &cloneOptions))
        }
        self.repository = repository!
        self.branchName = branchName
        guard !isHEADUnborn else {
            return
        }
        if currentBranchName != branchName {
            try checkoutAndChangeBranch(branchName: branchName, progressBlock: checkoutProgressBlock)
        }
    }

    deinit {
        git_repository_free(repository)
    }

    private var isHEADUnborn: Bool {
        git_repository_head_unborn(repository) == 1
    }

    private var currentBranchName: String? {
        var head: OpaquePointer?
        guard git_repository_head(&head, repository) == 0 else {
            return nil
        }
        defer { git_reference_free(head) }
        return git_reference_shorthand(head).map { String(cString: $0) }
    }

    private var workingDirectory: URL {
        get throws {
            guard let path = git_repository_workdir(repository) else {
                throw AppError.repositoryNotSet
            }
            return URL(fileURLWithPath: String(cString: path))
        }
    }

    public func checkoutAndChangeBranch(branchName: String, progressBlock: @escaping CheckoutProgressHandler) throws {
        self.branchName = branchName
        var branch: OpaquePointer?
        if git_branch_lookup(&branch, repository, branchName, GIT_BRANCH_LOCAL) != 0 {
            let remoteBranchName = "origin/\(branchName)"
            var remoteBranch: OpaquePointer?
            guard git_branch_lookup(&remoteBranch, repository, remoteBranchName, GIT_BRANCH_REMOTE) == 0 else {
                throw AppError.repositoryRemoteBranchNotFound(branchName: remoteBranchName)
            }
            defer { git_reference_free(remoteBranch) }
            var commit: OpaquePointer?
            try Git.check(git_reference_peel(&commit, remoteBranch, GIT_OBJECT_COMMIT))
            defer { git_object_free(commit) }
            try Git.check(git_branch_create(&branch, repository, branchName, commit, 0))
            try Git.check(git_branch_set_upstream(branch, remoteBranchName))
        }
        defer { git_reference_free(branch) }
        var commit: OpaquePointer?
        try Git.check(git_reference_peel(&commit, branch, GIT_OBJECT_COMMIT))
        defer { git_object_free(commit) }
        try checkout(commit, progressBlock: progressBlock)
        try Git.check(git_repository_set_head(repository, git_reference_name(branch)))
    }

    public func pull(
        options: GitRemoteOptions,
        signature: GitSignature,
        transferProgressBlock: @escaping TransferProgressHandler
    ) throws {
        let callbacks = RemoteCallbacks(options: options, transferProgress: transferProgressBlock)
        try withRemote { remote in
            var fetchOptions = git_fetch_options()
            git_fetch_options_init(&fetchOptions, UInt32(GIT_FETCH_OPTIONS_VERSION))
            try withExtendedLifetime(callbacks) {
                fetchOptions.callbacks = callbacks.rawCallbacks
                try callbacks.check(git_remote_fetch(remote, nil, &fetchOptions, nil))
            }
        }
        try mergeRemoteBranch(signature: signature)
    }

    public func getRecentCommits(count: Int) throws -> [GitCommit] {
        try commits(limit: count)
    }

    public func add(path: String) throws {
        try withIndex { index in
            try Git.check(git_index_add_bypath(index, path))
            try Git.check(git_index_write(index))
        }
    }

    public func rm(path: String) throws {
        let url = try workingDirectory.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try withIndex { index in
            try Git.check(git_index_remove_bypath(index, path))
            try Git.check(git_index_write(index))
        }
    }

    public func mv(from: String, to: String) throws {
        let workingDirectory = try workingDirectory
        let fromURL = workingDirectory.appendingPathComponent(from)
        let toURL = workingDirectory.appendingPathComponent(to)
        try FileManager.default.moveItem(at: fromURL, to: toURL)
        try add(path: to)
        try rm(path: from)
    }

    public func commit(name: String, email: String, message: String) throws -> GitCommit {
        try commit(signature: GitSignature(name: name, email: email), message: message)
    }

    public func commit(signature: GitSignature, message: String) throws -> GitCommit {
        var treeOID = git_oid()
        try withIndex { index in
            try Git.check(git_index_write_tree(&treeOID, index))
        }
        var parents: [OpaquePointer?] = []
        defer { parents.forEach { git_commit_free($0) } }
        if !isHEADUnborn {
            var headOID = git_oid()
            try Git.check(git_reference_name_to_id(&headOID, repository, "HEAD"))
            parents.append(try lookUpCommit(headOID))
        }
        return try createCommit(treeOID: treeOID, parents: &parents, signature: signature, message: message)
    }

    public func push(options: GitRemoteOptions, transferProgressBlock: @escaping PushProgressHandler) throws {
        try push(branch: currentBranchName ?? branchName, options: options, transferProgressBlock: transferProgressBlock)
    }

    func push(branch: String, options: GitRemoteOptions, transferProgressBlock: @escaping PushProgressHandler = { _, _ in }) throws {
        let callbacks = RemoteCallbacks(options: options, pushProgress: transferProgressBlock)
        try withRemote { remote in
            var pushOptions = git_push_options()
            git_push_options_init(&pushOptions, UInt32(GIT_PUSH_OPTIONS_VERSION))
            try withExtendedLifetime(callbacks) {
                pushOptions.callbacks = callbacks.rawCallbacks
                try Git.withStringArray(["refs/heads/\(branch):refs/heads/\(branch)"]) { refspecs in
                    try callbacks.check(git_remote_push(remote, refspecs, &pushOptions))
                }
            }
        }
        // The server may reject a reference without failing the push as a whole.
        guard !callbacks.pushRejected else {
            throw AppError.gitPushNotSuccessful
        }
    }

    /// The commits that have not been pushed yet, newest first. If the branch does not exist on the remote, all
    /// commits are local.
    public func getLocalCommits() throws -> [GitCommit] {
        try commits(hiding: "refs/remotes/origin/\(branchName)")
    }

    public func numberOfCommits() -> Int {
        (try? withRevisionWalk { walk in
            var count = 0
            var oid = git_oid()
            while git_revwalk_next(&oid, walk) == 0 {
                count += 1
            }
            return count
        }) ?? 0
    }

    public func reset() throws {
        let localCommits = try getLocalCommits()
        if localCommits.isEmpty {
            return
        }
        guard let firstLocalCommit = localCommits.last,
              firstLocalCommit.parentOIDs.count == 1,
              let newHead = firstLocalCommit.parentOIDs.first else {
            throw AppError.gitReset
        }
        var oid = git_oid()
        try Git.check(git_oid_fromstr(&oid, newHead))
        var commit: OpaquePointer?
        try Git.check(git_object_lookup(&commit, repository, &oid, GIT_OBJECT_COMMIT))
        defer { git_object_free(commit) }
        try Git.check(git_reset(repository, commit, GIT_RESET_HARD, nil))
    }

    public func lastCommitDate(path: String) throws -> Date {
        var blame: OpaquePointer?
        try Git.check(git_blame_file(&blame, repository, path, nil))
        defer { git_blame_free(blame) }
        let times = (0 ..< git_blame_hunkcount(blame)).compactMap { index in
            git_blame_hunk_byindex(blame, index)?.pointee.final_signature?.pointee.when.time
        }
        return Date(timeIntervalSince1970: TimeInterval(times.max() ?? 0))
    }

    // MARK: - Used by tests.

    static func initializeBareRepository(at url: URL) throws {
        Git.initialize()
        var repository: OpaquePointer?
        try Git.check(git_repository_init(&repository, url.path, 1))
        git_repository_free(repository)
    }

    func createBranch(named name: String) throws {
        var headOID = git_oid()
        try Git.check(git_reference_name_to_id(&headOID, repository, "HEAD"))
        let commit = try lookUpCommit(headOID)
        defer { git_commit_free(commit) }
        var branch: OpaquePointer?
        try Git.check(git_branch_create(&branch, repository, name, commit, 0))
        git_reference_free(branch)
    }

    // MARK: - Private

    private func mergeRemoteBranch(signature: GitSignature) throws {
        var theirOID = git_oid()
        guard git_reference_name_to_id(&theirOID, repository, "refs/remotes/origin/\(branchName)") == 0 else {
            // Nothing to merge from an empty remote.
            return
        }
        var theirHead: OpaquePointer?
        try Git.check(git_annotated_commit_lookup(&theirHead, repository, &theirOID))
        defer { git_annotated_commit_free(theirHead) }
        var heads: [OpaquePointer?] = [theirHead]
        var analysis = git_merge_analysis_t(rawValue: 0)
        var preference = git_merge_preference_t(rawValue: 0)
        try Git.check(git_merge_analysis(&analysis, &preference, repository, &heads, 1))

        if analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue != 0 {
            return
        }
        if analysis.rawValue & (GIT_MERGE_ANALYSIS_UNBORN.rawValue | GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue) != 0 {
            try fastForward(to: theirOID)
            return
        }
        try merge(theirOID, signature: signature)
    }

    private func fastForward(to oid: git_oid) throws {
        var oid = oid
        var commit: OpaquePointer?
        try Git.check(git_object_lookup(&commit, repository, &oid, GIT_OBJECT_COMMIT))
        defer { git_object_free(commit) }
        try checkout(commit)
        let referenceName = "refs/heads/\(branchName)"
        var reference: OpaquePointer?
        try Git.check(git_reference_create(&reference, repository, referenceName, &oid, 1, "pull: fast-forward"))
        git_reference_free(reference)
        try Git.check(git_repository_set_head(repository, referenceName))
    }

    /// Merge in memory first, so that the working directory stays untouched if there are conflicts.
    private func merge(_ theirOID: git_oid, signature: GitSignature) throws {
        var ourOID = git_oid()
        try Git.check(git_reference_name_to_id(&ourOID, repository, "HEAD"))
        var parents: [OpaquePointer?] = [try lookUpCommit(ourOID)]
        defer { parents.forEach { git_commit_free($0) } }
        parents.append(try lookUpCommit(theirOID))

        var index: OpaquePointer?
        try Git.check(git_merge_commits(&index, repository, parents[0], parents[1], nil))
        defer { git_index_free(index) }
        if git_index_has_conflicts(index) != 0 {
            throw AppError.gitMergeConflict(files: try conflictedPaths(in: index))
        }
        var treeOID = git_oid()
        try Git.check(git_index_write_tree_to(&treeOID, index, repository))
        let message = "Merge remote-tracking branch 'origin/\(branchName)'"
        _ = try createCommit(treeOID: treeOID, parents: &parents, signature: signature, message: message)

        var options = Git.checkoutOptions()
        try Git.check(git_checkout_head(repository, &options))
    }

    private func conflictedPaths(in index: OpaquePointer?) throws -> [String] {
        var iterator: OpaquePointer?
        try Git.check(git_index_conflict_iterator_new(&iterator, index))
        defer { git_index_conflict_iterator_free(iterator) }
        var paths: [String] = []
        var ancestor: UnsafePointer<git_index_entry>?
        var ours: UnsafePointer<git_index_entry>?
        var theirs: UnsafePointer<git_index_entry>?
        while git_index_conflict_next(&ancestor, &ours, &theirs, iterator) == 0 {
            if let path = (ours ?? theirs ?? ancestor)?.pointee.path {
                paths.append(String(cString: path))
            }
        }
        return paths
    }

    private func createCommit(treeOID: git_oid, parents: inout [OpaquePointer?], signature: GitSignature, message: String) throws -> GitCommit {
        var treeOID = treeOID
        var tree: OpaquePointer?
        try Git.check(git_tree_lookup(&tree, repository, &treeOID))
        defer { git_tree_free(tree) }
        var rawSignature: UnsafeMutablePointer<git_signature>?
        let offset = TimeZone.current.secondsFromGMT(for: signature.time) / 60
        try Git.check(git_signature_new(&rawSignature, signature.name, signature.email, git_time_t(signature.time.timeIntervalSince1970), Int32(offset)))
        defer { git_signature_free(rawSignature) }
        var commitOID = git_oid()
        try Git.check(git_commit_create(&commitOID, repository, "HEAD", rawSignature, rawSignature, nil, message, tree, parents.count, &parents))
        let commit = try lookUpCommit(commitOID)
        defer { git_commit_free(commit) }
        return GitCommit(commit)
    }

    private func checkout(_ commit: OpaquePointer?, progressBlock: CheckoutProgressHandler? = nil) throws {
        var options = Git.checkoutOptions()
        let progress = progressBlock.map(CheckoutProgress.init)
        try withExtendedLifetime(progress) {
            progress?.configure(&options)
            try Git.check(git_checkout_tree(repository, commit, &options))
        }
    }

    private func lookUpCommit(_ oid: git_oid) throws -> OpaquePointer? {
        var oid = oid
        var commit: OpaquePointer?
        try Git.check(git_commit_lookup(&commit, repository, &oid))
        return commit
    }

    private func commits(hiding hiddenReference: String? = nil, limit: Int = .max) throws -> [GitCommit] {
        try withRevisionWalk { walk in
            if let hiddenReference {
                var hiddenOID = git_oid()
                if git_reference_name_to_id(&hiddenOID, repository, hiddenReference) == 0 {
                    try Git.check(git_revwalk_hide(walk, &hiddenOID))
                }
            }
            var commits: [GitCommit] = []
            var oid = git_oid()
            while commits.count < limit, git_revwalk_next(&oid, walk) == 0 {
                let commit = try lookUpCommit(oid)
                defer { git_commit_free(commit) }
                commits.append(GitCommit(commit))
            }
            return commits
        }
    }

    /// Walk the commits reachable from HEAD, newest first. There are none if HEAD is unborn.
    private func withRevisionWalk<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var walk: OpaquePointer?
        try Git.check(git_revwalk_new(&walk, repository))
        defer { git_revwalk_free(walk) }
        try Git.check(git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue))
        if !isHEADUnborn {
            try Git.check(git_revwalk_push_head(walk))
        }
        return try body(walk)
    }

    private func withIndex<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var index: OpaquePointer?
        try Git.check(git_repository_index(&index, repository))
        defer { git_index_free(index) }
        return try body(index)
    }

    private func withRemote<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var remote: OpaquePointer?
        try Git.check(git_remote_lookup(&remote, repository, "origin"))
        defer { git_remote_free(remote) }
        return try body(remote)
    }
}

private extension GitCommit {
    init(_ commit: OpaquePointer?) {
        self.oid = String(cString: git_oid_tostr_s(git_commit_id(commit)))
        self.message = git_commit_message(commit).map { String(cString: $0) }
        self.author = git_commit_author(commit).map { GitSignature($0.pointee) }
        self.commitDate = Date(timeIntervalSince1970: TimeInterval(git_commit_time(commit)))
        self.parentOIDs = (0 ..< git_commit_parentcount(commit)).map { String(cString: git_oid_tostr_s(git_commit_parent_id(commit, $0))) }
    }
}

private extension GitSignature {
    init(_ signature: git_signature) {
        self.init(
            name: String(cString: signature.name),
            email: String(cString: signature.email),
            time: Date(timeIntervalSince1970: TimeInterval(signature.when.time))
        )
    }
}

private enum Git {
    private static let initialization: Void = {
        _ = git_libgit2_init()
    }()

    static func initialize() {
        _ = initialization
    }

    @discardableResult
    static func check(_ result: Int32) throws -> Int32 {
        guard result < 0 else {
            return result
        }
        let message = git_error_last().map { String(cString: $0.pointee.message) } ?? "Unknown error"
        throw GitError(code: result, message: message)
    }

    /// Checkout options that overwrite the working directory, which only contains committed changes.
    static func checkoutOptions() -> git_checkout_options {
        var options = git_checkout_options()
        git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        options.checkout_strategy = GIT_CHECKOUT_FORCE.rawValue
        return options
    }

    static func withStringArray<T>(_ strings: [String], _ body: (UnsafePointer<git_strarray>) throws -> T) rethrows -> T {
        var pointers = strings.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            var array = git_strarray(strings: buffer.baseAddress, count: buffer.count)
            return try withUnsafePointer(to: &array, body)
        }
    }
}

/// Bridges the C callbacks of a remote operation to the options and progress handlers. It must stay alive as long as
/// libgit2 may call back, see `withExtendedLifetime`.
private final class RemoteCallbacks {
    private let options: GitRemoteOptions
    private let transferProgress: TransferProgressHandler?
    private let pushProgress: PushProgressHandler?

    /// An error raised in a callback, which explains a failure better than libgit2's own message.
    private var error: Error?
    private(set) var pushRejected = false

    init(options: GitRemoteOptions, transferProgress: TransferProgressHandler? = nil, pushProgress: PushProgressHandler? = nil) {
        self.options = options
        self.transferProgress = transferProgress
        self.pushProgress = pushProgress
    }

    var rawCallbacks: git_remote_callbacks {
        var callbacks = git_remote_callbacks()
        git_remote_init_callbacks(&callbacks, UInt32(GIT_REMOTE_CALLBACKS_VERSION))
        callbacks.payload = Unmanaged.passUnretained(self).toOpaque()
        callbacks.credentials = { out, _, _, allowedTypes, payload in
            RemoteCallbacks.from(payload).credential(out, allowedTypes: allowedTypes)
        }
        callbacks.certificate_check = { certificate, _, host, payload in
            RemoteCallbacks.from(payload).checkCertificate(certificate, host: host)
        }
        callbacks.transfer_progress = { stats, payload in
            if let stats {
                let progress = GitTransferProgress(receivedObjects: Int(stats.pointee.received_objects), totalObjects: Int(stats.pointee.total_objects))
                RemoteCallbacks.from(payload).transferProgress?(progress)
            }
            return 0
        }
        callbacks.push_transfer_progress = { current, total, _, payload in
            RemoteCallbacks.from(payload).pushProgress?(Int(current), Int(total))
            return 0
        }
        callbacks.push_update_reference = { _, status, payload in
            if status != nil {
                RemoteCallbacks.from(payload).pushRejected = true
            }
            return 0
        }
        return callbacks
    }

    /// Like `Git.check`, but prefer the error raised in a callback.
    func check(_ result: Int32) throws {
        if result < 0, let error {
            throw error
        }
        try Git.check(result)
    }

    private static func from(_ payload: UnsafeMutableRawPointer?) -> RemoteCallbacks {
        Unmanaged<RemoteCallbacks>.fromOpaque(payload!).takeUnretainedValue()
    }

    private func credential(_ out: UnsafeMutablePointer<OpaquePointer?>?, allowedTypes: UInt32) -> Int32 {
        guard let credential = options.credential(allowedTypes == GIT_CREDENTIAL_USERNAME.rawValue) else {
            error = AppError.gitAuthentication
            return GIT_EUSER.rawValue
        }
        switch credential {
        case let .username(userName):
            return git_credential_username_new(out, userName)
        case let .password(userName, password):
            return git_credential_userpass_plaintext_new(out, userName, password)
        case let .sshKey(userName, privateKey, passphrase):
            return git_credential_ssh_key_memory_new(out, userName, nil, privateKey, passphrase)
        }
    }

    /// Verify SSH host keys. libgit2 checks HTTPS certificates against the system trust store itself.
    private func checkCertificate(_ certificate: UnsafeMutablePointer<git_cert>?, host: UnsafePointer<CChar>?) -> Int32 {
        guard let certificate, certificate.pointee.cert_type == GIT_CERT_HOSTKEY_LIBSSH2, let host else {
            return GIT_PASSTHROUGH.rawValue
        }
        let hostKey = UnsafeRawPointer(certificate).assumingMemoryBound(to: git_cert_hostkey.self).pointee
        guard let fingerprint = Self.fingerprint(of: hostKey) else {
            return GIT_ECERTIFICATE.rawValue
        }
        do {
            try options.hostKeys.verify(host: String(cString: host), fingerprint: fingerprint, approve: options.approveHostKey)
            return 0
        } catch {
            self.error = error
            return GIT_ECERTIFICATE.rawValue
        }
    }

    private static func fingerprint(of hostKey: git_cert_hostkey) -> String? {
        if hostKey.type.rawValue & GIT_CERT_SSH_SHA256.rawValue != 0 {
            return GitHostKeys.fingerprint(sha256: withUnsafeBytes(of: hostKey.hash_sha256) { Data($0) })
        }
        if hostKey.type.rawValue & GIT_CERT_SSH_RAW.rawValue != 0, let rawKey = hostKey.hostkey {
            return GitHostKeys.fingerprint(sha256: Data(SHA256.hash(data: Data(bytes: rawKey, count: hostKey.hostkey_len))))
        }
        return nil
    }
}

private final class CheckoutProgress {
    private let handler: CheckoutProgressHandler

    init(_ handler: @escaping CheckoutProgressHandler) {
        self.handler = handler
    }

    func configure(_ options: inout git_checkout_options) {
        options.progress_payload = Unmanaged.passUnretained(self).toOpaque()
        options.progress_cb = { path, completedSteps, totalSteps, payload in
            let progress = Unmanaged<CheckoutProgress>.fromOpaque(payload!).takeUnretainedValue()
            progress.handler(path.map { String(cString: $0) } ?? "", completedSteps, totalSteps)
        }
    }
}
