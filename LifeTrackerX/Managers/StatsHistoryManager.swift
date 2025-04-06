import Foundation
import SwiftUI

class StatsHistoryManager: ObservableObject {
    // Shared singleton instance
    static let shared = StatsHistoryManager()
    
    @Published var entries: [StatEntry] = []
    // Add a refresh trigger to force view updates
    @Published var refreshTrigger: UUID = UUID()
    private let saveKey = "StatsHistory"
    
    // Reference to HealthManager
    private let healthManager = HealthManager()
    
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
        
        // If this is a weight or height entry, recalculate BMI entries
        if entry.type == .weight || entry.type == .height {
            recalculateBMIEntries()
        }
        
        saveEntries()
        
        // If this is a manual entry and not from Apple Health, sync to HealthKit
        if entry.source == .manual && entry.type != .bmi {
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
    
    private func recalculateBMIEntries() {
        print("🔄 Recalculating BMI entries...")
        
        // Get all weight and height entries sorted by date
        let weightEntries = entries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let heightEntries = entries.filter { $0.type == .height }.sorted { $0.date < $1.date }
        
        print("🔄 Found \(weightEntries.count) weight entries")
        print("🔄 Found \(heightEntries.count) height entries")
        
        // Remove all existing BMI entries
        let oldBMICount = entries.filter { $0.type == .bmi }.count
        entries.removeAll { $0.type == .bmi }
        print("🔄 Removed \(oldBMICount) existing BMI entries")
        
        var newBMICount = 0
        
        // Calculate BMI for each weight entry using the most recent height at that time
        for weightEntry in weightEntries {
            if let heightEntry = heightEntries.last(where: { $0.date <= weightEntry.date }) {
                let heightInMeters = heightEntry.value / 100
                let bmi = weightEntry.value / (heightInMeters * heightInMeters)
                
                print("🔄 Calculating BMI for weight=\(weightEntry.value)kg, height=\(heightEntry.value)cm")
                print("🔄 BMI = \(bmi) on \(weightEntry.date)")
                
                // Create BMI entry with the same date as the weight entry
                let bmiEntry = StatEntry(
                    date: weightEntry.date,
                    value: bmi,
                    type: .bmi,
                    source: weightEntry.source // Use the same source as the weight entry
                )
                entries.append(bmiEntry)
                newBMICount += 1
            }
        }
        
        print("🔄 Created \(newBMICount) new BMI entries")
        
        // Sort entries by date (newest first)
        entries.sort { $0.date > $1.date }
        saveEntries()
        
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
        
        // If this is a weight or height entry, recalculate BMI entries
        if entry.type == .weight || entry.type == .height {
            recalculateBMIEntries()
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
                recalculateBMIEntries()
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
            recalculateBMIEntries()
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
        recalculateBMIEntries()
        saveEntries()
        triggerUpdate()
    }
}
