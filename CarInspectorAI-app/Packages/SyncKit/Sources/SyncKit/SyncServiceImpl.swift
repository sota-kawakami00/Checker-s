import Foundation
import SwiftData
import Core
import AppraisalKit

/// オフラインキュー・同期エンジン（02 §5 / NFR-04/05）。
/// - 全ての書き込みはまず SwiftData（呼び出し元）→ 本サービスが Firestore 相当へ反映
/// - 順序保証: createdAt 昇順・逐次実行（同一 appraisalId の直列性も担保）
/// - リトライ: 指数バックオフ 2s→8s→30s、最大3回/セッション → failed（FR-702で手動再送）
@MainActor
public final class SyncServiceImpl: SyncService, SyncEnqueuing {

    public static let defaultBackoff: [Duration] = [.seconds(2), .seconds(8), .seconds(30)]
    public static let maxRetries = 3

    /// 非同期タスク生存中の SwiftData スタック解放を防ぐため container を強参照する
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let backend: any RemoteBackend
    private let connectivity: any ConnectivityMonitoring
    private let masters: MasterCatalog
    private let notifier: AppraisalChangeNotifier
    private let backoff: [Duration]
    private let sleeper: @Sendable (Duration) async -> Void
    private let logger = CILogger.logger(category: "SyncService")

    private var isProcessing = false
    private var statusContinuations: [UUID: AsyncStream<SyncQueueStatus>.Continuation] = [:]
    private var lastSyncedAt: Date?
    private var observerTasks: [Task<Void, Never>] = []

    public init(
        container: ModelContainer,
        backend: any RemoteBackend,
        connectivity: any ConnectivityMonitoring,
        masters: MasterCatalog,
        notifier: AppraisalChangeNotifier = .shared,
        backoff: [Duration] = SyncServiceImpl.defaultBackoff,
        sleeper: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.modelContainer = container
        self.context = container.mainContext
        self.backend = backend
        self.connectivity = connectivity
        self.masters = masters
        self.notifier = notifier
        self.backoff = backoff
        self.sleeper = sleeper
        startObservers()
    }

    deinit {
        observerTasks.forEach { $0.cancel() }
    }

