import Foundation

enum StatSource: String, Codable, CaseIterable {
    case manual
    case appleHealth
    case automated
    
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
}

struct StatEntry: Identifiable, Codable {
    var id: UUID
    var date: Date
    var value: Double
    var type: StatType
    var source: StatSource
    var backendId: Int? // Backend database ID for sync operations
    
    // Sync-friendly fields
    var uuid: String? // Apple Health UUID or client-generated stable id for backend
    var lastUpdatedAt: Date
    var syncedWithHealth: Bool
    var syncedWithBackend: Bool
    var isDeleted: Bool
    var unit: String?
    
    init(
        id: UUID = UUID(),
        date: Date,
        value: Double,
        type: StatType,
        source: StatSource = .manual,
        backendId: Int? = nil,
        uuid: String? = nil,
        lastUpdatedAt: Date = Date(),
        syncedWithHealth: Bool = false,
        syncedWithBackend: Bool = false,
        isDeleted: Bool = false,
        unit: String? = nil
    ) {
        self.id = id
        self.date = date
        self.value = value
        self.type = type
        self.source = source
        self.backendId = backendId
        self.uuid = uuid
        self.lastUpdatedAt = lastUpdatedAt
        self.syncedWithHealth = syncedWithHealth
        self.syncedWithBackend = syncedWithBackend
        self.isDeleted = isDeleted
        self.unit = unit
    }
    
    // Backward-compatible Codable implementation (supports old saved data without new fields)
    enum CodingKeys: String, CodingKey {
        case id, date, value, type, source, backendId
        case uuid, lastUpdatedAt, syncedWithHealth, syncedWithBackend, isDeleted, unit
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decode(Date.self, forKey: .date)
        self.value = try container.decode(Double.self, forKey: .value)
        self.type = try container.decode(StatType.self, forKey: .type)
        self.source = try container.decode(StatSource.self, forKey: .source)
        self.backendId = try container.decodeIfPresent(Int.self, forKey: .backendId)
        
        // New fields with safe defaults for legacy data
        self.uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        self.lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt) ?? Date()
        self.syncedWithHealth = try container.decodeIfPresent(Bool.self, forKey: .syncedWithHealth) ?? (self.source == .appleHealth)
        self.syncedWithBackend = try container.decodeIfPresent(Bool.self, forKey: .syncedWithBackend) ?? false
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.unit = try container.decodeIfPresent(String.self, forKey: .unit)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(value, forKey: .value)
        try container.encode(type, forKey: .type)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(backendId, forKey: .backendId)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encode(lastUpdatedAt, forKey: .lastUpdatedAt)
        try container.encode(syncedWithHealth, forKey: .syncedWithHealth)
        try container.encode(syncedWithBackend, forKey: .syncedWithBackend)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(unit, forKey: .unit)
    }
    
    // Convenience mapping for backend source string
    var backendSource: String {
        switch source {
        case .appleHealth: return "apple_health"
        case .manual: return "app"
        case .automated: return "app"
        }
    }
}
