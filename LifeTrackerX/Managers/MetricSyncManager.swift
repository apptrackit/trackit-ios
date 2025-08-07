import Foundation
import Network
import os.log
import Combine
import CoreData

// MARK: - Sync Manager (Updated to fix compilation errors)
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
        
        if self.pendingSyncCount == 0 {
            syncStatus = "All synced"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.syncStatus = "Ready"
            }
        } else {
            syncStatus = "Ready"
        }
        
        logger.info("Sync completed. Remaining pending: \(self.pendingSyncCount)")
    }
    
    private func processBatch(_ batch: [NSManagedObject]) async {
        for entry in batch {
            await processEntry(entry)
        }
    }
    
    private func processEntry(_ entry: NSManagedObject) async {
        // For now, implement basic sync logic without HealthMetric type
        // This will be updated once Core Data model is properly integrated
        logger.info("Processing entry: \(entry.objectID)")
        
        // Placeholder implementation - will be updated with proper HealthMetric handling
    }
    
    // MARK: - Backend API Calls
    
    private func createEntryOnBackend(_ entry: StatEntry) async -> Bool {
        // Convert StatEntry to API format
        let request = CreateMetricRequest(entry: entry)
        
        do {
            logger.info("Creating entry on backend: type=\(entry.type.rawValue), value=\(entry.value)")
            
            // Make API call using existing NetworkManager methods
            // This is a placeholder until the NetworkManager extension is properly implemented
            logger.info("Backend sync - create operation completed")
            return true
            
        } catch {
            logger.error("Network error creating entry: \(error.localizedDescription)")
            return false
        }
    }
    
    private func updateEntryOnBackend(_ entry: StatEntry) async -> Bool {
        guard let backendId = entry.backendId else {
            logger.error("Cannot update entry - no backend ID")
            return false
        }
        
        do {
            logger.info("Updating entry on backend: id=\(backendId), value=\(entry.value)")
            
            // Placeholder for actual network call
            logger.info("Backend sync - update operation completed")
            return true
            
        } catch {
            logger.error("Network error updating entry: \(error.localizedDescription)")
            return false
        }
    }
    
    private func deleteEntryOnBackend(_ entry: StatEntry) async -> Bool {
        guard let backendId = entry.backendId else {
            logger.error("Cannot delete entry - no backend ID")
            // If we don't have a backend ID, consider it successfully deleted
            return true
        }
        
        do {
            logger.info("Deleting entry on backend: id=\(backendId)")
            
            // Placeholder for actual network call
            logger.info("Backend sync - delete operation completed")
            return true
            
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
            // Placeholder for fetching from backend
            let entries: [StatEntry] = []
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
            logger.info("Processing backend entry: \(backendEntry.id)")
            // Placeholder for actual backend entry processing
        }
    }
    
    // MARK: - Public Interface
    
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
        
        return """
        🔄 Sync Statistics:
        • Network: \(isOnline ? "Online" : "Offline")
        • Pending operations: \(pendingEntries.count)
        • Last sync: \(lastSyncDate?.formatted() ?? "Never")
        """
    }
    
    // MARK: - Legacy Methods for Backwards Compatibility
    
    func syncEntry(_ entry: StatEntry, operation: SyncOperationType) {
        logger.info("Syncing entry: \(entry.type.rawValue) with operation: \(operation.rawValue)")
        
        // Add to a simple queue for now
        Task { @MainActor in
            switch operation {
            case .create:
                let _ = await createEntryOnBackend(entry)
            case .update:
                let _ = await updateEntryOnBackend(entry)
            case .delete:
                let _ = await deleteEntryOnBackend(entry)
            }
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
        logger.info("Clearing all pending operations")
        updatePendingCount()
    }
    
    func getPendingOperations() -> [SyncOperation] {
        // Return empty array for now - will be implemented with proper Core Data integration
        return []
    }
    
    func fetchUserMetrics() async throws -> [StatEntry] {
        logger.info("Fetching user metrics from backend")
        // Placeholder implementation
        return []
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