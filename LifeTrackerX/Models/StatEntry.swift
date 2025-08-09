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
    var uuid: String? // Apple Health UUID or server UUID
    var date: Date
    var value: Double
    var type: StatType
    var source: StatSource
    var backendId: Int? // Legacy backend database ID for sync operations
    var lastUpdatedAt: Date
    var syncedWithHealth: Bool
    var syncedWithBackend: Bool
    var isDeleted: Bool
    
    init(
        id: UUID = UUID(),
        uuid: String? = nil,
        date: Date,
        value: Double,
        type: StatType,
        source: StatSource = .manual,
        backendId: Int? = nil,
        lastUpdatedAt: Date = Date(),
        syncedWithHealth: Bool = false,
        syncedWithBackend: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.uuid = uuid
        self.date = date
        self.value = value
        self.type = type
        self.source = source
        self.backendId = backendId
        self.lastUpdatedAt = lastUpdatedAt
        self.syncedWithHealth = syncedWithHealth
        self.syncedWithBackend = syncedWithBackend
        self.isDeleted = isDeleted
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, uuid, date, value, type, source, backendId, lastUpdatedAt, syncedWithHealth, syncedWithBackend, isDeleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        self.date = try container.decode(Date.self, forKey: .date)
        self.value = try container.decode(Double.self, forKey: .value)
        self.type = try container.decode(StatType.self, forKey: .type)
        self.source = try container.decode(StatSource.self, forKey: .source)
        self.backendId = try container.decodeIfPresent(Int.self, forKey: .backendId)
        self.lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt) ?? Date()
        self.syncedWithHealth = try container.decodeIfPresent(Bool.self, forKey: .syncedWithHealth) ?? false
        self.syncedWithBackend = try container.decodeIfPresent(Bool.self, forKey: .syncedWithBackend) ?? false
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encode(date, forKey: .date)
        try container.encode(value, forKey: .value)
        try container.encode(type, forKey: .type)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(backendId, forKey: .backendId)
        try container.encode(lastUpdatedAt, forKey: .lastUpdatedAt)
        try container.encode(syncedWithHealth, forKey: .syncedWithHealth)
        try container.encode(syncedWithBackend, forKey: .syncedWithBackend)
        try container.encode(isDeleted, forKey: .isDeleted)
    }
}
