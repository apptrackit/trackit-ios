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
    
    private init() {
        checkHealthDataAvailability()
    }
    
    deinit {
        stopAllObserverQueries()
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
            
            if success {
                // Start background observation
                startBackgroundObservation()
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
    
    // MARK: - Background Observation (Simplified)
    
    private func startBackgroundObservation() {
        print("🔄 Starting HealthKit background observation")
        
        for metricType in MetricType.healthKitSupportedTypes {
            guard let quantityType = metricType.healthKitType else { continue }
            
            let query = HKObserverQuery(sampleType: quantityType, predicate: nil) { [weak self] _, _, error in
                if let error = error {
                    print("❌ HealthKit observer error: \(error)")
                } else {
                    print("🔄 HealthKit data changed for \(metricType.displayName)")
                    // Trigger sync when data changes
                    Task {
                        await self?.syncFromHealthKit(for: metricType)
                    }
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    private func stopAllObserverQueries() {
        // Note: HKObserverQuery doesn't need explicit stopping, but we clear our references
        anchoredQueries.removeAll()
        print("🛑 Stopped all HealthKit observer queries")
    }
    
    // MARK: - Sync Operations
    
    func performFullSync() async -> Bool {
        guard isAuthorized else {
            await MainActor.run {
                self.lastError = "HealthKit authorization required"
            }
            return false
        }
        
        await MainActor.run {
            self.syncingStatus = "Syncing with HealthKit..."
            self.lastError = nil
        }
        
        print("🔄 Starting HealthKit full sync")
        
        let startTime = Date()
        var success = true
        
        // Sync each supported type
        for metricType in MetricType.healthKitSupportedTypes {
            let typeSuccess = await syncFromHealthKit(for: metricType)
            if !typeSuccess {
                success = false
            }
        }
        
        // Sync manual entries to HealthKit if authorized
        if isWriteAuthorized {
            let manualSyncSuccess = await syncToHealthKit()
            if !manualSyncSuccess {
                success = false
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        print("🔄 HealthKit sync completed in \(String(format: "%.1f", duration))s - Success: \(success)")
        
        await MainActor.run {
            if success {
                self.syncingStatus = "Sync completed successfully"
                self.storage.setSyncTimestamp(healthKit: Date())
            } else {
                self.syncingStatus = "Sync completed with errors"
            }
        }
        
        return success
    }
    
    private func syncFromHealthKit(for metricType: MetricType) async -> Bool {
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
                
                // Process samples
                var newCount = 0
                var skipCount = 0
                
                for sample in samples {
                    // Check if we already have this sample (by HealthKit UUID)
                    if self.storage.getMetric(by: sample.uuid.uuidString) != nil {
                        skipCount += 1
                        continue
                    }
                    
                    // Skip samples from our own app to avoid duplicates
                    if sample.metadata?["source"] as? String == "LifeTrackerX" {
                        skipCount += 1
                        continue
                    }
                    
                    // Create new metric from HealthKit sample
                    if let metric = Metric.fromHealthKitSample(sample, type: metricType) {
                        // Check for duplicates by date and type
                        if self.storage.findDuplicateMetric(
                            type: metricType,
                            date: sample.startDate,
                            source: metric.source
                        ) == nil {
                            _ = self.storage.createMetric(metric)
                            newCount += 1
                        } else {
                            skipCount += 1
                        }
                    }
                }
                
                print("📥 HealthKit sync for \(metricType): Added \(newCount), Skipped \(skipCount)")
                continuation.resume(returning: true)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func syncToHealthKit() async -> Bool {
        print("📤 Starting sync to HealthKit")
        
        let unsyncedMetrics = storage.getUnsyncedHealthKitMetrics()
        guard !unsyncedMetrics.isEmpty else {
            print("📤 No unsynced metrics to push to HealthKit")
            return true
        }
        
        var successCount = 0
        
        for metric in unsyncedMetrics {
            guard MetricType.healthKitSupportedTypes.contains(metric.type) else {
                continue // Skip unsupported types
            }
            
            guard let sample = metric.toHealthKitSample() else {
                print("❌ Failed to create HealthKit sample for \(metric.type)")
                continue
            }
            
            let success = await saveToHealthKit(sample: sample, metric: metric)
            if success {
                successCount += 1
            }
        }
        
        print("📤 HealthKit sync completed: \(successCount)/\(unsyncedMetrics.count) successful")
        return successCount > 0
    }
    
    private func saveToHealthKit(sample: HKQuantitySample, metric: Metric) async -> Bool {
        return await withCheckedContinuation { continuation in
            healthStore.save(sample) { [weak self] success, error in
                if success {
                    // Update sync status
                    var updatedMetric = metric
                    updatedMetric.syncedWithHealth = true
                    updatedMetric.healthKitUUID = sample.uuid.uuidString
                    
                    if self?.storage.updateMetric(updatedMetric) == true {
                        print("✅ Saved \(metric.type) to HealthKit")
                    }
                } else if let error = error {
                    print("❌ Failed to save \(metric.type) to HealthKit: \(error)")
                }
                
                continuation.resume(returning: success)
            }
        }
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
            guard let sample = metric.toHealthKitSample() else {
                return true // Local save succeeded, HealthKit failed but that's ok
            }
            
            return await saveToHealthKit(sample: sample, metric: metric)
        }
        
        return true
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
    
    // MARK: - Compatibility Methods (for existing code)
    
    var fetchingStatus: String {
        return syncingStatus
    }
    
    var lastUpdateTimestamp: Date {
        return storage.syncStatus.lastHealthKitSync ?? Date.distantPast
    }
    
    // Import all health data (compatibility method)
    func importAllHealthData(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        Task {
            let success = await performFullSync()
            completion(success)
        }
    }
    
    // Save to HealthKit (compatibility method)
    func saveToHealthKit(_ entry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
        let metric = Metric.fromStatEntry(entry)
        
        Task {
            let success = await saveManualEntry(metric)
            completion(success, success ? nil : NSError(domain: "HealthKitSync", code: -1))
        }
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
        } else {
            return "Connected"
        }
    }
}