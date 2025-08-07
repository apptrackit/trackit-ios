import Foundation
import HealthKit

// MARK: - Core Metric Model
struct Metric: Identifiable, Codable, Hashable {
    var id: UUID
    var healthKitUUID: String? // Apple Health UUID for deduplication
    var value: Double
    var type: MetricType
    var source: MetricSource
    var date: Date
    var unit: String
    var lastUpdatedAt: Date
    var syncedWithHealth: Bool
    var syncedWithBackend: Bool
    var isDeleted: Bool
    
    // Backend fields
    var backendId: String?
    var userId: Int?
    
    init(
        id: UUID = UUID(),
        healthKitUUID: String? = nil,
        value: Double,
        type: MetricType,
        source: MetricSource,
        date: Date,
        unit: String,
        lastUpdatedAt: Date = Date(),
        syncedWithHealth: Bool = false,
        syncedWithBackend: Bool = false,
        isDeleted: Bool = false,
        backendId: String? = nil,
        userId: Int? = nil
    ) {
        self.id = id
        self.healthKitUUID = healthKitUUID
        self.value = value
        self.type = type
        self.source = source
        self.date = date
        self.unit = unit
        self.lastUpdatedAt = lastUpdatedAt
        self.syncedWithHealth = syncedWithHealth
        self.syncedWithBackend = syncedWithBackend
        self.isDeleted = isDeleted
        self.backendId = backendId
        self.userId = userId
    }
}

// MARK: - Metric Source
enum MetricSource: String, Codable, CaseIterable {
    case health = "apple_health"
    case manual = "app"
    
    var displayName: String {
        switch self {
        case .health: return "Apple Health"
        case .manual: return "Manual Entry"
        }
    }
}

// MARK: - Metric Types
enum MetricType: String, Codable, CaseIterable {
    case weight = "weight"
    case height = "height"
    case bodyFat = "body_fat"
    case waist = "waist"
    case bicep = "bicep" 
    case chest = "chest"
    case thigh = "thigh"
    case shoulder = "shoulder"
    case glutes = "glutes"
    case calf = "calf"
    case neck = "neck"
    case forearm = "forearm"
    case steps = "steps"
    case heartRate = "heart_rate"
    
    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .height: return "Height"
        case .bodyFat: return "Body Fat"
        case .waist: return "Waist"
        case .bicep: return "Bicep"
        case .chest: return "Chest"
        case .thigh: return "Thigh"
        case .shoulder: return "Shoulder"
        case .glutes: return "Glutes"
        case .calf: return "Calf"
        case .neck: return "Neck"
        case .forearm: return "Forearm"
        case .steps: return "Steps"
        case .heartRate: return "Heart Rate"
        }
    }
    
    var defaultUnit: String {
        switch self {
        case .weight: return "kg"
        case .height: return "cm"
        case .bodyFat: return "%"
        case .waist, .bicep, .chest, .thigh, .shoulder, .glutes, .calf, .neck, .forearm: return "cm"
        case .steps: return "steps"
        case .heartRate: return "bpm"
        }
    }
    
    var healthKitType: HKQuantityType? {
        switch self {
        case .weight:
            return HKQuantityType.quantityType(forIdentifier: .bodyMass)
        case .height:
            return HKQuantityType.quantityType(forIdentifier: .height)
        case .bodyFat:
            return HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)
        case .waist:
            return HKQuantityType.quantityType(forIdentifier: .waistCircumference)
        case .steps:
            return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .heartRate:
            return HKQuantityType.quantityType(forIdentifier: .heartRate)
        default:
            return nil // Not directly supported in HealthKit
        }
    }
    
    var healthKitUnit: HKUnit? {
        switch self {
        case .weight:
            return HKUnit.gramUnit(with: .kilo)
        case .height:
            return HKUnit.meterUnit(with: .centi)
        case .bodyFat:
            return HKUnit.percent()
        case .waist:
            return HKUnit.meterUnit(with: .centi)
        case .steps:
            return HKUnit.count()
        case .heartRate:
            return HKUnit.count().unitDivided(by: HKUnit.minute())
        default:
            return nil
        }
    }
    
    static var healthKitSupportedTypes: [MetricType] {
        return [.weight, .height, .bodyFat, .waist, .steps, .heartRate]
    }
}

