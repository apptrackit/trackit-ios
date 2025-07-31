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
    
    // Function to sync all manual entries to Apple Health
    func syncManualEntriesToHealthKit() {
        guard healthManager.isAuthorized else { return }
        
        print("📤 Starting sync of all manual entries to Apple Health")
        
        // Get all manual entries that aren't BMI (since BMI is calculated)
        let manualEntries = entries.filter { $0.source == .manual && $0.type != .bmi }
        print("📤 Found \(manualEntries.count) manual entries to sync")
        
        for entry in manualEntries {
            healthManager.saveToHealthKit(entry) { success, error in
                if success {
                    print("✅ Successfully synced historical \(entry.type) to Apple Health")
                } else if let error = error {
                    print("❌ Error syncing historical data to Apple Health: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Function to sync all entries to backend database
    func syncAllEntriesToBackend() {
        print("📤 Starting sync of all entries to backend database")
        
        // Get all non-calculated entries
        let entriesToSync = entries.filter { !$0.type.isCalculated }
        print("📤 Found \(entriesToSync.count) entries to sync to backend")
        
        Task { @MainActor in
            metricSyncManager.syncAllEntries(entriesToSync)
        }
    }
    
    private func recalculateAllDerivedValues() {
        print("🔄 Recalculating all derived values...")
        
        // Get all entries sorted by date
        let weightEntries = entries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let heightEntries = entries.filter { $0.type == .height }.sorted { $0.date < $1.date }
        let bodyFatEntries = entries.filter { $0.type == .bodyFat }.sorted { $0.date < $1.date }
        
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
                    
                    // Calculate BMR
                    let bmr = 370 + (21.6 * lbm)
                    entries.append(StatEntry(
                        date: date,
                        value: bmr,
                        type: .bmr,
                        source: .automated
                    ))
                }
                
                // Calculate BSA
                let bsa = sqrt((height * weight) / 3600)
                entries.append(StatEntry(
                    date: date,
                    value: bsa,
                    type: .bsa,
                    source: .automated
                ))
            }
        }
        
        // Sort entries by date (newest first)
        entries.sort { $0.date > $1.date }
        saveEntries()
        
        // Force UI refresh
        triggerUpdate()
    }
    
    func addEntry(_ entry: StatEntry) {
        // Need to ensure we're on the main thread when modifying @Published properties
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.addEntry(entry)
            }
            return
        }
        
        print("⭐️ Adding entry: type=\(entry.type), source=\(entry.source), value=\(entry.value)")
        
        // Only replace if the entry has the same date, type and source
        if let index = entries.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: entry.date) &&
            $0.type == entry.type &&
            $0.source == entry.source
        }) {
            entries[index] = entry
            print("⭐️ Replaced existing entry at index \(index)")
        } else {
            entries.append(entry)
            print("⭐️ Added new entry")
        }
        
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
            print("📤 Syncing entry to backend: \(entry.type)")
            Task { @MainActor in
                metricSyncManager.syncEntry(entry, operation: .create)
            }
        }
        
        // If this is a manual entry and not from Apple Health, sync to HealthKit
        if entry.source == .manual && !entry.type.isCalculated {
            print("⭐️ Attempting to sync manual entry to HealthKit")
            print("⭐️ HealthKit authorized: \(healthManager.isAuthorized)")
            
            healthManager.saveToHealthKit(entry) { success, error in
                if success {
                    print("⭐️ Successfully synced \(entry.type) to Apple Health")
                } else if let error = error {
                    print("❌ Error syncing to Apple Health: \(error.localizedDescription)")
                } else {
                    print("❌ Failed to sync to Apple Health (no error details)")
                }
            }
        } else {
            print("⭐️ Entry not synced to HealthKit: source=\(entry.source), type=\(entry.type)")
        }
        
        // Force UI refresh
        triggerUpdate()
    }
    
    func removeEntry(_ entry: StatEntry) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.removeEntry(entry)
            }
            return
        }
        
        entries.removeAll { $0.id == entry.id }
        
        // Sync to backend database (for all non-calculated metrics)
        if !entry.type.isCalculated {
            print("📤 Syncing deleted entry to backend: \(entry.type)")
            Task { @MainActor in
                metricSyncManager.syncEntry(entry, operation: .delete)
            }
        }
        
        // If this is a weight or height entry, recalculate BMI entries
        if entry.type == .weight || entry.type == .height {
            recalculateAllDerivedValues()
        }
        
        // If this was a manual entry, also delete from HealthKit
        if entry.source == .manual {
            healthManager.deleteFromHealthKit(entry) { success, error in
                if success {
                    print("Successfully deleted \(entry.type) from Apple Health")
                } else if let error = error {
                    print("Error deleting from Apple Health: \(error.localizedDescription)")
                }
            }
        }
        
        saveEntries()
        triggerUpdate()
    }
    
    func updateEntry(_ entry: StatEntry) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.updateEntry(entry)
            }
            return
        }
        
        print("📝 Updating entry: type=\(entry.type), source=\(entry.source), value=\(entry.value)")
        
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let oldEntry = entries[index]
            entries[index] = entry
            
            // Sync to backend database (for all non-calculated metrics)
            if !entry.type.isCalculated {
                print("📤 Syncing updated entry to backend: \(entry.type)")
                Task { @MainActor in
                    metricSyncManager.syncEntry(entry, operation: .update)
                }
            }
            
            // If this is a manual entry and we're authorized, update in HealthKit
            if oldEntry.source == .manual && entry.type != .bmi && healthManager.isAuthorized {
                print("📤 Syncing updated entry to Apple Health")
                
                // First delete the old entry from HealthKit
                healthManager.deleteFromHealthKit(oldEntry) { success, error in
                    if success {
                        print("✅ Successfully deleted old entry from Apple Health")
                        // Then save the new entry to HealthKit
                        self.healthManager.saveToHealthKit(entry) { success, error in
                            if success {
                                print("✅ Successfully saved updated entry to Apple Health")
                            } else if let error = error {
                                print("❌ Error saving updated entry to Apple Health: \(error.localizedDescription)")
                            }
                        }
                    } else if let error = error {
                        print("❌ Error deleting old entry from Apple Health: \(error.localizedDescription)")
                    }
                }
            }
            
            // If this is a weight or height entry, recalculate BMI entries
            if entry.type == .weight || entry.type == .height {
                recalculateAllDerivedValues()
            }
            
            saveEntries()
            triggerUpdate()
        }
    }
    
    func getLatestValue(for type: StatType) -> Double? {
        let typeEntries = entries.filter { $0.type == type }
        if let latest = typeEntries.sorted(by: { $0.date > $1.date }).first {
            return latest.value
        }
        return nil
    }
    
    func getEntries(for type: StatType) -> [StatEntry] {
        return entries.filter { $0.type == type }.sorted(by: { $0.date > $1.date })
    }
    
    func getEntries(for type: StatType, source: StatSource) -> [StatEntry] {
        return entries.filter { $0.type == type && $0.source == source }.sorted(by: { $0.date > $1.date })
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
    
    private func saveEntries() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadEntries() {
        print("📱 Loading entries from storage...")
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([StatEntry].self, from: data) {
            entries = decoded
            print("📱 Loaded \(entries.count) total entries")
            print("📱 Weight entries: \(entries.filter { $0.type == .weight }.count)")
            print("📱 Height entries: \(entries.filter { $0.type == .height }.count)")
            print("📱 BMI entries: \(entries.filter { $0.type == .bmi }.count)")
            print("📱 Body Fat entries: \(entries.filter { $0.type == .bodyFat }.count)")
            
            // Recalculate BMI entries when loading data
            recalculateAllDerivedValues()
        } else {
            print("📱 No entries found in storage or failed to decode")
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
