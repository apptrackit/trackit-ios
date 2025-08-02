import Foundation

enum StatType: String, Codable, CaseIterable, Identifiable, CustomStringConvertible {
    case weight, height, bodyFat, bmi, waist, bicep, chest, thigh, shoulder, glutes
    case calf, neck, forearm
    case lbm, fm, ffmi, bmr, bsa  // Added new calculated measurements
    
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
        case .lbm: return "kg"
        case .fm: return "kg"
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
        case .lbm: return "Lean Body Mass"
        case .fm: return "Fat Mass"
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
        case .lbm: return "figure.arms.open"
        case .fm: return "figure.arms.open"
        case .ffmi: return "chart.bar.fill"
        case .bmr: return "flame.fill"
        case .bsa: return "person.fill"
        }
    }
    
    var isCalculated: Bool {
        switch self {
        case .bmi, .lbm, .fm, .ffmi, .bmr, .bsa:
            return true
        default:
            return false
        }
    }
    
    var description: String {
        return self.rawValue
    }
}
