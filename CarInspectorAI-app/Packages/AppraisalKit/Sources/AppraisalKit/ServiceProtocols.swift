import Foundation
import Core
import CoreGraphics

/// 査定ドメインの中核 Service（06_API_DESIGN.md §1.4）。
/// ViewModel はこの protocol のみを知る（02 §1）。
@MainActor
public protocol AppraisalService: AnyObject, Sendable {
    func createDraft(vehicle: Vehicle) async throws -> Appraisal
    func updateDraft(_ appraisal: Appraisal) async throws
    /// AI査定のリクエスト（キュー投入。オフライン時は UC-02 のとおり復帰後自動実行）
    func requestAIAppraisal(appraisalId: String) async throws
    /// Firestoreリスナー⇔SwiftData反映のストリーム
    func observeAppraisal(id: String) -> AsyncStream<Appraisal>
    /// 確定（FR-407, BR-01/03/06, UC-03）
    func confirm(appraisalId: String, price: Int, adjustmentReason: String?) async throws
    /// 修復歴の現車確認（UC-03）。「あり」確定時は BR-04 により再査定を発行する
    func setRepairConfirmed(appraisalId: String, state: RepairConfirmedState) async throws
    func updateCheckItem(appraisalId: String, itemCode: String, checked: Bool) async throws
    /// 履歴検索（FR-601、ページング50件）
    func history(filter: HistoryFilter, page: Int) async throws -> [Appraisal]
    /// 複製再査定（FR-602。車両情報のみ引継ぎ・写真/AI結果なし）
    func duplicate(appraisalId: String) async throws -> Appraisal
    /// 成約/失注（SCREEN_HISTORY §4。確定済みのみ可）
    func setOutcome(appraisalId: String, won: Bool) async throws
    func appraisal(id: String) async throws -> Appraisal
}

/// 車両情報・マスタ（06 §1.2 / FR-201〜204）
@MainActor
public protocol VehicleService: AnyObject, Sendable {
    /// 車検証OCR（FR-201）。Vision テキスト認識 + 車検証レイアウト規則で抽出
    func recognizeShaken(from image: CGImage) async throws -> ShakenOCRResult
    func makers() async throws -> [MakerMaster]
    func models(makerCode: String) async throws -> [ModelMaster]
    func grades(makerCode: String, modelCode: String) async throws -> [GradeMaster]
    func equipmentMaster() async throws -> [EquipmentMaster]
    func colorMaster() async throws -> [ColorMaster]
}

/// 査定書PDF（06 §1.5 / FR-502）
@MainActor
public protocol PDFService: AnyObject, Sendable {
    func generateAppraisalSheet(appraisalId: String) async throws -> URL
}

/// ダッシュボード（06 §1.5 / FR-603/604）
@MainActor
public protocol DashboardService: AnyObject, Sendable {
    func metrics(period: DashboardPeriod) async throws -> DashboardMetrics
    func staffPerformance(period: DashboardPeriod) async throws -> [StaffMetrics]
    func aiDeviationAnalysis(period: DashboardPeriod) async throws -> DeviationReport
}

/// 同期キューへの投入口。SyncKit の SyncService が実装する
/// （AppraisalKit → SyncKit の依存逆流を防ぐための protocol 注入。02 §1 一方向依存）。
@MainActor
public protocol SyncEnqueuing: AnyObject, Sendable {
    func enqueue(kind: SyncTaskKind, targetId: String, appraisalId: String)
    /// キューの処理を試みる（オフライン時は何もしない）
    func kick()
}

/// 査定ドキュメントの更新通知（Firestoreリスナー/ローカル更新 → observeAppraisal ストリームへの橋渡し）
@MainActor
public final class AppraisalChangeNotifier: Sendable {
    public static let shared = AppraisalChangeNotifier()

    private var continuations: [UUID: (id: String, send: @MainActor (String) -> Void)] = [:]

    public init() {}

    public func post(appraisalId: String) {
        for (_, entry) in continuations where entry.id == appraisalId {
            entry.send(appraisalId)
        }
    }

    public func subscribe(appraisalId: String, onChange: @escaping @MainActor (String) -> Void) -> UUID {
        let token = UUID()
        continuations[token] = (appraisalId, onChange)
        return token
    }

    public func unsubscribe(_ token: UUID) {
        continuations.removeValue(forKey: token)
    }
}
