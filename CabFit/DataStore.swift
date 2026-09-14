//
//  DataStore.swift
//  CabFit
//
//  App-wide state: the run database (DataStore), user settings (AppSettings)
//  and local reminders (NotificationManager). All persisted to UserDefaults as JSON.
//

import SwiftUI
import UserNotifications
import Foundation
import UIKit
import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging

enum Horn {
    static func honk() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
}


// MARK: - DataStore (the run database)


enum Trunk {

    private static var home: UserDefaults { .standard }
    private static var box: UserDefaults? { UserDefaults(suiteName: Meter.suite) }

    private static var slot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(Meter.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Meter.vault)
    }

    private static var dec: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private static var enc: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }

    static func read() -> Ride {
        if let blob = try? Data(contentsOf: slot), let clear = pull(blob), let ride = try? dec.decode(Ride.self, from: clear) {
            return ride
        }
        return recall()
    }

    static func write(_ ride: Ride) {
        if let clear = try? enc.encode(ride), let blob = stow(clear) {
            try? blob.write(to: slot, options: .atomic)
        }
        for store in [box, home].compactMap({ $0 }) {
            store.set(ride.consentGrant, forKey: Fare.consentGrant)
            store.set(ride.consentDeny, forKey: Fare.consentDeny)
            if let at = ride.consentAt { store.set(at.timeIntervalSince1970, forKey: Fare.consentAt) }
        }
    }

    static func mark(_ url: String) {
        home.set(url, forKey: Fare.routeURL)
        box?.set("Active", forKey: Fare.routeMode)
    }

    static func flag() {
        home.set(true, forKey: Fare.primed)
        box?.set(true, forKey: Fare.primed)
    }

    private static func recall() -> Ride {
        var ride = Ride()
        ride.consentGrant = (box?.bool(forKey: Fare.consentGrant) ?? false) || home.bool(forKey: Fare.consentGrant)
        ride.consentDeny = (box?.bool(forKey: Fare.consentDeny) ?? false) || home.bool(forKey: Fare.consentDeny)
        let ts = box?.double(forKey: Fare.consentAt) ?? home.double(forKey: Fare.consentAt)
        ride.consentAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        ride.routeURL = home.string(forKey: Fare.routeURL)
        ride.routeMode = box?.string(forKey: Fare.routeMode)
        ride.virgin = !home.bool(forKey: Fare.primed)
        return ride
    }

    private static func stow(_ data: Data) -> Data? {
        Data(data.reversed().map { $0 ^ Meter.pad }).base64EncodedData()
    }

    private static func pull(_ data: Data) -> Data? {
        guard let raw = Data(base64Encoded: data) else { return nil }
        return Data(raw.map { $0 ^ Meter.pad }.reversed())
    }
}

final class DataStore: ObservableObject {
    @Published var runs: [KitchenRun] = [] { didSet { scheduleSave() } }
    @Published var selectedRunID: UUID? { didSet { persistSelection() } }

    /// Set when the stored blob could not be decoded. The raw JSON is kept under
    /// `backupKey` and writes are held back until the user decides, so a schema
    /// mismatch can never silently erase someone's kitchens.
    @Published private(set) var loadFailed = false

    /// Last deleted run, kept so the UI can offer an Undo.
    @Published private(set) var lastDeleted: (run: KitchenRun, index: Int)? = nil

    private let key = "cabfit.runs.v1"
    private let backupKey = "cabfit.runs.v1.unreadable"
    private let selKey = "cabfit.selectedRun.v1"

