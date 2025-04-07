import Foundation

enum StatSource: String, Codable {
    case manual
    case appleHealth
    case automated
    
    var iconName: String {
        switch self {
        case .manual:
            return "person.fill"
        case .appleHealth:
            return "heart.fill"
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
    
    init(id: UUID = UUID(), date: Date, value: Double, type: StatType, source: StatSource = .manual) {
        self.id = id
        self.date = date
        self.value = value
        self.type = type
        self.source = source
    }
}
