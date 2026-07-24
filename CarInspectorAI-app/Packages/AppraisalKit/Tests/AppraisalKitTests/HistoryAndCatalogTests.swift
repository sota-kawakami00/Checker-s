import Foundation
import Testing
import SwiftData
import Core
@testable import AppraisalKit

/// 履歴フィルタ・複製・マスタ（SCREEN_HISTORY §14 / FR-601/602）
@MainActor
@Suite("HistoryAndCatalog")
struct HistoryAndCatalogTests {

    @Test("SCR-HIS-01: ステータスフィルタで正しく絞り込まれ、50件でページングされる")
    func filterAndPaging() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService()
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)

        for index in 0..<120 {
            let appraisal = Appraisal(
                storeId: "store-1",
                staffId: "staff-1",
                status: index % 2 == 0 ? .draft : .confirmed,
                vehicle: TestFactory.makeVehicle(),
                createdAt: Date(timeIntervalSinceNow: -Double(index) * 60)
            )
            if index % 2 == 1 {
                appraisal.confirmedPrice = 1_000_000
                appraisal.expiresAt = Date(timeIntervalSinceNow: 6 * 86_400)
            }
            container.mainContext.insert(appraisal)
        }
        try container.mainContext.save()

        let drafts = try await service.history(filter: HistoryFilter(statuses: [.draft]), page: 0)
        #expect(drafts.count == 50)
        #expect(drafts.allSatisfy { $0.status == .draft })

        let page1 = try await service.history(filter: HistoryFilter(statuses: [.draft]), page: 1)
        #expect(page1.count == 10)

        // 新しい順
        let all = try await service.history(filter: .all, page: 0)
        #expect(all.first?.createdAt ?? .distantPast >= all.last?.createdAt ?? .distantPast)
    }

    @Test("検索: 車種名・車台番号下桁でヒットする")
    func searchText() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService()
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)

        let appraisal = Appraisal(storeId: "store-1", staffId: "staff-1", status: .draft, vehicle: TestFactory.makeVehicle())
        container.mainContext.insert(appraisal)
        try container.mainContext.save()

        #expect(try await service.history(filter: HistoryFilter(searchText: "ヴォクシー"), page: 0).count == 1)
        #expect(try await service.history(filter: HistoryFilter(searchText: "234567"), page: 0).count == 1)
        #expect(try await service.history(filter: HistoryFilter(searchText: "セレナ"), page: 0).isEmpty)
    }

    @Test("SCR-HIS-02: 複製は車両情報のみ引継ぎ・写真/AI結果なしの draft")
    func duplicate() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService()
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)

        let source = try TestFactory.makeCompletedAppraisal(context: container.mainContext)
        source.photos.append(PhotoAsset(appraisalId: source.id, angle: .front, localOriginalPath: "/tmp/a.jpg"))
        source.aiResultJSON = Data("{}".utf8)
        try container.mainContext.save()

        let copy = try await service.duplicate(appraisalId: source.id)

        #expect(copy.id != source.id)
        #expect(copy.status == .draft)
        #expect(copy.photos.isEmpty)
        #expect(copy.aiResultJSON == nil)
        #expect(copy.vehicle.modelCode == source.vehicle.modelCode)
        #expect(copy.vehicle.id != source.vehicle.id)
    }

    @Test("SCR-HIS-03: 成約マークは確定済みのみ可・キュー投入")
    func outcome() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService()
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)

        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext)

        await #expect(throws: AppError.self) {
            try await service.setOutcome(appraisalId: appraisal.id, won: true)  // 未確定
        }

        try await service.confirm(appraisalId: appraisal.id, price: 1_820_000, adjustmentReason: nil)
        try await service.setOutcome(appraisalId: appraisal.id, won: true)
        #expect(appraisal.status == .won)
        #expect(sync.entries.filter { $0.kind == .uploadAppraisal }.count >= 2)
    }

    @Test("SCR-HIS-04: 期限残2日以内は warning 判定")
    func expiringSoon() throws {
        let appraisal = Appraisal(storeId: "s", staffId: "s", status: .confirmed, vehicle: TestFactory.makeVehicle())
        appraisal.expiresAt = Date(timeIntervalSinceNow: 1.5 * 86_400)
        #expect(HistoryFilterEngine.isExpiringSoon(appraisal))

        appraisal.expiresAt = Date(timeIntervalSinceNow: 5 * 86_400)
        #expect(!HistoryFilterEngine.isExpiringSoon(appraisal))
    }

    @Test("マスタ: バンドルJSONが読み込め、段階選択・スコア計算ができる")
    func masterCatalog() throws {
        let catalog = try MasterCatalog.bundled()
        #expect(catalog.makers.count == 9)
        #expect(!catalog.models(makerCode: "toyota").isEmpty)
        #expect(!catalog.grades(makerCode: "toyota", modelCode: "voxy").isEmpty)
        #expect(catalog.checkItems.count == 8)

        // 全確認済み = 1.0 / 全未確認 = 0.0 / 重み付き
        #expect(catalog.completenessScore(checkedCodes: Set(catalog.checkItems.map(\.code))) == 1.0)
        #expect(catalog.completenessScore(checkedCodes: []) == 0.0)
        let partial = catalog.completenessScore(checkedCodes: ["underbody", "engineStart"])  // 重み2+2 / 総重み10.5
        #expect(abs(partial - 4.0 / 10.5) < 1e-9)
    }

    @Test("査定漏れチェックON/OFFでスコア再計算・キュー投入（FR-406）")
    func updateCheckItem() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService()
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)

        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext)
        appraisal.uncheckedItems = ["spareKey", "underbody"]
        try container.mainContext.save()

        try await service.updateCheckItem(appraisalId: appraisal.id, itemCode: "spareKey", checked: true)
        #expect(appraisal.uncheckedItems == ["underbody"])
        #expect(appraisal.checkedItems.contains("spareKey"))
        let catalog = try MasterCatalog.bundled()
        let expected = catalog.completenessScore(checkedCodes: Set(catalog.checkItems.map(\.code)).subtracting(["underbody"]))
        #expect(appraisal.completenessScore == expected)
        #expect(sync.entries.contains { $0.kind == .uploadAppraisal })
    }
}
