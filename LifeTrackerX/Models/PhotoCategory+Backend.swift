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
}

extension Date {
    var iso8601StringUTC: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}


