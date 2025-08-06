import Foundation
import HealthKit
import Combine
import os.log

// MARK: - New HealthManager with Proper Sync Architecture
@MainActor
class NewHealthManager: ObservableObject {
    static let shared = NewHealthManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HealthManager")
    private let healthStore = HKHealthStore()
    private let localDatabase = LocalDatabaseManager.shared
    
    // MARK: - Published Properties
    @Published var isHealthDataAvailable = false
    @Published var isAuthorized = false
    @Published var isWriteAuthorized = false
    @Published var syncStatus: String = "Ready"
    @Published var lastSyncDate: Date?
    
    // MARK: - Health Data Types
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .waistCircumference)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!
    ]
    
    private let typesToWrite: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .waistCircumference)!
    ]
    
    // MARK: - Anchored Query Management
    private var anchoredQueries: [HKQuantityTypeIdentifier: HKAnchoredObjectQuery] = [:]
    private var observers: [HKQuantityTypeIdentifier: HKObserverQuery] = [:]
    
    private let supportedTypes: [HKQuantityTypeIdentifier] = [
        .bodyMass, .height, .bodyFatPercentage, .waistCircumference
    ]
    
    private init() {
        checkHealthDataAvailability()
        lastSyncDate = localDatabase.getLastHealthKitSyncDate()
    }
    
    deinit {
        stopAllObservers()
    }
    
    // MARK: - Authorization
    
    private func checkHealthDataAvailability() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        if isHealthDataAvailable {
            checkAuthorizationStatus()
        }
    }
    
    private func checkAuthorizationStatus() {
        var allReadAuthorized = true
        var allWriteAuthorized = true
        
        // Check read permissions
        for type in typesToRead {
            let status = healthStore.authorizationStatus(for: type)
            if status == .notDetermined || status == .sharingDenied {
                allReadAuthorized = false
                break
            }
        }
        
        // Check write permissions
        for type in typesToWrite {
            let status = healthStore.authorizationStatus(for: type)
            if status != .sharingAuthorized {
                allWriteAuthorized = false
                break
            }
        }
        
        DispatchQueue.main.async {
            self.isAuthorized = allReadAuthorized
            self.isWriteAuthorized = allWriteAuthorized
            self.logger.info("Auth status - Read: \(allReadAuthorized), Write: \(allWriteAuthorized)")
        }
    }
    
    func requestHealthAuthorization() async -> Bool {
        guard isHealthDataAvailable else {
            logger.error("HealthKit not available")
            return false
        }
        
        logger.info("Requesting HealthKit authorization...")
        
        do {
            let granted = try await healthStore.requestAuthorization(toShare: Set(typesToWrite), read: Set(typesToRead))
            
            await MainActor.run {
                checkAuthorizationStatus()
                
                if isAuthorized {
                    logger.info("HealthKit authorization granted")
                    // Start observers after authorization
                    Task {
                        await setupHealthKitObservers()
                        await performInitialSync()
                    }
                } else {
                    logger.warning("HealthKit authorization denied")
                }
            }
            
            return granted
        } catch {
            logger.error("HealthKit authorization error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Observer Setup
    
    private func setupHealthKitObservers() async {
        guard isAuthorized else {
            logger.warning("Cannot setup observers - not authorized")
            return
        }
        
        logger.info("Setting up HealthKit observers...")
        
        for typeIdentifier in supportedTypes {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
                continue
            }
            
            await setupObserver(for: quantityType, typeIdentifier: typeIdentifier)
        }
    }
    
    private func setupObserver(for quantityType: HKQuantityType, typeIdentifier: HKQuantityTypeIdentifier) async {
        // Stop existing observer if any
        if let existingObserver = observers[typeIdentifier] {
            healthStore.stop(existingObserver)
        }
        
        let observer = HKObserverQuery(sampleType: quantityType, predicate: nil) { [weak self] query, completionHandler, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Observer error for \(typeIdentifier.rawValue): \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            self.logger.info("HealthKit data changed for \(typeIdentifier.rawValue)")
            
            Task { @MainActor in
                await self.syncDataFromHealthKit(for: typeIdentifier)
                completionHandler()
            }
        }
        
        observers[typeIdentifier] = observer
        healthStore.execute(observer)
        
        logger.info("Set up observer for \(typeIdentifier.rawValue)")
    }
    
    private func stopAllObservers() {
        for (typeIdentifier, observer) in observers {
            healthStore.stop(observer)
            logger.info("Stopped observer for \(typeIdentifier.rawValue)")
        }
        observers.removeAll()
        
        for (typeIdentifier, query) in anchoredQueries {
            healthStore.stop(query)
            logger.info("Stopped anchored query for \(typeIdentifier.rawValue)")
        }
        anchoredQueries.removeAll()
    }
    
    // MARK: - Data Syncing
    
    func performInitialSync() async {
        guard isAuthorized else {
            logger.warning("Cannot perform initial sync - not authorized")
            return
        }
        
        await MainActor.run {
            syncStatus = "Syncing from HealthKit..."
        }
        
        logger.info("Starting initial sync from HealthKit")
        
        for typeIdentifier in supportedTypes {
            await syncDataFromHealthKit(for: typeIdentifier)
        }
        
        await MainActor.run {
            lastSyncDate = Date()
            localDatabase.updateLastHealthKitSyncDate(lastSyncDate!)
            syncStatus = "Sync completed"
            
            // Reset status after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.syncStatus = "Ready"
            }
        }
        
        logger.info("Initial sync completed")
    }
    
    private func syncDataFromHealthKit(for typeIdentifier: HKQuantityTypeIdentifier) async {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            logger.error("Invalid quantity type: \(typeIdentifier.rawValue)")
            return
        }
        
        // Get last sync anchor
        let anchorKey = "HealthKit_\(typeIdentifier.rawValue)_Anchor"
        var anchor: HKQueryAnchor?
        
        if let anchorData = UserDefaults.standard.data(forKey: anchorKey) {
            do {
                anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchorData)
            } catch {
                logger.error("Failed to unarchive anchor: \(error.localizedDescription)")
            }
        }
        
        logger.info("Syncing \(typeIdentifier.rawValue) with anchor: \(anchor?.description ?? "none")")
        
        await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: quantityType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] query, samples, deletedObjects, newAnchor, error in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if let error = error {
                    self.logger.error("Anchored query error for \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume()
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    self.logger.info("No samples returned for \(typeIdentifier.rawValue)")
                    continuation.resume()
                    return
                }
                
                self.logger.info("Processing \(samples.count) samples for \(typeIdentifier.rawValue)")
                
                Task { @MainActor in
                    await self.processHealthKitSamples(samples, for: typeIdentifier)
                    
                    // Process deletions
                    if let deletedObjects = deletedObjects {
                        await self.processHealthKitDeletions(deletedObjects, for: typeIdentifier)
                    }
                    
                    // Save new anchor
                    if let newAnchor = newAnchor {
                        do {
                            let anchorData = try NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true)
                            UserDefaults.standard.set(anchorData, forKey: anchorKey)
                            self.logger.info("Saved new anchor for \(typeIdentifier.rawValue)")
                        } catch {
                            self.logger.error("Failed to archive new anchor: \(error.localizedDescription)")
                        }
                    }
                    
                    continuation.resume()
                }
            }
            
            // Store the query for potential cancellation
            anchoredQueries[typeIdentifier] = query
            healthStore.execute(query)
        }
    }
    
    // MARK: - Sample Processing
    
    private func processHealthKitSamples(_ samples: [HKQuantitySample], for typeIdentifier: HKQuantityTypeIdentifier) async {
        let metricTypeId = getMetricTypeId(for: typeIdentifier)
        
        for sample in samples {
            // Skip samples that were created by our app to avoid circular sync
            if let metadata = sample.metadata,
               let source = metadata["source"] as? String,
               source == "LifeTrackerX" {
                logger.info("Skipping self-created sample")
                continue
            }
            
            let healthkitId = sample.uuid.uuidString
            
            // Check if we already have this sample to avoid duplicates
            if localDatabase.entryExists(healthkitId: healthkitId) {
                logger.info("Sample already exists, skipping: \(healthkitId)")
                continue
            }
            
            // Convert HealthKit sample to our format
            let value = convertHealthKitValue(sample.quantity, for: typeIdentifier)
            
            // Create entry in local database
            let _ = localDatabase.createEntry(
                metricTypeId: metricTypeId,
                value: value,
                date: sample.startDate,
                source: .healthKit,
                healthkitId: healthkitId,
                syncStatus: .pendingCreate
            )
            
            logger.info("Created entry from HealthKit: type=\(metricTypeId), value=\(value), date=\(sample.startDate)")
        }
    }
    
    private func processHealthKitDeletions(_ deletedObjects: [HKDeletedObject], for typeIdentifier: HKQuantityTypeIdentifier) async {
        for deletedObject in deletedObjects {
            let healthkitId = deletedObject.uuid.uuidString
            
            // Find the local entry with this HealthKit ID
            let request = HealthMetric.fetchRequest()
            request.predicate = NSPredicate(format: "healthkitId == %@", healthkitId)
            
            // This would need to be implemented in LocalDatabaseManager
            // For now, we'll mark it for deletion
            logger.info("HealthKit sample deleted: \(healthkitId)")
            // TODO: Implement proper deletion handling
        }
    }
    
    // MARK: - Value Conversion
    
    private func convertHealthKitValue(_ quantity: HKQuantity, for typeIdentifier: HKQuantityTypeIdentifier) -> Double {
        switch typeIdentifier {
        case .bodyMass:
            return quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        case .height:
            return quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
        case .bodyFatPercentage:
            return quantity.doubleValue(for: HKUnit.percent()) * 100.0 // Convert to percentage
        case .waistCircumference:
            return quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
        default:
            return quantity.doubleValue(for: HKUnit.count())
        }
    }
    
    private func getMetricTypeId(for typeIdentifier: HKQuantityTypeIdentifier) -> Int {
        switch typeIdentifier {
        case .bodyMass: return 1
        case .height: return 2
        case .bodyFatPercentage: return 3
        case .waistCircumference: return 4
        default: return 0
        }
    }
    
    // MARK: - Writing to HealthKit
    
    func saveToHealthKit(_ entry: HealthMetric) async -> Bool {
        guard isWriteAuthorized else {
            logger.warning("Cannot save to HealthKit - write access denied")
            return false
        }
        
        guard let typeIdentifier = getHealthKitTypeIdentifier(for: Int(entry.metricTypeId)) else {
            logger.error("Unsupported metric type for HealthKit: \(entry.metricTypeId)")
            return false
        }
        
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            logger.error("Invalid HealthKit quantity type: \(typeIdentifier.rawValue)")
            return false
        }
        
        let unit = getHealthKitUnit(for: typeIdentifier)
        let convertedValue = convertToHealthKitValue(entry.value, for: typeIdentifier)
        let quantity = HKQuantity(unit: unit, doubleValue: convertedValue)
        
        let sample = HKQuantitySample(
            type: quantityType,
            quantity: quantity,
            start: entry.date!,
            end: entry.date!,
            metadata: [
                "source": "LifeTrackerX",
                "entryId": entry.uuid!.uuidString
            ]
        )
        
        do {
            try await healthStore.save(sample)
            
            // Update local entry with HealthKit ID
            let _ = localDatabase.updateEntry(
                uuid: entry.uuid!,
                healthkitId: sample.uuid.uuidString
            )
            
            logger.info("Successfully saved to HealthKit: type=\(entry.metricTypeId), value=\(entry.value)")
            return true
        } catch {
            logger.error("Failed to save to HealthKit: \(error.localizedDescription)")
            return false
        }
    }
    
    func deleteFromHealthKit(_ entry: HealthMetric) async -> Bool {
        guard isWriteAuthorized else {
            logger.warning("Cannot delete from HealthKit - write access denied")
            return false
        }
        
        guard let healthkitId = entry.healthkitId,
              let uuid = UUID(uuidString: healthkitId) else {
            logger.warning("No HealthKit ID found for entry")
            return false
        }
        
        guard let typeIdentifier = getHealthKitTypeIdentifier(for: Int(entry.metricTypeId)),
              let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            logger.error("Invalid HealthKit type for deletion")
            return false
        }
        
        // Find and delete the specific sample
        let predicate = NSPredicate(format: "UUID == %@", uuid as CVarArg)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { [weak self] query, samples, error in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                if let error = error {
                    self.logger.error("Error finding sample to delete: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }
                
                guard let samples = samples, !samples.isEmpty else {
                    self.logger.warning("Sample not found for deletion")
                    continuation.resume(returning: true) // Consider it success if already gone
                    return
                }
                
                Task {
                    do {
                        try await self.healthStore.delete(samples)
                        self.logger.info("Successfully deleted sample from HealthKit")
                        continuation.resume(returning: true)
                    } catch {
                        self.logger.error("Failed to delete sample from HealthKit: \(error.localizedDescription)")
                        continuation.resume(returning: false)
                    }
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getHealthKitTypeIdentifier(for metricTypeId: Int) -> HKQuantityTypeIdentifier? {
        switch metricTypeId {
        case 1: return .bodyMass
        case 2: return .height
        case 3: return .bodyFatPercentage
        case 4: return .waistCircumference
        default: return nil
        }
    }
    
    private func getHealthKitUnit(for typeIdentifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch typeIdentifier {
        case .bodyMass: return HKUnit.gramUnit(with: .kilo)
        case .height: return HKUnit.meterUnit(with: .centi)
        case .bodyFatPercentage: return HKUnit.percent()
        case .waistCircumference: return HKUnit.meterUnit(with: .centi)
        default: return HKUnit.count()
        }
    }
    
    private func convertToHealthKitValue(_ value: Double, for typeIdentifier: HKQuantityTypeIdentifier) -> Double {
        switch typeIdentifier {
        case .bodyFatPercentage:
            return value / 100.0 // Convert percentage to decimal
        default:
            return value
        }
    }
    
    // MARK: - Public Interface
    
    func startHealthKitSync() async {
        guard isAuthorized else {
            let authorized = await requestHealthAuthorization()
            if !authorized {
                return
            }
        }
        
        await setupHealthKitObservers()
        await performInitialSync()
    }
    
    func stopHealthKitSync() {
        stopAllObservers()
        syncStatus = "Stopped"
        logger.info("HealthKit sync stopped")
    }
    
    func forceSyncFromHealthKit() async {
        guard isAuthorized else {
            logger.warning("Cannot force sync - not authorized")
            return
        }
        
        await performInitialSync()
    }
}