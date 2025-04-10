import Foundation
import SwiftUI

enum PhotoCategory: String, CaseIterable, Identifiable, Codable {
    case front, side, back
    case arms, chest, legs, shoulders, abs
    case other
    
    var id: String { self.rawValue }
    
    var name: String {
        switch self {
        case .front: return "Front"
        case .side: return "Side"
        case .back: return "Back"
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
    var categories: [PhotoCategory]
    var imageData: Data
    var associatedMeasurements: [StatEntry]?
    var notes: String?
    
    // Define the CodingKeys to handle both old and new format
    enum CodingKeys: String, CodingKey {
        case id, date, imageData, associatedMeasurements, notes
        case categories
        case category // For backward compatibility
    }
    
    init(id: UUID = UUID(), date: Date = Date(), categories: [PhotoCategory], imageData: Data, associatedMeasurements: [StatEntry]? = nil, notes: String? = nil) {
        self.id = id
        self.date = date
        self.categories = categories
        self.imageData = imageData
        self.associatedMeasurements = associatedMeasurements
        self.notes = notes
    }
    
    // For backward compatibility with older data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        imageData = try container.decode(Data.self, forKey: .imageData)
        associatedMeasurements = try container.decodeIfPresent([StatEntry].self, forKey: .associatedMeasurements)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        
        // Handle both old and new format
        if let singleCategory = try? container.decodeIfPresent(PhotoCategory.self, forKey: .category) {
            categories = [singleCategory]
        } else {
            categories = try container.decodeIfPresent([PhotoCategory].self, forKey: .categories) ?? []
        }
    }
    
    // Custom encode implementation to save in new format
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(imageData, forKey: .imageData)
        try container.encodeIfPresent(associatedMeasurements, forKey: .associatedMeasurements)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(categories, forKey: .categories)
    }
    
    // Primary category for backward compatibility
    var primaryCategory: PhotoCategory {
        categories.first ?? .other
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