// MARK: - Sync Status
struct SyncStatus: Codable {
    var lastHealthKitSync: Date?
    var lastBackendSync: Date?
    var healthKitAnchor: HKQueryAnchor?
    var pendingHealthKitCount: Int
    var pendingBackendCount: Int
    var isOnline: Bool
    var lastError: String?
    
    init() {
        self.pendingHealthKitCount = 0
        self.pendingBackendCount = 0
        self.isOnline = true
    }
}

// MARK: - Backend API Models
struct BackendMetric: Codable {
    let id: String?
    let userId: Int?
    let metricType: String
    let value: Double
    let unit: String
    let timestamp: String
    let source: String
    let lastUpdatedAt: String?
    let isDeleted: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case metricType = "metric_type"
        case value
        case unit
        case timestamp
        case source
        case lastUpdatedAt = "last_updated_at"
        case isDeleted = "is_deleted"
    }
}

struct BackendSyncResponse: Codable {
    let entries: [BackendMetric]
    let hasMore: Bool
    let serverTimestamp: String
    
    enum CodingKeys: String, CodingKey {
        case entries
        case hasMore = "has_more"
        case serverTimestamp = "server_timestamp"
    }
}

// MARK: - Extensions
extension Metric {
    // Convert to backend format
    func toBackendMetric() -> BackendMetric {
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return BackendMetric(
            id: backendId,
            userId: userId,
            metricType: type.rawValue,
            value: value,
            unit: unit,
            timestamp: iso8601Formatter.string(from: date),
            source: source.rawValue,
            lastUpdatedAt: iso8601Formatter.string(from: lastUpdatedAt),
            isDeleted: isDeleted
        )
    }
    
    // Create from backend format
    static func fromBackendMetric(_ backend: BackendMetric) -> Metric? {
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let type = MetricType(rawValue: backend.metricType),
              let source = MetricSource(rawValue: backend.source),
              let date = iso8601Formatter.date(from: backend.timestamp) else {
            return nil
        }
        
        let lastUpdated = backend.lastUpdatedAt.flatMap { iso8601Formatter.date(from: $0) } ?? date
        
        return Metric(
            id: UUID(),
            value: backend.value,
            type: type,
            source: source,
            date: date,
            unit: backend.unit,
            lastUpdatedAt: lastUpdated,
            syncedWithBackend: true,
            isDeleted: backend.isDeleted ?? false,
            backendId: backend.id,
            userId: backend.userId
        )
    }
    
    // Create from HealthKit sample
    static func fromHealthKitSample(_ sample: HKQuantitySample, type: MetricType) -> Metric? {
        guard let unit = type.healthKitUnit else { return nil }
        
        let value: Double
        switch type {
        case .weight:
            value = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        case .height:
            value = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
        case .bodyFat:
            value = sample.quantity.doubleValue(for: HKUnit.percent()) * 100.0 // Convert to percentage
        case .waist:
            value = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
        case .steps:
            value = sample.quantity.doubleValue(for: HKUnit.count())
        case .heartRate:
            value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        default:
            return nil
        }
        
        // Check if this was originally from our app
        let isOurEntry = sample.metadata?["source"] as? String == "LifeTrackerX"
        let source: MetricSource = isOurEntry ? .manual : .health
        
        return Metric(
            healthKitUUID: sample.uuid.uuidString,
            value: value,
            type: type,
            source: source,
            date: sample.startDate,
            unit: type.defaultUnit,
            syncedWithHealth: true
        )
    }
    
    // Create HealthKit sample
    func toHealthKitSample() -> HKQuantitySample? {
        guard let quantityType = type.healthKitType,
              let hkUnit = type.healthKitUnit else { return nil }
        
        let adjustedValue: Double
        switch type {
        case .bodyFat:
            adjustedValue = value / 100.0 // Convert percentage to decimal
        default:
            adjustedValue = value
        }
        
        let quantity = HKQuantity(unit: hkUnit, doubleValue: adjustedValue)
        let metadata = [
            "source": "LifeTrackerX",
            "lifeTrackerXEntryId": id.uuidString
        ]
        
        return HKQuantitySample(
            type: quantityType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: metadata
        )
    }
}