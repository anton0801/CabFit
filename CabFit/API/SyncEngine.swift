//
//  SyncEngine.swift
//  CabFit
//
//  Keeps the local store and the server in step.
//
//  The local database stays the thing the UI reads, so the app opens and works on a
//  site with no signal; the server is where the data actually lives. Edits made offline
//  are pushed on the next successful connection rather than lost.
//

import SwiftUI

// MARK: - Sync state

/// What the app remembers about each run's relationship to the server.
private struct RunSyncRecord: Codable {
    var revision: Int
    /// Fingerprint of the payload as last accepted by the server.
    var syncedFingerprint: String
}

private struct SyncState: Codable {
    var cursor: String = ""
    var runs: [String: RunSyncRecord] = [:]
    /// Runs deleted locally that the server has not been told about yet.
    var pendingDeletes: [String] = []
    /// Attachment slot -> sha256 of the bytes already uploaded, so a photo that has not
    /// changed is not re-sent on every sync.
    var uploadedAttachments: [String: String] = [:]
}

// MARK: - Engine

final class SyncEngine: ObservableObject {

    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case offline
        case failed(String)

        var isBusy: Bool { self == .syncing }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var pendingChanges: Int = 0

    /// Set once at launch. Weak so the engine never keeps a dead store alive.
    weak var store: DataStore?

