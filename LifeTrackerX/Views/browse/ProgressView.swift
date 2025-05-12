import SwiftUI

struct ProgressView: View {
    @ObservedObject private var historyManager = StatsHistoryManager.shared
    
    var body: some View {
        List {
            // HealthKit compatible measurements
            Section("HealthKit Measurements") {
                ForEach([StatType.weight, .height, .bodyFat, .waist], id: \.self) { statType in
                    NavigationLink(destination: HistoryView(historyManager: historyManager, statType: statType)) {
                        StatRow(statType: statType, value: historyManager.getLatestValue(for: statType))
                    }
                }
            }
            
            // Custom measurements
            Section("Body Measurements") {
                ForEach([StatType.bicep, .chest, .thigh, .shoulder, .glutes], id: \.self) { statType in
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
                
                // BMI
                let bmi = calculateBMI(weight: weight, height: height)
                NavigationLink(destination: HistoryView(historyManager: historyManager, statType: .bmi)) {
                    StatRow(statType: .bmi, value: bmi)
                }
                
                // LBM (Lean Body Mass)
                let lbm = calculateLBM(weight: weight, bodyFat: bodyFat)
                NavigationLink(destination: HistoryView(historyManager: historyManager, statType: .lbm)) {
                    StatRow(statType: .lbm, value: lbm)
                }
                
                // FM (Fat Mass)
                let fm = calculateFM(weight: weight, bodyFat: bodyFat)
                NavigationLink(destination: HistoryView(historyManager: historyManager, statType: .fm)) {
                    StatRow(statType: .fm, value: fm)
                }
                
                // FFMI (Fat-Free Mass Index)
                let ffmi = calculateFFMI(lbm: lbm, height: height)
                NavigationLink(destination: HistoryView(historyManager: historyManager, statType: .ffmi)) {
                    StatRow(statType: .ffmi, value: ffmi)
                }
                
                // BMR (Basal Metabolic Rate)
                let bmr = calculateBMR(lbm: lbm)
                NavigationLink(destination: HistoryView(historyManager: historyManager, statType: .bmr)) {
                    StatRow(statType: .bmr, value: bmr)
                }
                
                // BSA (Body Surface Area)
                let bsa = calculateBSA(weight: weight, height: height)
                NavigationLink(destination: HistoryView(historyManager: historyManager, statType: .bsa)) {
                    StatRow(statType: .bsa, value: bsa)
                }
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