import Foundation
import HealthKit
import Combine

class HealthManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var isHealthDataAvailable = false
    @Published var isAuthorized = false
    @Published var fetchingStatus: String = ""
    // Add this trigger to force view updates
    @Published var lastUpdateTimestamp: Date = Date()
    
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
    
    init() {
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
        // Check authorization status for all types we want to write
        var allAuthorized = true
        for type in typesToWrite {
            let status = healthStore.authorizationStatus(for: type)
            print("🔑 HealthKit authorization status for \(type): \(status.rawValue)")
            if status != .sharingAuthorized {
                allAuthorized = false
                break
            }
        }
        
        DispatchQueue.main.async {
            self.isAuthorized = allAuthorized
            print("🔑 isAuthorized set to: \(self.isAuthorized)")
            
            // Only request authorization if explicitly asked to do so
            if !self.isAuthorized && shouldRequestAccess {
                print("🔑 Not authorized, requesting authorization...")
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
                var allAuthorized = true
                for type in self.typesToWrite {
                    let status = self.healthStore.authorizationStatus(for: type)
                    print("🔑 Post-request status for \(type): \(status.rawValue)")
                    if status != .sharingAuthorized {
                        allAuthorized = false
                        break
                    }
                }
                
                self.isAuthorized = allAuthorized
                print("🔑 Post-request isAuthorized set to: \(self.isAuthorized)")
                
                if success && allAuthorized {
                    print("✅ HealthKit authorization successful")
                    self.fetchingStatus = "Authorization successful"
                    
                    // Perform initial sync after authorization
                    let historyManager = StatsHistoryManager.shared
                    self.importAllHealthData(historyManager: historyManager) { _ in
                        print("✅ Initial sync completed after authorization")
                        // After importing data, sync any existing manual entries
                        historyManager.syncManualEntriesToHealthKit()
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
        let totalOperations = 4  // Updated to include waist
        
        importWeightHistory(historyManager: historyManager) { success in
            if success { successCount += 1 }
            checkCompletion()
        }
        
        importHeightHistory(historyManager: historyManager) { success in
            if success { successCount += 1 }
            checkCompletion()
        }
        
        importBodyFatHistory(historyManager: historyManager) { success in
            if success { successCount += 1 }
            checkCompletion()
        }
        
        importWaistHistory(historyManager: historyManager) { success in
            if success { successCount += 1 }
            checkCompletion()
        }
        
        func checkCompletion() {
            DispatchQueue.main.async {
                if successCount == totalOperations {
                    self.fetchingStatus = "All data imported successfully!"
                    // Force UI refresh by updating timestamp
                    self.lastUpdateTimestamp = Date()
                    historyManager.triggerUpdate()
                    completion(true)
                } else if successCount + (totalOperations - successCount) == totalOperations {
                    self.fetchingStatus = "Partial data import: \(successCount)/\(totalOperations) successful"
                    // Force UI refresh by updating timestamp
                    self.lastUpdateTimestamp = Date()
                    historyManager.triggerUpdate()
                    completion(successCount > 0)
                }
            }
        }
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
        
        // Create a predicate with no time restrictions to get ALL data
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        
        // Sort by date, oldest first
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
                
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    DispatchQueue.main.async {
                        print("No weight samples found")
                        self.fetchingStatus = "No weight samples found"
                        completion(false)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    print("Fetched \(samples.count) weight samples")
                    self.fetchingStatus = "Fetched \(samples.count) weight samples"
                    
                    var addedCount = 0
                    for sample in samples {
                        let weightInKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                        let entry = StatEntry(
                            date: sample.startDate,
                            value: weightInKg,
                            type: .weight,
                            source: .appleHealth
                        )
                        historyManager.addEntry(entry)
                        addedCount += 1
                        
                        // Debug first sample
                        if addedCount == 1 {
                            print("Weight sample: \(weightInKg) kg on \(sample.startDate.formatted())")
                        }
                    }
                    
                    print("Added \(addedCount) weight entries to history")
                    self.fetchingStatus = "Added \(addedCount) weight entries to history"
                    // Force history manager to notify its subscribers
                    historyManager.triggerUpdate()
                    completion(true)
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
                
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    DispatchQueue.main.async {
                        print("No height samples found")
                        self.fetchingStatus = "No height samples found"
                        completion(false)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    print("Fetched \(samples.count) height samples")
                    self.fetchingStatus = "Fetched \(samples.count) height samples"
                    
                    var addedCount = 0
                    for sample in samples {
                        let heightInCm = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
                        let entry = StatEntry(
                            date: sample.startDate,
                            value: heightInCm,
                            type: .height,
                            source: .appleHealth
                        )
                        historyManager.addEntry(entry)
                        addedCount += 1
                    }
                    
                    print("Added \(addedCount) height entries to history")
                    self.fetchingStatus = "Added \(addedCount) height entries to history"
                    // Force history manager to notify its subscribers
                    historyManager.triggerUpdate()
                    completion(true)
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
        
        let query = HKSampleQuery(sampleType: bodyFatType,
                                predicate: predicate,
                                limit: HKObjectQueryNoLimit,
                                sortDescriptors: [sortDescriptor]) { [weak self] (query, samples, error) in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    print("❌ Error fetching body fat data: \(error.localizedDescription)")
                    self.fetchingStatus = "Error fetching body fat data: \(error.localizedDescription)"
                    completion(false)
                }
                return
            }
            
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                DispatchQueue.main.async {
                    print("No body fat samples found")
                    self.fetchingStatus = "No body fat samples found"
                    completion(true) // Still return true even if no data found
                }
                return
            }
            
            DispatchQueue.main.async {
                print("Fetched \(samples.count) body fat samples")
                self.fetchingStatus = "Fetched \(samples.count) body fat samples"
                
                var addedCount = 0
                for sample in samples {
                    let bodyFatDecimal = sample.quantity.doubleValue(for: HKUnit.percent())
                    // Convert from decimal (0.15) to percentage (15%)
                    let bodyFatPercentage = bodyFatDecimal * 100.0
                    let entry = StatEntry(
                        date: sample.startDate,
                        value: bodyFatPercentage,
                        type: .bodyFat,
                        source: .appleHealth
                    )
                    historyManager.addEntry(entry)
                    addedCount += 1
                }
                
                print("Added \(addedCount) body fat entries to history")
                self.fetchingStatus = "Added \(addedCount) body fat entries to history"
                // Force history manager to notify its subscribers
                historyManager.triggerUpdate()
                completion(true)
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
            
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                DispatchQueue.main.async {
                    print("No waist samples found")
                    self.fetchingStatus = "No waist samples found"
                    completion(true) // Still return true even if no data found
                }
                return
            }
            
            DispatchQueue.main.async {
                print("Fetched \(samples.count) waist samples")
                self.fetchingStatus = "Fetched \(samples.count) waist samples"
                
                var addedCount = 0
                for sample in samples {
                    let waistInCm = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
                    let entry = StatEntry(
                        date: sample.startDate,
                        value: waistInCm,
                        type: .waist,
                        source: .appleHealth
                    )
                    historyManager.addEntry(entry)
                    addedCount += 1
                }
                
                print("Added \(addedCount) waist entries to history")
                self.fetchingStatus = "Added \(addedCount) waist entries to history"
                // Force history manager to notify its subscribers
                historyManager.triggerUpdate()
                completion(true)
            }
        }
        healthStore.execute(query)
    }
    
    // Function to save a manual entry to HealthKit
    func saveToHealthKit(_ entry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
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
        case .bmi, .bicep, .chest, .thigh, .shoulder, .lbm, .fm, .ffmi, .bmr, .bsa:
            print("❌ \(entry.type) cannot be saved to HealthKit")
            completion(false, nil)
            return
        }
        
        guard let quantityType = quantityType else {
            print("❌ Invalid quantity type")
            completion(false, nil)
            return
        }
        
        // Check specific authorization for this type
        let status = healthStore.authorizationStatus(for: quantityType)
        print("🔑 Authorization status for \(entry.type): \(status.rawValue)")
        
        guard status == .sharingAuthorized else {
            print("❌ Not authorized to save \(entry.type) to HealthKit")
            completion(false, nil)
            return
        }
        
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: quantityType,
                                    quantity: quantity,
                                    start: entry.date,
                                    end: entry.date,
                                    metadata: ["source": "LifeTrackerX"])
        
        print("📝 Attempting to save \(entry.type) to HealthKit: \(value) at \(entry.date)")
        healthStore.save(sample) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("✅ Successfully saved \(entry.type) to HealthKit: \(value)")
                } else if let error = error {
                    print("❌ Error saving to HealthKit: \(error.localizedDescription)")
                }
                completion(success, error)
            }
        }
    }
    
    // Function to delete entries from HealthKit
    func deleteFromHealthKit(_ entry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
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
        case .bmi, .bicep, .chest, .thigh, .shoulder, .lbm, .fm, .ffmi, .bmr, .bsa:
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
}
