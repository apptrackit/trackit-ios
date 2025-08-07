import Foundation
import Combine
import HealthKit
import SwiftUI

class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()
    
    // Sync managers
    private let storage = LocalStorageManager.shared
    private let healthKitSync = HealthKitSyncManager.shared
    private let backendSync = BackendSyncManager.shared
    
    // Published state
    @Published var syncStatus: SyncStatus = SyncStatus()
    @Published var overallStatus: SyncOverallStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var errorMessage: String?
    
    // Auto-sync settings
    @Published var autoSyncEnabled = true
    @Published var syncInterval: TimeInterval = 300 // 5 minutes
    
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?
    private var lastFullSyncTime: Date?
    
    // Sync coordination
    private var isSyncing = false
    private let syncQueue = DispatchQueue(label: "com.trackit.sync.coordinator", qos: .utility)
    
    private init() {
        setupSyncStatusObservers()
        loadSettings()
        
        // Start auto-sync if enabled
        if autoSyncEnabled {
            startAutoSync()
        }
    }
    
    deinit {
        stopAutoSync()
    }
    
    // MARK: - Setup
    
    private func setupSyncStatusObservers() {
        // Observe individual sync managers
        storage.$syncStatus
            .sink { [weak self] status in
                self?.updateOverallStatus()
            }
            .store(in: &cancellables)
        
        healthKitSync.$syncingStatus
            .sink { [weak self] _ in
                self?.updateOverallStatus()
            }
            .store(in: &cancellables)
        
        backendSync.$syncingStatus
            .sink { [weak self] _ in
                self?.updateOverallStatus()
            }
            .store(in: &cancellables)
        
        // Observe errors
        healthKitSync.$lastError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.errorMessage = "HealthKit: \(error)"
            }
            .store(in: &cancellables)
        
        backendSync.$lastError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.errorMessage = "Backend: \(error)"
            }
            .store(in: &cancellables)
        
        // Auto-sync on network changes
        backendSync.$isOnline
            .sink { [weak self] isOnline in
                if isOnline {
                    print("🔄 Network restored - triggering sync")
                    Task {
                        await self?.performIncrementalSync()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateOverallStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isSyncing {
                self.overallStatus = .syncing
            } else if !self.backendSync.isOnline {
                self.overallStatus = .offline
            } else if !self.backendSync.isAuthenticated {
                self.overallStatus = .notAuthenticated
            } else if !self.healthKitSync.isAuthorized {
                self.overallStatus = .healthKitNotAuthorized
            } else {
                let pendingHealthKit = self.storage.syncStatus.pendingHealthKitCount
                let pendingBackend = self.storage.syncStatus.pendingBackendCount
                
                if pendingHealthKit > 0 || pendingBackend > 0 {
                    self.overallStatus = .pendingSync
                } else {
                    self.overallStatus = .synced
                }
            }
            
            // Update sync status details
            self.syncStatus = self.storage.syncStatus
        }
    }
    
    // MARK: - Authentication
    
    func requestHealthKitAuthorization() async -> Bool {
        return await healthKitSync.requestHealthAuthorization()
    }
    
    func login(username: String, password: String) async -> Bool {
        let success = await backendSync.login(username: username, password: password)
        
        if success {
            // Trigger full sync after successful login
            Task {
                await performFullSync()
            }
        }
        
        return success
    }
    
    func logout() async {
        await backendSync.logout()
        clearAllData()
    }
    
    // MARK: - Manual Entry Operations
    
    func addManualEntry(_ metric: Metric) async -> Bool {
        print("➕ Adding manual entry: \(metric.type) = \(metric.value)")
        
        // Step 1: Save to local storage first (offline-first approach)
        guard storage.createMetric(metric) != nil else {
            await MainActor.run {
                self.errorMessage = "Failed to save metric locally"
            }
            return false
        }
        
        // Step 2: Try to save to HealthKit if supported and authorized
        if healthKitSync.isConnected && healthKitSync.canWrite &&
           healthKitSync.isMetricTypeSupported(metric.type) {
            
            let healthKitSuccess = await healthKitSync.saveManualEntry(metric)
            if !healthKitSuccess {
                print("⚠️ Failed to save to HealthKit, but local storage succeeded")
            }
        }
        
        // Step 3: Sync to backend when online
        if backendSync.isOnline && backendSync.isAuthenticated {
            await performIncrementalSync()
        }
        
        return true
    }
    
    func updateMetric(_ metric: Metric) async -> Bool {
        print("📝 Updating metric: \(metric.type) = \(metric.value)")
        
        // Update timestamp and reset sync flags
        var updatedMetric = metric
        updatedMetric.lastUpdatedAt = Date()
        updatedMetric.syncedWithBackend = false
        updatedMetric.syncedWithHealth = false
        
        guard storage.updateMetric(updatedMetric) else {
            await MainActor.run {
                self.errorMessage = "Failed to update metric locally"
            }
            return false
        }
        
        // Sync changes
        await performIncrementalSync()
        return true
    }
    
    func deleteMetric(_ metric: Metric) async -> Bool {
        print("🗑️ Deleting metric: \(metric.type)")
        
        // Soft delete locally
        guard storage.deleteMetric(metric, soft: true) else {
            await MainActor.run {
                self.errorMessage = "Failed to delete metric locally"
            }
            return false
        }
        
        // Sync deletion
        await performIncrementalSync()
        return true
    }
    
    // MARK: - Data Retrieval
    
    func getAllMetrics(includeDeleted: Bool = false) -> [Metric] {
        return storage.getAllMetrics(includeDeleted: includeDeleted)
    }
    
    func getMetrics(for type: MetricType, includeDeleted: Bool = false) -> [Metric] {
        return storage.getMetrics(type: type, includeDeleted: includeDeleted)
    }
    
    func getLatestMetric(for type: MetricType) -> Metric? {
        let metrics = getMetrics(for: type).filter { !$0.isDeleted }
        return metrics.first // Already sorted by date (newest first)
    }
    
    // MARK: - Sync Operations
    
    func performFullSync() async -> Bool {
        guard !isSyncing else {
            print("⚠️ Sync already in progress")
            return false
        }
        
        isSyncing = true
        defer {
            isSyncing = false
            updateOverallStatus()
        }
        
        await MainActor.run {
            self.overallStatus = .syncing
            self.errorMessage = nil
        }
        
        print("🔄 Starting full sync")
        
        let startTime = Date()
        var success = true
        
        // Step 1: Sync with HealthKit (if authorized)
        if healthKitSync.isAuthorized {
            let healthKitSuccess = await healthKitSync.performFullSync()
            if !healthKitSuccess {
                success = false
                print("❌ HealthKit sync failed")
            } else {
                print("✅ HealthKit sync completed")
            }
        }
        
        // Step 2: Sync with Backend (if authenticated and online)
        if backendSync.isAuthenticated && backendSync.isOnline {
            let backendSuccess = await backendSync.performFullSync()
            if !backendSuccess {
                success = false
                print("❌ Backend sync failed")
            } else {
                print("✅ Backend sync completed")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        print("🔄 Full sync completed in \(String(format: "%.1f", duration))s - Success: \(success)")
        
        await MainActor.run {
            self.lastSyncTime = Date()
            self.lastFullSyncTime = Date()
            
            if success {
                self.errorMessage = nil
            }
        }
        
        return success
    }
    
    func performIncrementalSync() async -> Bool {
        guard !isSyncing else { return false }
        
        isSyncing = true
        defer {
            isSyncing = false
            updateOverallStatus()
        }
        
        print("🔄 Starting incremental sync")
        
        var success = true
        
        // Incremental sync with backend only (HealthKit uses background queries)
        if backendSync.isAuthenticated && backendSync.isOnline {
            let backendSuccess = await backendSync.performIncrementalSync()
            if !backendSuccess {
                success = false
            }
        }
        
        await MainActor.run {
            self.lastSyncTime = Date()
        }
        
        return success
    }
    
    // MARK: - Auto-Sync Management
    
    func startAutoSync() {
        guard autoSyncEnabled else { return }
        
        stopAutoSync()
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                // Perform full sync every 30 minutes, incremental otherwise
                let shouldDoFullSync = self.lastFullSyncTime == nil ||
                    Date().timeIntervalSince(self.lastFullSyncTime!) > 1800 // 30 minutes
                
                if shouldDoFullSync {
                    await self.performFullSync()
                } else {
                    await self.performIncrementalSync()
                }
            }
        }
        
        print("⏰ Auto-sync started with \(syncInterval)s interval")
    }
    
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        print("⏰ Auto-sync stopped")
    }
    
    func updateAutoSyncSettings(enabled: Bool, interval: TimeInterval) {
        autoSyncEnabled = enabled
        syncInterval = interval
        
        saveSettings()
        
        if enabled {
            startAutoSync()
        } else {
            stopAutoSync()
        }
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        autoSyncEnabled = UserDefaults.standard.bool(forKey: "TrackIt.AutoSyncEnabled")
        syncInterval = UserDefaults.standard.double(forKey: "TrackIt.SyncInterval")
        
        if syncInterval <= 0 {
            syncInterval = 300 // Default 5 minutes
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(autoSyncEnabled, forKey: "TrackIt.AutoSyncEnabled")
        UserDefaults.standard.set(syncInterval, forKey: "TrackIt.SyncInterval")
    }
    
    // MARK: - Data Management
    
    func clearAllData() {
        print("🧹 Clearing all data")
        
        // Disconnect HealthKit
        healthKitSync.disconnect()
        
        // Clear local storage
        storage.clearAllData()
        
        // Reset sync state
        lastSyncTime = nil
        lastFullSyncTime = nil
        errorMessage = nil
        
        updateOverallStatus()
    }
    
    func getDataSummary() -> DataSummary {
        let allMetrics = getAllMetrics()
        let healthKitMetrics = allMetrics.filter { $0.source == .health }
        let manualMetrics = allMetrics.filter { $0.source == .manual }
        
        return DataSummary(
            totalMetrics: allMetrics.count,
            healthKitMetrics: healthKitMetrics.count,
            manualMetrics: manualMetrics.count,
            syncedWithHealthKit: allMetrics.filter { $0.syncedWithHealth }.count,
            syncedWithBackend: allMetrics.filter { $0.syncedWithBackend }.count,
            pendingHealthKitSync: storage.syncStatus.pendingHealthKitCount,
            pendingBackendSync: storage.syncStatus.pendingBackendCount
        )
    }
    
    // MARK: - Status Properties
    
    var isConnected: Bool {
        return healthKitSync.isConnected && backendSync.isAuthenticated
    }
    
    var statusDescription: String {
        switch overallStatus {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "All synced"
        case .pendingSync:
            let pending = storage.syncStatus.pendingHealthKitCount + storage.syncStatus.pendingBackendCount
            return "\(pending) pending sync"
        case .offline:
            return "Offline"
        case .notAuthenticated:
            return "Not authenticated"
        case .healthKitNotAuthorized:
            return "HealthKit access needed"
        case .error:
            return "Sync error"
        }
    }
}

