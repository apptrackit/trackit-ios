import Foundation
import Network
import os.log
import Combine

// MARK: - New Sync Manager
@MainActor
class MetricSyncManager: ObservableObject {
    static let shared = MetricSyncManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SyncManager")
    private let networkManager = NetworkManager.shared
    private let localDatabase = LocalDatabaseManager.shared
    
    // MARK: - Published Properties
    @Published var isOnline = false
    @Published var syncStatus: String = "Ready"
    @Published var pendingSyncCount = 0
    @Published var lastSyncDate: Date?
    
    // MARK: - Network Monitoring
    private var networkMonitor: NWPathMonitor?
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 30 // 30 seconds
    
    // MARK: - Sync Configuration
    private let maxRetryCount = 3
    private let retryDelay: TimeInterval = 5
    private let batchSize = 10 // Process in batches to avoid overwhelming the server
    
    private init() {
        setupNetworkMonitoring()
        setupPeriodicSync()
        updatePendingCount()
        lastSyncDate = UserDefaults.standard.object(forKey: "LastBackendSyncDate") as? Date
    }
    
    deinit {
        networkMonitor?.cancel()
        syncTimer?.invalidate()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                
                self?.logger.info("Network status changed: \(self?.isOnline == true ? "online" : "offline")")
                
                // If we came back online, start syncing
                if !wasOnline && self?.isOnline == true {
                    self?.logger.info("Network restored, starting sync...")
                    Task { @MainActor in
                        await self?.processPendingOperations()
                    }
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
    
    // MARK: - Periodic Sync
    
    private func setupPeriodicSync() {
        syncTimer?.invalidate()
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processPendingOperations()
            }
        }
    }
    
    private func updatePendingCount() {
        let pendingEntries = localDatabase.getPendingSyncEntries()
        pendingSyncCount = pendingEntries.count
    }
    
    // MARK: - Sync Operations
    
    /// Process all pending sync operations
    func processPendingOperations() async {
        guard isOnline else {
            logger.info("Offline - skipping sync")
            return
        }
        
        let pendingEntries = localDatabase.getPendingSyncEntries()
        guard !pendingEntries.isEmpty else {
            return
        }
        
        logger.info("Processing \(pendingEntries.count) pending operations")
        syncStatus = "Syncing..."
        
        // Process in batches to avoid overwhelming the server
        let batches = pendingEntries.chunked(into: batchSize)
        
        for batch in batches {
            await processBatch(batch)
        }
        
        // Update counters and status
        updatePendingCount()
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "LastBackendSyncDate")
        
