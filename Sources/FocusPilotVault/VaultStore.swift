import Foundation
import FocusPilotCore

public struct VaultManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var vaultID: UUID
    public var currentSnapshot: String?

    public init(schemaVersion: Int = 1, vaultID: UUID, currentSnapshot: String? = nil) {
        self.schemaVersion = schemaVersion
        self.vaultID = vaultID
        self.currentSnapshot = currentSnapshot
    }
}

public struct VaultSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var state: AppState
    public var frontier: [String: Int64]

    public init(schemaVersion: Int = 1, createdAt: Date = .now, state: AppState, frontier: [UUID: Int64]) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.state = state
        self.frontier = Dictionary(uniqueKeysWithValues: frontier.map { ($0.key.uuidString, $0.value) })
    }

    public var uuidFrontier: [UUID: Int64] {
        Dictionary(uniqueKeysWithValues: frontier.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }
}

public struct CompactionReport: Sendable {
    public var prunedOperations: Int
    public var prunedSnapshots: Int
    public var snapshotFilename: String
}

public enum VaultStoreError: LocalizedError {
    case missingManifest
    case missingSnapshot(String)
    case snapshotVerificationFailed
    case compactionNotNeeded

    public var errorDescription: String? {
        switch self {
        case .missingManifest: "The selected folder is not a FocusPilot vault."
        case .missingSnapshot(let name): "The vault snapshot \(name) is missing."
        case .snapshotVerificationFailed: "The compacted snapshot did not reproduce the current state."
        case .compactionNotNeeded: "The vault is below its compaction thresholds."
        }
    }
}

