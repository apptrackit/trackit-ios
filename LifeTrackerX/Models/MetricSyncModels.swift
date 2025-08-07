import Foundation

// MARK: - Backend Metric Types Mapping
enum BackendMetricType: String, CaseIterable {
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
    
    // Legacy ID mapping for backward compatibility
    var legacyId: Int {
        switch self {
        case .weight: return 1
        case .height: return 2
        case .bodyFat: return 3
        case .waist: return 4
        case .bicep: return 5
        case .chest: return 6
        case .thigh: return 7
        case .shoulder: return 8
        case .glutes: return 9
        case .calf: return 10
        case .neck: return 11
        case .forearm: return 12
        }
    }
    
    static func fromLegacyId(_ id: Int) -> BackendMetricType? {
        switch id {
        case 1: return .weight
        case 2: return .height
        case 3: return .bodyFat
        case 4: return .waist
        case 5: return .bicep
        case 6: return .chest
        case 7: return .thigh
        case 8: return .shoulder
        case 9: return .glutes
        case 10: return .calf
        case 11: return .neck
        case 12: return .forearm
        default: return nil
        }
    }
}

// MARK: - Backend API Models (New Mobile Format)

// Create/Update Metric Request (Mobile Format)
struct MobileMetricRequest: Codable {
    let id: String? // Optional UUID for create, required for update
    let metric_type: String // "weight", "height", etc.
    let value: Double
    let unit: String // "kg", "cm", "%", etc.
    let timestamp: String // ISO 8601 format
    let source: String // "app" or "apple_health"
    let client_last_updated_at: String? // For conflict detection on updates
    
    init(entry: StatEntry, isUpdate: Bool = false) {
        self.id = entry.syncUUID
        self.metric_type = BackendMetricType.from(entry.type)?.rawValue ?? "weight"
        self.value = entry.value
        self.unit = entry.unit ?? entry.type.unit
        self.timestamp = ISO8601DateFormatter().string(from: entry.date)
        self.source = entry.source.rawValue
        self.client_last_updated_at = isUpdate ? ISO8601DateFormatter().string(from: entry.lastUpdatedAt) : nil
    }
}

// Sync Changes Response
struct SyncChangesResponse: Codable {
    let entries: [BackendMetricEntry]
    let has_more: Bool
    let server_timestamp: String
}

// Backend Metric Entry (Full Format)
struct BackendMetricEntry: Codable {
    let id: String // UUID
    let user_id: Int?
    let metric_type_id: Int? // Legacy field
    let metric_type: String // "weight", "height", etc.
    let value: Double
    let unit: String
    let date: String? // Legacy field
    let timestamp: String? // ISO 8601
    let source: String // "app" or "apple_health"
    let last_updated_at: String
    let is_deleted: Bool
    let created_at: String?
    
    // Convert to local StatEntry
    func toStatEntry() -> StatEntry {
        let dateFormatter = ISO8601DateFormatter()
        let date = dateFormatter.date(from: timestamp ?? date ?? "") ?? Date()
        let lastUpdated = dateFormatter.date(from: last_updated_at) ?? Date()
        
        let statType = BackendMetricType(rawValue: metric_type)?.toStatType() ?? 
                      BackendMetricType.fromLegacyId(metric_type_id ?? 1)?.toStatType() ?? 
                      .weight
        
        return StatEntry(
            id: UUID(uuidString: id) ?? UUID(),
            uuid: source == "apple_health" ? id : nil,
            date: date,
            value: value,
            type: statType,
            unit: unit,
            source: StatSource.fromLegacy(source),
            backendId: id,
            lastUpdatedAt: lastUpdated,
            syncedWithHealth: source == "apple_health",
            syncedWithBackend: true,
            isDeleted: is_deleted
        )
    }
}

// MARK: - API Response Models

struct MetricResponse: Codable {
    let success: Bool
    let message: String?
    let entry: BackendMetricEntry?
    let error: String?
    let code: Int? // For conflict detection (409)
}

struct MetricsListResponse: Codable {
    let success: Bool
    let entries: [BackendMetricEntry]
    let total: Int?
    let server_timestamp: String?
    let error: String?
}

// MARK: - Sync Operation (Enhanced)
struct SyncOperation: Codable, Identifiable {
    let id: UUID
    let operationType: SyncOperationType
    let entry: StatEntry // Store full entry instead of individual fields
    let createdAt: Date
    let retryCount: Int
    let lastError: String?
    
    init(operationType: SyncOperationType, entry: StatEntry, retryCount: Int = 0, lastError: String? = nil) {
        self.id = UUID()
        self.operationType = operationType
        self.entry = entry
        self.createdAt = Date()
        self.retryCount = retryCount
        self.lastError = lastError
    }
}

// MARK: - Sync Operation Types
enum SyncOperationType: String, Codable {
    case create = "CREATE"
    case update = "UPDATE"
    case delete = "DELETE"
    case restore = "RESTORE"
}

// MARK: - Sync Status
enum SyncStatus: Equatable {
    case idle
    case syncing
    case completed(Date)
    case failed(String)
    
    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
    
    var lastSyncDate: Date? {
        if case .completed(let date) = self { return date }
        return nil
    }
}

// MARK: - Sync Conflict
struct SyncConflict {
    let localEntry: StatEntry
    let serverEntry: StatEntry
    let resolution: ConflictResolution
    
    enum ConflictResolution {
        case useLocal
        case useServer
        case merge
    }
}

// MARK: - Network Connectivity
enum NetworkConnectivity {
    case connected
    case disconnected
    case unknown
} 