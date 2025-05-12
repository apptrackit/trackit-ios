import SwiftUI

struct ProgressView: View {
    @ObservedObject private var historyManager = StatsHistoryManager.shared
    
    // Helper function to get the date of the most recent entry for a stat type
    private func getLatestEntryDate(for statType: StatType) -> Date {
        return historyManager.getEntries(for: statType).first?.date ?? .distantPast
    }
    
    // Helper function to sort stat types by their most recent entry
    private func sortedStatTypes(_ types: [StatType]) -> [StatType] {
        return types.sorted { type1, type2 in
            getLatestEntryDate(for: type1) > getLatestEntryDate(for: type2)
        }
    }
    
    var body: some View {
        List {
            // HealthKit compatible measurements
            Section("HealthKit Measurements") {
                let healthKitTypes = [StatType.weight, .height, .bodyFat, .waist]
                ForEach(sortedStatTypes(healthKitTypes), id: \.self) { statType in
                    NavigationLink(destination: HistoryView(historyManager: historyManager, statType: statType)) {
                        StatRow(statType: statType, value: historyManager.getLatestValue(for: statType))
                    }
                }
            }
            
            // Custom measurements
            Section("Body Measurements") {
                let bodyTypes = [StatType.bicep, .chest, .thigh, .shoulder, .glutes, .calf, .neck, .forearm]
                ForEach(sortedStatTypes(bodyTypes), id: \.self) { statType in
                    NavigationLink(destination: HistoryView(historyManager: historyManager, statType: statType)) {
                        StatRow(statType: statType, value: historyManager.getLatestValue(for: statType))
                    }
                }
            }
            
            // Calculated measurements
            Section("Calculated") {
                let weight = historyManager.getLatestValue(for: .weight)
                let height = historyManager.getLatestValue(for: .height)
                let bodyFat = historyManager.getLatestValue(for: .bodyFat)
                
                let calculatedTypes = [StatType.bmi, .lbm, .fm, .ffmi, .bmr, .bsa]
                ForEach(sortedStatTypes(calculatedTypes), id: \.self) { statType in
                    NavigationLink(destination: HistoryView(historyManager: historyManager, statType: statType)) {
                        StatRow(statType: statType, value: getCalculatedValue(statType: statType, weight: weight, height: height, bodyFat: bodyFat))
                    }
                }
            }
        }
        .navigationTitle("Progress")
    }
    
    private func getCalculatedValue(statType: StatType, weight: Double?, height: Double?, bodyFat: Double?) -> Double? {
        switch statType {
        case .bmi:
            return calculateBMI(weight: weight, height: height)
        case .lbm:
            return calculateLBM(weight: weight, bodyFat: bodyFat)
        case .fm:
            return calculateFM(weight: weight, bodyFat: bodyFat)
        case .ffmi:
            let lbm = calculateLBM(weight: weight, bodyFat: bodyFat)
            return calculateFFMI(lbm: lbm, height: height)
        case .bmr:
            let lbm = calculateLBM(weight: weight, bodyFat: bodyFat)
            return calculateBMR(lbm: lbm)
        case .bsa:
            return calculateBSA(weight: weight, height: height)
        default:
            return nil
        }
    }
    
    private func calculateBMI(weight: Double?, height: Double?) -> Double? {
        if let weight = weight, let height = height, height > 0 {
            let heightInMeters = height / 100
            return weight / (heightInMeters * heightInMeters)
        }
        return nil
    }
    
    private func calculateLBM(weight: Double?, bodyFat: Double?) -> Double? {
        if let weight = weight, let bodyFat = bodyFat {
            return weight * (1 - bodyFat / 100)
        }
        return nil
    }
    
    private func calculateFM(weight: Double?, bodyFat: Double?) -> Double? {
        if let weight = weight, let bodyFat = bodyFat {
            return weight * (bodyFat / 100)
        }
        return nil
    }
    
    private func calculateFFMI(lbm: Double?, height: Double?) -> Double? {
        if let lbm = lbm, let height = height, height > 0 {
            let heightInMeters = height / 100
            return lbm / (heightInMeters * heightInMeters)
        }
        return nil
    }
    
    private func calculateBMR(lbm: Double?) -> Double? {
        if let lbm = lbm {
            return 370 + (21.6 * lbm)
        }
        return nil
    }
    
    private func calculateBSA(weight: Double?, height: Double?) -> Double? {
        if let weight = weight, let height = height {
            return sqrt((height * weight) / 3600)
        }
        return nil
    }
}

struct StatRow: View {
    let statType: StatType
    let value: Double?
    
    private func formatValue(_ value: Double) -> String {
        switch statType {
        case .bmr:
            // BMR should be shown as a whole number
            return String(format: "%.0f", value)
        case .bodyFat:
            // Body fat percentage should show one decimal
            return String(format: "%.1f", value)
        default:
            // All other measurements show one decimal
            return String(format: "%.1f", value)
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: statType.iconName)
                .foregroundColor(.green)
                .font(.system(size: 20))
                .frame(width: 30, height: 30)
            
            VStack(alignment: .leading) {
                Text(statType.title)
                    .font(.headline)
                
                if let value = value {
                    Text("\(formatValue(value)) \(statType.unit)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(statType.isCalculated ? "Need more data" : "No data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ProgressView()
    }
} 