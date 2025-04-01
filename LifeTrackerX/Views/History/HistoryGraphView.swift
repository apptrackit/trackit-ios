import SwiftUI
import Charts

enum TimeFrame: String, CaseIterable {
    case weekly, monthly, yearly
}

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
        case .yearly:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= yearAgo }
                .sorted(by: { $0.date < $1.date })
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
            
            if filteredData.isEmpty {
                Text("No data available for this time period")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                Chart {
                    ForEach(filteredData) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value(statType.title, entry.value)
                        )
                        .foregroundStyle(Color.blue)
                        
                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value(statType.title, entry.value)
                        )
                        .foregroundStyle(Color.blue)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel(format: getDateFormat())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: getYAxisDomain())
            }
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(10)
    }
    
    private func getDateFormat() -> Date.FormatStyle {
        switch selectedTimeFrame {
        case .weekly:
            return .dateTime.weekday(.abbreviated)
        case .monthly:
            return .dateTime.day()
        case .yearly:
            return .dateTime.month(.abbreviated)
        }
    }
    
    private func getYAxisDomain() -> ClosedRange<Double> {
        guard let minValue = filteredData.map({ $0.value }).min(),
              let maxValue = filteredData.map({ $0.value }).max() else {
            return 0...100
        }
        
        let padding = max((maxValue - minValue) * 0.1, 1.0)
        return (minValue - padding)...(maxValue + padding)
    }
}
