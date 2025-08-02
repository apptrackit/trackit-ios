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
    
    init(id: UUID = UUID(), date: Date, value: Double, type: StatType, source: StatSource = .manual, backendId: Int? = nil) {
        self.id = id
        self.date = date
        self.value = value
        self.type = type
        self.source = source
        self.backendId = backendId
    }
}