    private func startObservers() {
        // 復帰検知 → 自動同期（NFR-05: 60秒以内。即時開始する）
        let connectivityEvents = connectivity.events
        observerTasks.append(Task { [weak self] in
            for await online in connectivityEvents {
                guard let self else { return }
                if online {
                    await self.processQueue()
                } else {
                    self.publishStatus()
                }
            }
        })
        // AI結果・リモート更新の受信（Firestoreリスナー相当）
        let events = backend.appraisalEvents
        observerTasks.append(Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.apply(event)
            }
        })
    }

    // MARK: - SyncEnqueuing

    public func enqueue(kind: SyncTaskKind, targetId: String, appraisalId: String) {
        // 同一ターゲットの重複キューは1本にまとめる（最新状態をアップロードするため冪等）
        let existing = try? context.fetch(FetchDescriptor<SyncTask>()).first {
            $0.kind == kind && $0.targetId == targetId && $0.state == .pendingUpload
        }
        if existing == nil {
            context.insert(SyncTask(kind: kind, targetId: targetId, appraisalId: appraisalId))
            try? context.save()
        }
        publishStatus()
    }

    public func kick() {
        Task { await self.processQueue() }
    }

    // MARK: - SyncService

    public var queueStatus: AsyncStream<SyncQueueStatus> {
        AsyncStream { continuation in
            let token = UUID()
            statusContinuations[token] = continuation
            continuation.yield(currentQueueStatus)
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.statusContinuations.removeValue(forKey: token) }
            }
        }
    }

    public var currentQueueStatus: SyncQueueStatus {
        let tasks = (try? context.fetch(FetchDescriptor<SyncTask>())) ?? []
        return SyncQueueStatus(
            pendingCount: tasks.filter { $0.state == .pendingUpload }.count,
            uploadingCount: tasks.filter { $0.state == .uploading }.count,
            failedCount: tasks.filter { $0.state == .failed }.count,
            isOnline: connectivity.isOnline,
            lastSyncedAt: lastSyncedAt
        )
    }

    public func syncNow() async throws {
        guard connectivity.isOnline else { throw AppError.offline }
        await processQueue()
    }

    public func retryFailed() async throws {
        let tasks = (try? context.fetch(FetchDescriptor<SyncTask>())) ?? []
        for task in tasks where task.state == .failed {
            task.state = .pendingUpload
            task.retryCount = 0
            task.lastError = nil
        }
        try? context.save()
        publishStatus()
        try await syncNow()
    }

    // MARK: - キュー処理

    private func processQueue() async {
        guard !isProcessing, connectivity.isOnline else {
            publishStatus()
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
            publishStatus()
        }

        var madeProgress = true
        while madeProgress && connectivity.isOnline {
            madeProgress = false
            let descriptor = FetchDescriptor<SyncTask>(sortBy: [SortDescriptor(\.createdAt)])
            let pending = ((try? context.fetch(descriptor)) ?? []).filter { $0.state == .pendingUpload }
            guard !pending.isEmpty else { break }

            // createdAt 昇順の逐次実行（同一 appraisalId は自動的に直列 UT-SYNC-03）
            for task in pending {
                guard connectivity.isOnline else { break }
                let outcome = await execute(task)
                if outcome != .skippedPrecondition {
                    madeProgress = true
                }
                publishStatus()
            }
        }
    }

    private enum Outcome: Equatable {
        case done, retryScheduled, failedPermanently, skippedPrecondition
    }

    private func execute(_ task: SyncTask) async -> Outcome {
        task.state = .uploading
        publishStatus()
        do {
            try await perform(task)
            context.delete(task)
            lastSyncedAt = .now
            try? context.save()
            return .done
        } catch RemoteBackendError.preconditionNotMet {
            // 画像アップ未完で runAppraisal 等 → 前提が満たされたら自動再試行（UT-SYNC-05）
            task.state = .pendingUpload
            try? context.save()
            return .skippedPrecondition
        } catch RemoteBackendError.conflict(let server) {
            resolveConflict(task: task, server: server)
            context.delete(task)
            try? context.save()
            return .done
        } catch {
            task.retryCount += 1
            task.lastError = (error as? AppError).map(String.init(describing:)) ?? error.localizedDescription
            if task.retryCount >= Self.maxRetries {
                task.state = .failed   // UT-SYNC-04 → FR-702 のUIに露出
                markFailed(task)
                try? context.save()
                logger.error("sync task failed permanently: \(task.kind.rawValue, privacy: .public) \(task.targetId, privacy: .public)")
                return .failedPermanently
            }
            task.state = .pendingUpload
            try? context.save()
            let delay = backoff[min(task.retryCount - 1, backoff.count - 1)]
            await sleeper(delay)
            return .retryScheduled
        }
    }

    private func perform(_ task: SyncTask) async throws {
        switch task.kind {
        case .uploadAppraisal:
            guard let appraisal = fetchAppraisal(task.targetId) else { return }
            appraisal.syncState = .uploading
            try await backend.uploadAppraisal(AppraisalMapper.dto(from: appraisal))
            appraisal.syncState = .synced
            notifier.post(appraisalId: appraisal.id)

        case .uploadPhoto:
            guard let photo = fetchPhoto(task.targetId) else { return }
            // アップロード対象はマスク済のみ（07 §2.2 PhotoService.persist が強制）
            guard let maskedPath = photo.localMaskedPath,
                  let data = FileManager.default.contents(atPath: maskedPath) else {
                throw AppError.notFound(entity: "maskedPhoto")
            }
            photo.uploadState = .uploading
            guard let appraisal = fetchAppraisal(photo.appraisalId) else { return }
            let path = AppraisalMapper.storagePath(storeId: appraisal.storeId, appraisalId: photo.appraisalId, photoId: photo.id)
            let url = try await backend.uploadPhoto(data: data, storagePath: path)
            photo.uploadState = .done
            photo.remoteURL = url

        case .requestAIAppraisal:
            guard let appraisal = fetchAppraisal(task.targetId) else { return }
            // 前提: ドキュメント同期済み + 全画像アップロード完了（05 §1 / 02 §5.3）
            guard appraisal.syncState == .synced,
                  appraisal.photos.allSatisfy({ $0.uploadState == .done }) else {
                throw RemoteBackendError.preconditionNotMet
            }
            let request = buildRequest(appraisal: appraisal, requestId: task.id)
            try await backend.requestAppraisal(request)
        }
    }

    private func markFailed(_ task: SyncTask) {
        switch task.kind {
        case .uploadAppraisal, .requestAIAppraisal:
            fetchAppraisal(task.targetId)?.syncState = .failed
            if task.kind == .requestAIAppraisal, let appraisal = fetchAppraisal(task.targetId) {
                appraisal.aiFailureReason = "network"
                notifier.post(appraisalId: appraisal.id)
            }
        case .uploadPhoto:
            fetchPhoto(task.targetId)?.uploadState = .failed
        }
    }

    /// 競合はサーバー版採用 + ローカルを退避コピー（02 §5.2 / UT-SYNC-06）
    private func resolveConflict(task: SyncTask, server: AppraisalDTO) {
        guard let appraisal = fetchAppraisal(task.targetId) else { return }
        let vehicle = appraisal.vehicle
        let escape = Appraisal(
            storeId: appraisal.storeId,
            staffId: appraisal.staffId,
            status: appraisal.status,
            vehicle: Vehicle(
                vin: vehicle.vin,
                makerCode: vehicle.makerCode,
                modelCode: vehicle.modelCode,
                gradeCode: vehicle.gradeCode,
                modelYear: vehicle.modelYear,
                firstRegistrationYM: vehicle.firstRegistrationYM,
                mileageKm: vehicle.mileageKm,
                colorCode: vehicle.colorCode,
                inspectionExpiry: vehicle.inspectionExpiry,
                equipments: vehicle.equipments
            ),
            confirmedPrice: appraisal.confirmedPrice,
            adjustmentReason: appraisal.adjustmentReason,
            syncState: .conflict
        )
        context.insert(escape)
        AppraisalMapper.applyServer(server, to: appraisal)
        notifier.post(appraisalId: appraisal.id)
    }

    // MARK: - AI結果の適用（Firestoreリスナー相当）

    private func apply(_ event: AppraisalRemoteEvent) {
        guard let appraisal = fetchAppraisal(event.appraisalId) else { return }
        switch event.kind {
        case .running:
            appraisal.status = .aiRunning

        case .done(let result):
            do {
                // クライアント側でも BR-02 等を検証（00 §11-3。破綻時はAIエラー扱い）
                let validated = try AppraisalResultValidator.validate(
                    result,
                    validPhotoIds: Set(appraisal.photos.map(\.id)),
                    marketAverage: result.marketAveragePrice
                )
                appraisal.aiResultJSON = try? validated.encoded()
                appraisal.aiConfidence = validated.confidence
                appraisal.aiProposedPrice = validated.appraisedPrice
                appraisal.repairProbability = validated.repairFinding.probability
                appraisal.completenessScore = validated.completeness.score
                appraisal.uncheckedItems = validated.completeness.uncheckedItems.map(\.code)
                    .filter { !appraisal.checkedItems.contains($0) }
                appraisal.marketAveragePrice = validated.marketAveragePrice
                appraisal.aiFailureReason = nil
                appraisal.status = .aiCompleted
            } catch {
                appraisal.aiFailureReason = "aiInvalidResponse"
                logger.error("AI result validation failed: \(String(describing: error), privacy: .public)")
            }

        case .failed(let reason):
            appraisal.aiFailureReason = reason
        }
        appraisal.updatedAt = .now
        try? context.save()
        notifier.post(appraisalId: appraisal.id)
    }

    // MARK: - fetch helpers

    private func fetchAppraisal(_ id: String) -> Appraisal? {
        var descriptor = FetchDescriptor<Appraisal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchPhoto(_ id: String) -> PhotoAsset? {
        var descriptor = FetchDescriptor<PhotoAsset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func buildRequest(appraisal: Appraisal, requestId: String) -> AppraisalRequestDTO {
        AppraisalRequestDTO(
            appraisalId: appraisal.id,
            requestId: requestId,
            repairConfirmed: {
                switch appraisal.repairConfirmedState {
                case .confirmedYes: true
                case .confirmedNo: false
                default: nil
                }
            }(),
            vehicle: AppraisalRequestDTO.VehicleDTO(from: appraisal.vehicle),
            photos: appraisal.photos.map { AppraisalRequestDTO.PhotoDTO(from: $0, storeId: appraisal.storeId) },
            market: nil,   // 相場は CF fetchMarketPrice が付与（06 §2.3）
            store: nil,
            checkItems: masters.checkItems.map {
                AppraisalRequestDTO.CheckItemDTO(code: $0.code, label: $0.label, weight: $0.weight)
            }
        )
    }

    private func publishStatus() {
        let status = currentQueueStatus
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }
}
