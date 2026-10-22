import Foundation
import Testing
import FocusPilotCore
@testable import FocusPilotVault

@Test func encryptionRoundTripAndWrongKeyFailure() throws {
    let key = VaultCrypto.generateKey()
    let task = TaskItem(title: "Encrypted")
    let envelope = try VaultCrypto.encrypt(task, key: key)
    let decrypted = try VaultCrypto.decrypt(TaskItem.self, envelope: envelope, key: key)

    #expect(decrypted.id == task.id)
    #expect(decrypted.title == task.title)
    #expect(throws: (any Error).self) {
        try VaultCrypto.decrypt(TaskItem.self, envelope: envelope, key: VaultCrypto.generateKey())
    }
}

@Test func compactionPrunesCoveredOperationsButKeepsHistory() async throws {
    let base = FileManager.default.temporaryDirectory
        .appending(path: "FocusPilotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }
    let (store, key) = try await VaultStore.create(repositoryURL: base)
    let task = TaskItem(title: "Persist me")
    try await store.append(.upsertTask(task))
    try await store.commitPending()

    let report = try await store.compact(force: true)
    let reopened = try await VaultStore.open(repositoryURL: base, key: key, deviceID: UUID())
    let state = await reopened.currentState()

    #expect(report.prunedOperations == 1)
    #expect(state.tasks[task.id]?.title == task.title)

    let history = try GitClient(repositoryURL: base).run(["log", "--all", "--oneline"]).output
    #expect(history.contains("save 1 change"))
    #expect(history.contains("prune superseded"))
}

@Test func syncReloadsOperationsFromRemote() async throws {
    let base = FileManager.default.temporaryDirectory
        .appending(path: "FocusPilotSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let remote = base.appending(path: "remote.git")
    let firstClone = base.appending(path: "first")
    let secondClone = base.appending(path: "second")
    defer { try? FileManager.default.removeItem(at: base) }
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try runGit(["init", "--bare", remote.path], at: base)

    let (firstStore, key) = try await VaultStore.create(repositoryURL: firstClone)
    let firstGit = GitClient(repositoryURL: firstClone)
    try firstGit.run(["remote", "add", "origin", remote.path])
    try firstGit.run(["push", "-u", "origin", "HEAD"])
    try runGit(["clone", remote.path, secondClone.path], at: base)

    let secondStore = try await VaultStore.open(repositoryURL: secondClone, key: key, deviceID: UUID())
    let remoteTask = TaskItem(title: "Created on another device")
    try await secondStore.append(.upsertTask(remoteTask))
    try await secondStore.commitPending()
    try GitClient(repositoryURL: secondClone).push()

    let synced = try await firstStore.sync()

    #expect(synced.tasks[remoteTask.id]?.title == remoteTask.title)
}

private func runGit(_ arguments: [String], at directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw GitError.commandFailed(arguments: arguments, status: process.terminationStatus, output: "")
    }
}
