import Foundation
import SwiftUI

class StatsHistoryManager: ObservableObject {
    @Published var entries: [StatEntry] = []
    private let saveKey = "StatsHistory"
    
    init() {
        loadEntries()
    }
    
    func addEntry(_ entry: StatEntry) {
        // Only replace if the entry is from the same source, otherwise keep both
        if let index = entries.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: entry.date) &&
            $0.type == entry.type &&
            $0.source == entry.source
        }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        
        entries.sort { $0.date > $1.date }
        saveEntries()
    }
    
    func removeEntry(_ entry: StatEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }
    
    func updateEntry(_ entry: StatEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveEntries()
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
}
