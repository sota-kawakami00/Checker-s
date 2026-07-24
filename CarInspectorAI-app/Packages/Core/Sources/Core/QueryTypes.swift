import Foundation

/// 履歴検索フィルタ（FR-601 / SCREEN_HISTORY.md §15-1）
public struct HistoryFilter: Equatable, Sendable {
    public var searchText: String
    public var from: Date?
    public var to: Date?
    public var statuses: Set<AppraisalStatus>
    public var staffId: String?
    public var repairSuspectedOnly: Bool

    public init(
        searchText: String = "",
        from: Date? = nil,
        to: Date? = nil,
        statuses: Set<AppraisalStatus> = [],
        staffId: String? = nil,
        repairSuspectedOnly: Bool = false
    ) {
        self.searchText = searchText
        self.from = from
        self.to = to
        self.statuses = statuses
        self.staffId = staffId
        self.repairSuspectedOnly = repairSuspectedOnly
    }

    public static let all = HistoryFilter()
}

/// ダッシュボード期間（FR-603）
public enum DashboardPeriod: String, CaseIterable, Sendable {
    case today, thisWeek, thisMonth, custom
}

/// KPI（前期間比付き、SCREEN_DASHBOARD.md §2-②）
public struct KPIValue: Equatable, Sendable {
    public var value: Double
    /// 前期間比（例 +0.12 = 12%増）。前期間0件などで比較不能なら nil
    public var deltaRate: Double?

    public init(value: Double, deltaRate: Double? = nil) {
        self.value = value
        self.deltaRate = deltaRate
    }
}

public struct DashboardDailyPoint: Equatable, Sendable, Identifiable {
    public var date: Date
    public var appraisalCount: Int
    public var wonCount: Int
    public var id: Date { date }

    public init(date: Date, appraisalCount: Int, wonCount: Int) {
        self.date = date
        self.appraisalCount = appraisalCount
        self.wonCount = wonCount
    }
}

/// ダッシュボード集計（FR-603）
public struct DashboardMetrics: Equatable, Sendable {
    public var appraisalCount: KPIValue
    public var confirmRate: KPIValue      // 確定率
    public var wonRate: KPIValue          // 成約率
    public var averageAppraisedPrice: KPIValue
    public var daily: [DashboardDailyPoint]

    public init(
        appraisalCount: KPIValue,
        confirmRate: KPIValue,
        wonRate: KPIValue,
        averageAppraisedPrice: KPIValue,
        daily: [DashboardDailyPoint]
    ) {
        self.appraisalCount = appraisalCount
        self.confirmRate = confirmRate
        self.wonRate = wonRate
        self.averageAppraisedPrice = averageAppraisedPrice
        self.daily = daily
    }
}

/// スタッフ別実績（FR-603）
public struct StaffMetrics: Equatable, Sendable, Identifiable {
    public var staffId: String
    public var displayName: String
    public var appraisalCount: Int
    public var confirmedCount: Int
    public var wonCount: Int
    public var averageAdjustment: Double   // 平均調整幅（確定額 - AI提案額）
    public var id: String { staffId }

    public init(staffId: String, displayName: String, appraisalCount: Int, confirmedCount: Int, wonCount: Int, averageAdjustment: Double) {
        self.staffId = staffId
        self.displayName = displayName
        self.appraisalCount = appraisalCount
        self.confirmedCount = confirmedCount
        self.wonCount = wonCount
        self.averageAdjustment = averageAdjustment
    }
}

/// AI乖離分析（FR-604）
public struct DeviationReport: Equatable, Sendable {
    public var averageDeviation: Double        // 平均乖離額（confirmedPrice - aiProposedPrice）
    public var averageDeviationRate: Double    // 平均乖離率
    public var outliers: [DeviationItem]       // 乖離大の査定

    public init(averageDeviation: Double, averageDeviationRate: Double, outliers: [DeviationItem]) {
        self.averageDeviation = averageDeviation
        self.averageDeviationRate = averageDeviationRate
        self.outliers = outliers
    }
}

public struct DeviationItem: Equatable, Sendable, Identifiable {
    public var appraisalId: String
    public var vehicleLabel: String
    public var aiProposedPrice: Int
    public var confirmedPrice: Int
    public var id: String { appraisalId }

    public var deviation: Int { confirmedPrice - aiProposedPrice }

    public init(appraisalId: String, vehicleLabel: String, aiProposedPrice: Int, confirmedPrice: Int) {
        self.appraisalId = appraisalId
        self.vehicleLabel = vehicleLabel
        self.aiProposedPrice = aiProposedPrice
        self.confirmedPrice = confirmedPrice
    }
}

/// 同期キュー状態（FR-702）
public struct SyncQueueStatus: Equatable, Sendable {
    public var pendingCount: Int
    public var uploadingCount: Int
    public var failedCount: Int
    public var isOnline: Bool
    public var lastSyncedAt: Date?

    public init(pendingCount: Int = 0, uploadingCount: Int = 0, failedCount: Int = 0, isOnline: Bool = true, lastSyncedAt: Date? = nil) {
        self.pendingCount = pendingCount
        self.uploadingCount = uploadingCount
        self.failedCount = failedCount
        self.isOnline = isOnline
        self.lastSyncedAt = lastSyncedAt
    }

    public var totalQueued: Int { pendingCount + uploadingCount + failedCount }
}

/// 車検証OCR結果（FR-201 / SCREEN_VEHICLE_INFO.md §9）
public struct ShakenOCRResult: Equatable, Sendable {
    public var vin: String?
    public var katashiki: String?              // 型式
    public var firstRegistrationYM: String?    // "2021-03"
    public var inspectionExpiry: Date?
    /// 信頼度が低く自動適用しなかったフィールド名（SCR-VEH-02）
    public var lowConfidenceFields: [String]

    public init(
        vin: String? = nil,
        katashiki: String? = nil,
        firstRegistrationYM: String? = nil,
        inspectionExpiry: Date? = nil,
        lowConfidenceFields: [String] = []
    ) {
        self.vin = vin
        self.katashiki = katashiki
        self.firstRegistrationYM = firstRegistrationYM
        self.inspectionExpiry = inspectionExpiry
        self.lowConfidenceFields = lowConfidenceFields
    }
}