public actor VaultStore {
    public let repositoryURL: URL
    public let vaultID: UUID
    public let deviceID: UUID

    private let key: Data
    private let git: GitClient
    private var state: AppState
    private var frontier: [UUID: Int64]
    private var lastTimestamp: LogicalTimestamp
    private var commitTask: Task<Void, Never>?
    private var pendingChanges = 0

    private var vaultURL: URL { repositoryURL.appending(path: "vault", directoryHint: .isDirectory) }
    private var operationsURL: URL { vaultURL.appending(path: "operations", directoryHint: .isDirectory) }
    private var snapshotsURL: URL { vaultURL.appending(path: "snapshots", directoryHint: .isDirectory) }
    private var quarantineURL: URL { vaultURL.appending(path: "quarantine", directoryHint: .isDirectory) }
    private var manifestURL: URL { vaultURL.appending(path: "manifest.json") }

    private init(
        repositoryURL: URL,
        vaultID: UUID,
        deviceID: UUID,
        key: Data,
        state: AppState,
        frontier: [UUID: Int64]
    ) {
        self.repositoryURL = repositoryURL
        self.vaultID = vaultID
        self.deviceID = deviceID
        self.key = key
        self.git = GitClient(repositoryURL: repositoryURL)
        self.state = state
        self.frontier = frontier
        self.lastTimestamp = .init(milliseconds: Int64(Date.now.timeIntervalSince1970 * 1000))
    }

    public static func create(repositoryURL: URL, deviceID: UUID = UUID()) async throws -> (VaultStore, Data) {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        let git = GitClient(repositoryURL: repositoryURL)
        try git.initializeIfNeeded()

        let vaultID = UUID()
        let key = VaultCrypto.generateKey()
        let vaultURL = repositoryURL.appending(path: "vault", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: vaultURL.appending(path: "operations"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: vaultURL.appending(path: "snapshots"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: vaultURL.appending(path: "quarantine"), withIntermediateDirectories: true)
        let manifest = VaultManifest(vaultID: vaultID)
        try JSONEncoder.vaultEncoder.encode(manifest)
            .write(to: vaultURL.appending(path: "manifest.json"), options: .atomic)
        _ = try git.commitVaultChanges(message: "FocusPilot: initialize encrypted vault")

        let store = VaultStore(
            repositoryURL: repositoryURL,
            vaultID: vaultID,
            deviceID: deviceID,
            key: key,
            state: .init(),
            frontier: [:]
        )
        return (store, key)
    }

    public static func open(repositoryURL: URL, key: Data, deviceID: UUID) async throws -> VaultStore {
        let manifestURL = repositoryURL.appending(path: "vault/manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw VaultStoreError.missingManifest }
        let vaultURL = repositoryURL.appending(path: "vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL.appending(path: "operations"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultURL.appending(path: "snapshots"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultURL.appending(path: "quarantine"), withIntermediateDirectories: true)
        let manifest = try JSONDecoder.vaultDecoder.decode(VaultManifest.self, from: Data(contentsOf: manifestURL))
        let loaded = try loadState(repositoryURL: repositoryURL, manifest: manifest, key: key)
        return VaultStore(
            repositoryURL: repositoryURL,
            vaultID: manifest.vaultID,
            deviceID: deviceID,
            key: key,
            state: loaded.state,
            frontier: loaded.frontier
        )
    }

    public func currentState() -> AppState { state }

    @discardableResult
    public func append(_ mutation: VaultMutation) throws -> VaultOperation {
        let nextSequence = (frontier[deviceID] ?? 0) + 1
        let now = Int64(Date.now.timeIntervalSince1970 * 1000)
        let timestamp: LogicalTimestamp
        if now > lastTimestamp.milliseconds {
            timestamp = .init(milliseconds: now)
        } else {
            timestamp = .init(milliseconds: lastTimestamp.milliseconds, counter: lastTimestamp.counter + 1)
        }
        lastTimestamp = timestamp

        let operation = VaultOperation(
            deviceID: deviceID,
            deviceSequence: nextSequence,
            timestamp: timestamp,
            mutation: mutation
        )
        let envelope = try VaultCrypto.encrypt(operation, key: key)
        let data = try JSONEncoder.vaultEncoder.encode(envelope)
        try data.write(to: operationsURL.appending(path: "\(operation.eventID.uuidString).json"), options: .atomic)
        let persistedOperation = try VaultCrypto.decrypt(VaultOperation.self, envelope: envelope, key: key)
        let reduction = StateReducer.reduce(base: state, frontier: frontier, operations: [persistedOperation])
        state = reduction.state
        frontier = reduction.frontier
        pendingChanges += 1
        scheduleCommit()
        return operation
    }

    public func commitPending() throws {
        commitTask?.cancel()
        commitTask = nil
        guard pendingChanges > 0 else { return }
        let count = pendingChanges
        if try git.commitVaultChanges(message: "FocusPilot: save \(count) change\(count == 1 ? "" : "s")") {
            pendingChanges = 0
            _ = try? compact(force: false)
        }
    }

    public func compact(force: Bool = false) throws -> CompactionReport {
        try commitPending()
        try git.ensureNoUnrelatedChanges()
        let operationFiles = try jsonFiles(in: operationsURL)
        let byteCount = try operationFiles.reduce(0) {
            $0 + Int((try $1.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        }
        if !force && operationFiles.count < 500 && byteCount < 10_000_000 {
            throw VaultStoreError.compactionNotNeeded
        }

        let snapshot = VaultSnapshot(state: state, frontier: frontier)
        let envelope = try VaultCrypto.encrypt(snapshot, key: key)
        let snapshotFilename = "\(UUID().uuidString).json"
        let snapshotURL = snapshotsURL.appending(path: snapshotFilename)
        try JSONEncoder.vaultEncoder.encode(envelope).write(to: snapshotURL, options: .atomic)

        var manifest = try readManifest()
        manifest.currentSnapshot = snapshotFilename
        try JSONEncoder.vaultEncoder.encode(manifest).write(to: manifestURL, options: .atomic)
        _ = try git.commitVaultChanges(message: "FocusPilot: create verified vault snapshot")

        let verifiedEnvelope = try JSONDecoder.vaultDecoder.decode(EncryptedEnvelope.self, from: Data(contentsOf: snapshotURL))
        let verified = try VaultCrypto.decrypt(VaultSnapshot.self, envelope: verifiedEnvelope, key: key)
        guard verified.state == state && verified.uuidFrontier == frontier else {
            throw VaultStoreError.snapshotVerificationFailed
        }

        var prunedOperations = 0
        for file in operationFiles {
            let envelope = try JSONDecoder.vaultDecoder.decode(EncryptedEnvelope.self, from: Data(contentsOf: file))
            let operation = try VaultCrypto.decrypt(VaultOperation.self, envelope: envelope, key: key)
            if operation.deviceSequence <= (frontier[operation.deviceID] ?? 0) {
                try FileManager.default.removeItem(at: file)
                prunedOperations += 1
            }
        }

        var prunedSnapshots = 0
        for file in try jsonFiles(in: snapshotsURL) where file.lastPathComponent != snapshotFilename {
            try FileManager.default.removeItem(at: file)
            prunedSnapshots += 1
        }
        _ = try git.commitVaultChanges(message: "FocusPilot: prune superseded vault files")
        return CompactionReport(
            prunedOperations: prunedOperations,
            prunedSnapshots: prunedSnapshots,
            snapshotFilename: snapshotFilename
        )
    }

    public func sync() throws -> AppState {
        try commitPending()
        guard try git.hasRemote() else { return state }
        try git.fetch()
        try git.pullRebase()
        let manifest = try readManifest()
        let loaded = try Self.loadState(repositoryURL: repositoryURL, manifest: manifest, key: key)
        state = loaded.state
        frontier = loaded.frontier
        try git.push()
        return state
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            try? await self?.commitPending()
        }
    }

    private func readManifest() throws -> VaultManifest {
        try JSONDecoder.vaultDecoder.decode(VaultManifest.self, from: Data(contentsOf: manifestURL))
    }

    private func jsonFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
    }

    private static func loadState(
        repositoryURL: URL,
        manifest: VaultManifest,
        key: Data
    ) throws -> ReductionResult {
        let vaultURL = repositoryURL.appending(path: "vault", directoryHint: .isDirectory)
        var state = AppState()
        var frontier: [UUID: Int64] = [:]

        if let snapshotName = manifest.currentSnapshot {
            let snapshotURL = vaultURL.appending(path: "snapshots/\(snapshotName)")
            guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
                throw VaultStoreError.missingSnapshot(snapshotName)
            }
            let envelope = try JSONDecoder.vaultDecoder.decode(EncryptedEnvelope.self, from: Data(contentsOf: snapshotURL))
            let snapshot = try VaultCrypto.decrypt(VaultSnapshot.self, envelope: envelope, key: key)
            state = snapshot.state
            frontier = snapshot.uuidFrontier
        }

        let operationsURL = vaultURL.appending(path: "operations", directoryHint: .isDirectory)
        let urls = try FileManager.default.contentsOfDirectory(
            at: operationsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        let operations = try urls.map { url in
            let envelope = try JSONDecoder.vaultDecoder.decode(EncryptedEnvelope.self, from: Data(contentsOf: url))
            return try VaultCrypto.decrypt(VaultOperation.self, envelope: envelope, key: key)
        }
        var reduction = StateReducer.reduce(base: state, frontier: frontier, operations: operations)
        reduction.state.schemaVersion = AppState.currentSchemaVersion
        return reduction
    }
}
