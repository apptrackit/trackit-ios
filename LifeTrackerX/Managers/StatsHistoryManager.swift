import Foundation
import SwiftUI

class StatsHistoryManager: ObservableObject {
    // Shared singleton instance
    static let shared = StatsHistoryManager()
    
    @Published var entries: [StatEntry] = []
    // Add a refresh trigger to force view updates
    @Published var refreshTrigger: UUID = UUID()
    private let saveKey = "StatsHistory"
    
    // Reference to HealthManager and MetricSyncManager
    private let healthManager = HealthManager()
    private let metricSyncManager = MetricSyncManager.shared
    
    // Make init private to enforce singleton pattern
    private init() {
        loadEntries()
    }
    
    // Add this method to force UI updates
    func triggerUpdate() {
        DispatchQueue.main.async {
            self.refreshTrigger = UUID()
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Entry Management with UUID Support
    
    func findEntry(byUUID uuid: String) -> StatEntry? {
        return entries.first { entry in
            entry.syncUUID == uuid || entry.backendId == uuid
        }
    }
    
    func updateEntryBackendId(localId: UUID, backendId: String) {
        if let index = entries.firstIndex(where: { $0.id == localId }) {
            entries[index].backendId = backendId
            saveEntries()
        }
    }
    
    func markEntrySynced(_ id: UUID, syncedWithBackend: Bool = false, syncedWithHealth: Bool = false) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            if syncedWithBackend {
                entries[index].syncedWithBackend = true
            }
            if syncedWithHealth {
                entries[index].syncedWithHealth = true
            }
            saveEntries()
        }
    }
    
