import Foundation
import SwiftUI

class StatsHistoryManager: ObservableObject {
    // Shared singleton instance
    static let shared = StatsHistoryManager()
    
    @Published var entries: [StatEntry] = []
    // Add a refresh trigger to force view updates
    @Published var refreshTrigger: UUID = UUID()
    private let saveKey = "StatsHistory"
    
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
    
    func addEntry(_ entry: StatEntry) {
        // Need to ensure we're on the main thread when modifying @Published properties
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.addEntry(entry)
            }
            return
        }
        
        // Only replace if the entry has the same date, type and source
        if let index = entries.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: entry.date) &&
            $0.type == entry.type &&
            $0.source == entry.source
        }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        
        // Sort entries by date (newest first)
        entries.sort { $0.date > $1.date }
        
        // If this is a weight or height entry, recalculate BMI entries
        if entry.type == .weight || entry.type == .height {
            recalculateBMIEntries()
        }
        
        saveEntries()
        
        // Force UI refresh
        triggerUpdate()
    }
    
    private func recalculateBMIEntries() {
        // Get all weight and height entries sorted by date
        let weightEntries = entries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let heightEntries = entries.filter { $0.type == .height }.sorted { $0.date < $1.date }
        
        // Remove all existing BMI entries
        entries.removeAll { $0.type == .bmi }
        
        // Calculate BMI for each weight entry using the most recent height at that time
        for weightEntry in weightEntries {
            if let heightEntry = heightEntries.last(where: { $0.date <= weightEntry.date }) {
                let heightInMeters = heightEntry.value / 100
                let bmi = weightEntry.value / (heightInMeters * heightInMeters)
                
                // Create BMI entry with the same date as the weight entry
                let bmiEntry = StatEntry(
                    date: weightEntry.date,
                    value: bmi,
                    type: .bmi,
                    source: weightEntry.source // Use the same source as the weight entry
                )
                entries.append(bmiEntry)
            }
        }
        
        // Sort entries by date (newest first)
        entries.sort { $0.date > $1.date }
        saveEntries()
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
        
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            
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
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([StatEntry].self, from: data) {
            entries = decoded
            // Recalculate BMI entries when loading data
            recalculateBMIEntries()
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
