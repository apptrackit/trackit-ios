import SwiftUI
import Charts

struct HistoryGraphView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @Binding var selectedTimeFrame: TimeFrame
    @AppStorage("preferredWeightUnit") private var preferredWeightUnit: String = "kg"
    
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
    
    private var displayCurrentValue: Double {
        if statType == .weight {
            return (filteredData.last?.value ?? 0.0) * (preferredWeightUnit == "lb" ? 2.20462262 : 1.0)
        }
        return currentValue
    }
    
    private var unitString: String {
        statType == .weight ? (preferredWeightUnit == "lb" ? "lb" : "kg") : statType.unit
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
                value: displayCurrentValue,
                unit: unitString,
                historyManager: historyManager,
                statType: statType,
                timeFrame: selectedTimeFrame
            )
        }
    }
}