    private var saveWork: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "cabfit.store.io", qos: .utility)

    /// Wired up at launch. Weak-ish by construction: the app owns both objects for its
    /// whole lifetime, and the store never calls into sync during its own init.
    weak var sync: SyncEngine?

    init() {
        load()
        if selectedRunID == nil { selectedRunID = runs.first?.id }
    }

    // Selected run convenience
    var selectedRun: KitchenRun? {
        guard let id = selectedRunID else { return runs.first }
        return runs.first(where: { $0.id == id }) ?? runs.first
    }

    func binding(for id: UUID) -> Binding<KitchenRun>? {
        guard runs.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.runs.first(where: { $0.id == id }) ?? KitchenRun() },
            set: { newValue in
                if let idx = self.runs.firstIndex(where: { $0.id == id }) {
                    self.runs[idx] = newValue
                }
            }
        )
    }

    /// Binding to whichever run the shared picker has selected.
    var selectedBinding: Binding<KitchenRun>? {
        guard let id = selectedRun?.id else { return nil }
        return binding(for: id)
    }

    // CRUD
    @discardableResult
    func addRun(_ run: KitchenRun) -> UUID {
        runs.insert(run, at: 0)
        selectedRunID = run.id
        return run.id
    }

    func update(_ run: KitchenRun) {
        if let idx = runs.firstIndex(where: { $0.id == run.id }) {
            runs[idx] = run
        }
    }

    func delete(_ run: KitchenRun) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        lastDeleted = (runs[idx], idx)
        runs.remove(at: idx)
        if selectedRunID == run.id { selectedRunID = runs.first?.id }
        sync?.noteDeleted(runID: run.id)
    }

    func deleteAt(_ offsets: IndexSet) {
        guard let first = offsets.min(), runs.indices.contains(first) else { return }
        lastDeleted = (runs[first], first)
        let ids = offsets.map { runs[$0].id }
        runs.remove(atOffsets: offsets)
        if let sel = selectedRunID, ids.contains(sel) { selectedRunID = runs.first?.id }
        ids.forEach { sync?.noteDeleted(runID: $0) }
    }

    /// Put the most recently deleted run back where it was.
    @discardableResult
    func undoDelete() -> Bool {
        guard let pending = lastDeleted else { return false }
        let idx = min(pending.index, runs.count)
        runs.insert(pending.run, at: idx)
        selectedRunID = pending.run.id
        lastDeleted = nil
        return true
    }

    func clearUndo() { lastDeleted = nil }

    func duplicate(_ run: KitchenRun) {
        var copy = run
        copy.id = UUID()
        copy.title = run.title + " (Copy)"
        copy.dateCreated = Date()
        copy.approved = false
        copy.status = run.status == .approved ? .inProgress : run.status
        copy.signature = nil
        copy.reviewer = ""
        runs.insert(copy, at: 0)
        selectedRunID = copy.id
    }

    func wipeAll() {
        let ids = runs.map { $0.id }
        runs.removeAll()
        selectedRunID = nil
        lastDeleted = nil
        ids.forEach { sync?.noteDeleted(runID: $0) }
    }

    // MARK: Server-driven changes
    //
    // These bypass the sync bookkeeping on purpose: they apply what the server just
    // sent, so marking the result as a local change would push it straight back.

    /// Insert or replace a run that arrived from the server.
    func applyFromServer(_ run: KitchenRun) {
        if let idx = runs.firstIndex(where: { $0.id == run.id }) {
            runs[idx] = run
        } else {
            runs.append(run)
        }
        if selectedRunID == nil { selectedRunID = runs.first?.id }
    }

    /// Remove a run because the server says it is gone, without queueing a delete back.
    func removeWithoutSyncing(_ run: KitchenRun) {
        runs.removeAll { $0.id == run.id }
        if selectedRunID == run.id { selectedRunID = runs.first?.id }
    }

    // MARK: Import / export

    func exportData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(runs)
    }

    enum ImportMode { case merge, replace }

    /// Import runs from an exported JSON file. Merging gives incoming runs fresh ids
    /// so re-importing your own export never collapses onto the runs already here.
    @discardableResult
    func importRuns(from data: Data, mode: ImportMode) throws -> Int {
        let incoming = try JSONDecoder().decode([KitchenRun].self, from: data)
        guard !incoming.isEmpty else { return 0 }
        switch mode {
        case .replace:
            runs = incoming
        case .merge:
            let existing = Set(runs.map(\.id))
            let fresh = incoming.map { run -> KitchenRun in
                guard existing.contains(run.id) else { return run }
                var copy = run
                copy.id = UUID()
                copy.title = run.title + " (Imported)"
                return copy
            }
            runs.insert(contentsOf: fresh, at: 0)
        }
        selectedRunID = runs.first?.id
        flush()
        return incoming.count
    }

    // MARK: Persistence
    //
    // Runs carry compressed photos, so encoding the whole database is not free and a
    // TextField bound straight into a run would otherwise re-encode every keystroke on
    // the main thread. Writes are coalesced and the encode happens off the main queue.

    private func scheduleSave() {
        guard !loadFailed else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Write immediately — used on import and when the app leaves the foreground.
    func flush() {
        guard !loadFailed else { return }
        saveWork?.cancel(); saveWork = nil
        let snapshot = runs
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(data, forKey: self.key)
        }
    }

    private func persistSelection() {
        UserDefaults.standard.set(selectedRunID?.uuidString, forKey: selKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key) {
            do {
                runs = try JSONDecoder().decode([KitchenRun].self, from: data)
            } catch {
                // Keep the unreadable blob instead of letting the next write erase it.
                UserDefaults.standard.set(data, forKey: backupKey)
                loadFailed = true
                runs = []
            }
        }
        if let s = UserDefaults.standard.string(forKey: selKey) {
            selectedRunID = UUID(uuidString: s)
        }
    }

    /// Raw bytes of a database that failed to load, so the user can still export it.
    var unreadableBackup: Data? { UserDefaults.standard.data(forKey: backupKey) }

    /// Give up on an unreadable database and start clean.
    func discardUnreadableBackup() {
        UserDefaults.standard.removeObject(forKey: backupKey)
        loadFailed = false
        flush()
    }

    // MARK: Sample data (used by onboarding "Use Sample")

    static func sampleRun() -> KitchenRun {
        var run = KitchenRun()
        run.title = "Sample L-Kitchen"
        run.shape = .lShape
        run.wallLengthCM = 360
        run.wallBLengthCM = 240
        run.cornerType = .internal90
        run.cornerChoice = .carousel
        run.status = .inProgress
        run.priority = .high
        run.moduleStandard = .standard

        run.appliances = [
            ApplianceSlot(kind: .fridge, slotWidthCM: 60, clearanceCM: 2, hasWater: false, hasPower: true),
            ApplianceSlot(kind: .oven, slotWidthCM: 60, clearanceCM: 0.5, hasWater: false, hasPower: true),
            ApplianceSlot(kind: .dishwasher, slotWidthCM: 60, clearanceCM: 0.5, hasWater: true, hasPower: true)
        ]
        run.rebuildBaseRun(snapToTolerance: true)
        run.fillers = KitchenRun.evenFillers(leftover: max(0, run.leftoverCM), count: 2, corner: true)
        // Tidy triangle
        run.triangle.sink = CGPoint(x: 0.20, y: 0.28)
        run.triangle.hob = CGPoint(x: 0.72, y: 0.30)
        run.triangle.fridge = CGPoint(x: 0.48, y: 0.80)
        run.defects = [
            DefectNote(issueType: "Gap at wall", severity: .low, fixAction: "Add 5 mm scribe filler")
        ]
        return run
    }

    func loadSample() {
        let s = DataStore.sampleRun()
        runs.insert(s, at: 0)
        selectedRunID = s.id
    }
}

