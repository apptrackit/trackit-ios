import Foundation

extension PhotoCategory {
    // Backend image_types assumed IDs from seed order:
    // 1 front, 2 back, 3 side, 4 biceps, 5 chest, 6 legs, 7 full body, 8 other
    var backendImageTypeId: Int {
        switch self {
        case .front: return 1
        case .back: return 2
        case .side: return 3
        case .arms: return 4 // biceps
        case .chest: return 5
        case .legs: return 6
        case .shoulders: return 8 // not present on backend, map to other
        case .abs: return 8 // not present on backend, map to other
        case .glutes: return 8 // not present on backend, map to other
        case .other, .all: return 8
        }
    }

    static func fromBackendImageTypeId(_ id: Int) -> PhotoCategory {
        switch id {
        case 1: return .front
        case 2: return .back
        case 3: return .side
        case 4: return .arms
        case 5: return .chest
        case 6: return .legs
        case 7: return .other // full body not defined; map to other
        case 8: return .other
        default: return .other
        }
    }
}

extension Date {
    var iso8601StringUTC: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}


