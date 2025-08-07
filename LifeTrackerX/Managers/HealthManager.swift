import Foundation
import HealthKit
import os.log

// MARK: - HealthManager (Updated for compatibility)
@MainActor
class HealthManager: ObservableObject {
    static let shared = HealthManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HealthManager")
    private let healthStore = HKHealthStore()
    private let localDatabase = LocalDatabaseManager.shared
    
    // MARK: - Published Properties
    @Published var isAuthorized = false
    @Published var isWriteAuthorized = false
    @Published var authorizationStatus: String = "Not Requested"
    @Published var syncStatus = "Ready"
    
    // MARK: - HealthKit Types
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .waistCircumference)!
    ]
    
    private let typesToWrite: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .waistCircumference)!
    ]
    
    // MARK: - Health Data Availability
    var isHealthDataAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    // MARK: - Observer Management
    private var anchoredQueries: [HKQuantityTypeIdentifier: HKAnchoredObjectQuery] = [:]
    private var observers: [HKQuantityTypeIdentifier: HKObserverQuery] = [:]
    
    private init() {
        logger.info("HealthManager initialized")
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        for type in typesToRead {
            if let quantityType = type as? HKQuantityType {
                let status = healthStore.authorizationStatus(for: quantityType)
                logger.info("Authorization status for \(quantityType.identifier): \(status.rawValue)")
            }
        }
        
        // Update published properties based on current status
        let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let readStatus = healthStore.authorizationStatus(for: bodyMassType)
        isAuthorized = (readStatus == .sharingAuthorized)
        
        authorizationStatus = isAuthorized ? "Authorized" : "Not Authorized"
    }
    
    func requestHealthAuthorization() async -> Bool {
        logger.info("Requesting HealthKit authorization")
        
        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { [weak self] success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.logger.error("HealthKit authorization failed: \(error.localizedDescription)")
                        self?.authorizationStatus = "Authorization Failed"
                        continuation.resume(returning: false)
                        return
                    }
                    
                    self?.logger.info("HealthKit authorization completed: \(success)")
                    self?.checkAuthorizationStatus()
                    
                    if success {
                        Task {
                            await self?.setupHealthKitObservers()
                            await self?.performInitialSync()
                        }
                    }
                    
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - HealthKit Observers
    
    private func setupHealthKitObservers() async {
        logger.info("Setting up HealthKit observers")
        
        let typesToObserve: [HKQuantityTypeIdentifier] = [.bodyMass, .height, .bodyFatPercentage, .waistCircumference]
        
        for typeIdentifier in typesToObserve {
            if let quantityType = HKObjectType.quantityType(forIdentifier: typeIdentifier) {
                await setupObserver(for: quantityType, typeIdentifier: typeIdentifier)
            }
        }
    }
    
    private func setupObserver(for quantityType: HKQuantityType, typeIdentifier: HKQuantityTypeIdentifier) async {
        // Stop existing observer if any
        if let existingObserver = observers[typeIdentifier] {
            healthStore.stop(existingObserver)
        }
        
        let observer = HKObserverQuery(sampleType: quantityType, predicate: nil) { [weak self] query, completionHandler, error in
            if let error = error {
                self?.logger.error("Observer query error for \(typeIdentifier.rawValue): \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            self?.logger.info("HealthKit change detected for \(typeIdentifier.rawValue)")
            
            Task {
                await self?.syncDataFromHealthKit(for: typeIdentifier)
                completionHandler()
            }
        }
        
        observers[typeIdentifier] = observer
        healthStore.execute(observer)
        
        logger.info("Observer set up for \(typeIdentifier.rawValue)")
    }
    
    private func stopAllObservers() {
        for (identifier, observer) in observers {
            healthStore.stop(observer)
            logger.info("Stopped observer for \(identifier.rawValue)")
        }
        observers.removeAll()
        
        for (identifier, query) in anchoredQueries {
            healthStore.stop(query)
            logger.info("Stopped anchored query for \(identifier.rawValue)")
        }
        anchoredQueries.removeAll()
    }
    
    // MARK: - Data Syncing
    
    func performInitialSync() async {
        guard isAuthorized else {
            logger.warning("Cannot perform initial sync - not authorized")
            return
        }
        
        syncStatus = "Initial sync..."
        logger.info("Starting initial HealthKit sync")
        
        let typesToSync: [HKQuantityTypeIdentifier] = [.bodyMass, .height, .bodyFatPercentage, .waistCircumference]
        
        for typeIdentifier in typesToSync {
            await syncDataFromHealthKit(for: typeIdentifier)
        }
        
        syncStatus = "Sync completed"
        logger.info("Initial HealthKit sync completed")
        
        // Reset status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.syncStatus = "Ready"
        }
    }
    
    private func syncDataFromHealthKit(for typeIdentifier: HKQuantityTypeIdentifier) async {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: typeIdentifier) else {
            logger.warning("Could not create quantity type for \(typeIdentifier.rawValue)")
            return
        }
        
        logger.info("Syncing \(typeIdentifier.rawValue) from HealthKit")
        
        let lastSyncDate = localDatabase.getLastHealthKitSyncDate()
        let startDate = lastSyncDate ?? Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        
        return await withCheckedContinuation { continuation in
            let anchoredQuery = HKAnchoredObjectQuery(
                type: quantityType,
                predicate: HKQuery.predicateForSamples(withStart: startDate, end: nil),
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { [weak self] query, samples, deletedObjects, anchor, error in
                if let error = error {
                    self?.logger.error("Anchored query error for \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume()
                    return
                }
                
                Task {
                    if let samples = samples as? [HKQuantitySample] {
                        await self?.processHealthKitSamples(samples, for: typeIdentifier)
                    }
                    
                    if let deletedObjects = deletedObjects {
                        await self?.processHealthKitDeletions(deletedObjects, for: typeIdentifier)
                    }
                    
                    // Update last sync date
                    self?.localDatabase.updateLastHealthKitSyncDate(Date())
                    
                    continuation.resume()
                }
            }
            
            anchoredQueries[typeIdentifier] = anchoredQuery
            healthStore.execute(anchoredQuery)
        }
    }
    
    private func processHealthKitSamples(_ samples: [HKQuantitySample], for typeIdentifier: HKQuantityTypeIdentifier) async {
        logger.info("Processing \(samples.count) HealthKit samples for \(typeIdentifier.rawValue)")
        
        for sample in samples {
            let healthkitId = "\(sample.startDate)-\(sample.endDate)-\(typeIdentifier.rawValue)"
            
            // Check if we already have this entry (deduplication)
            if localDatabase.entryExists(healthkitId: healthkitId) {
                continue // Skip duplicates
            }
            
            // Convert HealthKit type to our metric type ID
            let metricTypeId = getMetricTypeId(for: typeIdentifier)
            guard metricTypeId > 0 else {
                logger.warning("Unsupported HealthKit type: \(typeIdentifier.rawValue)")
                continue
            }
            
            // Get the appropriate unit and value
            let (value, unit) = getValueAndUnit(from: sample, typeIdentifier: typeIdentifier)
            
            // Create entry in local database
            let _ = localDatabase.createEntry(
                metricTypeId: metricTypeId,
                value: value,
                date: sample.startDate,
                source: .healthKit,
                healthkitId: healthkitId,
                syncStatus: .pendingCreate
            )
            
            logger.info("Added HealthKit entry: type=\(metricTypeId), value=\(value), date=\(sample.startDate)")
        }
    }
    
    private func processHealthKitDeletions(_ deletedObjects: [HKDeletedObject], for typeIdentifier: HKQuantityTypeIdentifier) async {
        logger.info("Processing \(deletedObjects.count) HealthKit deletions for \(typeIdentifier.rawValue)")
        
        for deletedObject in deletedObjects {
            // Try to find the corresponding entry in our database
            // This is challenging without a direct mapping, so we'll log for now
            logger.info("HealthKit deletion detected: \(deletedObject.uuid)")
        }
    }
    
    // MARK: - Save to HealthKit
    
    func saveToHealthKit(_ entry: TempHealthMetric) async -> Bool {
        guard isWriteAuthorized else {
            logger.warning("Cannot save to HealthKit - no write authorization")
            return false
        }
        
        let typeIdentifier = getHealthKitTypeIdentifier(for: entry.metricTypeId)
        guard typeIdentifier != nil else {
            logger.warning("Unsupported metric type for HealthKit: \(entry.metricTypeId)")
            return false
        }
        
        guard let quantityType = HKObjectType.quantityType(forIdentifier: typeIdentifier!) else {
            logger.error("Could not create quantity type")
            return false
        }
        
        let unit = getHealthKitUnit(for: entry.metricTypeId)
        let quantity = HKQuantity(unit: unit, doubleValue: entry.value)
        
        let sample = HKQuantitySample(
            type: quantityType,
            quantity: quantity,
            start: entry.date,
            end: entry.date
        )
        
        return await withCheckedContinuation { continuation in
            healthStore.save(sample) { [weak self] success, error in
                if let error = error {
                    self?.logger.error("Failed to save to HealthKit: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    self?.logger.info("Successfully saved to HealthKit: type=\(entry.metricTypeId)")
                    continuation.resume(returning: true)
                }
            }
        }
    }
    
    func deleteFromHealthKit(_ entry: TempHealthMetric) async -> Bool {
        guard isWriteAuthorized else {
            logger.warning("Cannot delete from HealthKit - no write authorization")
            return false
        }
        
        // HealthKit deletion is complex and may not be directly supported for all types
        // For now, we'll return true as a placeholder
        logger.info("HealthKit deletion requested for entry: \(entry.uuid)")
        return true
    }
    
    // MARK: - Helper Methods
    
    private func getMetricTypeId(for identifier: HKQuantityTypeIdentifier) -> Int {
        switch identifier {
        case .bodyMass: return 1 // weight
        case .height: return 2 // height
        case .bodyFatPercentage: return 3 // body fat
        case .waistCircumference: return 4 // waist
        default: return 0
        }
    }
    
    private func getHealthKitTypeIdentifier(for metricTypeId: Int) -> HKQuantityTypeIdentifier? {
        switch metricTypeId {
        case 1: return .bodyMass
        case 2: return .height
        case 3: return .bodyFatPercentage
        case 4: return .waistCircumference
        default: return nil
        }
    }
    
    private func getHealthKitUnit(for metricTypeId: Int) -> HKUnit {
        switch metricTypeId {
        case 1: return HKUnit.gramUnit(with: .kilo) // kg
        case 2: return HKUnit.meterUnit(with: .centi) // cm
        case 3: return HKUnit.percent() // %
        case 4: return HKUnit.meterUnit(with: .centi) // cm
        default: return HKUnit.count()
        }
    }
    
    private func getValueAndUnit(from sample: HKQuantitySample, typeIdentifier: HKQuantityTypeIdentifier) -> (Double, HKUnit) {
        let unit = getHealthKitUnit(for: getMetricTypeId(for: typeIdentifier))
        let value = sample.quantity.doubleValue(for: unit)
        return (value, unit)
    }
    
    // MARK: - Public Interface
    
    func startHealthKitSync() async {
        await performInitialSync()
    }
    
    func forceSyncFromHealthKit() async {
        await performInitialSync()
    }
    
    func stopHealthKitSync() {
        stopAllObservers()
        syncStatus = "Stopped"
    }
    
    // MARK: - Legacy Methods for Backward Compatibility
    
    func requestHealthAuthorization() {
        Task {
            let _ = await requestHealthAuthorization()
        }
    }
    
    func saveToHealthKit(_ entry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
        // Convert StatEntry to TempHealthMetric
        let tempEntry = TempHealthMetric(
            uuid: entry.id,
            metricTypeId: entry.type.metricTypeId,
            value: entry.value,
            date: entry.date,
            source: entry.source == .appleHealth ? .healthKit : .localApp,
            backendId: entry.backendId
        )
        
        Task {
            let success = await saveToHealthKit(tempEntry)
            completion(success, nil)
        }
    }
    
    func deleteFromHealthKit(_ entry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
        // Convert StatEntry to TempHealthMetric
        let tempEntry = TempHealthMetric(
            uuid: entry.id,
            metricTypeId: entry.type.metricTypeId,
            value: entry.value,
            date: entry.date,
            source: entry.source == .appleHealth ? .healthKit : .localApp,
            backendId: entry.backendId
        )
        
        Task {
            let success = await deleteFromHealthKit(tempEntry)
            completion(success, nil)
        }
    }
    
    func importAllHealthData(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        Task {
            await performInitialSync()
            completion(true)
        }
    }
    
    func clearHealthKitSampleMap() {
        // This method is no longer needed with the new architecture
        logger.info("clearHealthKitSampleMap called - not needed with new architecture")
    }
}
