import Foundation

enum TimeFrame: String, CaseIterable {
    case week = "W"
    case month = "M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "Y"
    case all = "All"
    
    // Legacy cases for backward compatibility
    case weekly = "W"
    case monthly = "M"
    case yearly = "Y"
    case allTime = "All"
    
    var title: String {
        switch self {
        case .week, .weekly: return "Week"
        case .month, .monthly: return "Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .year, .yearly: return "Year"
        case .all, .allTime: return "All Time"
        }
    }
} 