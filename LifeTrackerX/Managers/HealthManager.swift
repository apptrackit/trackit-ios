import Foundation
import HealthKit
import Combine

class HealthManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var isHealthDataAvailable = false
    @Published var isAuthorized = false
    @Published var isWriteAuthorized = false
    @Published var fetchingStatus: String = ""
    // Add this trigger to force view updates
    @Published var lastUpdateTimestamp: Date = Date()
    // Persisted timestamp of last successful HealthKit sync
    @Published var lastSyncTimestamp: Date? {
        didSet {
            if let ts = lastSyncTimestamp {
                UserDefaults.standard.set(ts.timeIntervalSince1970, forKey: Self.lastSyncTimestampKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncTimestampKey)
            }
        }
    }
    
    // Add a timer for periodic syncing
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 300 // 5 minutes
    
    // Health data types we want to read
    private let typesToRead: Set = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .waistCircumference)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!
    ]
    
    // Health data types we want to write
    private let typesToWrite: Set = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .waistCircumference)!
    ]
    
    // Backward-compatibility map for older entries imported before using client UUIDs directly
    private var healthKitSampleMap: [UUID: String] = [:]

    private static let lastSyncTimestampKey = "HealthKitLastSyncTimestamp"
    
    init() {
        // Load last sync timestamp
        if let stored = UserDefaults.standard.object(forKey: Self.lastSyncTimestampKey) as? TimeInterval {
            lastSyncTimestamp = Date(timeIntervalSince1970: stored)
        } else {
            lastSyncTimestamp = nil
        }
        checkHealthDataAvailability()
        setupPeriodicSync()
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    private func setupPeriodicSync() {
        // Cancel existing timer if any
        syncTimer?.invalidate()
        
        // Create a new timer that fires every 5 minutes
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            self?.performBackgroundSync()
        }
    }
    
    private func performBackgroundSync() {
        guard isAuthorized else { return }
        
        // Get the shared StatsHistoryManager instance
        let historyManager = StatsHistoryManager.shared
        importAllHealthData(historyManager: historyManager) { _ in
            // Background sync completed
            print("Background sync completed at \(Date())")
        }
    }
    
    private func checkHealthDataAvailability() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        if isHealthDataAvailable {
            // Only check the status, don't request authorization
            checkAuthorizationStatus(shouldRequestAccess: false)
        }
    }
    
    func checkAuthorizationStatus(shouldRequestAccess: Bool = false) {
        // Check authorization status for all types we want to read
        var allReadAuthorized = true
        for type in typesToRead {
            let status = healthStore.authorizationStatus(for: type)
            if status.rawValue == 0 || status.rawValue == 2 { // .notDetermined = 0, .sharingDenied = 2
                print("🔑 Read access denied for \(type)")
                allReadAuthorized = false
                break
            }
        }
        
        // Check authorization status for all types we want to write
        var allWriteAuthorized = true
        for type in typesToWrite {
            let status = healthStore.authorizationStatus(for: type)
            if status != .sharingAuthorized {
                print("🔑 Write access denied for \(type)")
                allWriteAuthorized = false
                break
            }
        }
        
        DispatchQueue.main.async {
            self.isAuthorized = allReadAuthorized
            self.isWriteAuthorized = allWriteAuthorized
            print("🔑 isAuthorized (read) set to: \(self.isAuthorized)")
            print("🔑 isWriteAuthorized set to: \(self.isWriteAuthorized)")
            
            // Only request authorization if explicitly asked to do so
            if !self.isAuthorized && shouldRequestAccess {
                print("🔑 Not authorized for reading, requesting authorization...")
                self.requestHealthAuthorization()
            }
        }
    }
    
    func requestHealthAuthorization() {
        guard isHealthDataAvailable else {
            print("❌ HealthKit not available")
            return
        }
        
        print("🔑 Requesting HealthKit authorization...")
        print("🔑 Types to write: \(typesToWrite)")
        print("🔑 Types to read: \(typesToRead)")
        
        // Request authorization for both reading and writing
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { [weak self] success, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ HealthKit authorization error: \(error.localizedDescription)")
                    self.fetchingStatus = "Authorization error: \(error.localizedDescription)"
                }
                
                // Re-check authorization status for all types
                var allReadAuthorized = true
                for type in self.typesToRead {
                    let status = self.healthStore.authorizationStatus(for: type)
                    print("🔑 Read authorization status for \(type): \(status.rawValue) (\(status))")
                    
                    // For read permissions, Apple may return .sharingDenied even when access is granted
                    // to protect user privacy. Only .notDetermined means definitely no access.
                    if status == .notDetermined {
                        print("🔑 Post-request read access not determined for \(type)")
                        allReadAuthorized = false
                        break
                    }
                    // Note: .sharingDenied might still allow reading, so we don't fail on it
                }
                
                var allWriteAuthorized = true
                for type in self.typesToWrite {
                    let status = self.healthStore.authorizationStatus(for: type)
                    print("🔑 Write authorization status for \(type): \(status.rawValue) (\(status))")
                    if status != .sharingAuthorized {
                        print("🔑 Post-request write access denied for \(type)")
                        allWriteAuthorized = false
                        break
                    }
                }
                
                self.isAuthorized = allReadAuthorized
                self.isWriteAuthorized = allWriteAuthorized
                print("🔑 Post-request isAuthorized (read) set to: \(self.isAuthorized)")
                print("🔑 Post-request isWriteAuthorized set to: \(self.isWriteAuthorized)")
                
                if allReadAuthorized {
                    if allWriteAuthorized {
                        print("✅ HealthKit authorization successful (read & write access)")
                        self.fetchingStatus = "Authorization successful"
                    } else {
                        print("✅ HealthKit read authorization successful (write access denied)")
                        self.fetchingStatus = "Read authorization successful"
                    }
                    
                    // Perform initial sync after authorization
                    let historyManager = StatsHistoryManager.shared
                    self.importAllHealthData(historyManager: historyManager) { _ in
                        print("✅ Initial sync completed after authorization")
                        
                        // Backend sync of Apple Health entries is triggered by StatsHistoryManager during import.
                        
                        // After importing data, sync any existing manual entries only if write access is available
                        if self.isWriteAuthorized {
                            historyManager.syncManualEntriesToHealthKit()
                        } else {
                            print("⚠️ Write access not available - manual entries will not be synced to HealthKit")
                        }

                        // Set initial last sync timestamp
                        self.lastSyncTimestamp = Date()
                    }
                } else {
                    print("❌ HealthKit authorization denied")
                    self.fetchingStatus = "Authorization denied"
                }
            }
        }
    }
    
    // Import all health data at once
    func importAllHealthData(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.fetchingStatus = "Starting data import..."
        }
        
        var successCount = 0
        let totalOperations = 4
        var completedOperations = 0
        
        func checkCompletion(success: Bool) {
            completedOperations += 1
            if success {
                successCount += 1
            }
            
            if completedOperations == totalOperations {
                DispatchQueue.main.async {
                    if successCount == totalOperations {
                        self.fetchingStatus = "All data imported successfully!"
                    } else {
                        self.fetchingStatus = "Partial data import: \(successCount)/\(totalOperations) successful"
                    }
                    self.lastUpdateTimestamp = Date()
                    historyManager.triggerUpdate()
                    completion(successCount > 0)
                }
            }
        }
        
        importWeightHistory(historyManager: historyManager, completion: checkCompletion)
        importHeightHistory(historyManager: historyManager, completion: checkCompletion)
        importBodyFatHistory(historyManager: historyManager, completion: checkCompletion)
        importWaistHistory(historyManager: historyManager, completion: checkCompletion)
    }
    
    // Import all weight data from HealthKit
    private func importWeightHistory(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            DispatchQueue.main.async {
                self.fetchingStatus = "Weight type not available in HealthKit"
            }
            completion(false)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(
            sampleType: weightType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor],
            resultsHandler: { [weak self] query, samples, error in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        print("Error fetching weight data: \(error.localizedDescription)")
                        self.fetchingStatus = "Error fetching weight data: \(error.localizedDescription)"
                        completion(false)
                    }
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    DispatchQueue.main.async {
                        print("No weight samples found")
                        self.fetchingStatus = "No weight samples found"
                        completion(true)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.fetchingStatus = "Fetched \(samples.count) weight samples"
                    self.syncWithHealthKit(historyManager: historyManager, type: .weight, samples: samples, completion: completion)
                }
            }
        )
        healthStore.execute(query)
    }
    
    // Import all height data from HealthKit
    private func importHeightHistory(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        // Similar implementation with the same pattern as importWeightHistory
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            DispatchQueue.main.async {
                self.fetchingStatus = "Height type not available in HealthKit"
            }
            completion(false)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(
            sampleType: heightType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor],
            resultsHandler: { [weak self] query, samples, error in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        print("Error fetching height data: \(error.localizedDescription)")
                        self.fetchingStatus = "Error fetching height data: \(error.localizedDescription)"
                        completion(false)
                    }
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    DispatchQueue.main.async {
                        print("No height samples found")
                        self.fetchingStatus = "No height samples found"
                        completion(true)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.fetchingStatus = "Fetched \(samples.count) height samples"
                    self.syncWithHealthKit(historyManager: historyManager, type: .height, samples: samples, completion: completion)
                }
            }
        )
        healthStore.execute(query)
    }
    
    // Import all body fat data from HealthKit
    private func importBodyFatHistory(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            DispatchQueue.main.async {
                self.fetchingStatus = "Body fat type not available in HealthKit"
            }
            completion(false)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(
            sampleType: bodyFatType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    print("Error fetching body fat data: \(error.localizedDescription)")
                    self.fetchingStatus = "Error fetching body fat data: \(error.localizedDescription)"
                    completion(false)
                }
                return
            }
            
            guard let samples = samples as? [HKQuantitySample] else {
                DispatchQueue.main.async {
                    print("No body fat samples found")
                    self.fetchingStatus = "No body fat samples found"
                    completion(true)
                }
                return
            }
            
            DispatchQueue.main.async {
                self.fetchingStatus = "Fetched \(samples.count) body fat samples"
                self.syncWithHealthKit(historyManager: historyManager, type: .bodyFat, samples: samples, completion: completion)
            }
        }
        healthStore.execute(query)
    }
    
    // Import waist circumference data from HealthKit
    private func importWaistHistory(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        guard let waistType = HKQuantityType.quantityType(forIdentifier: .waistCircumference) else {
            DispatchQueue.main.async {
                self.fetchingStatus = "Waist circumference type not available in HealthKit"
            }
            completion(false)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(
            sampleType: waistType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    print("Error fetching waist data: \(error.localizedDescription)")
                    self.fetchingStatus = "Error fetching waist data: \(error.localizedDescription)"
                    completion(false)
                }
                return
            }
            
            guard let samples = samples as? [HKQuantitySample] else {
                DispatchQueue.main.async {
                    print("No waist samples found")
                    self.fetchingStatus = "No waist samples found"
                    completion(true)
                }
                return
            }
            
            DispatchQueue.main.async {
                self.fetchingStatus = "Fetched \(samples.count) waist samples"
                self.syncWithHealthKit(historyManager: historyManager, type: .waist, samples: samples, completion: completion)
            }
        }
        healthStore.execute(query)
    }
    
    // Function to get the HealthKit sample UUID for a StatEntry
    func getHealthKitSampleUUID(for entry: StatEntry) -> String? {
        return healthKitSampleMap[entry.id]
    }
    
    // Function to sync with HealthKit and handle deletions
    private func syncWithHealthKit(historyManager: StatsHistoryManager, type: StatType, samples: [HKQuantitySample], completion: @escaping (Bool) -> Void) {
        // Get all existing entries of this type from Apple Health
        let existingEntries = historyManager.getEntries(for: type, source: .appleHealth)
        
        // Create a set of sample UUIDs from HealthKit
        let currentSampleUUIDs = Set(samples.map { $0.uuid.uuidString })
        
        // Find entries that need to be deleted (exist in our app but not in HealthKit)
        let entriesToDelete = existingEntries.filter { entry in
            // Prefer direct client UUID comparison; fallback to legacy map if present
            let candidateUUID = getHealthKitSampleUUID(for: entry) ?? entry.id.uuidString
            return !currentSampleUUIDs.contains(candidateUUID)
        }
        
        // Delete entries that no longer exist in HealthKit
        for entry in entriesToDelete {
            print("🗑️ Deleting entry that no longer exists in HealthKit: \(entry.type) from \(entry.date)")
            historyManager.removeEntry(entry)
        }
        
        // Add or update entries from HealthKit
        var newEntries: [StatEntry] = []
        var addedCount = 0
        var skippedCount = 0
        
        for sample in samples {
            if let metadata = sample.metadata,
               let source = metadata["source"] as? String,
               source == "LifeTrackerX" {
                skippedCount += 1
                continue
            }
            
            let entry: StatEntry
            switch type {
            case .weight:
                let weightInKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                entry = StatEntry(id: sample.uuid, date: sample.startDate, value: weightInKg, type: .weight, source: .appleHealth)
            case .height:
                let heightInCm = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
                entry = StatEntry(id: sample.uuid, date: sample.startDate, value: heightInCm, type: .height, source: .appleHealth)
            case .bodyFat:
                let bodyFatDecimal = sample.quantity.doubleValue(for: HKUnit.percent())
                let bodyFatPercentage = bodyFatDecimal * 100.0
                entry = StatEntry(id: sample.uuid, date: sample.startDate, value: bodyFatPercentage, type: .bodyFat, source: .appleHealth)
            case .waist:
                let waistInCm = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
                entry = StatEntry(id: sample.uuid, date: sample.startDate, value: waistInCm, type: .waist, source: .appleHealth)
            default:
                continue
            }
            
            let existingEntry = existingEntries.first { existing in
                Calendar.current.isDate(existing.date, inSameDayAs: entry.date) &&
                existing.type == entry.type &&
                existing.source == entry.source
            }
            
            if existingEntry != nil {
                skippedCount += 1
                continue
            }
            
            newEntries.append(entry)
            addedCount += 1
        }
        
        if !newEntries.isEmpty {
            historyManager.addEntries(newEntries)
        }
        
        print("📊 Sync completed for \(type): Added \(addedCount) entries, Skipped \(skippedCount) duplicates, Deleted \(entriesToDelete.count) entries")
        completion(true)
    }
    
    // Function to save an entry to HealthKit. Returns the created sample UUID (client_uuid) when successful
    func saveToHealthKit(_ entry: StatEntry, completion: @escaping (Bool, Error?, UUID?) -> Void) {
        // Check if we have write authorization
        guard isWriteAuthorized else {
            print("❌ Not authorized to write to HealthKit - write access denied")
            completion(false, nil, nil)
            return
        }
        
        var quantityType: HKQuantityType?
        var unit: HKUnit
        var value = entry.value // Default to the original value
        
        switch entry.type {
        case .weight:
            quantityType = HKQuantityType.quantityType(forIdentifier: .bodyMass)
            unit = HKUnit.gramUnit(with: .kilo)
            print("📝 Preparing to save weight: \(value) \(unit)")
        case .height:
            quantityType = HKQuantityType.quantityType(forIdentifier: .height)
            unit = HKUnit.meterUnit(with: .centi)
            print("📝 Preparing to save height: \(value) \(unit)")
        case .bodyFat:
            quantityType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)
            unit = HKUnit.percent()
            // Convert from percentage (15%) to decimal (0.15)
            value = entry.value / 100.0
            print("📝 Preparing to save body fat: \(value) \(unit) (converted from \(entry.value)%)")
        case .waist:
            quantityType = HKQuantityType.quantityType(forIdentifier: .waistCircumference)
            unit = HKUnit.meterUnit(with: .centi)
            print("📝 Preparing to save waist: \(value) \(unit)")
        case .bmi, .bicep, .chest, .thigh, .shoulder, .glutes, .calf, .neck, .forearm, .lbm, .fm, .ffmi, .bmr, .bsa:
            print("❌ \(entry.type) cannot be saved to HealthKit")
            completion(false, nil, nil)
            return
        }
        
        guard let quantityType = quantityType else {
            print("❌ Invalid quantity type")
            completion(false, nil, nil)
            return
        }
        
        // Check specific authorization for this type
        let status = healthStore.authorizationStatus(for: quantityType)
        print("🔑 Authorization status for \(entry.type): \(status.rawValue)")
        
        guard status == .sharingAuthorized else {
            print("❌ Not authorized to save \(entry.type) to HealthKit")
            completion(false, nil, nil)
            return
        }
        
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: quantityType,
                                    quantity: quantity,
                                    start: entry.date,
                                    end: entry.date,
                                    metadata: ["source": "LifeTrackerX", "lifeTrackerXEntryId": entry.id.uuidString])
        
        print("📝 Attempting to save \(entry.type) to HealthKit: \(value) at \(entry.date)")
        healthStore.save(sample) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("✅ Successfully saved \(entry.type) to HealthKit: \(value)")
                } else if let error = error {
                    print("❌ Error saving to HealthKit: \(error.localizedDescription)")
                }
                completion(success, error, sample.uuid)
            }
        }
    }
    
    // Function to delete entries from HealthKit by searching for date range (legacy fallback)
    func deleteFromHealthKit(_ entry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
        // Check if we have write authorization
        guard isWriteAuthorized else {
            print("❌ Not authorized to delete from HealthKit - write access denied")
            completion(false, nil)
            return
        }
        
        var quantityType: HKQuantityType?
        
        switch entry.type {
        case .weight:
            quantityType = HKQuantityType.quantityType(forIdentifier: .bodyMass)
            print("🗑️ Preparing to delete weight entry")
        case .height:
            quantityType = HKQuantityType.quantityType(forIdentifier: .height)
            print("🗑️ Preparing to delete height entry")
        case .bodyFat:
            quantityType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)
            print("🗑️ Preparing to delete body fat entry")
        case .waist:
            quantityType = HKQuantityType.quantityType(forIdentifier: .waistCircumference)
            print("🗑️ Preparing to delete waist entry")
        case .bmi, .bicep, .chest, .thigh, .shoulder, .glutes, .calf, .neck, .forearm, .lbm, .fm, .ffmi, .bmr, .bsa:
            print("❌ Cannot delete \(entry.type) from HealthKit - not supported")
            completion(false, nil)
            return
        }
        
        guard let quantityType = quantityType else {
            print("❌ Invalid quantity type for deletion")
            completion(false, nil)
            return
        }
        
        // Check specific authorization for this type
        let status = healthStore.authorizationStatus(for: quantityType)
        print("🔑 Authorization status for deleting \(entry.type): \(status.rawValue)")
        
        guard status == .sharingAuthorized else {
            print("❌ Not authorized to delete \(entry.type) from HealthKit")
            completion(false, nil)
            return
        }
        
        // Create a predicate to find samples with the exact date
        let predicate = HKQuery.predicateForSamples(withStart: entry.date,
                                                   end: entry.date.addingTimeInterval(1),
                                                   options: .strictStartDate)
        
        print("🔍 Searching for \(entry.type) entries to delete at \(entry.date)")
        
        // Query for samples to delete
        let query = HKSampleQuery(sampleType: quantityType,
                                predicate: predicate,
                                limit: HKObjectQueryNoLimit,
                                sortDescriptors: nil) { [weak self] (query, samples, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error searching for samples to delete: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, error)
                }
                return
            }
            
            guard let samplesToDelete = samples as? [HKQuantitySample] else {
                print("❌ No matching samples found to delete")
                DispatchQueue.main.async {
                    completion(false, nil)
                }
                return
            }
            
            if samplesToDelete.isEmpty {
                print("⚠️ No samples found to delete for \(entry.type) at \(entry.date)")
                DispatchQueue.main.async {
                    completion(true, nil) // Return success since there's nothing to delete
                }
                return
            }
            
            print("🗑️ Found \(samplesToDelete.count) samples to delete")
            
            // Delete the found samples
            self.healthStore.delete(samplesToDelete) { (success, error) in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Successfully deleted \(samplesToDelete.count) \(entry.type) entries from HealthKit")
                    } else if let error = error {
                        print("❌ Error deleting from HealthKit: \(error.localizedDescription)")
                    }
                    completion(success, error)
                }
            }
        }
        
        healthStore.execute(query)
    }

    // Function to delete a HealthKit sample by its UUID (preferred precise deletion)
    func deleteFromHealthKit(byUUID uuid: UUID, type: StatType, completion: @escaping (Bool, Error?) -> Void) {
        guard isWriteAuthorized else {
            print("❌ Not authorized to delete from HealthKit - write access denied")
            completion(false, nil)
            return
        }

        var quantityType: HKQuantityType?
        switch type {
        case .weight:
            quantityType = HKQuantityType.quantityType(forIdentifier: .bodyMass)
        case .height:
            quantityType = HKQuantityType.quantityType(forIdentifier: .height)
        case .bodyFat:
            quantityType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)
        case .waist:
            quantityType = HKQuantityType.quantityType(forIdentifier: .waistCircumference)
        default:
            print("❌ Cannot delete \(type) from HealthKit - not supported")
            completion(false, nil)
            return
        }

        guard let sampleType = quantityType else {
            completion(false, nil)
            return
        }

        // Fetch all samples for this type and filter by UUID
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, results, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(false, error) }
                return
            }
            guard let samples = results else {
                DispatchQueue.main.async { completion(false, nil) }
                return
            }

            if let match = samples.first(where: { $0.uuid == uuid }) {
                self.healthStore.delete(match) { success, error in
                    DispatchQueue.main.async { completion(success, error) }
                }
            } else {
                DispatchQueue.main.async {
                    print("⚠️ No HealthKit sample found with UUID \(uuid.uuidString)")
                    completion(true, nil)
                }
            }
        }
        healthStore.execute(query)
    }
    
    // Add a function to clear the sample map when disconnecting
    func clearHealthKitSampleMap() {
        healthKitSampleMap.removeAll()
    }
}
