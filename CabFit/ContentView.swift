import SwiftUI
import Network

struct ContentView: View {
    
    @StateObject private var driver = Driver()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true
    @State private var monitor = NWPathMonitor()

    var body: some View {
        ZStack {
            switch driver.cruise {
            case .vacant, .hail:
                LaunchView()
                    .transition(.opacity)
            case .ride:
                WindshieldView()
                    .transition(.opacity)
            case .park:
                main.transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: cover(.hail)) { HailFace(driver: driver) }
        .fullScreenCover(isPresented: coverOffline) { OffFace() }
        .onReceive(NotificationCenter.default.publisher(for: .metered)) { note in
            guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
            driver.feed(bag.mapValues { "\($0)" })
        }
        .onReceive(NotificationCenter.default.publisher(for: .routed)) { note in
            guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
            driver.pair(bag.mapValues { "\($0)" })
        }
        .onAppear(perform: start)
    }
    
    private var main: some View {
        ZStack {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
    }
    
    private func cover(_ target: Cruise) -> Binding<Bool> {
        Binding(get: { driver.cruise == target }, set: { _ in })
    }

    private func start() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in driver.power(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        driver.ignite()
    }
    
    private var coverOffline: Binding<Bool> {
        Binding(get: { driver.offline }, set: { _ in })
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DataStore())
            .environmentObject(AppSettings())
            .environmentObject(NotificationManager.shared)
            .environmentObject(SyncEngine())
            .environmentObject(CatalogueStore.shared)
    }
}


private struct HailFace: View {
    let driver: Driver

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                Image("nocab-fff")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()
                if !wide {
                    VStack(spacing: 12) {
                        Spacer()
                        VStack(spacing: 12) {
                            Text("ALLOW NOTIFICATIONS ABOUT\nBОNUSЕS AND PRОМОS")
                                .font(.system(size: 23, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("STAY TUNЕD WITН BЕST OFFЕRS FRОM\nОUR САSINО")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        
                        VStack(spacing: 12) {
                            Button { driver.take() } label: {
                                Image("cab-bt").resizable().frame(width: 300, height: 55)
                            }
                            Button { driver.pass() } label: {
                                Image("cab-skbt").resizable().frame(width: 280, height: 40)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 28)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ALLOW NOTIFICATIONS ABOUT\nBОNUSЕS AND PRОМОS")
                                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                Text("STAY TUNЕD WITН BЕST OFFЕRS FRОM\nОUR САSINО")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            Spacer()
                            VStack(spacing: 12) {
                                Button { driver.take() } label: {
                                    Image("cab-bt").resizable().frame(width: 300, height: 55)
                                }
                                Button { driver.pass() } label: {
                                    Image("cab-skbt").resizable().frame(width: 280, height: 40)
                                }
                            }
                            .padding(.horizontal, 12)
                            Spacer()
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

private struct OffFace: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("nocab-fff")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    Image("error_loading")
                        .resizable()
                        .frame(width: 260, height: 260)
                }
            }
        }
        .ignoresSafeArea()
    }
}
