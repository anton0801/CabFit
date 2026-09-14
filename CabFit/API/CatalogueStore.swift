//
//  CatalogueStore.swift
//  CabFit
//
//  Module widths, appliance presets and price lists, served from the API.
//
//  Prices and supplier ranges change far more often than App Store releases, so these
//  live on the server. The values compiled into the app stay as the fallback: with no
//  catalogue cached yet — first launch on a plane, say — the app behaves exactly like
//  1.0 rather than showing empty pickers.
//

import Foundation

struct CatalogueStandard: Codable, Equatable {
    let code: String
    let title: String
    let widths_cm: [Double]
}

struct CatalogueAppliance: Codable, Equatable {
    let code: String
    let title: String
    let default_width_cm: Double
    let default_clearance_cm: Double
    let needs_water: Bool
    let needs_power: Bool
}

struct CataloguePriceList: Codable, Equatable, Identifiable {
    let code: String
    let title: String
    let currency: String
    let price_per_cabinet: Double
    let price_per_front: Double
    let price_per_worktop_metre: Double
    let reserve_percent: Double

    var id: String { code }
}

struct Catalogue: Codable, Equatable {
    var version: Int
    var standards: [CatalogueStandard]
    var appliances: [CatalogueAppliance]
    var price_lists: [CataloguePriceList]

    static let empty = Catalogue(version: 0, standards: [], appliances: [], price_lists: [])
}

/// Caches the catalogue and answers lookups synchronously.
///
/// Reads come from an in-memory snapshot, because the layout engine asks for module
/// widths inside view bodies and a disk hit there would be felt.
final class CatalogueStore: ObservableObject {

    static let shared = CatalogueStore()

    @Published private(set) var catalogue: Catalogue
    @Published private(set) var lastRefresh: Date?

    private let defaultsKey = "cabfit.catalogue.v1"
    private let refreshKey = "cabfit.catalogue.refreshedAt"
    private let lock = NSLock()
    private var snapshot: Catalogue

    private init() {
        let loaded: Catalogue
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(Catalogue.self, from: data) {
            loaded = decoded
        } else {
            loaded = .empty
        }
        catalogue = loaded
        snapshot = loaded
        lastRefresh = UserDefaults.standard.object(forKey: refreshKey) as? Date
    }

    var isLoaded: Bool { snapshot.version > 0 }

    // MARK: Lookups used by the model

    /// Server widths for a standard, or nil to let the built-in list stand.
    func widths(forStandard code: String) -> [Double]? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = snapshot.standards.first(where: { $0.code == code }),
              !entry.widths_cm.isEmpty else { return nil }
        return entry.widths_cm.sorted()
    }

    func title(forStandard code: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return snapshot.standards.first(where: { $0.code == code })?.title
    }

    func appliance(_ code: String) -> CatalogueAppliance? {
        lock.lock(); defer { lock.unlock() }
        return snapshot.appliances.first(where: { $0.code == code })
    }

    var priceLists: [CataloguePriceList] {
        lock.lock(); defer { lock.unlock() }
        return snapshot.price_lists
    }

    // MARK: Refresh

    /// Pull the catalogue if the cached copy is older than `maxAge`.
    func refreshIfStale(maxAge: TimeInterval = 6 * 3600, completion: ((Bool) -> Void)? = nil) {
        if let last = lastRefresh, Date().timeIntervalSince(last) < maxAge, isLoaded {
            completion?(false)
            return
        }
        refresh(completion: completion)
    }

    func refresh(completion: ((Bool) -> Void)? = nil) {
        APIClient.shared.ensureAuthenticated { [weak self] result in
            guard let self = self else { return }
            guard case .success = result else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            APIClient.shared.get("/v1/catalogue") { (result: Result<Catalogue, APIError>) in
                switch result {
                case .success(let fresh):
                    self.apply(fresh)
                    DispatchQueue.main.async { completion?(true) }
                case .failure:
                    // A stale catalogue is better than none; keep what is cached.
                    DispatchQueue.main.async { completion?(false) }
                }
            }
        }
    }

    private func apply(_ fresh: Catalogue) {
        lock.lock()
        snapshot = fresh
        lock.unlock()

        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: refreshKey)

        DispatchQueue.main.async {
            self.catalogue = fresh
            self.lastRefresh = now
        }
    }
}
