import Foundation
import SwiftUI
import PhotosUI

class ProgressPhotoManager: ObservableObject {
    static let shared = ProgressPhotoManager()
    
    private let saveKey = "progress_photos"
    @Published var photos: [ProgressPhoto] = []
    @Published var selectedCategory: PhotoCategory?
    
    init() {
        loadPhotos()
    }
    
    func addPhoto(photo: ProgressPhoto) {
        photos.append(photo)
        photos.sort { $0.date > $1.date }
        savePhotos()
    }
    
    func updatePhoto(photo: ProgressPhoto) {
        if let index = photos.firstIndex(where: { $0.id == photo.id }) {
            photos[index] = photo
            savePhotos()
        }
    }
    
    func deletePhoto(id: UUID) {
        photos.removeAll { $0.id == id }
        savePhotos()
    }
    
    func getPhotos(for category: PhotoCategory? = nil) -> [ProgressPhoto] {
        if let category = category {
            return photos.filter { $0.categories.contains(category) }.sorted(by: { $0.date > $1.date })
        } else {
            return photos.sorted(by: { $0.date > $1.date })
        }
    }
    
    func getPhotosByDate(category: PhotoCategory? = nil) -> [Date: [ProgressPhoto]] {
        let filteredPhotos = category != nil ? getPhotos(for: category!) : photos
        
        return Dictionary(grouping: filteredPhotos) { photo in
            // Group by day (without time)
            Calendar.current.startOfDay(for: photo.date)
        }
    }
    
    func getLatestPhotosByCategory() -> [PhotoCategory: ProgressPhoto] {
        var result: [PhotoCategory: ProgressPhoto] = [:]
        
        for category in PhotoCategory.allCases {
            if let latestPhoto = photos
                .filter({ $0.categories.contains(category) })
                .sorted(by: { $0.date > $1.date })
                .first {
                result[category] = latestPhoto
            }
        }
        
        return result
    }
    
    // Get the most recent and second most recent photos for a category
    func getComparisonPhotos(for category: PhotoCategory) -> (latest: ProgressPhoto?, previous: ProgressPhoto?) {
        let categoryPhotos = photos
            .filter { $0.categories.contains(category) }
            .sorted(by: { $0.date > $1.date })
        
        if categoryPhotos.isEmpty {
            return (nil, nil)
        } else if categoryPhotos.count == 1 {
            return (categoryPhotos[0], nil)
        } else {
            return (categoryPhotos[0], categoryPhotos[1])
        }
    }
    
    // Return all categories that a photo belongs to
    func getCategories(for photo: ProgressPhoto) -> [PhotoCategory] {
        return photo.categories
    }
    
    // Check if a photo belongs to a specific category
    func photoInCategory(photo: ProgressPhoto, category: PhotoCategory) -> Bool {
        return photo.categories.contains(category)
    }
    
    private func savePhotos() {
        if let encoded = try? JSONEncoder().encode(photos) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadPhotos() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ProgressPhoto].self, from: data) {
            photos = decoded
            print("📱 Loaded \(photos.count) photos")
        } else {
            print("📱 No photos found in storage or failed to decode")
        }
    }
    
    // Helper function to associate measurements with a photo
    func getMeasurementsAtTime(date: Date, statsManager: StatsHistoryManager) -> [StatEntry] {
        var measurements: [StatEntry] = []
        
        // Get key measurements close to the photo date
        let relevantTypes: [StatType] = [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder]
        
        for type in relevantTypes {
            if let entry = statsManager.getEntries(for: type)
                .filter({ $0.date <= date })
                .sorted(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                .first {
                measurements.append(entry)
            }
        }
        
        return measurements
    }
} 