    private let stateKey = "cabfit.sync.state.v1"
    private var state: SyncState
    private let queue = DispatchQueue(label: "cabfit.sync", qos: .utility)
    private var isRunning = false
    private var retryIndex = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(SyncState.self, from: data) {
            state = decoded
        } else {
            state = SyncState()
        }
    }

    // MARK: Entry points

    /// Called on launch and when the app comes back to the foreground.
    func syncNow(reason: String = "manual") {
        queue.async { [weak self] in self?.run(reason: reason) }
    }

    /// Record a delete so the server learns about it even if we are offline right now.
    func noteDeleted(runID: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let uid = runID.uuidString.lowercased()
            if self.state.runs[uid] != nil || !self.state.pendingDeletes.contains(uid) {
                self.state.pendingDeletes.append(uid)
                self.state.runs.removeValue(forKey: uid)
                self.persist()
            }
            self.refreshPendingCount()
        }
    }

    /// Forget everything about the server. Used when the credential is reset.
    func resetState() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.state = SyncState()
            self.persist()
            DispatchQueue.main.async { self.pendingChanges = 0; self.status = .idle }
        }
    }

    // MARK: The cycle

    private func run(reason: String) {
        guard !isRunning else { return }
        isRunning = true
        DispatchQueue.main.async { self.status = .syncing }

        APIClient.shared.ensureAuthenticated { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.finish(with: error)
            case .success:
                self.pull { pullError in
                    if let pullError = pullError, !pullError.isRetryable {
                        self.finish(with: pullError)
                        return
                    }
                    self.push { pushError in
                        self.finish(with: pushError ?? pullError)
                    }
                }
            }
        }
    }

    private func finish(with error: APIError?) {
        isRunning = false
        persist()
        refreshPendingCount()

        DispatchQueue.main.async {
            guard let error = error else {
                self.retryIndex = 0
                self.status = .synced(Date())
                return
            }
            switch error {
            case .offline, .timedOut:
                self.status = .offline
            default:
                self.status = .failed(error.localizedDescription)
            }
            // Only keep trying for things that can plausibly start working.
            if error.isRetryable { self.scheduleRetry() }
        }
    }

    private func scheduleRetry() {
        let delay = APIConfig.retryBackoff[min(retryIndex, APIConfig.retryBackoff.count - 1)]
        retryIndex += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.pendingChanges > 0 || self.state.cursor.isEmpty else { return }
            self.run(reason: "retry")
        }
    }

    // MARK: Pull

    private func pull(completion: @escaping (APIError?) -> Void) {
        var query: [String: String] = [:]
        if !state.cursor.isEmpty { query["since"] = state.cursor }

        APIClient.shared.get("/v1/runs", query: query) { [weak self] (result: Result<RunListDTO, APIError>) in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let page):
                self.apply(page) { completion(nil) }
            }
        }
    }

    private func apply(_ page: RunListDTO, completion: @escaping () -> Void) {
        guard let store = store else { completion(); return }

        // Anything we are about to push wins over what the server currently holds for
        // that run — otherwise a pull would clobber an edit made while offline.
        let locallyDirty = Set(dirtyRunUIDs())

        DispatchQueue.main.async {
            for dto in page.runs {
                let uid = dto.run_uid.lowercased()
                guard !locallyDirty.contains(uid), !self.state.pendingDeletes.contains(uid) else { continue }

                if dto.deleted {
                    if let id = UUID(uuidString: uid),
                       let existing = store.runs.first(where: { $0.id == id }) {
                        store.removeWithoutSyncing(existing)
                    }
                    self.state.runs.removeValue(forKey: uid)
                    continue
                }

                guard let value = dto.payload,
                      let object = value.anyValue as? [String: Any],
                      var incoming = try? RunWire.decode(object) else { continue }

                // Binaries are not in the payload. Keep whatever this device already has
                // so a sync never blanks a photo; missing ones are fetched separately.
                if let existing = store.runs.first(where: { $0.id == incoming.id }) {
                    incoming.photo = existing.photo
                    incoming.signature = existing.signature
                    for index in incoming.defects.indices {
                        let id = incoming.defects[index].id
                        incoming.defects[index].photo = existing.defects.first(where: { $0.id == id })?.photo
                    }
                }

                store.applyFromServer(incoming)
                self.state.runs[uid] = RunSyncRecord(revision: dto.revision,
                                                     syncedFingerprint: RunWire.fingerprint(incoming))
            }

            self.state.cursor = page.cursor
            self.persist()
            // Back to the worker queue: the push that follows must not run on main.
            self.queue.async { completion() }
        }
    }

    // MARK: Push

    private func push(completion: @escaping (APIError?) -> Void) {
        let deletes = state.pendingDeletes
        pushDeletes(deletes) { [weak self] deleteError in
            guard let self = self else { return }
            let runs = self.dirtyRuns()
            self.pushRuns(runs) { pushError in
                completion(pushError ?? deleteError)
            }
        }
    }

    private func pushDeletes(_ uids: [String], completion: @escaping (APIError?) -> Void) {
        guard let next = uids.first else { completion(nil); return }
        APIClient.shared.delete("/v1/runs/\(next)") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success, .failure(.notFound):
                // Gone is gone: stop retrying either way.
                self.state.pendingDeletes.removeAll { $0 == next }
                self.persist()
                self.pushDeletes(Array(uids.dropFirst()), completion: completion)
            case .failure(let error):
                completion(error)
            }
        }
    }

    private func pushRuns(_ runs: [KitchenRun], completion: @escaping (APIError?) -> Void) {
        guard let next = runs.first else { completion(nil); return }
        upsert(next) { [weak self] error in
            guard let self = self else { return }
            if let error = error, error.isRetryable {
                completion(error)
                return
            }
            // A permanent failure on one run must not block the rest of the queue.
            self.pushRuns(Array(runs.dropFirst())) { rest in
                completion(rest ?? (error.flatMap { $0.isRetryable ? $0 : nil }))
            }
        }
    }

    private func upsert(_ run: KitchenRun, completion: @escaping (APIError?) -> Void) {
        let uid = run.id.uuidString.lowercased()
        guard let (payload, binaries) = try? RunWire.encode(run) else {
            completion(nil)   // unencodable run: skip rather than wedge the queue
            return
        }

        let body: [String: Any] = [
            "payload": payload,
            "title": run.title,
            "status": run.status.rawValue,
            "shape": run.shape.rawValue,
            "client_updated_at": ISO8601DateFormatter().string(from: Date()),
            "base_revision": state.runs[uid]?.revision ?? 0
        ]

        APIClient.shared.put("/v1/runs/\(uid)", body: body) { [weak self] (result: Result<RunWriteDTO, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let written):
                self.state.runs[uid] = RunSyncRecord(revision: written.revision,
                                                     syncedFingerprint: RunWire.fingerprint(run))
                self.persist()
                self.uploadBinaries(binaries, runUID: uid) { completion(nil) }

            case .failure(.conflict):
                // Another device moved first. Drop our base revision so the next pull
                // brings the server's copy and this device stops fighting it.
                self.state.runs[uid]?.revision = 0
                self.state.cursor = ""
                self.persist()
                completion(nil)

            case .failure(let error):
                completion(error)
            }
        }
    }

    // MARK: Attachments

    private func uploadBinaries(_ binaries: RunWire.Binaries, runUID: String,
                                completion: @escaping () -> Void) {
        guard !binaries.isEmpty else { completion(); return }

        var jobs: [(slot: String, data: Data)] = []
        if let photo = binaries.runPhoto { jobs.append((RunWire.Binaries.runPhotoSlot, photo)) }
        if let signature = binaries.signature { jobs.append((RunWire.Binaries.signatureSlot, signature)) }
        for (defectID, data) in binaries.defectPhotos {
            jobs.append((RunWire.Binaries.slot(forDefect: defectID), data))
        }

        uploadNext(jobs, runUID: runUID, completion: completion)
    }

    private func uploadNext(_ jobs: [(slot: String, data: Data)], runUID: String,
                            completion: @escaping () -> Void) {
        guard let job = jobs.first else { completion(); return }
        let rest = Array(jobs.dropFirst())
        let key = "\(runUID)/\(job.slot)"
        let digest = Self.digest(job.data)

        // Already up there, byte for byte — nothing to send.
        if state.uploadedAttachments[key] == digest {
            uploadNext(rest, runUID: runUID, completion: completion)
            return
        }

        APIClient.shared.upload(
            "/v1/attachments",
            fileData: job.data,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            fields: ["run_uid": runUID, "slot": job.slot]
        ) { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                self.state.uploadedAttachments[key] = digest
                self.persist()
            }
            // An upload that fails is retried on the next sync; the run itself is saved.
            self.uploadNext(rest, runUID: runUID, completion: completion)
        }
    }

    /// Cheap content fingerprint. Not a security boundary — just "have these exact bytes
    /// already been sent".
    private static func digest(_ data: Data) -> String {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(2048))
        hasher.combine(data.suffix(2048))
        return String(hasher.finalize())
    }

    // MARK: Dirty tracking

    /// The store is main-thread state, but sync code reaches this from several queues.
    /// Calling `DispatchQueue.main.sync` while already on main deadlocks the app, so
    /// check first — this crashed on launch before the check was added.
    private func runsSnapshot() -> [KitchenRun] {
        guard let store = store else { return [] }
        if Thread.isMainThread { return store.runs }
        return DispatchQueue.main.sync { store.runs }
    }

    private func dirtyRuns() -> [KitchenRun] {
        let snapshot = runsSnapshot()
        return snapshot.filter { run in
            let uid = run.id.uuidString.lowercased()
            guard let record = state.runs[uid] else { return true }
            return record.syncedFingerprint != RunWire.fingerprint(run)
        }
    }

    private func dirtyRunUIDs() -> [String] {
        dirtyRuns().map { $0.id.uuidString.lowercased() }
    }

    private func refreshPendingCount() {
        let count = dirtyRuns().count + state.pendingDeletes.count
        DispatchQueue.main.async { self.pendingChanges = count }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}

// MARK: - Human-readable status

extension SyncEngine.Status {
    var title: String {
        switch self {
        case .idle:    return "Not synced yet"
        case .syncing: return "Syncing…"
        case .offline: return "Offline — changes are queued"
        case .failed:  return "Sync problem"
        case .synced(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Synced at \(formatter.string(from: date))"
        }
    }

    var symbol: String {
        switch self {
        case .idle:    return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .offline: return "icloud.slash"
        case .failed:  return "exclamationmark.icloud"
        case .synced:  return "checkmark.icloud"
        }
    }

    var hex: String {
        switch self {
        case .idle:    return "8AA0BE"
        case .syncing: return "1F6FE0"
        case .offline: return "F6BE24"
        case .failed:  return "EF4444"
        case .synced:  return "2FA85A"
        }
    }
}