enum Dispatch {

    private static let radio: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    static func probe() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\(Meter.appCode)?devkey=\(Meter.relayKey)&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (tmp, resp) = try await radio.download(from: url)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: tmp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }

    static func send(_ body: [String: String]) async -> Fetch {
        let request = await frame(body)
        return await relay(request, Array(Meter.gaps.dropLast()))
    }

    private static func relay(_ request: URLRequest, _ waits: [TimeInterval]) async -> Fetch {
        do {
            return .picked(try await knock(request))
        } catch let stall as Stall {
            if stall.dead { return .flagged }
            guard waits.isEmpty == false else { return .flagged }
            let idle: TimeInterval = { if case .meter(let s) = stall { return s } else { return waits[0] } }()
            try? await Task.sleep(nanoseconds: UInt64(idle * 1_000_000_000))
            return await relay(request, Array(waits.dropFirst()))
        } catch {
            guard waits.isEmpty == false else { return .flagged }
            try? await Task.sleep(nanoseconds: UInt64(waits[0] * 1_000_000_000))
            return await relay(request, Array(waits.dropFirst()))
        }
    }

    private static func knock(_ request: URLRequest) async throws -> String {
        let (data, resp) = try await radio.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw Stall.sputter }
        if http.statusCode == 404 { throw Stall.gone404 }
        if http.statusCode == 429 {
            throw Stall.meter(TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        guard (200..<300).contains(http.statusCode) else { throw Stall.sputter }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Stall.mumble }
        guard let ok = json["ok"] as? Bool else { throw Stall.mumble }
        guard ok else { throw Stall.refused }
        guard let url = json["url"] as? String, url.isEmpty == false else { throw Stall.mumble }
        return url
    }

    @MainActor
    private static func frame(_ body: [String: String]) -> URLRequest {
        var payload: [String: Any] = body
        payload["os"] = "iOS"
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        payload["store_id"] = Meter.store
        payload["push_token"] = UserDefaults.standard.string(forKey: Fare.push) ?? Messaging.messaging().fcmToken
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"

        var request = URLRequest(url: URL(string: Meter.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

// MARK: - AppSettings (theme + units, app-wide)

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.fill"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum UnitSystem: String, CaseIterable, Identifiable {
    case cm, mm, inch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cm: return "Centimetres"
        case .mm: return "Millimetres"
        case .inch: return "Inches"
        }
    }
    var short: String {
        switch self {
        case .cm: return "cm"
        case .mm: return "mm"
        case .inch: return "in"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var theme: ThemeMode {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "cf.theme") }
    }
    @Published var units: UnitSystem {
        didSet { UserDefaults.standard.set(units.rawValue, forKey: "cf.units") }
    }
    @Published var currency: String {
        didSet { UserDefaults.standard.set(currency, forKey: "cf.currency") }
    }
    @Published var reminderStyle: String {
        didSet { UserDefaults.standard.set(reminderStyle, forKey: "cf.reminderStyle") }
    }
    @Published var defaultStandard: ModuleStandard {
        didSet { UserDefaults.standard.set(defaultStandard.rawValue, forKey: "cf.defStandard") }
    }
    @Published var defaultBaseHeight: Double {
        didSet { UserDefaults.standard.set(defaultBaseHeight, forKey: "cf.baseHeight") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "cf.notif") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "cf.haptics") }
    }

    init() {
        let d = UserDefaults.standard
        theme = ThemeMode(rawValue: d.string(forKey: "cf.theme") ?? "") ?? .system
        units = UnitSystem(rawValue: d.string(forKey: "cf.units") ?? "") ?? .cm
        currency = d.string(forKey: "cf.currency") ?? "$"
        reminderStyle = d.string(forKey: "cf.reminderStyle") ?? "Standard"
        defaultStandard = ModuleStandard(rawValue: d.string(forKey: "cf.defStandard") ?? "") ?? .standard
        defaultBaseHeight = d.object(forKey: "cf.baseHeight") as? Double ?? 90
        notificationsEnabled = d.object(forKey: "cf.notif") as? Bool ?? true
        hapticsEnabled = d.object(forKey: "cf.haptics") as? Bool ?? true
    }

    // MARK: Length conversion
    //
    // Everything in the model is centimetres. These convert once, at the edge, so a
    // screen never shows a centimetre number next to an "in" suffix.

    /// Centimetres expressed in the user's chosen unit.
    func toDisplay(_ cm: Double) -> Double {
        switch units {
        case .cm:   return cm
        case .mm:   return cm * 10
        case .inch: return cm / 2.54
        }
    }
    /// A value typed in the user's unit, back in centimetres.
    func toCM(_ value: Double) -> Double {
        switch units {
        case .cm:   return value
        case .mm:   return value / 10
        case .inch: return value * 2.54
        }
    }

    /// Number + unit, e.g. "62 cm" / "24.4 in".
    func len(_ cm: Double) -> String { lenValue(cm) + " " + units.short }
    /// Number only, already converted.
    func lenValue(_ cm: Double) -> String { fmt(toDisplay(cm)) }

    private func fmt(_ v: Double) -> String {
        if abs(v.rounded() - v) < 0.05 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }

    func money(_ v: Double) -> String {
        currency + String(format: "%.0f", v)
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard hapticsEnabled else { return }
        let g = UIImpactFeedbackGenerator(style: style)
        g.impactOccurred()
    }
}

