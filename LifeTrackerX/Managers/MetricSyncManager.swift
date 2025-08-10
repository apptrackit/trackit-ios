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
            self?.processPendingOperations()
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
            existing.isAppleHealth == operation.isAppleHealth &&
            existing.uuid == operation.uuid &&
            existing.isDeleted == operation.isDeleted
        }
        
        if isDuplicate {
            logger.info("Skipping duplicate operation: \(operation.operationType.rawValue) for \(operation.statType.rawValue)")
            return
        }
        
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
            // For create operations, check if the entry already exists on the backend
            if await entryExistsOnBackend(operation) {
                logger.info("Entry already exists on backend, skipping create: \(operation.statType.rawValue) for \(operation.date)")
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
        // Prefer v2 lookup by UUID if available
        if let uuid = operation.uuid {
            do {
                let path = "/api/metrics?id=\(uuid)"
                let (data, response) = try await networkManager.makeAuthenticatedRawRequest(path, method: "GET")
                if (200...299).contains(response.statusCode) {
                    // If any entries are returned, it exists
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let entries = json["entries"] as? [Any] {
                        return !entries.isEmpty
                    }
                }
            } catch {
                logger.error("V2 existence check failed: \(error.localizedDescription)")
            }
        }
        
        // Legacy fallback
        do {
            let response: MetricsListResponse = try await networkManager.makeAuthenticatedRequest(
                "/api/metrics",
                method: "GET"
            )
            
            if response.success {
                let backendTypeId = BackendMetricType.from(operation.statType)?.rawValue
                let existingEntry = response.entries.first { metric in
                    metric.metric_type_id == backendTypeId &&
                    metric.date == Self.dateFormatter.string(from: operation.date) &&
                    metric.is_apple_health == operation.isAppleHealth
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
                    source: operation.isAppleHealth ? .appleHealth : .manual,
                    backendId: operation.backendId,
                    uuid: operation.uuid,
                    lastUpdatedAt: operation.clientLastUpdatedAt,
                    syncedWithHealth: false,
                    syncedWithBackend: false,
                    isDeleted: operation.isDeleted,
                    unit: operation.unit
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
    
    // MARK: - API Operations (V2 preferred with legacy fallback)
    private func createMetric(_ operation: SyncOperation) async throws {
        // Prefer v2 payload
        let v2 = CreateMetricV2Request(
            id: operation.uuid,
            metric_type: operation.statType.rawValue,
            metric_type_id: BackendMetricType.from(operation.statType)?.rawValue,
            value: operation.value,
            unit: operation.unit,
            timestamp: DateCoding.iso8601.string(from: operation.date),
            date: nil,
            source: operation.isAppleHealth ? "apple_health" : "app"
        )
        let v2Data = try JSONEncoder().encode(v2)
        do {
            let (data, response) = try await networkManager.makeAuthenticatedRawRequest("/api/metrics", method: "POST", body: v2Data)
            guard (200...299).contains(response.statusCode) else { throw AuthError.unknown }
            // Success
            logger.info("Successfully created metric (v2): \(operation.statType.rawValue)")
            return
        } catch {
            logger.error("Create v2 failed, falling back to legacy: \(error.localizedDescription)")
        }
        
        // Legacy fallback
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
            throw NSError(domain: "MetricSync", code: -1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"]) }
        logger.info("Successfully created metric (legacy): \(operation.statType.rawValue)")
    }
    
    private func updateMetric(_ operation: SyncOperation) async throws {
        // Prefer v2 update using UUID if available
        if let uuid = operation.uuid {
            let v2 = UpdateMetricV2Request(
                value: operation.value,
                unit: operation.unit,
                timestamp: DateCoding.iso8601.string(from: operation.date),
                source: operation.isAppleHealth ? "apple_health" : "app",
                client_last_updated_at: DateCoding.iso8601.string(from: operation.clientLastUpdatedAt)
            )
            let v2Data = try JSONEncoder().encode(v2)
            do {
                let path = "/api/metrics/\(uuid)"
                let (_, response) = try await networkManager.makeAuthenticatedRawRequest(path, method: "PUT", body: v2Data)
                switch response.statusCode {
                case 200...299:
                    logger.info("Successfully updated metric (v2): \(operation.statType.rawValue)")
                    return
                case 409, 410:
                    // Conflict or Gone - pull changes then treat as success
                    await StatsHistoryManager.shared.loadMetricsFromServer()
                    logger.info("Resolved conflict/gone by syncing from server for: \(operation.statType.rawValue)")
                    return
                default:
                    throw AuthError.unknown
                }
            } catch {
                logger.error("Update v2 failed, falling back to legacy: \(error.localizedDescription)")
            }
        }
        
        // Legacy fallback by backend ID or UUID
        let entry = StatEntry(
            id: operation.entryId,
            date: operation.date,
            value: operation.value,
            type: operation.statType,
            source: operation.isAppleHealth ? .appleHealth : .manual,
            backendId: operation.backendId
        )
        let request = UpdateMetricRequest(entry: entry)
        let requestData = try JSONEncoder().encode(request)
        let identifier = entry.backendId?.description ?? operation.entryId.uuidString
        let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/\(identifier)",
            method: "PUT",
            body: requestData
        )
        if !response.success {
            throw NSError(domain: "MetricSync", code: -1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"]) }
        logger.info("Successfully updated metric (legacy): \(operation.statType.rawValue)")
    }
    
    private func deleteMetric(_ operation: SyncOperation) async throws {
        // Prefer v2 soft delete by UUID
        if let uuid = operation.uuid {
            do {
                let path = "/api/metrics/\(uuid)"
                let (_, response) = try await networkManager.makeAuthenticatedRawRequest(path, method: "DELETE", body: nil)
                guard (200...299).contains(response.statusCode) else { throw AuthError.unknown }
                logger.info("Successfully deleted metric (v2 soft): \(operation.statType.rawValue)")
                return
            } catch {
                logger.error("Delete v2 failed, falling back to legacy: \(error.localizedDescription)")
            }
        }
        
        // Legacy fallback by backend ID or UUID
        let identifier = operation.backendId?.description ?? operation.entryId.uuidString
        let response: MetricResponse = try await networkManager.makeAuthenticatedRequest(
            "/api/metrics/\(identifier)",
            method: "DELETE"
        )
        if !response.success {
            throw NSError(domain: "MetricSync", code: -1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"]) }
        logger.info("Successfully deleted metric (legacy): \(operation.statType.rawValue)")
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
    
    // MARK: - Data Fetching (Legacy list for initial load)
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
        
        let entries = response.entries.map { metric in
            let parsedDate = Self.isoDateFormatter.date(from: metric.date) ?? Self.dateOnlyFormatter.date(from: metric.date) ?? Date()
            return StatEntry(
                id: UUID(), // Generate new UUID for local storage
                date: parsedDate,
                value: Double(metric.value) ?? 0.0, // Convert string to Double
                type: BackendMetricType(rawValue: metric.metric_type_id)?.toStatType() ?? .weight,
                source: metric.is_apple_health ? .appleHealth : .manual,
                backendId: metric.id
            )
        }
        
        logger.info("Successfully fetched \(entries.count) metrics from server")
        return entries
    }
    
    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(abbreviation: "UTC")
        return f
    }()
    
    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()
} 