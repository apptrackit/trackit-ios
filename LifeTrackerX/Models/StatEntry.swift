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
    // id acts as client_uuid (source of truth)
    var id: UUID
    var date: Date
    var value: Double
    var type: StatType
    var source: StatSource
    // Optimistic locking version
    var version: Int
    // Legacy/compatibility with older backend flows
    var backendId: Int?

    init(
        id: UUID = UUID(),
        date: Date,
        value: Double,
        type: StatType,
        source: StatSource = .manual,
        version: Int = 1,
        backendId: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.value = value
        self.type = type
        self.source = source
        self.version = version
        self.backendId = backendId
    }

    // Custom Codable to remain backward compatible with previously saved entries (without version)
    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case value
        case type
        case source
        case version
        case backendId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decode(Date.self, forKey: .date)
        self.value = try container.decode(Double.self, forKey: .value)
        self.type = try container.decode(StatType.self, forKey: .type)
        self.source = try container.decode(StatSource.self, forKey: .source)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.backendId = try container.decodeIfPresent(Int.self, forKey: .backendId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(value, forKey: .value)
        try container.encode(type, forKey: .type)
        try container.encode(source, forKey: .source)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(backendId, forKey: .backendId)
    }
}