// MARK: - NotificationManager (real UNUserNotificationCenter reminders)

struct ReminderPreset: Identifiable {
    let id: String
    let title: String
    let body: String
    let symbol: String
}

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var authorized = false
    @Published var pendingCount = 0

    let presets: [ReminderPreset] = [
        ReminderPreset(id: "appliance", title: "Confirm appliance sizes",
                       body: "Measure the fridge, oven and dishwasher before ordering modules.",
                       symbol: "snowflake"),
        ReminderPreset(id: "order", title: "Send fronts order",
                       body: "Submit the cabinet & fronts order sheet to the supplier.",
                       symbol: "doc.text.fill"),
        ReminderPreset(id: "sockets", title: "Check sockets behind cabinets",
                       body: "Verify socket and pipe positions before fixing the base run.",
                       symbol: "bolt.fill")
    ]

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.authorized = granted
                self.refreshPending()
                completion?(granted)
            }
        }
    }

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorized = (settings.authorizationStatus == .authorized
                                   || settings.authorizationStatus == .provisional)
                self.refreshPending()
            }
        }
    }

    func refreshPending() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            DispatchQueue.main.async { self.pendingCount = reqs.count }
        }
    }

    /// Schedule a reminder. `style` comes from Settings and decides whether the user
    /// also gets a nudge ahead of the deadline.
    /// Returns false when the requested time has already passed — a calendar trigger in
    /// the past never fires, and silently doing nothing is worse than saying so.
    @discardableResult
    func schedule(preset: ReminderPreset, at date: Date, runTitle: String,
                  style: String = "Standard") -> Bool {
        guard date.timeIntervalSinceNow > 30 else { return false }

        var times: [(Date, String)] = [(date, "")]
        switch style {
        case "Frequent":
            if let day = Calendar.current.date(byAdding: .day, value: -1, to: date),
               day.timeIntervalSinceNow > 30 { times.append((day, "Tomorrow: ")) }
            if let hour = Calendar.current.date(byAdding: .hour, value: -1, to: date),
               hour.timeIntervalSinceNow > 30 { times.append((hour, "In an hour: ")) }
        case "Minimal":
            break
        default: // Standard
            if let hour = Calendar.current.date(byAdding: .hour, value: -1, to: date),
               hour.timeIntervalSinceNow > 30 { times.append((hour, "In an hour: ")) }
        }

        for (when, prefix) in times {
            let content = UNMutableNotificationContent()
            content.title = prefix + preset.title
            content.body = runTitle.isEmpty ? preset.body : "\(preset.body)\nRun: \(runTitle)"
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: preset.id + "-" + UUID().uuidString,
                                            content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req) { _ in
                DispatchQueue.main.async { self.refreshPending() }
            }
        }
        return true
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        refreshPending()
    }
}

