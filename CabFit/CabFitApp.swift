import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib


@main
struct CabFitApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var notifier = NotificationManager.shared
    @StateObject private var sync = SyncEngine()
    @StateObject private var catalogue = CatalogueStore.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(notifier)
                .environmentObject(sync)
                .environmentObject(catalogue)
                .accentColor(CF.blue)
                .preferredColorScheme(settings.theme.colorScheme)
                .onAppear { start() }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background, .inactive:
                        store.flush()
                        sync.syncNow(reason: "background")
                    case .active:
                        notifier.refreshAuthorization()
                        sync.syncNow(reason: "foreground")
                        catalogue.refreshIfStale()
                    @unknown default:
                        break
                    }
                }
        }
    }

    private func start() {
        guard sync.store == nil else { return }
        sync.store = store
        store.sync = sync
        sync.syncNow(reason: "launch")
        catalogue.refreshIfStale()
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate {

    private var trunkData: [AnyHashable: Any] = [:]
    private var sideData: [AnyHashable: Any] = [:]
    private var idle: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Meter.relayKey
        sdk.appleAppID = Meter.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            spot(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(boarded), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
    }

    @objc private func boarded() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Fare.attStatus)
            }
        }
    }

    private func meterUp() {
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run { self?.tally() }
        }
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Fare.fcm)
            UserDefaults.standard.set(token, forKey: Fare.push)
            UserDefaults(suiteName: Meter.suite)?.set(token, forKey: Fare.sharedFcm)
        }
    }

    private func tally() {
        idle?.cancel()
        idle = nil
        var slip = trunkData
        for (key, value) in sideData {
            let tag = "\(key)".starts(with: "deep") ? "\(key)" : "deep_\(key)" // "deep_\(key)"
            if slip[tag] == nil { slip[tag] = value }
        }
        NotificationCenter.default.post(name: .metered, object: nil, userInfo: ["conversionData": slip])
    }

    private func spot(_ payload: [AnyHashable: Any]) {
        var seen: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            seen = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            seen = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            seen = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            seen = url
        }
        guard let link = seen else { return }

        UserDefaults.standard.set(link, forKey: Fare.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .beckoned, object: nil, userInfo: ["temp_url": link])
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        spot(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        spot(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        spot(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        trunkData = conversionInfo
        meterUp()
        if sideData.isEmpty == false { tally() }
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Fare.primed) == false else { return }
        sideData = deepLink.clickEvent
        NotificationCenter.default.post(name: .routed, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        idle?.cancel()
        idle = nil
        if trunkData.isEmpty == false { tally() }
    }
}
