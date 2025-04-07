import SwiftUI

struct ProgressView: View {
    @ObservedObject private var historyManager = StatsHistoryManager.shared
    
    var body: some View {
        List {
            ForEach(StatType.allCases.filter { $0 != .bmi }, id: \.self) { statType in
                NavigationLink(destination: HistoryView(historyManager: historyManager, statType: statType)) {
                    HStack {
                        Image(systemName: statType.iconName)
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                        
                        VStack(alignment: .leading) {
                            Text(statType.title)
                                .font(.headline)
                            
                            if let value = historyManager.getLatestValue(for: statType) {
                                Text("\(value.formatted()) \(statType.unit)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No data")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // BMI (calculated)
            let weight = historyManager.getLatestValue(for: .weight)
            let height = historyManager.getLatestValue(for: .height)
            let bmi = calculateBMI(weight: weight, height: height)
            
            NavigationLink(destination: HistoryView(historyManager: historyManager, statType: .bmi)) {
                HStack {
                    Image(systemName: StatType.bmi.iconName)
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                        .frame(width: 30, height: 30)
                    
                    VStack(alignment: .leading) {
                        Text(StatType.bmi.title)
                            .font(.headline)
                        
                        if let bmi = bmi {
                            Text("\(bmi.formatted()) \(StatType.bmi.unit)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Need weight and height")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Progress")
    }
    
    private func calculateBMI(weight: Double?, height: Double?) -> Double? {
        if let weight = weight, let height = height, height > 0 {
            let heightInMeters = height / 100
            return weight / (heightInMeters * heightInMeters)
        }
        return nil
    }
}

extension StatType {
    var iconName: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .height: return "ruler.fill"
        case .bodyFat: return "figure.arms.open"
        case .bmi: return "chart.bar.fill"
        }
    }
}

#Preview {
    NavigationStack {
        ProgressView()
    }
} 