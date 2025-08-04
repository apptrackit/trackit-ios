import SwiftUI
import Charts

struct HistoryGraphView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @Binding var selectedTimeFrame: TimeFrame
    
    var filteredData: [StatEntry] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeFrame {
        case .weekly:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= weekAgo }
                .sorted(by: { $0.date < $1.date })
        case .monthly:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= monthAgo }
                .sorted(by: { $0.date < $1.date })
        case .sixMonths:
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= sixMonthsAgo }
                .sorted(by: { $0.date < $1.date })
        case .yearly:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= yearAgo }
                .sorted(by: { $0.date < $1.date })
        case .allTime:
            return historyManager.getEntries(for: statType)
                .sorted(by: { $0.date < $1.date })
        }
    }
    
    var currentValue: Double {
        filteredData.last?.value ?? 0.0
    }
    
    var body: some View {
        VStack {
            Picker("Time Frame", selection: $selectedTimeFrame) {
                ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                    Text(timeFrame.rawValue.capitalized).tag(timeFrame)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            ProgressChartView(
                title: statType.title,
                value: currentValue,
                unit: statType.unit,
                historyManager: historyManager,
                statType: statType,
                timeFrame: selectedTimeFrame
            )
        }
    }
}
