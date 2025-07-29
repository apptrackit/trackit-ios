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
            self?.processPendingOperations()
        }
    }
    
    // MARK: - Queue Management
    func queueOperation(_ operation: SyncOperation) {
        pendingOperations.append(operation)
        savePendingOperations()
        updatePendingCount()
        
        logger.info("Queued operation: \(operation.operationType.rawValue) for \(operation.statType.rawValue)")
        
        // Try to process immediately if online
        if isOnline {
            processPendingOperations()
        }
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
            try await createMetric(operation)
        case .update:
            try await updateMetric(operation)
        case .delete:
            try await deleteMetric(operation)
        }
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
                    source: operation.isAppleHealth ? .appleHealth : .manual,
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
            source: operation.isAppleHealth ? .appleHealth : .manual
        )
        
        let request = CreateMetricRequest(entry: entry)
        let requestData = try JSONEncoder().encode(request)
        
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
        
        logger.info("Successfully created metric: \(operation.statType.rawValue)")
    }
    
    private func updateMetric(_ operation: SyncOperation) async throws {
        let entry = StatEntry(
            id: operation.entryId,
            date: operation.date,
            value: operation.value,
            type: operation.statType,
            source: operation.isAppleHealth ? .appleHealth : .manual
        )
        
        let request = UpdateMetricRequest(entry: entry)
        let requestData = try JSONEncoder().encode(request)
        
        // Use backend ID if available, otherwise use UUID
        let identifier = entry.backendId?.description ?? operation.entryId.uuidString
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
        // Use backend ID if available, otherwise use UUID
        let identifier = operation.backendId?.description ?? operation.entryId.uuidString
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
        for entry in entries {
            // Only sync non-calculated metrics
            if !entry.type.isCalculated {
                syncEntry(entry, operation: .create)
            }
        }
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
} 