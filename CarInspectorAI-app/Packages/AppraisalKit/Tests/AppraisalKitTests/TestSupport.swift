import Foundation
import SwiftData
import Core
@testable import AppraisalKit

/// テスト用モック（08_TEST_PLAN §1: AppContainer.mock() 相当。ネットワーク到達禁止）

@MainActor
final class MockAuthService: AuthService {
    var currentStaff: Staff?

    init(role: StaffRole = .staff) {
        currentStaff = Staff(
            id: "staff-1",
            storeId: "store-1",
            displayName: "テストスタッフ",
            email: "staff@example.com",
            role: role
        )
    }

    func signIn(email: String, password: String) async throws -> Staff {
        guard let staff = currentStaff else { throw AppError.unauthenticated }
        return staff
    }

    func signOut() async throws { currentStaff = nil }
    func sendPasswordReset(email: String) async throws {}
    func observeAuthState() -> AsyncStream<Staff?> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
final class SpySyncEnqueuer: SyncEnqueuing {
    struct Entry: Equatable {
        var kind: SyncTaskKind
        var targetId: String
        var appraisalId: String
    }

    var entries: [Entry] = []
    var kickCount = 0

    func enqueue(kind: SyncTaskKind, targetId: String, appraisalId: String) {
        entries.append(Entry(kind: kind, targetId: targetId, appraisalId: appraisalId))
    }

    func kick() { kickCount += 1 }
}

@MainActor
enum TestFactory {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Vehicle.self, Appraisal.self, PhotoAsset.self, SyncTask.self, AdjustmentLog.self, AuditLog.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeService(
        container: ModelContainer,
        auth: MockAuthService,
        sync: SpySyncEnqueuer,
        now: @escaping @Sendable () -> Date = { .now }
    ) throws -> AppraisalServiceImpl {
        AppraisalServiceImpl(
            container: container,
            auth: auth,
            sync: sync,
            masters: try MasterCatalog.bundled(),
            notifier: AppraisalChangeNotifier(),
            now: now
        )
    }

    static func makeVehicle() -> Vehicle {
        Vehicle(
            vin: "ZWR80-1234567",
            makerCode: "toyota",
            modelCode: "voxy",
            gradeCode: "voxy_s_g",
            modelYear: 2021,
            firstRegistrationYM: "2021-03",
            mileageKm: 42000,
            colorCode: "pearlWhite",
            equipments: ["navi", "etc"]
        )
    }

    /// aiCompleted 状態の査定を作る
    static func makeCompletedAppraisal(
        context: ModelContext,
        confidence: Double = 0.94,
        repairProbability: Double = 0.22,
        aiProposedPrice: Int = 1_820_000
    ) throws -> Appraisal {
        let appraisal = Appraisal(storeId: "store-1", staffId: "staff-1", status: .aiCompleted, vehicle: makeVehicle())
        appraisal.aiConfidence = confidence
        appraisal.aiProposedPrice = aiProposedPrice
        appraisal.repairProbability = repairProbability
        appraisal.repairConfirmedState = RepairConfirmedState.none
        context.insert(appraisal)
        try context.save()
        return appraisal
    }
}

enum Fixtures {
    static func data(_ name: String, ext: String = "json") throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw AppError.notFound(entity: name)
        }
        return try Data(contentsOf: url)
    }
}
