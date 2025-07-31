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
    }
}

// MARK: - Backend API Models
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
    let value: String // Server returns value as string
    let date: String
    let is_apple_health: Bool
    
    // Optional fields that might not be present
    let user_id: Int?
    let created_at: String?
    let updated_at: String?
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