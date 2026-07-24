import Foundation
import SwiftUI
import SwiftData
import Core
import AppraisalKit
import CameraKit
import SyncKit

/// DIコンテナ（02_SYSTEM_ARCHITECTURE.md §3）。
/// ViewModel へは protocol 型で注入する。シングルトンの新規作成は禁止（CLAUDE.md §2.3）。
@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let masters: MasterCatalog
    let store: StoreInfo

    let authService: any AuthService
    let vehicleService: any VehicleService
    let photoService: any PhotoService
    let appraisalService: any AppraisalService
    let syncService: any SyncService
    let pdfService: any PDFService
    let dashboardService: any DashboardService

    let cameraSession: any CameraSessionProviding
    let tiltProvider: any TiltProviding
    let connectivity: any ConnectivityMonitoring

    private init(
        modelContainer: ModelContainer,
        backend: any RemoteBackend,
        connectivity: any ConnectivityMonitoring,
        cameraSession: any CameraSessionProviding,
        tiltProvider: any TiltProviding,
        authDefaults: UserDefaults
    ) throws {
        self.modelContainer = modelContainer
        self.masters = try MasterCatalog.bundled()
        self.store = StoreInfo(
            id: "store-demo",
            name: "カーインスペクター東京店",
            address: "東京都千代田区丸の内1-1-1"
        )
        self.connectivity = connectivity
        self.cameraSession = cameraSession
        self.tiltProvider = tiltProvider

        let context = modelContainer.mainContext
        let auth = SyncKit.MockAuthService(defaults: authDefaults)
        self.authService = auth

        let sync = SyncServiceImpl(
            container: modelContainer,
            backend: backend,
            connectivity: connectivity,
            masters: masters
        )
        self.syncService = sync

        self.appraisalService = AppraisalServiceImpl(
            container: modelContainer,
            auth: auth,
            sync: sync,
            masters: masters
        )
        self.vehicleService = VehicleServiceImpl(masters: masters)
        self.photoService = PhotoServiceImpl(context: context, tiltProvider: tiltProvider)
        self.pdfService = PDFServiceImpl(context: context, auth: auth, masters: masters, storeName: store.name)
        self.dashboardService = DashboardServiceImpl(context: context, auth: auth, masters: masters)
    }

    /// 本番構成。
    /// 注: Firebase 実プロジェクト設定（GoogleService-Info.plist）投入までは
    /// RemoteBackend をローカル模擬（InMemoryRemoteBackend）で構成する（README「Firebase接続」参照）。
    static func production() -> AppContainer {
        do {
            let modelContainer = try ModelContainerFactory.production()
            let session: any CameraSessionProviding = {
                #if os(iOS) && !targetEnvironment(simulator)
                let real = AVCameraSession()
                return real.isAvailable ? real : MockCameraSession()
                #else
                return MockCameraSession()
                #endif
            }()
            let tilt: any TiltProviding = {
                #if os(iOS) && !targetEnvironment(simulator)
                return MotionTiltProvider()
                #else
                return FixedTiltProvider(tilt: 1.2)
                #endif
            }()
            return try AppContainer(
                modelContainer: modelContainer,
                backend: InMemoryRemoteBackend(),
                connectivity: NetworkPathConnectivity(),
                cameraSession: session,
                tiltProvider: tilt,
                authDefaults: .standard
            )
        } catch {
            // 起動不能級の失敗はインメモリで縮退起動（データ消失ゼロ方針のため通常は到達しない）
            return .mock()
        }
    }

    /// Preview / テスト用（08 §1: 実ネットワーク禁止）
    static func mock() -> AppContainer {
        do {
            let defaults = UserDefaults(suiteName: "mock-\(UUID().uuidString)") ?? .standard
            return try AppContainer(
                modelContainer: ModelContainerFactory.inMemory(),
                backend: InMemoryRemoteBackend(appraisalDelay: .seconds(1.5)),
                connectivity: ManualConnectivity(online: true),
                cameraSession: MockCameraSession(),
                tiltProvider: FixedTiltProvider(tilt: 1.2),
                authDefaults: defaults
            )
        } catch {
            fatalError("AppContainer.mock() 構築に失敗: \(error)")
        }
    }
}

private struct AppContainerKey: EnvironmentKey {
    /// EnvironmentKey は nonisolated 要求のため assumeIsolated で橋渡し
    /// （View更新は常に MainActor。既定値はアプリ側で必ず注入されるため Preview 用のフォールバック）。
    static var defaultValue: AppContainer {
        MainActor.assumeIsolated { AppContainer.mock() }
    }
}

extension EnvironmentValues {
    var appContainer: AppContainer {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
