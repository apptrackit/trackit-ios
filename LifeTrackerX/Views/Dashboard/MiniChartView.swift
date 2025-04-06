import SwiftUI
import Charts

struct MiniChartView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    
    private var last30DaysData: [StatEntry] {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        
        // Get all entries for this type
        let allEntries = historyManager.getEntries(for: statType)
        print("📊 \(statType.title) - Total entries available: \(allEntries.count)")
        
        // Filter for last 30 days
        let recentEntries = allEntries
            .filter { $0.date >= thirtyDaysAgo }
            .sorted(by: { $0.date > $1.date }) // Sort newest first to match history view
        
        print("📊 \(statType.title) - Entries in last 30 days: \(recentEntries.count)")
        if let newest = recentEntries.first {
            print("📊 Newest entry: \(newest.value) on \(newest.date)")
        }
        if let oldest = recentEntries.last {
            print("📊 Oldest entry: \(oldest.value) on \(oldest.date)")
        }
        
        return recentEntries.reversed() // Reverse for chart display (oldest to newest)
    }
    
    var body: some View {
        let data = last30DaysData
        if data.isEmpty {
            EmptyView()
                .onAppear {
                    print("📊 No data available for \(statType.title) mini chart")
                    // Debug: Print some entries from history to verify they exist
                    let allEntries = historyManager.getEntries(for: statType)
                    print("📊 Total \(statType.title) entries in history: \(allEntries.count)")
                    for entry in allEntries.prefix(3) {
                        print("📊 History entry: \(entry.value) on \(entry.date)")
                    }
                }
        } else {
            Chart {
                ForEach(data) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value(statType.title, entry.value)
                    )
                    .foregroundStyle(Color.purple.opacity(0.8))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 80, height: 40)
        }
    }
} 