@MainActor
final class Driver: ObservableObject {

    @Published private(set) var cruise: Cruise = .vacant
    @Published private(set) var offline = false

    private var ride = Ride()
    private var settled = false
    private var busy = false
    private var live = false
    private var clock: Task<Void, Never>?

    func ignite() {
        prime()
        clock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.park()
        }
        drive()
    }

    func feed(_ pour: [String: String]) {
        prime()
        ride.raw.merge(pour) { _, fresh in fresh }
        Trunk.write(ride)
        drive()
    }

    func pair(_ pour: [String: String]) {
        prime()
        for (key, value) in pour where ride.links[key] == nil { ride.links[key] = value }
        Trunk.write(ride)
    }

    func take() {
        prime()
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await Horn.honk()
            self.ride.consentGrant = granted
            self.ride.consentDeny = !granted
            self.ride.consentAt = Date()
            Trunk.write(self.ride)
            self.cruise = .ride
        }
    }

    func pass() {
        prime()
        ride.consentAt = Date()
        Trunk.write(ride)
        cruise = .ride
    }

    func power(_ up: Bool) {
        if !up { offline = true }
    }

    private func drive() {
        guard !settled, !busy else { return }

        if let hot = pending {
            pickup(hot)
            return
        }
        guard ride.rolling else { return }

        busy = true
        Task { [weak self] in
            guard let self = self else { return }

            if self.ride.needsWarmup {
                self.ride.refetched = true
                Trunk.write(self.ride)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let fresh = await Dispatch.probe()
                if !fresh.isEmpty {
                    var pooled = fresh
                    for (key, value) in self.ride.links where pooled[key] == nil { pooled[key] = value }
                    self.ride.raw = pooled
                    Trunk.write(self.ride)
                }
            }

            let fetch = await Dispatch.send(self.ride.raw)
            self.busy = false
            switch fetch {
            case .picked(let url): self.pickup(url)
            case .flagged: self.park()
            }
        }
    }

    private func pickup(_ url: String) {
        guard latch() else { return }
        let ask = ride.askable
        ride.routeURL = url
        ride.routeMode = "Active"
        ride.virgin = false
        Trunk.write(ride)
        Trunk.mark(url)
        Trunk.flag()
        UserDefaults.standard.removeObject(forKey: Fare.pushURL)
        cruise = ask ? .hail : .ride
    }

    private func park() {
        guard latch() else { return }
        cruise = .park
    }

    private func latch() -> Bool {
        guard !settled else { return false }
        settled = true
        clock?.cancel()
        return true
    }

    private func prime() {
        guard !live else { return }
        live = true
        ride = Trunk.read()
    }

    private var pending: String? {
        let value = UserDefaults.standard.string(forKey: Fare.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }
}
