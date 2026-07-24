import Foundation
import Core

/// Cloud Functions runAppraisal への入力契約（schemas/appraisal_request.schema.json 準拠）
public struct AppraisalRequestDTO: Codable, Equatable, Sendable {
    public var appraisalId: String
    public var requestId: String                 // 冪等性キー
    public var repairConfirmed: Bool?            // 人間確定の修復歴。nil=未確定
    public var vehicle: VehicleDTO
    public var photos: [PhotoDTO]
    public var market: MarketDTO?
    public var store: StorePolicyDTO?
    public var checkItems: [CheckItemDTO]

    public init(
        appraisalId: String,
        requestId: String,
        repairConfirmed: Bool?,
        vehicle: VehicleDTO,
        photos: [PhotoDTO],
        market: MarketDTO?,
        store: StorePolicyDTO?,
        checkItems: [CheckItemDTO]
    ) {
        self.appraisalId = appraisalId
        self.requestId = requestId
        self.repairConfirmed = repairConfirmed
        self.vehicle = vehicle
        self.photos = photos
        self.market = market
        self.store = store
        self.checkItems = checkItems
    }

    public struct VehicleDTO: Codable, Equatable, Sendable {
        public var vinMasked: String?            // 下6桁マスク済VIN（07 §2.1）
        public var makerCode: String
        public var modelCode: String
        public var gradeCode: String?
        public var modelYear: Int?
        public var firstRegistrationYM: String?
        public var mileageKm: Int
        public var colorCode: String
        public var inspectionExpiry: String?     // "yyyy-MM-dd"
        public var equipments: [String]

        public init(from vehicle: Vehicle) {
            self.vinMasked = vehicle.vin.map(VINMasking.mask)
            self.makerCode = vehicle.makerCode
            self.modelCode = vehicle.modelCode
            self.gradeCode = vehicle.gradeCode
            self.modelYear = vehicle.modelYear
            self.firstRegistrationYM = vehicle.firstRegistrationYM
            self.mileageKm = vehicle.mileageKm
            self.colorCode = vehicle.colorCode
            self.inspectionExpiry = vehicle.inspectionExpiry.map {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter.string(from: $0)
            }
            self.equipments = vehicle.equipments
        }
    }

    public struct PhotoDTO: Codable, Equatable, Sendable {
        public var photoId: String
        public var angle: String
        public var damageTag: String?
        public var memo: String?
        public var storagePath: String

        public init(from photo: PhotoAsset, storeId: String) {
            self.photoId = photo.id
            self.angle = photo.angle.rawValue
            self.damageTag = photo.damageTag
            self.memo = photo.memo
            // Storage パス規約（firestore_collections.md）
            self.storagePath = "stores/\(storeId)/appraisals/\(photo.appraisalId)/photos/\(photo.id).jpg"
        }
    }

    public struct MarketDTO: Codable, Equatable, Sendable {
        public var average: Int
        public var median: Int
        public var sampleCount: Int
        public var range: Range
        public var trend30d: Double
        public var fetchedAt: String
        public var stale: Bool

        public struct Range: Codable, Equatable, Sendable {
            public var p25: Int
            public var p75: Int

            public init(p25: Int, p75: Int) {
                self.p25 = p25
                self.p75 = p75
            }
        }

        public init(average: Int, median: Int, sampleCount: Int, range: Range, trend30d: Double, fetchedAt: String, stale: Bool) {
            self.average = average
            self.median = median
            self.sampleCount = sampleCount
            self.range = range
            self.trend30d = trend30d
            self.fetchedAt = fetchedAt
            self.stale = stale
        }
    }

    public struct StorePolicyDTO: Codable, Equatable, Sendable {
        public var targetMarginRate: Double?

        public init(targetMarginRate: Double?) {
            self.targetMarginRate = targetMarginRate
        }
    }

    public struct CheckItemDTO: Codable, Equatable, Sendable {
        public var code: String
        public var label: String
        public var weight: Double

        public init(code: String, label: String, weight: Double) {
            self.code = code
            self.label = label
            self.weight = weight
        }
    }
}
