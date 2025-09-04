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
    @Published var syncStatus: SyncStatus = .completed
    @Published var pendingOperationsCount = 0
    
    private var pendingOperations: [SyncOperation] = []
    private var networkMonitor: NWPathMonitor?
    private var syncTimer: Timer?
    private let maxRetryCount = 3
    private let syncInterval: TimeInterval = 30 // 30 seconds
    
    private let pendingOperationsKey = "PendingMetricOperations"
    
    private init() {
        // Clear any old pending operations on app start to prevent infinite loops
        clearAllPendingOperations()
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
                    self?.logger.info("Network connection restored, processing pending operations")
                    self?.processPendingOperations()
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global())
    }
    
    // MARK: - Periodic Sync
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processPendingOperations()
            }
        }
    }
    
    // MARK: - Queue Management
    func queueOperation(_ operation: SyncOperation) {
        // Check if this exact operation is already queued to prevent duplicates
        let isDuplicate = pendingOperations.contains { existing in
            existing.operationType == operation.operationType &&
            existing.statType == operation.statType &&
            existing.date == operation.date &&
            existing.value == operation.value &&
            existing.source == operation.source
        }
        
        if isDuplicate {
            logger.info("Skipping duplicate operation: \(operation.operationType.rawValue) for \(operation.statType.rawValue)")
            return
        }
        
        pendingOperations.append(operation)
        savePendingOperations()
        updatePendingCount()
        
        logger.info("Queued operation: \(operation.operationType.rawValue) for \(operation.statType.rawValue)")
    }
    
    func removeOperation(_ operation: SyncOperation) {
        pendingOperations.removeAll { $0.id == operation.id }
        savePendingOperations()
        updatePendingCount()
    }
    
    private func updatePendingCount() {
        DispatchQueue.main.async {
            self.pendingOperationsCount = self.pendingOperations.count
        }
    }
    
    // MARK: - Operation Processing
    private func processPendingOperations() {
        guard isOnline && !self.pendingOperations.isEmpty else { return }
        
        logger.info("Processing \(self.pendingOperations.count) pending operations")
        
        DispatchQueue.main.async {
            self.syncStatus = .inProgress
        }
        
        // Make a snapshot to avoid re-entrancy and duplicate processing
        let operationsToProcess = self.pendingOperations.sorted { $0.createdAt < $1.createdAt }
        
        Task { @MainActor in
            for operation in operationsToProcess {
                do {
                    try await processOperation(operation)
                    self.removeOperation(operation)
                } catch {
                    self.logger.error("Failed to process operation: \(error.localizedDescription)")
                    self.handleOperationFailure(operation, error: error)
                }
            }
            
            self.syncStatus = .completed
        }
    }
    
    private func processOperation(_ operation: SyncOperation) async throws {
        switch operation.operationType {
        case .create:
            // For create operations, check if the entry already exists on the backend
            if await entryExistsOnBackend(operation) {
                logger.info("Entry already exists on backend, skipping create: \(operation.statType.rawValue) for \(operation.date)")
                // Persist backendId if found
                if let foundId = await getBackendIdForClientUUID(operation.entryId) {
                    await persistBackendId(clientUUID: operation.entryId, backendId: foundId)
                }
                return
            }
            try await createMetric(operation)
        case .update:
            try await updateMetric(operation)
        case .delete:
            try await deleteMetric(operation)
        }
    }
    
    private func entryExistsOnBackend(_ operation: SyncOperation) async -> Bool {
        do {
            let response: MetricsListResponse = try await networkManager.makeAuthenticatedRequest(
                "/api/metrics",
                method: "GET"
            )
            
            if response.success {
                // Prefer matching by client_uuid to prevent duplicates
                let existingEntry = response.entries.first { metric in
                    metric.client_uuid == operation.entryId.uuidString
                }
                return existingEntry != nil
            }
        } catch {
            logger.error("Failed to check if entry exists on backend: \(error.localizedDescription)")
        }
        return false
    }
    
    private func handleOperationFailure(_ operation: SyncOperation, error: Error) {
        if operation.retryCount < self.maxRetryCount {
            let retryOperation = SyncOperation(
                operationType: operation.operationType,
                entry: StatEntry(
                    id: operation.entryId,
                    date: operation.date,
                    value: operation.value,
                    type: operation.statType,
                    source: operation.source,
                    backendId: operation.backendId
                ),
                retryCount: operation.retryCount + 1
            )
            
            removeOperation(operation)
            queueOperation(retryOperation)
            
            logger.info("Retrying operation (attempt \(retryOperation.retryCount)/\(self.maxRetryCount))")
        } else {
            logger.error("Operation failed after \(self.maxRetryCount) retries: \(operation.operationType.rawValue)")
            removeOperation(operation)
        }
    }
    
    // MARK: - API Operations
    private func createMetric(_ operation: SyncOperation) async throws {
        let entry = StatEntry(
            id: operation.entryId,
            date: operation.date,
            value: operation.value,
            type: operation.statType,
            source: operation.source,
            version: operation.version
        )
        
        let request = CreateMetricRequest(entry: entry)
        let requestData = try JSONEncoder().encode(request)
        
        do {
            let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
                "/api/metrics",
                method: "POST",
                body: requestData
            )
            if !response.success {
                throw NSError(domain: "MetricSync", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: response.error ?? "Unknown error"
                ])
            }
            // If backend returned an ID, persist it on the local entry
            if let createdId = response.entryId {
                await persistBackendId(clientUUID: operation.entryId, backendId: createdId)
            }
        } catch {
            // If server reports duplicate (already created), treat as success
            // by verifying existence using client_uuid
            if let foundId = await getBackendIdForClientUUID(operation.entryId) {
                await persistBackendId(clientUUID: operation.entryId, backendId: foundId)
                logger.info("Server reported error, but entry exists on backend. Treating as success.")
            } else {
                throw error
            }
        }
        
        logger.info("Successfully created metric: \(operation.statType.rawValue)")
    }

    // Attempt to find backend ID for a given client UUID by fetching metrics
    private func getBackendIdForClientUUID(_ clientUUID: UUID) async -> Int? {
        do {
            let response: MetricsListResponse = try await networkManager.makeAuthenticatedRequest(
                "/api/metrics",
                method: "GET"
            )
            if response.success,
               let match = response.entries.first(where: { $0.client_uuid == clientUUID.uuidString }) {
                return match.id
            }
        } catch {
            logger.error("Failed to fetch backend ID for client UUID: \(error.localizedDescription)")
        }
        return nil
    }

    // Persist backendId on the matching local entry and save
    @MainActor
    private func persistBackendId(clientUUID: UUID, backendId: Int) {
        let manager = StatsHistoryManager.shared
        manager.setBackendId(forClientUUID: clientUUID, backendId: backendId)
    }
    
    private func updateMetric(_ operation: SyncOperation) async throws {
        let entry = StatEntry(
            id: operation.entryId,
            date: operation.date,
            value: operation.value,
            type: operation.statType,
            source: operation.source,
            version: operation.version
        )
        
        let request = UpdateMetricRequest(entry: entry)
        let requestData = try JSONEncoder().encode(request)
        
        // Use backend ID for updates, as the URL path expects an integer ID
        guard let backendId = operation.backendId else {
            throw NSError(domain: "MetricSync", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot update entry without backend ID"
            ])
        }
        let identifier = backendId.description
        let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/\(identifier)",
            method: "PUT",
            body: requestData
        )
        
        if !response.success {
            throw NSError(domain: "MetricSync", code: -1, userInfo: [
                NSLocalizedDescriptionKey: response.error ?? "Unknown error"
            ])
        }
        
        logger.info("Successfully updated metric: \(operation.statType.rawValue)")
    }
    
    private func deleteMetric(_ operation: SyncOperation) async throws {
        // Use backend ID for deletes, as the URL path expects an integer ID
        guard let backendId = operation.backendId else {
            throw NSError(domain: "MetricSync", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot delete entry without backend ID"
            ])
        }
        let identifier = backendId.description
        let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/\(identifier)",
            method: "DELETE"
        )
        
        if !response.success {
            throw NSError(domain: "MetricSync", code: -1, userInfo: [
                NSLocalizedDescriptionKey: response.error ?? "Unknown error"
            ])
        }
        
        logger.info("Successfully deleted metric: \(operation.statType.rawValue)")
    }
    
    // MARK: - Public Interface
    func syncEntry(_ entry: StatEntry, operation: SyncOperationType) {
        let syncOperation = SyncOperation(operationType: operation, entry: entry)
        queueOperation(syncOperation)
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

    // MARK: - Bulk Upload (initial/full sync)
    func bulkUpload(_ entries: [StatEntry]) async throws {
        let payload = entries.filter { !$0.type.isCalculated }.map { CreateMetricRequest(entry: $0) }
        let data = try JSONEncoder().encode(payload)
        let _: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/bulk",
            method: "POST",
            body: data
        )
        logger.info("Bulk upload completed for \(payload.count) entries")
    }
    
    func forceSync() {
        if isOnline {
            processPendingOperations()
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
            logger.info("Loaded \(self.pendingOperations.count) pending operations")
        } catch {
            logger.error("Failed to load pending operations: \(error.localizedDescription)")
            pendingOperations = []
        }
    }
    
    // MARK: - Utility
    func clearAllPendingOperations() {
        pendingOperations.removeAll()
        savePendingOperations()
        updatePendingCount()
        logger.info("Cleared all pending operations")
    }
    
    func getPendingOperations() -> [SyncOperation] {
        return pendingOperations
    }
    
    // MARK: - Data Fetching
    func fetchUserMetrics() async throws -> [StatEntry] {
        logger.info("Fetching user metrics from server")
        
        let response: MetricsListResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics",
            method: "GET"
        )
        
        if !response.success {
            throw NSError(domain: "MetricSync", code: -1, userInfo: [
                NSLocalizedDescriptionKey: response.error ?? "Failed to fetch metrics"
            ])
        }
        
        let entries = response.entries.map { metric -> StatEntry in
            // Parse the source from the server response, default to manual if missing
            let statSource = StatSource(rawValue: metric.source ?? "manual") ?? .manual
            
            let parsedDate = Self.dateFormatter.date(from: metric.date)
            
            return StatEntry(
                id: UUID(uuidString: metric.client_uuid ?? "") ?? UUID(),
                date: parsedDate ?? Date(),
                value: metric.value, // Already a Double
                type: BackendMetricType(rawValue: metric.metric_type_id)?.toStatType() ?? .weight,
                source: statSource,
                version: metric.version ?? 1,
                backendId: metric.id
            )
        }
        
        logger.info("Successfully fetched \(entries.count) metrics from server")
        return entries
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()
} 