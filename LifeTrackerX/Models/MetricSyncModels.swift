import Foundation

// MARK: - Backend Metric Types Mapping
enum BackendMetricType: Int, CaseIterable {
    case weight = 1
    case height = 2
    case bodyFat = 3
    case waist = 4
    case bicep = 5
    case chest = 6
    case thigh = 7
    case shoulder = 8
    case glutes = 9
    case calf = 10
    case neck = 11
    case forearm = 12
    
    static func from(_ statType: StatType) -> BackendMetricType? {
        switch statType {
        case .weight: return .weight
        case .height: return .height
        case .bodyFat: return .bodyFat
        case .waist: return .waist
        case .bicep: return .bicep
        case .chest: return .chest
        case .thigh: return .thigh
        case .shoulder: return .shoulder
        case .glutes: return .glutes
        case .calf: return .calf
        case .neck: return .neck
        case .forearm: return .forearm
        default: return nil // BMI, LBM, FM, FFMI, BMR, BSA are calculated
        }
    }
    
    func toStatType() -> StatType {
        switch self {
        case .weight: return .weight
        case .height: return .height
        case .bodyFat: return .bodyFat
        case .waist: return .waist
        case .bicep: return .bicep
        case .chest: return .chest
        case .thigh: return .thigh
        case .shoulder: return .shoulder
        case .glutes: return .glutes
        case .calf: return .calf
        case .neck: return .neck
        case .forearm: return .forearm
        }
    }
}

// MARK: - Sync Operation Types
enum SyncOperationType: String, Codable {
    case create = "CREATE"
    case update = "UPDATE"
    case delete = "DELETE"
}

// MARK: - Sync Operation
struct SyncOperation: Codable, Identifiable {
    let id: UUID
    let operationType: SyncOperationType
    let entryId: UUID
    let statType: StatType
    let value: Double
    let date: Date
    let isAppleHealth: Bool
    let createdAt: Date
    let retryCount: Int
    let backendId: Int?
    
    // v2 sync fields
    let uuid: String?
    let clientLastUpdatedAt: Date
    let isDeleted: Bool
    let unit: String?
    
    init(operationType: SyncOperationType, entry: StatEntry, retryCount: Int = 0) {
        self.id = UUID()
        self.operationType = operationType
        self.entryId = entry.id
        self.statType = entry.type
        self.value = entry.value
        self.date = entry.date
        self.isAppleHealth = entry.source == .appleHealth
        self.createdAt = Date()
        self.retryCount = retryCount
        self.backendId = entry.backendId
        self.uuid = entry.uuid ?? entry.id.uuidString
        self.clientLastUpdatedAt = entry.lastUpdatedAt
        self.isDeleted = entry.isDeleted
        self.unit = entry.unit ?? entry.type.unit
    }
}

// MARK: - Backend API Models (Legacy)
struct CreateMetricRequest: Codable {
    let metric_type_id: Int
    let value: Double
    let date: String
    let is_apple_health: Bool
    
    init(entry: StatEntry) {
        self.metric_type_id = BackendMetricType.from(entry.type)?.rawValue ?? 1
        self.value = entry.value
        self.date = Self.dateFormatter.string(from: entry.date)
        self.is_apple_health = entry.source == .appleHealth
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct UpdateMetricRequest: Codable {
    let value: Double
    let date: String
    
    init(entry: StatEntry) {
        self.value = entry.value
        self.date = Self.dateFormatter.string(from: entry.date)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct MetricResponse: Codable {
    let success: Bool
    let message: String?
    let entryId: Int?
    let error: String?
}

// MARK: - Metrics Fetching Models (Legacy)
struct MetricsListResponse: Codable {
    let success: Bool
    let entries: [MetricData]
    let total: Int
    let error: String?
}

struct MetricData: Codable {
    let id: Int
    let metric_type_id: Int
    let value: String // Server returns value as string
    let date: String
    let is_apple_health: Bool
    
    // Optional fields that might not be present
    let user_id: Int?
    let created_at: String?
    let updated_at: String?
}

// MARK: - V2 Mobile Sync Models
struct MobileMetricEntryDTO: Codable {
    let id: String
    let metric_type: String?
    let metric_type_id: Int?
    let value: Double
    let unit: String?
    let timestamp: String?
    let date: String?
    let source: String?
    let last_updated_at: String?
    let is_deleted: Bool?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.metric_type = try container.decodeIfPresent(String.self, forKey: .metric_type)
        self.metric_type_id = try container.decodeIfPresent(Int.self, forKey: .metric_type_id)
        // value may come as number or string; handle both
        if let doubleValue = try? container.decode(Double.self, forKey: .value) {
            self.value = doubleValue
        } else if let stringValue = try? container.decode(String.self, forKey: .value), let doubleValue = Double(stringValue) {
            self.value = doubleValue
        } else {
            self.value = 0
        }
        self.unit = try container.decodeIfPresent(String.self, forKey: .unit)
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        self.date = try container.decodeIfPresent(String.self, forKey: .date)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.last_updated_at = try container.decodeIfPresent(String.self, forKey: .last_updated_at)
        self.is_deleted = try container.decodeIfPresent(Bool.self, forKey: .is_deleted)
    }
}

struct SyncChangesResponseV2: Codable {
    let entries: [MobileMetricEntryDTO]
    let has_more: Bool
    let server_timestamp: String
}

struct CreateMetricV2Request: Codable {
    let id: String?
    let metric_type: String?
    let metric_type_id: Int?
    let value: Double
    let unit: String?
    let timestamp: String?
    let date: String?
    let source: String
}

struct UpdateMetricV2Request: Codable {
    let value: Double?
    let unit: String?
    let timestamp: String?
    let source: String?
    let client_last_updated_at: String
}

// MARK: - Date Helpers
enum DateCoding {
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
    
    static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

// MARK: - Sync Status
enum SyncStatus {
    case pending
    case inProgress
    case completed
    case failed(Error)
    
    var isCompleted: Bool {
        switch self {
        case .completed: return true
        case .failed: return true
        default: return false
        }
    }
}

// MARK: - Network Connectivity
enum NetworkConnectivity {
    case connected
    case disconnected
    case unknown
} 