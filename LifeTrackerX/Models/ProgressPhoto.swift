import Foundation
import SwiftUI

enum PhotoCategory: String, CaseIterable, Identifiable, Codable {
    case front, side, back
    case arms, chest, legs, shoulders, abs
    case other
    
    var id: String { self.rawValue }
    
    var name: String {
        switch self {
        case .front: return "Front View"
        case .side: return "Side View"
        case .back: return "Back View"
        case .arms: return "Arms"
        case .chest: return "Chest"
        case .legs: return "Legs"
        case .shoulders: return "Shoulders"
        case .abs: return "Abs"
        case .other: return "Other"
        }
    }
    
    var iconName: String {
        switch self {
        case .front: return "person.fill"
        case .side: return "person.fill.turn.right"
        case .back: return "person.fill.turn.down"
        case .arms: return "figure.arms.open"
        case .chest: return "heart.fill"
        case .legs: return "figure.walk"
        case .shoulders: return "figure.american.football"
        case .abs: return "figure.core.training"
        case .other: return "camera.fill"
        }
    }
}

struct ProgressPhoto: Identifiable, Codable {
    var id: UUID
    var date: Date
    var category: PhotoCategory
    var imageData: Data
    var associatedMeasurements: [StatEntry]?
    var notes: String?
    
    init(id: UUID = UUID(), date: Date = Date(), category: PhotoCategory, imageData: Data, associatedMeasurements: [StatEntry]? = nil, notes: String? = nil) {
        self.id = id
        self.date = date
        self.category = category
        self.imageData = imageData
        self.associatedMeasurements = associatedMeasurements
        self.notes = notes
    }
}

// Extension to get UIImage from Data
extension ProgressPhoto {
    var image: UIImage? {
        if let uiImage = UIImage(data: imageData) {
            return uiImage
        }
        return nil
    }
} 