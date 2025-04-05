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
        HKObjectType.quantityType(forIdentifier: .stepCount)!
    ]
    
    // Health data types we want to write
    private let typesToWrite: Set = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!
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
            checkAuthorizationStatus()
        }
    }
    
    private func checkAuthorizationStatus() {
        guard let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }
        let status = healthStore.authorizationStatus(for: weightType)
        DispatchQueue.main.async {
            self.isAuthorized = status == .sharingAuthorized
        }
    }
    
    func requestHealthAuthorization() {
        guard isHealthDataAvailable else { return }
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("HealthKit authorization error: \(error.localizedDescription)")
                    self.fetchingStatus = "Authorization error: \(error.localizedDescription)"
                }
                if success {
                    self.isAuthorized = true
                    print("HealthKit authorization successful")
                    self.fetchingStatus = "Authorization successful"
                    
                    // Perform initial sync after authorization
                    let historyManager = StatsHistoryManager.shared
                    self.importAllHealthData(historyManager: historyManager) { _ in
                        print("Initial sync completed after authorization")
                    }
                } else {
                    print("HealthKit authorization denied")
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
        let totalOperations = 3
        
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
        // Similar implementation with the same pattern as importWeightHistory
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
            sortDescriptors: [sortDescriptor],
            resultsHandler: { [weak self] query, samples, error in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        print("Error fetching body fat data: \(error.localizedDescription)")
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
                        let bodyFatPercentage = sample.quantity.doubleValue(for: HKUnit.percent())
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
        )
        healthStore.execute(query)
    }
}
