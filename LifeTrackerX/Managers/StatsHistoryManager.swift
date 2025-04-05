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
        saveEntries()
        triggerUpdate()
    }
}
