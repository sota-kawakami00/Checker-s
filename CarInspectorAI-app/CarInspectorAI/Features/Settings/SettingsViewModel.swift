import Foundation
import Observation
import Core
import CameraKit

/// 設定（SCREEN_SETTINGS.md §4）
@MainActor
@Observable
final class SettingsViewModel {

    struct StorageUsage: Equatable {
        var originalBytes: Int64 = 0
        var maskedBytes: Int64 = 0
        var pdfBytes: Int64 = 0
        var total: Int64 { originalBytes + maskedBytes + pdfBytes }
    }

    private(set) var staff: Staff?
    private(set) var queueStatus = SyncQueueStatus()
    private(set) var storageUsage: StorageUsage?
    private(set) var isSyncing = false
    private(set) var isMeasuringStorage = false
    private(set) var resetMessageShown = false
    var isAppLockEnabled: Bool {
        didSet { defaults.set(isAppLockEnabled, forKey: Self.appLockKey) }
    }
    var error: AppError?

    private static let appLockKey = "carinspector.settings.appLock"

    private let auth: any AuthService
    private let syncService: any SyncService
    private let storeInfo: StoreInfo
    private let defaults: UserDefaults
    @ObservationIgnored private nonisolated(unsafe) var statusTask: Task<Void, Never>?

    init(auth: any AuthService, syncService: any SyncService, storeInfo: StoreInfo, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.syncService = syncService
        self.storeInfo = storeInfo
        self.defaults = defaults
        self.isAppLockEnabled = defaults.bool(forKey: Self.appLockKey)
    }

    deinit {
        statusTask?.cancel()
    }

    var storeName: String { storeInfo.name }
    var storeAddress: String { storeInfo.address }

    /// ②店舗セクションは manager+ のみ（SCR-SET-01）
    var showsStoreSection: Bool {
        (staff?.role ?? .staff) >= .manager
    }

    func onAppear() async {
        staff = auth.currentStaff
        queueStatus = syncService.currentQueueStatus
        if statusTask == nil {
            let stream = syncService.queueStatus
            statusTask = Task { [weak self] in
                for await status in stream {
                    self?.queueStatus = status
                }
            }
        }
        await measureStorage()
    }

    // MARK: - 同期（FR-702）

    func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await syncService.syncNow()
        } catch {
            self.error = (error as? AppError) ?? .offline
        }
    }

    func retryFailed() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await syncService.retryFailed()
        } catch {
            self.error = (error as? AppError) ?? .offline
        }
    }

    // MARK: - ストレージ（FR-703）

    /// FileManager 集計をバックグラウンド実行（§15-1）
    func measureStorage() async {
        isMeasuringStorage = true
        defer { isMeasuringStorage = false }
        let usage = await Task.detached(priority: .utility) { () -> StorageUsage in
            func directorySize(_ url: URL) -> Int64 {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
                    return 0
                }
                var total: Int64 = 0
                for case let fileURL as URL in enumerator {
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    total += Int64(size)
                }
                return total
            }
            let base = URL.applicationSupportDirectory
            return StorageUsage(
                originalBytes: directorySize(base.appending(path: "photos/original")),
                maskedBytes: directorySize(base.appending(path: "photos/masked")),
                pdfBytes: directorySize(base.appending(path: "pdf"))
            )
        }.value
        storageUsage = usage
    }

    /// キャッシュ削除: synced 済データのみ対象。未同期は削除不可（SCR-SET-03 / NFR-04）
    func clearCache() async {
        guard queueStatus.totalQueued == 0 else {
            error = .validation(reason: "unsynced")
            return
        }
        let base = URL.applicationSupportDirectory
        try? FileManager.default.removeItem(at: base.appending(path: "pdf"))
        await measureStorage()
    }

    // MARK: - アカウント

    func sendPasswordReset() async {
        guard let email = staff?.email else { return }
        do {
            try await auth.sendPasswordReset(email: email)
            resetMessageShown = true
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
        }
    }

    /// ログアウト前の未同期件数（SCR-SET-04: 警告に件数表示）
    var unsyncedCountForLogout: Int {
        queueStatus.totalQueued
    }

    func signOut() async {
        do {
            try await auth.signOut()
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
        }
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
