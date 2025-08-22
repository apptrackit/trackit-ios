import SwiftUI
import Charts

struct HistoryGraphView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @Binding var selectedTimeFrame: TimeFrame
    @AppStorage("preferredWeightUnit") private var preferredWeightUnit: String = "kg"
    @AppStorage("preferredLengthUnit") private var preferredLengthUnit: String = "cm"
    
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
        let base = filteredData.last?.value ?? 0.0
        if statType == .weight {
            return base * (preferredWeightUnit == "lb" ? 2.20462262 : 1.0)
        }
        if isLengthType {
            return base * (preferredLengthUnit == "in" ? (1.0/2.54) : 1.0)
        }
        return base
    }
    
    private var unitString: String {
        if statType == .weight { return preferredWeightUnit == "lb" ? "lb" : "kg" }
        if isLengthType { return preferredLengthUnit == "in" ? "in" : "cm" }
        return statType.unit
    }

    private var isLengthType: Bool {
        switch statType {
        case .height, .waist, .bicep, .chest, .thigh, .shoulder, .glutes, .calf, .neck, .forearm:
            return true
        default:
            return false
        }
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
