import Foundation

enum StatSource: String, Codable, CaseIterable {
    case manual = "app"
    case appleHealth = "apple_health"
    case automated = "automated"
    
    var iconName: String {
        switch self {
        case .manual:
            return "figure.walk"
        case .appleHealth:
            return "applehealthdark"
        case .automated:
            return "gearshape.2.fill"
        }
    }
    
    // Legacy support for old data
    static func fromLegacy(_ value: String) -> StatSource {
        switch value {
        case "manual": return .manual
        case "appleHealth": return .appleHealth
        case "automated": return .automated
        case "app": return .manual
        case "apple_health": return .appleHealth
        default: return .manual
        }
    }
}

struct StatEntry: Identifiable, Codable {
    var id: UUID
    var uuid: String? // Apple Health UUID (if from HealthKit)
    var date: Date
    var value: Double
    var type: StatType
    var unit: String? // Unit of measurement (e.g., "kg", "cm", "%")
    var source: StatSource
    var backendId: String? // Backend database ID for sync operations (now using UUID string)
    var lastUpdatedAt: Date // For conflict resolution
    var syncedWithHealth: Bool = false
    var syncedWithBackend: Bool = false
    var isDeleted: Bool = false
    var createdAt: Date // Track when entry was created locally
    
    init(id: UUID = UUID(), 
         uuid: String? = nil,
         date: Date, 
         value: Double, 
         type: StatType, 
         unit: String? = nil,
         source: StatSource = .manual, 
         backendId: String? = nil,
         lastUpdatedAt: Date? = nil,
         syncedWithHealth: Bool = false,
         syncedWithBackend: Bool = false,
         isDeleted: Bool = false,
         createdAt: Date? = nil) {
        self.id = id
        self.uuid = uuid
        self.date = date
        self.value = value
        self.type = type
        self.unit = unit ?? type.unit
        self.source = source
        self.backendId = backendId
        self.lastUpdatedAt = lastUpdatedAt ?? Date()
        self.syncedWithHealth = syncedWithHealth
        self.syncedWithBackend = syncedWithBackend
        self.isDeleted = isDeleted
        self.createdAt = createdAt ?? Date()
    }
    
    // Helper to get the UUID to use for backend sync
    var syncUUID: String {
        // Use Apple Health UUID if available, otherwise use our local UUID
        return uuid ?? id.uuidString
    }
    
    // Check if this entry needs syncing to backend
    var needsBackendSync: Bool {
        return !syncedWithBackend && !type.isCalculated
    }
    
    // Check if this entry needs syncing to HealthKit
    var needsHealthKitSync: Bool {
        return !syncedWithHealth && source == .manual && !type.isCalculated
    }
}

// Migration support for old data
extension StatEntry {
    init(legacyEntry: StatEntry) {
        self.id = legacyEntry.id
        self.uuid = legacyEntry.uuid
        self.date = legacyEntry.date
        self.value = legacyEntry.value
        self.type = legacyEntry.type
        self.unit = legacyEntry.unit ?? legacyEntry.type.unit
        self.source = StatSource.fromLegacy(legacyEntry.source.rawValue)
        self.backendId = legacyEntry.backendId
        self.lastUpdatedAt = legacyEntry.lastUpdatedAt
        self.syncedWithHealth = legacyEntry.syncedWithHealth
        self.syncedWithBackend = legacyEntry.syncedWithBackend
        self.isDeleted = legacyEntry.isDeleted
        self.createdAt = legacyEntry.createdAt
    }
}
