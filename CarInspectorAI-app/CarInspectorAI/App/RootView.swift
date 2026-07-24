import SwiftUI
import LocalAuthentication
import Core
import DesignSystem

/// 認証ゲート + タブルート（SCREEN_HOME §15-2: タブは TabView ルート、Route は タブ毎の NavigationStack）
struct RootView: View {
    @Environment(\.appContainer) private var container
    @State private var staff: Staff?
    @State private var isRestoring = true
    @State private var isLocked = false

    var body: some View {
        Group {
            if isRestoring {
                ProgressView()
            } else if staff == nil {
                LoginView(onSignedIn: { staff = $0 })
            } else if isLocked {
                appLockView
            } else {
                MainTabView()
            }
        }
        .task {
            await evaluateAppLock()
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--uitest-signin") {
                staff = try? await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")
            }
            if staff == nil {
                staff = container.authService.currentStaff
            }
            isRestoring = false
            for await current in container.authService.observeAuthState() {
                staff = current
            }
        }
    }

    // アプリロック（07 §4: Face ID / Touch ID。店舗強制ONにも対応）
    private var appLockView: some View {
        VStack(spacing: CIToken.Space.l) {
            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundStyle(CIToken.Colors.primary)
            Text("applock.message")
                .font(CIToken.Fonts.body)
            PrimaryButton(String(localized: "applock.unlock")) {
                Task { await unlock() }
            }
            .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CIToken.Colors.bgBase)
    }

    private func evaluateAppLock() async {
        let enabled = UserDefaults.standard.bool(forKey: "carinspector.settings.appLock")
            || container.store.settings.forceAppLock
        guard enabled, !ProcessInfo.processInfo.arguments.contains("--uitest") else { return }
        isLocked = true
        await unlock()
    }

    private func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 生体認証もパスコードも未設定の端末（シミュレータ等）はロックをスキップ
            isLocked = false
            return
        }
        let reason = String(localized: "applock.reason")
        let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        if success {
            isLocked = false
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("tab.home", systemImage: "house.fill") {
                HomeNavigationStack()
            }
            Tab("tab.history", systemImage: "clock.arrow.circlepath") {
                HistoryNavigationStack()
            }
            Tab("tab.dashboard", systemImage: "chart.bar.xaxis") {
                DashboardNavigationStack()
            }
            Tab("tab.settings", systemImage: "gearshape.fill") {
                SettingsNavigationStack()
            }
        }
        .tint(CIToken.Colors.primary)
    }
}

/// タブ毎の NavigationStack + Route 解決
struct HomeNavigationStack: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    routeDestination(route, path: $path)
                }
        }
    }
}

struct HistoryNavigationStack: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HistoryView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    routeDestination(route, path: $path)
                }
        }
    }
}

struct DashboardNavigationStack: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            DashboardView()
                .navigationDestination(for: Route.self) { route in
                    routeDestination(route, path: $path)
                }
        }
    }
}

struct SettingsNavigationStack: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView()
                .navigationDestination(for: Route.self) { route in
                    routeDestination(route, path: $path)
                }
        }
    }
}

@ViewBuilder
@MainActor
func routeDestination(_ route: Route, path: Binding<[Route]>) -> some View {
    switch route {
    case .vehicleInfo(let draftId):
        VehicleInfoView(draftId: draftId, path: path)
    case .camera(let appraisalId):
        CameraView(appraisalId: appraisalId, path: path)
    case .appraisalRunning(let appraisalId), .appraisalResult(let appraisalId), .historyDetail(let appraisalId):
        AppraisalResultView(appraisalId: appraisalId, path: path)
    case .dashboard:
        DashboardView()
    case .settings:
        SettingsView()
    }
}
