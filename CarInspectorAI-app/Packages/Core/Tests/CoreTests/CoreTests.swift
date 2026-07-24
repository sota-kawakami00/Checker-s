import Foundation
import Testing
@testable import Core

@Suite("Core")
struct CoreTests {

    @Test("VINマスキング: 下6桁が伏字になる（07 §2.1）")
    func vinMasking() {
        #expect(VINMasking.mask("ZWR80-1234567") == "ZWR80-1******")
        #expect(VINMasking.mask("ABC123") == "******")
        #expect(VINMasking.mask("AB") == "**")
    }

    @Test("AppError: ユーザー向け文言に技術詳細が含まれない（CLAUDE.md §2.4）")
    func errorMessages() {
        let error = AppError.serverError(code: 500)
        let message = error.errorDescription ?? ""
        #expect(!message.contains("500"))
        #expect(message.contains("保存"))

        #expect(AppError.offline.localizationKey == "error.offline")
        #expect(AppError.validation(reason: "x").localizationKey == "error.validation")
    }

    @Test("PhotoAngle: 規定12アングル + damage（FR-301）")
    func photoAngles() {
        #expect(PhotoAngle.guided.count == 12)
        #expect(!PhotoAngle.guided.contains(.damage))
        #expect(PhotoAngle.allCases.count == 13)
    }

    @Test("StaffRole: 権限順序（06 §4）")
    func roleOrdering() {
        #expect(StaffRole.staff < .manager)
        #expect(StaffRole.manager < .admin)
        #expect(StaffRole.manager >= .manager)
    }

    @Test("SyncQueueStatus: 合計件数")
    func queueStatus() {
        let status = SyncQueueStatus(pendingCount: 2, uploadingCount: 1, failedCount: 3, isOnline: false)
        #expect(status.totalQueued == 6)
    }
}
