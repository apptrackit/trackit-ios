import Foundation
import HealthKit

class HealthManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var isHealthDataAvailable = false
    @Published var isAuthorized = false
    
    // Health data types we want to read
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!
    ]
    
    // Health data types we want to write
    private let typesToWrite: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!
    ]
    
    init() {
        checkHealthDataAvailability()
    }
    
    private func checkHealthDataAvailability() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        if isHealthDataAvailable {
            checkAuthorizationStatus()
        }
    }
    
    private func checkAuthorizationStatus() {
        // Check authorization status for at least one type
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
                }
                
                if success {
                    self.isAuthorized = true
                    print("HealthKit authorization successful")
                } else {
                    print("HealthKit authorization denied")
                }
            }
        }
    }
    
    // Methods to read health data
    func fetchLatestWeight(completion: @escaping (Double?) -> Void) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            completion(nil)
            return
        }
        
        let query = HKSampleQuery(
            sampleType: weightType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)],
            resultsHandler: { query, samples, error in
                guard let sample = samples?.first as? HKQuantitySample else {
                    completion(nil)
                    return
                }
                
                let weightInKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                completion(weightInKg)
            }
        )
        
        healthStore.execute(query)
    }
    
    // Method to write health data
    func saveWeight(_ weight: Double, completion: @escaping (Bool, Error?) -> Void) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            completion(false, nil)
            return
        }
        
        let weightQuantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: weight)
        let sample = HKQuantitySample(type: weightType, quantity: weightQuantity, start: Date(), end: Date())
        
        healthStore.save(sample) { success, error in
            completion(success, error)
        }
    }
    
    // Import all weight data from HealthKit
    func importWeightHistory(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            completion(false)
            return
        }
        
        // Create a predicate to get all weight samples
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: weightType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)],
            resultsHandler: { query, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    for sample in samples {
                        let weightInKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                        let entry = StatEntry(
                            date: sample.startDate,
                            value: weightInKg,
                            type: .weight,
                            source: .appleHealth
                        )
                        historyManager.addEntry(entry)
                    }
                    completion(true)
                }
            }
        )
        
        healthStore.execute(query)
    }
    
    // Import all height data from HealthKit
    func importHeightHistory(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            completion(false)
            return
        }
        
        // Create a predicate to get all height samples
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: heightType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)],
            resultsHandler: { query, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    for sample in samples {
                        let heightInCm = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
                        let entry = StatEntry(
                            date: sample.startDate,
                            value: heightInCm,
                            type: .height,
                            source: .appleHealth
                        )
                        historyManager.addEntry(entry)
                    }
                    completion(true)
                }
            }
        )
        
        healthStore.execute(query)
    }
    
    // Import all body fat data from HealthKit
    func importBodyFatHistory(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            completion(false)
            return
        }
        
        // Create a predicate to get all body fat samples
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: bodyFatType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)],
            resultsHandler: { query, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    for sample in samples {
                        let bodyFatPercentage = sample.quantity.doubleValue(for: HKUnit.percent())
                        let entry = StatEntry(
                            date: sample.startDate,
                            value: bodyFatPercentage,
                            type: .bodyFat,
                            source: .appleHealth
                        )
                        historyManager.addEntry(entry)
                    }
                    completion(true)
                }
            }
        )
        
        healthStore.execute(query)
    }
    
    // Import all health data at once
    func importAllHealthData(historyManager: StatsHistoryManager, completion: @escaping (Bool) -> Void) {
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
            if successCount == totalOperations {
                completion(true)
            } else if successCount + (totalOperations - successCount) == totalOperations {
                completion(successCount > 0)
            }
        }
    }
}