// MARK: - Supporting Types

enum SyncOverallStatus {
    case idle
    case syncing
    case synced
    case pendingSync
    case offline
    case notAuthenticated
    case healthKitNotAuthorized
    case error
}

struct DataSummary {
    let totalMetrics: Int
    let healthKitMetrics: Int
    let manualMetrics: Int
    let syncedWithHealthKit: Int
    let syncedWithBackend: Int
    let pendingHealthKitSync: Int
    let pendingBackendSync: Int
}

// MARK: - SwiftUI Integration

struct SyncStatusView: View {
    @ObservedObject var syncCoordinator = SyncCoordinator.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusIcon
                Text(syncCoordinator.statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if syncCoordinator.overallStatus == .syncing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            
            if let lastSync = syncCoordinator.lastSyncTime {
                Text("Last sync: \(lastSync, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let error = syncCoordinator.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
    }
    
    private var statusIcon: some View {
        Image(systemName: statusIconName)
            .foregroundColor(statusColor)
            .font(.caption)
    }
    
    private var statusIconName: String {
        switch syncCoordinator.overallStatus {
        case .synced:
            return "checkmark.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .pendingSync:
            return "clock.circle"
        case .offline:
            return "wifi.slash"
        case .notAuthenticated:
            return "person.circle.fill"
        case .healthKitNotAuthorized:
            return "heart.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        default:
            return "circle"
        }
    }
    
    private var statusColor: Color {
        switch syncCoordinator.overallStatus {
        case .synced:
            return .green
        case .syncing:
            return .blue
        case .pendingSync:
            return .orange
        case .offline, .notAuthenticated, .healthKitNotAuthorized:
            return .gray
        case .error:
            return .red
        default:
            return .primary
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
extension SyncCoordinator {
    static func createPreview() -> SyncCoordinator {
        let coordinator = SyncCoordinator()
        coordinator.overallStatus = .synced
        coordinator.lastSyncTime = Date().addingTimeInterval(-120) // 2 minutes ago
        return coordinator
    }
}
#endif