    func softDeleteEntry(_ id: UUID) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].isDeleted = true
            entries[index].lastUpdatedAt = Date()
            entries[index].syncedWithBackend = false
            saveEntries()
            triggerUpdate()
        }
    }
    
    func updateEntry(_ entry: StatEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            entries[index].lastUpdatedAt = Date()
            entries[index].syncedWithBackend = false
            saveEntries()
            
            // Recalculate if needed
            if entry.type == .weight || entry.type == .height || entry.type == .bodyFat {
                recalculateAllDerivedValues()
            }
            
            triggerUpdate()
        }
    }
    
    // Function to sync all manual entries to Apple Health
    func syncManualEntriesToHealthKit() {
        guard healthManager.isWriteAuthorized else { 
            print("⚠️ Cannot sync manual entries to HealthKit - write access not available")
            return 
        }
        
        print("📤 Starting sync of all manual entries to Apple Health")
        
        // Get all manual entries that need syncing to HealthKit
        let entriesToSync = entries.filter { $0.needsHealthKitSync && !$0.isDeleted }
        print("📤 Found \(entriesToSync.count) manual entries to sync to HealthKit")
        
        for entry in entriesToSync {
            healthManager.saveToHealthKit(entry) { [weak self] success, error in
                if success {
                    print("✅ Successfully synced \(entry.type) to Apple Health")
                    self?.markEntrySynced(entry.id, syncedWithHealth: true)
                } else if let error = error {
                    print("❌ Error syncing to Apple Health: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Function to sync entries to backend
    func syncEntriesToBackend() {
        print("📤 Starting sync to backend database")
        
        // Get all entries that need backend sync
        let entriesToSync = entries.filter { $0.needsBackendSync && !$0.isDeleted }
        print("📤 Found \(entriesToSync.count) entries to sync to backend")
        
        for entry in entriesToSync {
            Task { @MainActor in
                metricSyncManager.syncEntry(entry, operation: entry.backendId != nil ? .update : .create)
            }
        }
    }
    
    // Function to perform full sync
    func performFullSync() {
        Task { @MainActor in
            // First sync with backend
            await metricSyncManager.performFullSync()
            
            // Then sync manual entries to HealthKit if authorized
            if healthManager.isWriteAuthorized {
                syncManualEntriesToHealthKit()
            }
        }
    }
    
    private func recalculateAllDerivedValues() {
        print("🔄 Recalculating all derived values...")
        
        // Get all entries sorted by date
        let weightEntries = entries.filter { $0.type == .weight && !$0.isDeleted }.sorted { $0.date < $1.date }
        let heightEntries = entries.filter { $0.type == .height && !$0.isDeleted }.sorted { $0.date < $1.date }
        let bodyFatEntries = entries.filter { $0.type == .bodyFat && !$0.isDeleted }.sorted { $0.date < $1.date }
        
        // Remove all existing calculated entries
        entries.removeAll { $0.type.isCalculated }
        
        // For each weight entry, calculate all possible derived values
        for weightEntry in weightEntries {
            let date = weightEntry.date
            let weight = weightEntry.value
            
            // Find the most recent height and body fat at this time
            if let height = heightEntries.last(where: { $0.date <= date })?.value {
                // Calculate BMI
                let heightInMeters = height / 100
                let bmi = weight / (heightInMeters * heightInMeters)
                entries.append(StatEntry(
                    date: date,
                    value: bmi,
                    type: .bmi,
                    source: .automated
                ))
                
                // If we have body fat, calculate LBM, FM, FFMI, BMR
                if let bodyFat = bodyFatEntries.last(where: { $0.date <= date })?.value {
                    // Calculate LBM
                    let lbm = weight * (1 - bodyFat / 100)
                    entries.append(StatEntry(
                        date: date,
                        value: lbm,
                        type: .lbm,
                        source: .automated
                    ))
                    
                    // Calculate FM
                    let fm = weight * (bodyFat / 100)
                    entries.append(StatEntry(
                        date: date,
                        value: fm,
                        type: .fm,
                        source: .automated
                    ))
                    
                    // Calculate FFMI
                    let ffmi = lbm / (heightInMeters * heightInMeters)
                    entries.append(StatEntry(
                        date: date,
                        value: ffmi,
                        type: .ffmi,
                        source: .automated
                    ))
                    
                    // Calculate BMR (Katch-McArdle formula)
                    let bmr = 370 + (21.6 * lbm)
                    entries.append(StatEntry(
                        date: date,
                        value: bmr,
                        type: .bmr,
                        source: .automated
                    ))
                }
                
                // Calculate BSA (Mosteller formula)
                let bsa = sqrt((height * weight) / 3600)
                entries.append(StatEntry(
                    date: date,
                    value: bsa,
                    type: .bsa,
                    source: .automated
                ))
            }
        }
        
        print("✅ Recalculation complete")
        saveEntries()
    }
    
    // MARK: - Entry CRUD Operations
    
    func addEntry(_ entry: StatEntry) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.addEntry(entry)
            }
            return
        }
        
        // Check for duplicate using UUID or same date/type/source combination
        let isDuplicate = entries.contains { existing in
            // Check by UUID if both have one
            if let existingUUID = existing.uuid, let entryUUID = entry.uuid {
                return existingUUID == entryUUID && !existing.isDeleted
            }
            // Otherwise check by date/type/source
            return Calendar.current.isDate(existing.date, inSameDayAs: entry.date) &&
                   existing.type == entry.type &&
                   existing.source == entry.source &&
                   !existing.isDeleted
        }
        
        if !isDuplicate {
            var newEntry = entry
            newEntry.lastUpdatedAt = Date()
            newEntry.syncedWithBackend = false
            entries.append(newEntry)
            
            // Sort entries by date (newest first)
            entries.sort { $0.date > $1.date }
            
            // If this is a weight, height, or body fat entry, recalculate all derived values
            if entry.type == .weight || entry.type == .height || entry.type == .bodyFat {
                recalculateAllDerivedValues()
            } else {
                saveEntries()
            }
            
            // Sync to backend database (for all non-calculated metrics)
            if !entry.type.isCalculated {
                print("📤 Syncing new entry to backend: \(entry.type)")
                Task { @MainActor in
                    metricSyncManager.syncEntry(entry, operation: .create)
                }
            }
            
            // If this is a manual entry, sync to HealthKit
            if entry.source == .manual && !entry.type.isCalculated {
                if healthManager.isWriteAuthorized {
                    healthManager.saveToHealthKit(entry) { [weak self] success, error in
                        if success {
                            print("✅ Synced \(entry.type) to Apple Health")
                            self?.markEntrySynced(entry.id, syncedWithHealth: true)
                        } else if let error = error {
                            print("❌ Error syncing to Apple Health: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } else {
            print("⚠️ Skipping duplicate entry: \(entry.type) on \(entry.date)")
        }
        
        // Force UI refresh
        triggerUpdate()
    }

    func addEntries(_ newEntries: [StatEntry]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.addEntries(newEntries)
            }
            return
        }

        var addedCount = 0
        
        for entry in newEntries {
            // Check for duplicate using UUID or same date/type/source combination
            let isDuplicate = entries.contains { existing in
                // Check by UUID if both have one
                if let existingUUID = existing.uuid, let entryUUID = entry.uuid {
                    return existingUUID == entryUUID && !existing.isDeleted
                }
                // Otherwise check by date/type/source
                return Calendar.current.isDate(existing.date, inSameDayAs: entry.date) &&
                       existing.type == entry.type &&
                       existing.source == entry.source &&
                       !existing.isDeleted
            }
            
            if !isDuplicate {
                var newEntry = entry
                newEntry.lastUpdatedAt = Date()
                if entry.source == .appleHealth {
                    newEntry.syncedWithHealth = true
                }
                entries.append(newEntry)
                addedCount += 1
            }
        }

        if addedCount > 0 {
            entries.sort { $0.date > $1.date }
            recalculateAllDerivedValues()
            
            print("✅ Added \(addedCount) new entries out of \(newEntries.count) total")
            
            // Sync new entries to backend
            syncEntriesToBackend()
        }
        
        triggerUpdate()
    }
    
    func removeEntry(_ entry: StatEntry) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.removeEntry(entry)
            }
            return
        }
        
        // Soft delete instead of hard delete
        softDeleteEntry(entry.id)
        
        // Sync deletion to backend
        if !entry.type.isCalculated {
            print("📤 Syncing deleted entry to backend: \(entry.type)")
            Task { @MainActor in
                metricSyncManager.deleteEntry(entry)
            }
        }
        
        // Recalculate derived values if needed
        if entry.type == .weight || entry.type == .height || entry.type == .bodyFat {
            recalculateAllDerivedValues()
        }
        
        triggerUpdate()
    }
    
    func getLatestValue(for type: StatType) -> Double? {
        let typeEntries = entries.filter { $0.type == type && !$0.isDeleted }
        if let latest = typeEntries.sorted(by: { $0.date > $1.date }).first {
            return latest.value
        }
        return nil
    }
    
    func getEntries(for type: StatType) -> [StatEntry] {
        return entries.filter { $0.type == type && !$0.isDeleted }.sorted(by: { $0.date > $1.date })
    }
    
    func getEntries(for type: StatType, source: StatSource) -> [StatEntry] {
        return entries.filter { $0.type == type && $0.source == source && !$0.isDeleted }.sorted(by: { $0.date > $1.date })
    }
    
    func getEntriesAt(date: Date) -> [StatEntry] {
        var result: [StatEntry] = []
        
        let relevantTypes: [StatType] = [.weight, .height, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
        
        for type in relevantTypes {
            // Find the most recent entry for this type on or before the given date
            if let latestEntry = entries.filter({ $0.type == type && $0.date <= date && !$0.isDeleted })
                .sorted(by: { $0.date > $1.date })
                .first {
                result.append(latestEntry)
            }
        }
        
        return result
    }
    
    func getLatestEntry(for type: StatType) -> StatEntry? {
        return entries
            .filter { $0.type == type && !$0.isDeleted }
            .sorted { $0.date > $1.date }
            .first
    }
    
    func getEntries(for type: StatType, in timeFrame: TimeFrame) -> [StatEntry] {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        switch timeFrame {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)!
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: now)!
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -6, to: now)!
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now)!
        case .all:
            startDate = Date.distantPast
        }
        
        return entries
            .filter { $0.type == type && $0.date >= startDate && !$0.isDeleted }
            .sorted { $0.date < $1.date }
    }
    
    func getAllMeasurements(for date: Date) -> [StatEntry] {
        return entries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: date) && !entry.isDeleted
        }.sorted { $0.type.rawValue < $1.type.rawValue }
    }
    
    func getHistoricalData(for type: StatType, days: Int) -> [StatEntry] {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!
        
        return entries
            .filter { 
                $0.type == type && 
                $0.date >= startDate && 
                $0.date <= endDate &&
                !$0.isDeleted
            }
            .sorted { $0.date < $1.date }
    }
    
    // MARK: - Data Persistence
    
    private func saveEntries() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(entries)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            print("Failed to save entries: \(error)")
        }
    }
    
    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        
        do {
            let decoder = JSONDecoder()
            let loadedEntries = try decoder.decode([StatEntry].self, from: data)
            
            // Migrate old entries if needed
            self.entries = loadedEntries.map { entry in
                // Check if this is an old entry that needs migration
                if entry.uuid == nil && entry.source == .appleHealth {
                    // For old Apple Health entries without UUID, keep them as is
                    return entry
                }
                return entry
            }
            
            print("Loaded \(entries.count) entries from storage")
        } catch {
            print("Failed to load entries: \(error)")
        }
    }
    
    // Debug function to clear all entries
    func clearAllEntries() {
        entries.removeAll()
        saveEntries()
        triggerUpdate()
    }
    
    // Function to clear only entries from a specific source
    func clearEntries(from source: StatSource) {
        entries.removeAll { $0.source == source }
        
        // Reset sync flag if Apple Health entries were cleared
        if source == .appleHealth {
            // This logic needs to be re-evaluated in the new sync model
            // For now, we'll just remove the entries, the sync manager will handle re-syncing
        }
        
        // Recalculate BMI entries after clearing data
        recalculateAllDerivedValues()
        saveEntries()
        triggerUpdate()
    }
    
    // MARK: - Server Data Loading
    func loadMetricsFromServer() async {
        print("📱 Loading metrics from server...")
        
        do {
            let serverEntries = try await MetricSyncManager.shared.fetchUserMetrics()
            
            // Update UI on main thread
            await MainActor.run {
                // Clear existing entries and add server entries
                entries = serverEntries
                
                // Recalculate BMI entries
                recalculateAllDerivedValues()
                
                // Save to local storage
                saveEntries()
                
                // Trigger UI update
                triggerUpdate()
            }
            
            print("📱 Successfully loaded \(serverEntries.count) metrics from server")
        } catch {
            print("❌ Failed to load metrics from server: \(error.localizedDescription)")
            // Don't throw error - just log it and continue with empty data
            // This allows the app to work even if the endpoint doesn't exist yet
        }
    }
}
