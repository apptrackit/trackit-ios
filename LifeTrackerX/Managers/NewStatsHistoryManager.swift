import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - New Stats History Manager
/// Refactored to use the new local database layer and sync architecture
@MainActor
class NewStatsHistoryManager: ObservableObject {
    static let shared = NewStatsHistoryManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "StatsHistory")
    private let localDatabase = LocalDatabaseManager.shared
    private let userActionHandler = UserActionHandler.shared
    
    // MARK: - Published Properties
    @Published var entries: [StatEntry] = []
    @Published var refreshTrigger: UUID = UUID()
    @Published var isLoading = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
        loadEntries()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Listen for changes in the local database
        // This would be more sophisticated with actual Core Data notifications
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshFromDatabase()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    func loadEntries() {
        isLoading = true
        logger.info("Loading entries from local database")
        
        Task { @MainActor in
            let allHealthMetrics = localDatabase.getAllEntries(includeDeleted: false)
            
            // Convert HealthMetric entries to StatEntry for UI compatibility
            var convertedEntries: [StatEntry] = []
            
            for healthMetric in allHealthMetrics {
                if let statEntry = healthMetric.toStatEntry() {
                    convertedEntries.append(statEntry)
                }
            }
            
            // Calculate derived metrics (BMI, LBM, etc.)
            let entriesWithDerived = addDerivedMetrics(to: convertedEntries)
            
            // Sort by date (newest first)
            self.entries = entriesWithDerived.sorted { $0.date > $1.date }
            
            isLoading = false
            triggerUpdate()
            
            logger.info("Loaded \(self.entries.count) entries (\(allHealthMetrics.count) from DB + derived)")
        }
    }
    
    func refreshFromDatabase() {
        loadEntries()
    }
    
    // MARK: - User Actions
    
    func addEntry(_ entry: StatEntry) {
        logger.info("Adding entry via user action: \(entry.type.rawValue) = \(entry.value)")
        
        userActionHandler.handleUserAdd(entry) { [weak self] success, error in
            if success {
                self?.logger.info("✅ Entry added successfully")
                self?.loadEntries() // Refresh from database
            } else if let error = error {
                self?.logger.error("❌ Failed to add entry: \(error.localizedDescription)")
            }
        }
    }
    
    func updateEntry(_ entry: StatEntry) {
        logger.info("Updating entry via user action: \(entry.id)")
        
        userActionHandler.handleUserEdit(entry) { [weak self] success, error in
            if success {
                self?.logger.info("✅ Entry updated successfully")
                self?.loadEntries() // Refresh from database
            } else if let error = error {
                self?.logger.error("❌ Failed to update entry: \(error.localizedDescription)")
            }
        }
    }
    
    func removeEntry(_ entry: StatEntry) {
        logger.info("Removing entry via user action: \(entry.id)")
        
        userActionHandler.handleUserDelete(entry) { [weak self] success, error in
            if success {
                self?.logger.info("✅ Entry removed successfully")
                self?.loadEntries() // Refresh from database
            } else if let error = error {
                self?.logger.error("❌ Failed to remove entry: \(error.localizedDescription)")
            }
        }
    }
    
    func addEntries(_ newEntries: [StatEntry]) {
        logger.info("Adding \(newEntries.count) entries via batch operation")
        
        let entriesData = newEntries.map { entry in
            (metricTypeId: entry.type.metricTypeId, value: entry.value, date: entry.date)
        }
        
        userActionHandler.handleBatchAdd(entries: entriesData) { [weak self] successCount, totalCount, error in
            self?.logger.info("Batch add completed: \(successCount)/\(totalCount) successful")
            if let error = error {
                self?.logger.error("Batch add error: \(error.localizedDescription)")
            }
            self?.loadEntries() // Refresh from database
        }
    }
    
    // MARK: - Data Queries
    
    func getLatestValue(for type: StatType) -> Double? {
        let typeEntries = entries.filter { $0.type == type }
        return typeEntries.sorted { $0.date > $1.date }.first?.value
    }
    
    func getEntries(for type: StatType) -> [StatEntry] {
        return entries.filter { $0.type == type }.sorted { $0.date > $1.date }
    }
    
    func getEntries(for type: StatType, source: StatSource) -> [StatEntry] {
        return entries.filter { $0.type == type && $0.source == source }.sorted { $0.date > $1.date }
    }
    
    func getEntriesAt(date: Date) -> [StatEntry] {
        var result: [StatEntry] = []
        
        let relevantTypes: [StatType] = [.weight, .height, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
        
        for type in relevantTypes {
            // Find the most recent entry for this type on or before the given date
            if let latestEntry = entries.filter({ $0.type == type && $0.date <= date })
                .sorted(by: { $0.date > $1.date })
                .first {
                result.append(latestEntry)
            }
        }
        
        return result
    }
    
    // MARK: - Calculated Metrics
    
    private func addDerivedMetrics(to baseEntries: [StatEntry]) -> [StatEntry] {
        var allEntries = baseEntries
        
        logger.info("Calculating derived metrics for \(baseEntries.count) base entries")
        
        // Get sorted entries by type for calculations
        let weightEntries = baseEntries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let heightEntries = baseEntries.filter { $0.type == .height }.sorted { $0.date < $1.date }
        let bodyFatEntries = baseEntries.filter { $0.type == .bodyFat }.sorted { $0.date < $1.date }
        
        // Calculate derived metrics for each weight entry
        for weightEntry in weightEntries {
            let date = weightEntry.date
            let weight = weightEntry.value
            
            // Find the most recent height and body fat at this time
            if let height = heightEntries.last(where: { $0.date <= date })?.value {
                // Calculate BMI
                let heightInMeters = height / 100
                let bmi = weight / (heightInMeters * heightInMeters)
                allEntries.append(StatEntry(
                    id: UUID(),
                    date: date,
                    value: bmi,
                    type: .bmi,
                    source: .automated
                ))
                
                // If we have body fat, calculate additional metrics
                if let bodyFat = bodyFatEntries.last(where: { $0.date <= date })?.value {
                    // Calculate LBM (Lean Body Mass)
                    let lbm = weight * (1 - bodyFat / 100)
                    allEntries.append(StatEntry(
                        id: UUID(),
                        date: date,
                        value: lbm,
                        type: .lbm,
                        source: .automated
                    ))
                    
                    // Calculate FM (Fat Mass)
                    let fm = weight * (bodyFat / 100)
                    allEntries.append(StatEntry(
                        id: UUID(),
                        date: date,
                        value: fm,
                        type: .fm,
                        source: .automated
                    ))
                    
                    // Calculate FFMI (Fat-Free Mass Index)
                    let ffmi = lbm / (heightInMeters * heightInMeters)
                    allEntries.append(StatEntry(
                        id: UUID(),
                        date: date,
                        value: ffmi,
                        type: .ffmi,
                        source: .automated
                    ))
                    
                    // Calculate BMR (Basal Metabolic Rate)
                    let bmr = 370 + (21.6 * lbm)
                    allEntries.append(StatEntry(
                        id: UUID(),
                        date: date,
                        value: bmr,
                        type: .bmr,
                        source: .automated
                    ))
                }
                
                // Calculate BSA (Body Surface Area)
                let bsa = sqrt((height * weight) / 3600)
                allEntries.append(StatEntry(
                    id: UUID(),
                    date: date,
                    value: bsa,
                    type: .bsa,
                    source: .automated
                ))
            }
        }
        
        logger.info("Added \(allEntries.count - baseEntries.count) derived metrics")
        return allEntries
    }
    
    // MARK: - Sync Operations
    
    func startHealthKitImport() {
        logger.info("Starting HealthKit import via user action")
        isLoading = true
        
        userActionHandler.handleHealthKitImport { [weak self] success, error in
            self?.isLoading = false
            if success {
                self?.logger.info("✅ HealthKit import completed")
                self?.loadEntries() // Refresh from database
            } else if let error = error {
                self?.logger.error("❌ HealthKit import failed: \(error.localizedDescription)")
            }
        }
    }
    
    func forceSyncToBackend() async {
        logger.info("Force syncing to backend")
        await userActionHandler.forceSyncAll()
        loadEntries() // Refresh after sync
    }
    
    func forceSyncFromBackend() async {
        logger.info("Force syncing from backend")
        await userActionHandler.forceSyncFromBackend()
        loadEntries() // Refresh after sync
    }
    
    // MARK: - Utility Methods
    
    func triggerUpdate() {
        DispatchQueue.main.async {
            self.refreshTrigger = UUID()
            self.objectWillChange.send()
        }
    }
    
    func clearAllEntries() {
        logger.warning("Clearing all entries - this will affect the local database")
        localDatabase.clearAllData()
        loadEntries()
    }
    
    func clearEntries(from source: StatSource) {
        logger.info("Clearing entries from source: \(source.rawValue)")
        
        // Get entries from this source and mark them for deletion
        let entriesToDelete = entries.filter { $0.source == source }
        
        for entry in entriesToDelete {
            removeEntry(entry)
        }
    }
    
    // MARK: - Debug and Status
    
    func getDebugInfo() -> String {
        let dbStats = localDatabase.getDataStatistics()
        let syncStatus = userActionHandler.getSyncStatus()
        
        return """
        📊 Stats History Debug Info:
        • Displayed entries: \(entries.count)
        • Loading: \(isLoading)
        
        \(dbStats)
        
        \(syncStatus)
        """
    }
    
    // MARK: - Migration from Old System
    
    /// Migrate data from the old UserDefaults-based system to the new Core Data system
    func migrateFromOldSystem() {
        logger.info("Starting migration from old UserDefaults system")
        
        let saveKey = "StatsHistory" // The old key used by the original StatsHistoryManager
        
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let oldEntries = try? JSONDecoder().decode([StatEntry].self, from: data) else {
            logger.info("No old data found for migration")
            return
        }
        
        logger.info("Found \(oldEntries.count) entries to migrate")
        
        // Filter out calculated entries as they will be regenerated
        let entriesToMigrate = oldEntries.filter { !$0.type.isCalculated }
        
        logger.info("Migrating \(entriesToMigrate.count) base entries (excluding calculated ones)")
        
        // Add each entry through the proper flow
        addEntries(entriesToMigrate)
        
        // Clear the old data after successful migration
        UserDefaults.standard.removeObject(forKey: saveKey)
        logger.info("✅ Migration completed and old data cleared")
    }
}

// MARK: - Backwards Compatibility
extension NewStatsHistoryManager {
    /// Legacy method names for backwards compatibility with existing views
    
    func syncManualEntriesToHealthKit() {
        logger.info("Legacy sync method called - starting HealthKit import")
        startHealthKitImport()
    }
    
    func syncAppleHealthEntriesToBackend() {
        logger.info("Legacy sync method called - force syncing to backend")
        Task {
            await forceSyncToBackend()
        }
    }
    
    func syncAllEntriesToBackend() {
        logger.info("Legacy sync method called - force syncing all to backend")
        Task {
            await forceSyncToBackend()
        }
    }
    
    func resetAppleHealthSyncFlag() {
        logger.info("Legacy reset method called - restarting HealthKit sync")
        startHealthKitImport()
    }
    
    func loadMetricsFromServer() async {
        logger.info("Legacy server load method called - syncing from backend")
        await forceSyncFromBackend()
    }
}