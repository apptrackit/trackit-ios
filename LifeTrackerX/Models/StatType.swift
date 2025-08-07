import Foundation

enum StatType: String, Codable, CaseIterable, Identifiable, CustomStringConvertible {
    case weight, height, bodyFat, bmi, waist, bicep, chest, thigh, shoulder, glutes
    case calf, neck, forearm
    case lbm, fm, ffmi, bmr, bsa  // Added new calculated measurements
    case leanBodyMass, bodyFatMass  // Additional names for compatibility
    
    var id: String { self.rawValue }
    
    var unit: String {
        switch self {
        case .weight: return "kg"
        case .height: return "cm"
        case .bodyFat: return "%"
        case .bmi: return ""
        case .waist: return "cm"
        case .bicep: return "cm"
        case .chest: return "cm"
        case .thigh: return "cm"
        case .shoulder: return "cm"
        case .glutes: return "cm"
        case .calf: return "cm"
        case .neck: return "cm"
        case .forearm: return "cm"
        case .lbm, .leanBodyMass: return "kg"
        case .fm, .bodyFatMass: return "kg"
        case .ffmi: return ""
        case .bmr: return "kcal"
        case .bsa: return "m²"
        }
    }
    
    var title: String {
        switch self {
        case .weight: return "Weight"
        case .height: return "Height"
        case .bodyFat: return "Body Fat"
        case .bmi: return "BMI"
        case .waist: return "Waist"
        case .bicep: return "Bicep"
        case .chest: return "Chest"
        case .thigh: return "Thigh"
        case .shoulder: return "Shoulder"
        case .glutes: return "Glutes"
        case .calf: return "Calf"
        case .neck: return "Neck"
        case .forearm: return "Forearm"
        case .lbm, .leanBodyMass: return "Lean Body Mass"
        case .fm, .bodyFatMass: return "Body Fat Mass"
        case .ffmi: return "Fat-Free Mass Index"
        case .bmr: return "Basal Metabolic Rate"
        case .bsa: return "Body Surface Area"
        }
    }
    
    var appleHealthIdentifier: String {
        switch self {
        case .weight: return "HKQuantityTypeIdentifierBodyMass"
        case .height: return "HKQuantityTypeIdentifierHeight"
        case .bodyFat: return "HKQuantityTypeIdentifierBodyFatPercentage"
        case .waist: return "HKQuantityTypeIdentifierWaistCircumference"
        default: return "" // Other measurements are not supported by HealthKit
        }
    }
    
    var iconName: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .height: return "ruler.fill"
        case .bodyFat: return "figure.arms.open"
        case .bmi: return "chart.bar.fill"
        case .waist: return "figure.walk"
        case .bicep: return "figure.arms.open"
        case .chest: return "heart.fill"
        case .thigh: return "figure.walk"
        case .shoulder: return "figure.american.football"
        case .glutes: return "figure.cross.training"
        case .calf: return "figure.walk"
        case .neck: return "person.bust"
        case .forearm: return "figure.arms.open"
        case .lbm, .leanBodyMass: return "figure.arms.open"
        case .fm, .bodyFatMass: return "figure.arms.open"
        case .ffmi: return "chart.bar.fill"
        case .bmr: return "flame.fill"
        case .bsa: return "person.fill"
        }
    }
    
    var isCalculated: Bool {
        switch self {
        case .bmi, .lbm, .fm, .ffmi, .bmr, .bsa, .leanBodyMass, .bodyFatMass:
            return true
        default:
            return false
        }
    }
    
    var description: String {
        return self.rawValue
    }
}

// MARK: - Sync Operation Type
enum SyncOperationType: String, Codable, CaseIterable {
    case create
    case update
    case delete
}

// MARK: - Create/Update Request Models
struct CreateMetricRequest: Codable {
    let metric_type_id: Int
    let value: Double
    let date: String
    let is_apple_health: Bool
    
    init(entry: StatEntry) {
        self.metric_type_id = entry.type.metricTypeId
        self.value = entry.value
        self.date = DateFormatter.apiFormatter.string(from: entry.date)
        self.is_apple_health = entry.source == .appleHealth
    }
}

struct UpdateMetricRequest: Codable {
    let value: Double
    let date: String
    
    init(entry: StatEntry) {
        self.value = entry.value
        self.date = DateFormatter.apiFormatter.string(from: entry.date)
    }
}

// MARK: - Response Models
struct MetricResponse: Codable {
    let success: Bool
    let message: String
    let entryId: Int?
    let error: String?
}

// MARK: - Date Formatter Extension
extension DateFormatter {
    static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Legacy Sync Operation (for backward compatibility)
struct SyncOperation: Codable {
    let operationType: SyncOperationType
    let entry: StatEntry
    
    init(operationType: SyncOperationType, entry: StatEntry) {
        self.operationType = operationType
        self.entry = entry
    }
}
