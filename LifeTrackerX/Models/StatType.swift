import Foundation

enum StatType: String, Codable, CaseIterable, Identifiable {
    case weight, height, bodyFat
    
    var id: String { self.rawValue }
    
    var unit: String {
        switch self {
        case .weight: return "kg"
        case .height: return "cm"
        case .bodyFat: return "%"
        }
    }
    
    var title: String {
        switch self {
        case .weight: return "Weight"
        case .height: return "Height"
        case .bodyFat: return "Body Fat"
        }
    }
    
    var appleHealthIdentifier: String {
        switch self {
        case .weight: return "HKQuantityTypeIdentifierBodyMass"
        case .height: return "HKQuantityTypeIdentifierHeight"
        case .bodyFat: return "HKQuantityTypeIdentifierBodyFatPercentage"
        }
    }
}