        if pendingSyncCount == 0 {
            syncStatus = "All synced"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.syncStatus = "Ready"
            }
        } else {
            syncStatus = "Ready"
        }
        
        logger.info("Sync completed. Remaining pending: \(pendingSyncCount)")
    }
    
    private func processBatch(_ batch: [HealthMetric]) async {
        for entry in batch {
            await processEntry(entry)
        }
    }
    
    private func processEntry(_ entry: HealthMetric) async {
        logger.info("Processing entry: \(entry.uuid!.uuidString), status: \(entry.syncStatus!)")
        
        do {
            switch entry.syncStatusEnum {
            case .pendingCreate:
                let success = await createEntryOnBackend(entry)
                if success {
                    logger.info("Successfully created entry on backend")
                } else {
                    logger.warning("Failed to create entry on backend")
                }
                
            case .pendingUpdate:
                let success = await updateEntryOnBackend(entry)
                if success {
                    logger.info("Successfully updated entry on backend")
                } else {
                    logger.warning("Failed to update entry on backend")
                }
                
            case .pendingDelete:
                let success = await deleteEntryOnBackend(entry)
                if success {
                    // Permanently delete from local database after successful backend deletion
                    let _ = localDatabase.permanentlyDeleteEntry(uuid: entry.uuid!)
                    logger.info("Successfully deleted entry from backend and local storage")
                } else {
                    logger.warning("Failed to delete entry from backend")
                }
                
            case .synced:
                // Already synced, skip
                break
            }
        }
    }
    
    // MARK: - Backend API Calls
    
    private func createEntryOnBackend(_ entry: HealthMetric) async -> Bool {
        // Convert HealthMetric to API format
        let request = CreateMetricRequest(
            metric_type_id: Int(entry.metricTypeId),
            value: entry.value,
            date: formatDateForAPI(entry.date!),
            is_apple_health: entry.sourceEnum == .healthKit
        )
        
        do {
            logger.info("Creating entry on backend: type=\(entry.metricTypeId), value=\(entry.value)")
            
            // Make API call
            let response = try await networkManager.createMetric(request)
            
            if response.success, let backendId = response.entryId {
                // Update local entry with backend ID and mark as synced
                let _ = localDatabase.updateSyncStatus(
                    uuid: entry.uuid!,
                    status: .synced,
                    backendId: backendId
                )
                return true
            } else {
                logger.error("Backend returned error: \(response.error ?? "unknown error")")
                return false
            }
            
        } catch {
            logger.error("Network error creating entry: \(error.localizedDescription)")
            return false
        }
    }
    
    private func updateEntryOnBackend(_ entry: HealthMetric) async -> Bool {
        guard let backendId = entry.backendIdInt else {
            logger.error("Cannot update entry - no backend ID")
            return false
        }
        
        let request = UpdateMetricRequest(
            value: entry.value,
            date: formatDateForAPI(entry.date!)
        )
        
        do {
            logger.info("Updating entry on backend: id=\(backendId), value=\(entry.value)")
            
            let response = try await networkManager.updateMetric(backendId, request: request)
            
            if response.success {
                // Mark as synced
                let _ = localDatabase.updateSyncStatus(uuid: entry.uuid!, status: .synced)
                return true
            } else {
                logger.error("Backend returned error: \(response.error ?? "unknown error")")
                return false
            }
            
        } catch {
            logger.error("Network error updating entry: \(error.localizedDescription)")
            return false
        }
    }
    
    private func deleteEntryOnBackend(_ entry: HealthMetric) async -> Bool {
        guard let backendId = entry.backendIdInt else {
            logger.error("Cannot delete entry - no backend ID")
            // If we don't have a backend ID, consider it successfully deleted
            return true
        }
        
        do {
            logger.info("Deleting entry on backend: id=\(backendId)")
            
            let response = try await networkManager.deleteMetric(backendId)
            
            if response.success {
                return true
            } else {
                logger.error("Backend returned error: \(response.error ?? "unknown error")")
                return false
            }
            
        } catch {
            logger.error("Network error deleting entry: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Data Syncing from Backend
    
    /// Sync data from backend to local database (for multi-device sync)
    func syncFromBackend() async {
        guard isOnline else {
            logger.info("Offline - cannot sync from backend")
            return
        }
        
        syncStatus = "Syncing from backend..."
        logger.info("Starting sync from backend")
        
        do {
            let entries = try await networkManager.fetchUserMetrics()
            await processBackendEntries(entries)
            
            syncStatus = "Backend sync completed"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.syncStatus = "Ready"
            }
            
            logger.info("Successfully synced \(entries.count) entries from backend")
        } catch {
            logger.error("Failed to sync from backend: \(error.localizedDescription)")
            syncStatus = "Backend sync failed"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.syncStatus = "Ready"
            }
        }
    }
    
    private func processBackendEntries(_ backendEntries: [StatEntry]) async {
        for backendEntry in backendEntries {
            // Check if we already have this entry
            if let existingEntry = localDatabase.getEntry(backendId: backendEntry.backendId!) {
                // Update if backend version is newer
                if backendEntry.date > existingEntry.modifiedAt! {
                    logger.info("Updating local entry from backend: \(backendEntry.id)")
                    let _ = localDatabase.updateEntry(
                        uuid: existingEntry.uuid!,
                        value: backendEntry.value,
                        date: backendEntry.date,
                        syncStatus: .synced
                    )
                }
            } else {
                // Create new entry from backend
                logger.info("Creating new entry from backend: type=\(backendEntry.type.metricTypeId)")
                let source: DataSource = backendEntry.source == .appleHealth ? .healthKit : .localApp
                
                let _ = localDatabase.createEntry(
                    uuid: backendEntry.id,
                    metricTypeId: backendEntry.type.metricTypeId,
                    value: backendEntry.value,
                    date: backendEntry.date,
                    source: source,
                    backendId: backendEntry.backendId,
                    syncStatus: .synced
                )
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Queue a new entry for creation
    func queueForCreation(_ entry: HealthMetric) {
        let _ = localDatabase.updateSyncStatus(uuid: entry.uuid!, status: .pendingCreate)
        updatePendingCount()
        
        logger.info("Queued entry for creation: \(entry.uuid!.uuidString)")
        
        // Try to sync immediately if online
        if isOnline {
            Task {
                await processPendingOperations()
            }
        }
    }
    
    /// Queue an entry for update
    func queueForUpdate(_ entry: HealthMetric) {
        let _ = localDatabase.updateSyncStatus(uuid: entry.uuid!, status: .pendingUpdate)
        updatePendingCount()
        
        logger.info("Queued entry for update: \(entry.uuid!.uuidString)")
        
        // Try to sync immediately if online
        if isOnline {
            Task {
                await processPendingOperations()
            }
        }
    }
    
    /// Queue an entry for deletion
    func queueForDeletion(_ entry: HealthMetric) {
        let _ = localDatabase.markEntryForDeletion(uuid: entry.uuid!)
        updatePendingCount()
        
        logger.info("Queued entry for deletion: \(entry.uuid!.uuidString)")
        
        // Try to sync immediately if online
        if isOnline {
            Task {
                await processPendingOperations()
            }
        }
    }
    
    /// Force sync all pending operations
    func forceSyncAll() async {
        logger.info("Force syncing all pending operations")
        await processPendingOperations()
    }
    
    /// Force sync from backend
    func forceSyncFromBackend() async {
        logger.info("Force syncing from backend")
        await syncFromBackend()
    }
    
    /// Get sync statistics
    func getSyncStatistics() -> String {
        let pendingEntries = localDatabase.getPendingSyncEntries()
        
        let pendingCreate = pendingEntries.filter { $0.syncStatusEnum == .pendingCreate }.count
        let pendingUpdate = pendingEntries.filter { $0.syncStatusEnum == .pendingUpdate }.count
        let pendingDelete = pendingEntries.filter { $0.syncStatusEnum == .pendingDelete }.count
        
        return """
        🔄 Sync Statistics:
        • Network: \(isOnline ? "Online" : "Offline")
        • Pending create: \(pendingCreate)
        • Pending update: \(pendingUpdate)
        • Pending delete: \(pendingDelete)
        • Last sync: \(lastSyncDate?.formatted() ?? "Never")
        """
    }
    
    // MARK: - Legacy Methods for Backwards Compatibility
    
    func syncEntry(_ entry: StatEntry, operation: SyncOperationType) {
        // Convert StatEntry to HealthMetric if possible
        let allEntries = localDatabase.getAllEntries(includeDeleted: false)
        if let healthMetric = allEntries.first(where: { $0.uuid == entry.id }) {
            switch operation {
            case .create:
                queueForCreation(healthMetric)
            case .update:
                queueForUpdate(healthMetric)
            case .delete:
                queueForDeletion(healthMetric)
            }
        } else {
            logger.warning("Entry not found in local database for sync: \(entry.id)")
        }
    }
    
    func syncAllEntries(_ entries: [StatEntry]) {
        logger.info("Starting sync of \(entries.count) entries to backend")
        for entry in entries {
            // Only sync non-calculated metrics
            if !entry.type.isCalculated {
                logger.info("Syncing entry: \(entry.type.rawValue) from \(entry.source.rawValue) for date \(entry.date)")
                syncEntry(entry, operation: .create)
            }
        }
    }
    
    func forceSync() {
        if isOnline {
            Task {
                await processPendingOperations()
            }
        }
    }
    
    func clearAllPendingOperations() {
        // This is handled by the local database now
        logger.info("Legacy clear method called - no action needed")
    }
    
    func getPendingOperations() -> [SyncOperation] {
        // Convert HealthMetric entries to legacy SyncOperation format for compatibility
        let pendingEntries = localDatabase.getPendingSyncEntries()
        var operations: [SyncOperation] = []
        
        for entry in pendingEntries {
            if let statEntry = entry.toStatEntry() {
                let operationType: SyncOperationType
                switch entry.syncStatusEnum {
                case .pendingCreate:
                    operationType = .create
                case .pendingUpdate:
                    operationType = .update
                case .pendingDelete:
                    operationType = .delete
                case .synced:
                    continue // Skip synced entries
                }
                
                let operation = SyncOperation(operationType: operationType, entry: statEntry)
                operations.append(operation)
            }
        }
        
        return operations
    }
    
    func fetchUserMetrics() async throws -> [StatEntry] {
        return try await networkManager.fetchUserMetrics()
    }
    
    // MARK: - Helper Methods
    
    private func formatDateForAPI(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - NetworkManager Extensions
extension NetworkManager {
    func createMetric(_ request: CreateMetricRequest) async throws -> MetricResponse {
        // This would need to be implemented in the existing NetworkManager
        // For now, return a mock response
        return MetricResponse(success: true, message: "Created", entryId: Int.random(in: 1...1000), error: nil)
    }
    
    func updateMetric(_ id: Int, request: UpdateMetricRequest) async throws -> MetricResponse {
        // This would need to be implemented in the existing NetworkManager
        return MetricResponse(success: true, message: "Updated", entryId: id, error: nil)
    }
    
    func deleteMetric(_ id: Int) async throws -> MetricResponse {
        // This would need to be implemented in the existing NetworkManager
        return MetricResponse(success: true, message: "Deleted", entryId: id, error: nil)
    }
    
    func fetchUserMetrics() async throws -> [StatEntry] {
        // This would need to be implemented in the existing NetworkManager
        // For now, return empty array
        return []
    }
} 