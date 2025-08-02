import Foundation
import SwiftUI
import PhotosUI
import os.log

class ProgressPhotoManager: ObservableObject {
    static let shared = ProgressPhotoManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ProgressPhoto")
    
    private let fileManager = FileManager.default
    private var photosDirectory: URL? {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Could not access documents directory")
            return nil
        }
        let photosDir = documentsDirectory.appendingPathComponent("ProgressPhotos", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: photosDir.path) {
            do {
                try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)
                logger.info("Created progress photos directory")
            } catch {
                logger.error("Failed to create progress photos directory: \(error.localizedDescription)")
                return nil
            }
        }
        
        return photosDir
    }
    
    private var metadataURL: URL? {
        photosDirectory?.appendingPathComponent("metadata.json")
    }
    
    @Published var photos: [ProgressPhoto] = []
    @Published var selectedCategory: PhotoCategory?
    
    private init() {
        loadPhotos()
    }
    
    func addPhoto(photo: ProgressPhoto) {
        self.photos.append(photo)
        self.photos.sort { $0.date > $1.date }
        savePhotos()
    }
    
    func updatePhoto(photo: ProgressPhoto) {
        if let index = self.photos.firstIndex(where: { $0.id == photo.id }) {
            self.photos[index] = photo
            savePhotos()
        }
    }
    
    func deletePhoto(id: UUID) {
        if self.photos.contains(where: { $0.id == id }) {
            // Delete the actual photo file
            deletePhoto(id: id.uuidString)
            // Remove from metadata
            self.photos.removeAll { $0.id == id }
            savePhotos()
        }
    }
    
    func getPhotos(for category: PhotoCategory? = nil) -> [ProgressPhoto] {
        if let category = category {
            if category == .all {
                return self.photos.sorted(by: { $0.date > $1.date })
            }
            return self.photos.filter { $0.categories.contains(category) }.sorted(by: { $0.date > $1.date })
        } else {
            return self.photos.sorted(by: { $0.date > $1.date })
        }
    }
    
    func getPhotosByDate(category: PhotoCategory? = nil) -> [Date: [ProgressPhoto]] {
        let filteredPhotos = category != nil ? getPhotos(for: category!) : self.photos
        
        return Dictionary(grouping: filteredPhotos) { photo in
            Calendar.current.startOfDay(for: photo.date)
        }
    }
    
    func getLatestPhotosByCategory() -> [PhotoCategory: ProgressPhoto] {
        var result: [PhotoCategory: ProgressPhoto] = [:]
        
        for category in PhotoCategory.allCases {
            if category == .all {
                if let latestPhoto = self.photos.sorted(by: { $0.date > $1.date }).first {
                    result[category] = latestPhoto
                }
            } else if let latestPhoto = self.photos
                .filter({ $0.categories.contains(category) })
                .sorted(by: { $0.date > $1.date })
                .first {
                result[category] = latestPhoto
            }
        }
        
        return result
    }
    
    func getComparisonPhotos(for category: PhotoCategory) -> (latest: ProgressPhoto?, previous: ProgressPhoto?) {
        let categoryPhotos: [ProgressPhoto]
        
        if category == .all {
            categoryPhotos = self.photos.sorted(by: { $0.date > $1.date })
        } else {
            categoryPhotos = self.photos
                .filter { $0.categories.contains(category) }
                .sorted(by: { $0.date > $1.date })
        }
        
        if categoryPhotos.isEmpty {
            return (nil, nil)
        } else if categoryPhotos.count == 1 {
            return (categoryPhotos[0], nil)
        } else {
            return (categoryPhotos[0], categoryPhotos[1])
        }
    }
    
    func getCategories(for photo: ProgressPhoto) -> [PhotoCategory] {
        return photo.categories
    }
    
    func photoInCategory(photo: ProgressPhoto, category: PhotoCategory) -> Bool {
        return photo.categories.contains(category)
    }
    
    private func savePhotos() {
        guard let metadataURL = metadataURL else {
            logger.error("Failed to get metadata URL")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self.photos)
            try data.write(to: metadataURL)
            logger.info("Successfully saved photo metadata")
        } catch {
            logger.error("Failed to save photo metadata: \(error.localizedDescription)")
        }
    }
    
    private func loadPhotos() {
        guard let metadataURL = metadataURL else {
            logger.error("Failed to get metadata URL")
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            self.photos = try decoder.decode([ProgressPhoto].self, from: data)
            logger.info("Successfully loaded \(self.photos.count) photos from metadata")
        } catch {
            logger.error("Failed to load photo metadata: \(error.localizedDescription)")
            self.photos = []
        }
    }
    
    func getMeasurementsAtTime(date: Date, statsManager: StatsHistoryManager) -> [StatEntry] {
        var measurements: [StatEntry] = []
        let relevantTypes: [StatType] = [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
        
        for type in relevantTypes {
            let entries = statsManager.getEntries(for: type)
                .filter { $0.date <= date }
                .sorted { $0.date > $1.date }
            
            if let entry = entries.first {
                measurements.append(entry)
            }
        }
        
        return measurements
    }
    
    func savePhoto(_ photoData: Data, id: String) {
        guard let photosDir = photosDirectory else { return }
        
        let photoURL = photosDir.appendingPathComponent("\(id).jpg")
        
        do {
            try photoData.write(to: photoURL)
            logger.info("Successfully saved progress photo with ID: \(id)")
        } catch {
            logger.error("Failed to save progress photo: \(error.localizedDescription)")
        }
    }
    
    func getPhoto(id: String) -> Data? {
        guard let photosDir = photosDirectory else { return nil }
        
        let photoURL = photosDir.appendingPathComponent("\(id).jpg")
        
        do {
            let photoData = try Data(contentsOf: photoURL)
            logger.info("Successfully loaded progress photo with ID: \(id)")
            return photoData
        } catch {
            logger.error("Failed to load progress photo: \(error.localizedDescription)")
            return nil
        }
    }
    
    func deletePhoto(id: String) {
        guard let photosDir = photosDirectory else { return }
        
        let photoURL = photosDir.appendingPathComponent("\(id).jpg")
        
        do {
            try fileManager.removeItem(at: photoURL)
            logger.info("Successfully deleted progress photo with ID: \(id)")
        } catch {
            logger.error("Failed to delete progress photo: \(error.localizedDescription)")
        }
    }
    
    func getAllPhotoIds() -> [String] {
        guard let photosDir = photosDirectory else { return [] }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            let photoIds = fileURLs.compactMap { url -> String? in
                let filename = url.lastPathComponent
                return filename.replacingOccurrences(of: ".jpg", with: "")
            }
            logger.info("Found \(photoIds.count) progress photos")
            return photoIds
        } catch {
            logger.error("Failed to get progress photo IDs: \(error.localizedDescription)")
            return []
        }
    }
    
    func clearAllPhotos() {
        guard let photosDir = photosDirectory else { return }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try fileManager.removeItem(at: fileURL)
            }
            self.photos = []
            savePhotos()
            logger.info("Successfully cleared all progress photos")
        } catch {
            logger.error("Failed to clear progress photos: \(error.localizedDescription)")
        }
    }
} 