import Foundation
import Network
import os.log

@MainActor
class MetricSyncManager: ObservableObject {
    static let shared = MetricSyncManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MetricSync")
    private let networkManager = NetworkManager.shared
    private let secureStorage = SecureStorageManager.shared
    
    @Published var isOnline = false
    @Published var syncStatus: SyncStatus = .idle
    @Published var pendingOperationsCount = 0
    @Published var lastSyncTimestamp: Date?
    @Published var syncProgress: Double = 0.0
    
    private var pendingOperations: [SyncOperation] = []
    private var networkMonitor: NWPathMonitor?
    private var syncTimer: Timer?
    private let maxRetryCount = 3
    private let syncInterval: TimeInterval = 60 // 1 minute for more responsive sync
    
    private let pendingOperationsKey = "PendingMetricOperations"
    private let lastSyncTimestampKey = "LastMetricSyncTimestamp"
    
    private init() {
        loadLastSyncTimestamp()
        loadPendingOperations()
        setupNetworkMonitoring()
        setupPeriodicSync()
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
                
                if !wasOnline && self?.isOnline == true {
                    self?.logger.info("Network connection restored, starting sync")
                    Task {
                        await self?.performFullSync()
                    }
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global())
    }
    
    // MARK: - Periodic Sync
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performIncrementalSync()
            }
        }
    }
    
    // MARK: - Full Sync Flow
    func performFullSync() async {
        guard isOnline else {
            logger.info("Offline - skipping full sync")
            return
        }
        
        guard syncStatus != .syncing else {
            logger.info("Sync already in progress")
            return
        }
        
        syncStatus = .syncing
        syncProgress = 0.0
        
        do {
            // 1. Process pending operations first
            syncProgress = 0.2
            await processPendingOperations()
            
            // 2. Push unsynced local changes
            syncProgress = 0.4
            try await pushUnsyncedLocalChanges()
            
            // 3. Pull server changes
            syncProgress = 0.6
            let serverChanges = try await pullServerChanges()
            
            // 4. Apply server changes with conflict resolution
            syncProgress = 0.8
            await applyServerChanges(serverChanges)
            
            // 5. Update sync timestamp
            syncProgress = 1.0
            updateLastSyncTimestamp()
            
            syncStatus = .completed(Date())
            logger.info("Full sync completed successfully")
            
        } catch {
            syncStatus = .failed(error.localizedDescription)
            logger.error("Full sync failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Incremental Sync
    func performIncrementalSync() async {
        guard isOnline else { return }
        guard syncStatus != .syncing else { return }
        
        // Only do incremental sync if we have a last sync timestamp
        guard let lastSync = lastSyncTimestamp else {
            await performFullSync()
            return
        }
        
        syncStatus = .syncing
        
        do {
            // 1. Process any pending operations
            await processPendingOperations()
            
            // 2. Push recent unsynced changes
            try await pushUnsyncedLocalChanges()
            
            // 3. Pull changes since last sync
            let changes = try await pullIncrementalChanges(since: lastSync)
            
            // 4. Apply changes
            await applyServerChanges(changes)
            
            // 5. Update timestamp
            updateLastSyncTimestamp()
            
            syncStatus = .completed(Date())
            
        } catch {
            syncStatus = .failed(error.localizedDescription)
            logger.error("Incremental sync failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Push Local Changes
    private func pushUnsyncedLocalChanges() async throws {
        let historyManager = StatsHistoryManager.shared
        let unsyncedEntries = historyManager.entries.filter { $0.needsBackendSync && !$0.isDeleted }
        
        logger.info("Pushing \(unsyncedEntries.count) unsynced local changes")
        
        for entry in unsyncedEntries {
            do {
                if let _ = entry.backendId {
                    // Update existing entry
                    try await updateMetric(entry)
                } else {
                    // Create new entry
                    let createdEntry = try await createMetric(entry)
                    // Update local entry with backend ID
                    historyManager.updateEntryBackendId(localId: entry.id, backendId: createdEntry.id)
                }
                
                // Mark as synced
                historyManager.markEntrySynced(entry.id, syncedWithBackend: true)
                
            } catch {
                logger.error("Failed to push entry \(entry.id): \(error.localizedDescription)")
                // Queue for retry
                queueOperation(SyncOperation(operationType: .create, entry: entry))
            }
        }
    }
    
    // MARK: - Pull Server Changes
    private func pullServerChanges() async throws -> [BackendMetricEntry] {
        logger.info("Pulling all server changes")
        
        let response: MetricsListResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics?include_deleted=true",
            method: "GET"
        )
        
        guard response.success else {
            throw NSError(domain: "MetricSync", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: response.error ?? "Failed to fetch metrics"])
        }
        
        logger.info("Fetched \(response.entries.count) entries from server")
        return response.entries
    }
    
    private func pullIncrementalChanges(since: Date) async throws -> [BackendMetricEntry] {
        let isoFormatter = ISO8601DateFormatter()
        let sinceTimestamp = isoFormatter.string(from: since)
        
        logger.info("Pulling incremental changes since \(sinceTimestamp)")
        
        let response: SyncChangesResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/sync/changes?since_timestamp=\(sinceTimestamp)",
            method: "GET"
        )
        
        logger.info("Fetched \(response.entries.count) changed entries")
        
        // Handle pagination if needed
        var allEntries = response.entries
        if response.has_more {
            // TODO: Implement pagination handling
            logger.warning("More changes available but pagination not yet implemented")
        }
        
        return allEntries
    }
    
    // MARK: - Apply Server Changes
    private func applyServerChanges(_ serverEntries: [BackendMetricEntry]) async {
        let historyManager = StatsHistoryManager.shared
        
        for serverEntry in serverEntries {
            let localEntry = historyManager.findEntry(byUUID: serverEntry.id)
            
            if serverEntry.is_deleted {
                // Handle soft delete
                if let local = localEntry {
                    historyManager.softDeleteEntry(local.id)
                }
            } else if let local = localEntry {
                // Check for conflict
                let serverDate = ISO8601DateFormatter().date(from: serverEntry.last_updated_at) ?? Date()
                
                if serverDate > local.lastUpdatedAt {
                    // Server wins - update local
                    let updatedEntry = serverEntry.toStatEntry()
                    historyManager.updateEntry(updatedEntry)
                    logger.info("Updated local entry with server data: \(serverEntry.metric_type)")
                } else {
                    logger.info("Local entry is newer, keeping local: \(serverEntry.metric_type)")
                }
            } else {
                // New entry from server
                let newEntry = serverEntry.toStatEntry()
                historyManager.addEntry(newEntry)
                logger.info("Added new entry from server: \(serverEntry.metric_type)")
            }
        }
    }
    
    // MARK: - API Operations
    private func createMetric(_ entry: StatEntry) async throws -> BackendMetricEntry {
        let request = MobileMetricRequest(entry: entry)
        let requestData = try JSONEncoder().encode(request)
        
        let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics",
            method: "POST",
            body: requestData
        )
        
        if !response.success {
            throw NSError(domain: "MetricSync", code: response.code ?? -1,
                         userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
        }
        
        guard let createdEntry = response.entry else {
            throw NSError(domain: "MetricSync", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No entry returned from server"])
        }
        
        logger.info("Successfully created metric: \(entry.type.rawValue)")
        return createdEntry
    }
    
    private func updateMetric(_ entry: StatEntry) async throws {
        let request = MobileMetricRequest(entry: entry, isUpdate: true)
        let requestData = try JSONEncoder().encode(request)
        
        let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/\(entry.syncUUID)",
            method: "PUT",
            body: requestData
        )
        
        if response.code == 409 {
            // Conflict - server has newer data
            logger.warning("Conflict detected for entry \(entry.id), server data is newer")
            throw NSError(domain: "MetricSync", code: 409,
                         userInfo: [NSLocalizedDescriptionKey: "Server has newer data"])
        }
        
        if response.code == 410 {
            // Entry was deleted on server
            logger.warning("Entry \(entry.id) was deleted on server")
            throw NSError(domain: "MetricSync", code: 410,
                         userInfo: [NSLocalizedDescriptionKey: "Entry was deleted"])
        }
        
        if !response.success {
            throw NSError(domain: "MetricSync", code: response.code ?? -1,
                         userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
        }
        
        logger.info("Successfully updated metric: \(entry.type.rawValue)")
    }
    
    private func deleteMetric(_ entry: StatEntry) async throws {
        let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/\(entry.syncUUID)",
            method: "DELETE"
        )
        
        if !response.success && response.code != 404 {
            throw NSError(domain: "MetricSync", code: response.code ?? -1,
                         userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
        }
        
        logger.info("Successfully deleted metric: \(entry.type.rawValue)")
    }
    
    // MARK: - Queue Management
    func queueOperation(_ operation: SyncOperation) {
        // Check for duplicates
        let isDuplicate = pendingOperations.contains { existing in
            existing.operationType == operation.operationType &&
            existing.entry.id == operation.entry.id
        }
        
        if !isDuplicate {
            pendingOperations.append(operation)
            savePendingOperations()
            updatePendingCount()
            logger.info("Queued operation: \(operation.operationType.rawValue) for \(operation.entry.type.rawValue)")
        }
    }
    
    private func processPendingOperations() async {
        guard !pendingOperations.isEmpty else { return }
        
        logger.info("Processing \(pendingOperations.count) pending operations")
        
        let operationsToProcess = pendingOperations
        pendingOperations.removeAll()
        savePendingOperations()
        
        for operation in operationsToProcess {
            do {
                switch operation.operationType {
                case .create:
                    _ = try await createMetric(operation.entry)
                case .update:
                    try await updateMetric(operation.entry)
                case .delete:
                    try await deleteMetric(operation.entry)
                case .restore:
                    // TODO: Implement restore
                    logger.warning("Restore operation not yet implemented")
                }
            } catch {
                handleOperationFailure(operation, error: error)
            }
        }
        
        updatePendingCount()
    }
    
    private func handleOperationFailure(_ operation: SyncOperation, error: Error) {
        if operation.retryCount < maxRetryCount {
            let retryOperation = SyncOperation(
                operationType: operation.operationType,
                entry: operation.entry,
                retryCount: operation.retryCount + 1,
                lastError: error.localizedDescription
            )
            queueOperation(retryOperation)
            logger.info("Retrying operation (attempt \(retryOperation.retryCount)/\(maxRetryCount))")
        } else {
            logger.error("Operation failed after \(maxRetryCount) retries: \(operation.operationType.rawValue)")
        }
    }
    
    private func updatePendingCount() {
        DispatchQueue.main.async {
            self.pendingOperationsCount = self.pendingOperations.count
        }
    }
    
    // MARK: - Persistence
    private func savePendingOperations() {
        do {
            let data = try JSONEncoder().encode(pendingOperations)
            UserDefaults.standard.set(data, forKey: pendingOperationsKey)
        } catch {
            logger.error("Failed to save pending operations: \(error.localizedDescription)")
        }
    }
    
    private func loadPendingOperations() {
        guard let data = UserDefaults.standard.data(forKey: pendingOperationsKey) else { return }
        
        do {
            pendingOperations = try JSONDecoder().decode([SyncOperation].self, from: data)
            updatePendingCount()
            logger.info("Loaded \(pendingOperations.count) pending operations")
        } catch {
            logger.error("Failed to load pending operations: \(error.localizedDescription)")
            pendingOperations = []
        }
    }
    
    private func updateLastSyncTimestamp() {
        lastSyncTimestamp = Date()
        UserDefaults.standard.set(lastSyncTimestamp, forKey: lastSyncTimestampKey)
    }
    
    private func loadLastSyncTimestamp() {
        lastSyncTimestamp = UserDefaults.standard.object(forKey: lastSyncTimestampKey) as? Date
    }
    
    // MARK: - Public Interface
    func syncEntry(_ entry: StatEntry, operation: SyncOperationType) {
        queueOperation(SyncOperation(operationType: operation, entry: entry))
        
        Task {
            await performIncrementalSync()
        }
    }
    
    func deleteEntry(_ entry: StatEntry) {
        queueOperation(SyncOperation(operationType: .delete, entry: entry))
        
        Task {
            await performIncrementalSync()
        }
    }
    
    func forceSync() {
        Task {
            await performFullSync()
        }
    }
    
    func clearAllData() {
        pendingOperations.removeAll()
        savePendingOperations()
        updatePendingCount()
        lastSyncTimestamp = nil
        UserDefaults.standard.removeObject(forKey: lastSyncTimestampKey)
        logger.info("Cleared all sync data")
    }
} 