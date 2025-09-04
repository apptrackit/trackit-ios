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
    let source: StatSource
    let version: Int
    let createdAt: Date
    let retryCount: Int
    let backendId: Int?
    
    init(operationType: SyncOperationType, entry: StatEntry, retryCount: Int = 0) {
        self.id = UUID()
        self.operationType = operationType
        self.entryId = entry.id
        self.statType = entry.type
        self.value = entry.value
        self.date = entry.date
        self.source = entry.source
        self.version = entry.version
        self.createdAt = Date()
        self.retryCount = retryCount
        self.backendId = entry.backendId
    }
}

// MARK: - Backend API Models
struct CreateMetricRequest: Codable {
    let client_uuid: String
    let metric_type_id: Int
    let value: Double
    let date: String
    let source: String
    let version: Int
    
    enum CodingKeys: String, CodingKey {
        case client_uuid
        case metric_type_id
        case value
        case date = "entry_date"
        case source
        case version
    }
    
    init(entry: StatEntry) {
        self.client_uuid = entry.id.uuidString
        self.metric_type_id = BackendMetricType.from(entry.type)?.rawValue ?? 1
        self.value = entry.value
        self.date = Self.dateFormatter.string(from: entry.date)
        self.source = entry.source.rawValue
        self.version = entry.version
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()
}

struct UpdateMetricRequest: Codable {
    let client_uuid: String
    let value: Double
    let date: String
    let source: String
    let version: Int
    
    enum CodingKeys: String, CodingKey {
        case client_uuid
        case value
        case date = "entry_date"
        case source
        case version
    }
    
    init(entry: StatEntry) {
        self.client_uuid = entry.id.uuidString
        self.value = entry.value
        self.date = Self.dateFormatter.string(from: entry.date)
        self.source = entry.source.rawValue
        self.version = entry.version
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()
}

struct MetricResponse: Codable {
    let success: Bool
    let message: String?
    let entryId: Int?
    let error: String?
}

// MARK: - Metrics Fetching Models
struct MetricsListResponse: Codable {
    let success: Bool
    let entries: [MetricData]
    let total: Int
    let error: String?
}

struct MetricData: Codable {
    let id: Int
    let metric_type_id: Int
    let value: Double // Server returns value as number
    let date: String
    // New fields for client-managed IDs and optimistic locking
    let client_uuid: String?
    let version: Int?
    let source: String?
    
    // Optional fields that might not be present
    let user_id: Int?
    let created_at: String?
    let updated_at: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case metric_type_id
        case value
        case date = "entry_date"
        case client_uuid
        case version
        case source
        case user_id
        case created_at
        case updated_at
    }
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