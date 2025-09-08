import Foundation
import Network
import os.log

@MainActor
class ImageSyncManager: ObservableObject {
    static let shared = ImageSyncManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ImageSync")
    private let networkManager = NetworkManager.shared
    private let photoManager = ProgressPhotoManager.shared
    
    @Published var isOnline = false
    @Published var syncing = false
    
    private var networkMonitor: NWPathMonitor?
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 30
    
    private init() {
        setupNetworkMonitoring()
        setupPeriodicSync()
    }
    
    deinit {
        networkMonitor?.cancel()
        syncTimer?.invalidate()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                if !wasOnline && self?.isOnline == true {
                    Task { await self?.sync() }
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global())
    }
    
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sync()
            }
        }
    }
    
    func sync() async {
        guard isOnline && !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            // 1) Fetch remote metadata
            let remote = try await networkManager.listImages(limit: 1000, offset: 0)
            let remoteIds = Set(remote.images.compactMap { Int($0.id) })
            
            // 2) Build local map by backendId (if present)
            var localByBackendId: [Int: ProgressPhoto] = [:]
            for photo in photoManager.photos {
                if let backendId = photo.backendId {
                    localByBackendId[backendId] = photo
                }
            }
            
            // 3) Upload local photos missing on server
            for photo in photoManager.photos {
                if let backendId = photo.backendId, remoteIds.contains(backendId) {
                    continue
                }
                // No backendId or remote missing → upload using primary category
                let typeId = photo.primaryCategory.backendImageTypeId
                let uploadedAt = photo.date.iso8601StringUTC
                do {
                    let resp = try await networkManager.uploadImage(imageData: photo.imageData, imageTypeId: typeId, uploadedAtISO8601: uploadedAt)
                    if resp.success == true, let newId = resp.id {
                        // Persist backendId locally
                        if let index = photoManager.photos.firstIndex(where: { $0.id == photo.id }) {
                            var updated = photoManager.photos[index]
                            updated.backendId = newId
                            photoManager.photos[index] = updated
                            // Save metadata file
                            // ProgressPhotoManager handles save on updatePhoto; call update to persist
                            photoManager.updatePhoto(photo: updated)
                        }
                    }
                } catch {
                    logger.error("Upload during sync failed: \(error.localizedDescription)")
                }
            }
            
            // 4) Remote entries missing locally → no action (no download pipeline yet)
            //    Could be implemented later using downloadImage
            
            // 5) Handle deletions queued locally (not yet tracked separately). If a local photo has backendId but was deleted locally, we already removed it.
            //    For now, expose a public delete API to be called by UI that will also call backend.
        } catch {
            logger.error("Image sync failed: \(error.localizedDescription)")
        }
    }
    
    func delete(photo: ProgressPhoto) async {
        // Remove locally first
        photoManager.deletePhoto(id: photo.id)
        // If it exists on backend, attempt soft delete
        if let backendId = photo.backendId {
            do {
                _ = try await networkManager.deleteImage(id: backendId)
            } catch {
                logger.error("Failed to delete remote image: \(error.localizedDescription)")
            }
        }
    }
}


