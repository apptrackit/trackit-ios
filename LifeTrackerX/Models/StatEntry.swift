import Foundation

struct StatEntry: Identifiable, Codable {
    let id: UUID
    var date: Date
    var value: Double
    var type: StatType
    
    init(id: UUID = UUID(), date: Date, value: Double, type: StatType) {
        self.id = id
        self.date = date
        self.value = value
        self.type = type
    }
}
