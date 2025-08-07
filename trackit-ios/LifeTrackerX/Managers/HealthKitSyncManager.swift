import Foundation
import HealthKit
import Combine

class HealthKitSyncManager: ObservableObject {
    static let shared = HealthKitSyncManager()
    
    private let healthStore = HKHealthStore()
    private let storage = LocalStorageManager.shared
    
    @Published var isHealthDataAvailable = false
    @Published var isAuthorized = false
    @Published var isWriteAuthorized = false
    @Published var syncingStatus: String = "Ready"
    @Published var lastError: String?
    
    // Active queries for background observation
    private var anchoredQueries: [MetricType: HKAnchoredObjectQuery] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Sync queue to prevent concurrent operations
    private let syncQueue = DispatchQueue(label: "com.trackit.healthkit.sync", qos: .utility)
    private var isSyncing = false
    
    private init() {
        checkHealthDataAvailability()
    }
    
    deinit {
        stopAllObserverQueries()
        endBackgroundTask()
    }
    
    // MARK: - Health Data Availability & Authorization
    
    private func checkHealthDataAvailability() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        
        if isHealthDataAvailable {
            checkAuthorizationStatus()
        } else {
            print("❌ HealthKit not available on this device")
        }
    }
    
    func requestHealthAuthorization() async -> Bool {
        guard isHealthDataAvailable else {
            await MainActor.run {
                self.lastError = "HealthKit not available on this device"
            }
            return false
        }
        
        let typesToRead = Set(MetricType.healthKitSupportedTypes.compactMap { $0.healthKitType })
        let typesToWrite = Set(MetricType.healthKitSupportedTypes.compactMap { $0.healthKitType })
        
        do {
            let success = try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            
            await MainActor.run {
                self.checkAuthorizationStatus()
                if success {
                    self.syncingStatus = "Authorization granted"
                } else {
                    self.lastError = "Authorization denied"
                }
            }
            
            return success
        } catch {
            await MainActor.run {
                self.lastError = "Authorization error: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    private func checkAuthorizationStatus() {
        let supportedTypes = MetricType.healthKitSupportedTypes.compactMap { $0.healthKitType }
        
        // Check read authorization
        var allReadAuthorized = true
        var allWriteAuthorized = true
        
        for type in supportedTypes {
            let readStatus = healthStore.authorizationStatus(for: type)
            let writeStatus = healthStore.authorizationStatus(for: type)
            
            if readStatus != .sharingAuthorized {
                allReadAuthorized = false
            }
            
            if writeStatus != .sharingAuthorized {
                allWriteAuthorized = false
            }
        }
        
        DispatchQueue.main.async {
            self.isAuthorized = allReadAuthorized
            self.isWriteAuthorized = allWriteAuthorized
            
            print("🔑 HealthKit - Read: \(allReadAuthorized), Write: \(allWriteAuthorized)")
            
            // Start background queries if authorized
            if allReadAuthorized && self.anchoredQueries.isEmpty {
                self.startBackgroundObservation()
            }
        }
    }
    
    // MARK: - Background Observation
    
    private func startBackgroundObservation() {
        print("🔄 Starting HealthKit background observation")
        
        for metricType in MetricType.healthKitSupportedTypes {
            guard let quantityType = metricType.healthKitType else { continue }
            
            startAnchoredQuery(for: metricType, quantityType: quantityType)
        }
    }
    
    private func startAnchoredQuery(for metricType: MetricType, quantityType: HKQuantityType) {
        // Get stored anchor or nil for first run
        let anchor = storage.getHealthKitAnchor()
        
        let query = HKAnchoredObjectQuery(
            type: quantityType,
            predicate: nil, // Get all samples
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, newAnchor, error in
            
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.lastError = "HealthKit query error: \(error.localizedDescription)"
                }
                return
            }
            
            // Save new anchor
            if let newAnchor = newAnchor {
                self.storage.setHealthKitAnchor(newAnchor)
            }
            
            // Process new samples
            if let samples = samples as? [HKQuantitySample], !samples.isEmpty {
                self.processHealthKitSamples(samples, for: metricType)
            }
            
            // Process deleted samples
            if let deletedObjects = deletedObjects, !deletedObjects.isEmpty {
                self.processDeletedHealthKitSamples(deletedObjects, for: metricType)
            }
        }
        
        // Set update handler for live updates
        query.updateHandler = { [weak self] query, samples, deletedObjects, newAnchor, error in
            
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.lastError = "HealthKit update error: \(error.localizedDescription)"
                }
                return
            }
            
            // Save new anchor
            if let newAnchor = newAnchor {
                self.storage.setHealthKitAnchor(newAnchor)
            }
            
            // Process updates
            if let samples = samples as? [HKQuantitySample], !samples.isEmpty {
                self.processHealthKitSamples(samples, for: metricType)
            }
            
            if let deletedObjects = deletedObjects, !deletedObjects.isEmpty {
                self.processDeletedHealthKitSamples(deletedObjects, for: metricType)
            }
        }
        
        healthStore.execute(query)
        anchoredQueries[metricType] = query
        
        print("✅ Started anchored query for \(metricType.displayName)")
    }
    
    private func stopAllObserverQueries() {
        for (_, query) in anchoredQueries {
            healthStore.stop(query)
        }
        anchoredQueries.removeAll()
        print("🛑 Stopped all HealthKit observer queries")
    }
    
    // MARK: - Sample Processing
    
    private func processHealthKitSamples(_ samples: [HKQuantitySample], for metricType: MetricType) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            
            var newMetrics: [Metric] = []
            var updatedMetrics: [Metric] = []
            
            for sample in samples {
                // Check if we already have this sample (by HealthKit UUID)
                if let existingMetric = self.storage.getMetric(by: sample.uuid.uuidString) {
                    // Update existing metric if needed
                    if let updatedMetric = Metric.fromHealthKitSample(sample, type: metricType) {
                        var finalMetric = updatedMetric
                        finalMetric.id = existingMetric.id // Keep original ID
                        finalMetric.syncedWithBackend = existingMetric.syncedWithBackend
                        finalMetric.backendId = existingMetric.backendId
                        
                        if finalMetric.lastUpdatedAt > existingMetric.lastUpdatedAt {
                            updatedMetrics.append(finalMetric)
                        }
                    }
                } else {
                    // Create new metric
                    if let newMetric = Metric.fromHealthKitSample(sample, type: metricType) {
                        // Check for duplicates by date and type
                        if self.storage.findDuplicateMetric(
                            type: metricType,
                            date: sample.startDate,
                            source: newMetric.source
                        ) == nil {
                            newMetrics.append(newMetric)
                        } else {
                            print("⚠️ Skipping duplicate HealthKit sample for \(metricType) on \(sample.startDate)")
                        }
                    }
                }
            }
            
            // Save new metrics
            for metric in newMetrics {
                _ = self.storage.createMetric(metric)
            }
            
            // Update existing metrics
            for metric in updatedMetrics {
                _ = self.storage.updateMetric(metric)
            }
            
            if !newMetrics.isEmpty || !updatedMetrics.isEmpty {
                DispatchQueue.main.async {
                    self.syncingStatus = "Processed \(newMetrics.count + updatedMetrics.count) HealthKit updates"
                    print("📥 Processed \(newMetrics.count) new, \(updatedMetrics.count) updated \(metricType) from HealthKit")
                }
            }
        }
    }
    
    private func processDeletedHealthKitSamples(_ deletedObjects: [HKDeletedObject], for metricType: MetricType) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            
            var deletedCount = 0
            
            for deletedObject in deletedObjects {
                if let existingMetric = self.storage.getMetric(by: deletedObject.uuid.uuidString) {
                    var updatedMetric = existingMetric
                    updatedMetric.isDeleted = true
                    updatedMetric.lastUpdatedAt = Date()
                    updatedMetric.syncedWithBackend = false // Need to sync deletion
                    
                    if self.storage.updateMetric(updatedMetric) {
                        deletedCount += 1
                    }
                }
            }
            
            if deletedCount > 0 {
                DispatchQueue.main.async {
                    self.syncingStatus = "Processed \(deletedCount) HealthKit deletions"
                    print("🗑️ Processed \(deletedCount) deleted \(metricType) from HealthKit")
                }
            }
        }
    }
    
    // MARK: - Manual Sync Operations
    
    func performFullSync() async -> Bool {
        guard isAuthorized else {
            await MainActor.run {
                self.lastError = "HealthKit authorization required"
            }
            return false
        }
        
        guard !isSyncing else {
            print("⚠️ Sync already in progress")
            return false
        }
        
        isSyncing = true
        startBackgroundTask()
        
        defer {
            isSyncing = false
            endBackgroundTask()
        }
        
        await MainActor.run {
            self.syncingStatus = "Syncing with HealthKit..."
            self.lastError = nil
        }
        
        return await withTaskGroup(of: Bool.self) { group in
            // Sync from HealthKit to local
            group.addTask { await self.syncFromHealthKit() }
            
            // Sync from local to HealthKit
            group.addTask { await self.syncToHealthKit() }
            
            var allSucceeded = true
            for await result in group {
                if !result {
                    allSucceeded = false
                }
            }
            
            await MainActor.run {
                if allSucceeded {
                    self.syncingStatus = "Sync completed successfully"
                    self.storage.setSyncTimestamp(healthKit: Date())
                } else {
                    self.syncingStatus = "Sync completed with errors"
                }
            }
            
            return allSucceeded
        }
    }
    
    private func syncFromHealthKit() async -> Bool {
        print("📥 Starting sync from HealthKit")
        
        let success = await withTaskGroup(of: Bool.self) { group in
            for metricType in MetricType.healthKitSupportedTypes {
                group.addTask {
                    await self.syncMetricTypeFromHealthKit(metricType)
                }
            }
            
            var allSucceeded = true
            for await result in group {
                if !result {
                    allSucceeded = false
                }
            }
            return allSucceeded
        }
        
        print("📥 HealthKit sync \(success ? "completed" : "failed")")
        return success
    }
    
    private func syncMetricTypeFromHealthKit(_ metricType: MetricType) async -> Bool {
        guard let quantityType = metricType.healthKitType else {
            return true // Skip unsupported types
        }
        
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: Date.distantPast,
                end: Date(),
                options: .strictEndDate
            )
            
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [weak self] _, samples, error in
                
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                if let error = error {
                    print("❌ Error fetching \(metricType) from HealthKit: \(error)")
                    continuation.resume(returning: false)
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: true)
                    return
                }
                
                self.processHealthKitSamples(samples, for: metricType)
                continuation.resume(returning: true)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func syncToHealthKit() async -> Bool {
        guard isWriteAuthorized else {
            print("⚠️ HealthKit write access not available - skipping sync to HealthKit")
            return true
        }
        
        print("📤 Starting sync to HealthKit")
        
        let unsyncedMetrics = storage.getUnsyncedHealthKitMetrics()
        guard !unsyncedMetrics.isEmpty else {
            print("📤 No unsynced metrics to push to HealthKit")
            return true
        }
        
        var successCount = 0
        let group = DispatchGroup()
        
        for metric in unsyncedMetrics {
            guard MetricType.healthKitSupportedTypes.contains(metric.type) else {
                continue // Skip unsupported types
            }
            
            guard let sample = metric.toHealthKitSample() else {
                print("❌ Failed to create HealthKit sample for \(metric.type)")
                continue
            }
            
            group.enter()
            
            healthStore.save(sample) { [weak self] success, error in
                defer { group.leave() }
                
                if success {
                    // Update sync status
                    var updatedMetric = metric
                    updatedMetric.syncedWithHealth = true
                    updatedMetric.healthKitUUID = sample.uuid.uuidString
                    
                    if self?.storage.updateMetric(updatedMetric) == true {
                        successCount += 1
                        print("✅ Saved \(metric.type) to HealthKit")
                    }
                } else if let error = error {
                    print("❌ Failed to save \(metric.type) to HealthKit: \(error)")
                }
            }
        }
        
        group.wait()
        
        print("📤 HealthKit sync completed: \(successCount)/\(unsyncedMetrics.count) successful")
        return successCount > 0
    }
    
    // MARK: - Manual Entry Operations
    
    func saveManualEntry(_ metric: Metric) async -> Bool {
        // Save to local storage first
        guard storage.createMetric(metric) != nil else {
            await MainActor.run {
                self.lastError = "Failed to save metric locally"
            }
            return false
        }
        
        // Try to save to HealthKit if supported and authorized
        if isWriteAuthorized && MetricType.healthKitSupportedTypes.contains(metric.type) {
            return await saveToHealthKit(metric)
        }
        
        return true
    }
    
    private func saveToHealthKit(_ metric: Metric) async -> Bool {
        guard let sample = metric.toHealthKitSample() else {
            await MainActor.run {
                self.lastError = "Failed to create HealthKit sample"
            }
            return false
        }
        
        return await withCheckedContinuation { continuation in
            healthStore.save(sample) { [weak self] success, error in
                if success {
                    // Update local metric with HealthKit UUID
                    var updatedMetric = metric
                    updatedMetric.syncedWithHealth = true
                    updatedMetric.healthKitUUID = sample.uuid.uuidString
                    
                    _ = self?.storage.updateMetric(updatedMetric)
                    print("✅ Saved manual entry to HealthKit: \(metric.type)")
                } else if let error = error {
                    DispatchQueue.main.async {
                        self?.lastError = "HealthKit save error: \(error.localizedDescription)"
                    }
                    print("❌ Failed to save to HealthKit: \(error)")
                }
                
                continuation.resume(returning: success)
            }
        }
    }
    
    // MARK: - Background Task Management
    
    private func startBackgroundTask() {
        endBackgroundTask()
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HealthKitSync") { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - Cleanup
    
    func disconnect() {
        stopAllObserverQueries()
        
        DispatchQueue.main.async {
            self.isAuthorized = false
            self.isWriteAuthorized = false
            self.syncingStatus = "Disconnected"
            self.lastError = nil
        }
        
        print("🔌 HealthKit disconnected")
    }
    
    // MARK: - Utility Methods
    
    func getSupportedMetricTypes() -> [MetricType] {
        return MetricType.healthKitSupportedTypes
    }
    
    func isMetricTypeSupported(_ type: MetricType) -> Bool {
        return MetricType.healthKitSupportedTypes.contains(type)
    }
}

// MARK: - Extensions

extension HealthKitSyncManager {
    var isConnected: Bool {
        return isHealthDataAvailable && isAuthorized
    }
    
    var canWrite: Bool {
        return isConnected && isWriteAuthorized
    }
    
    var statusSummary: String {
        if !isHealthDataAvailable {
            return "HealthKit not available"
        } else if !isAuthorized {
            return "Authorization required"
        } else if isSyncing {
            return syncingStatus
        } else {
            return "Connected"
        }
    }
}