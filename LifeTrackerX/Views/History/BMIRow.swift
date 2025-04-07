import SwiftUI

struct BMIRow: View {
    let entry: StatEntry
    @ObservedObject var historyManager: StatsHistoryManager
    
    private var weightAndHeight: (weight: Double, height: Double)? {
        let weightEntry = historyManager.getEntries(for: .weight)
            .filter { $0.date <= entry.date }
            .sorted { $0.date > $1.date }
            .first
        
        let heightEntry = historyManager.getEntries(for: .height)
            .filter { $0.date <= entry.date }
            .sorted { $0.date > $1.date }
            .first
        
        if let weight = weightEntry, let height = heightEntry {
            return (weight: weight.value, height: height.value)
        }
        return nil
    }
    
    private var bodyFat: Double? {
        let bodyFatEntry = historyManager.getEntries(for: .bodyFat)
            .filter { $0.date <= entry.date }
            .sorted { $0.date > $1.date }
            .first
        
        return bodyFatEntry?.value
    }
    
    private var sourceDataText: String {
        switch entry.type {
        case .bmi:
            if let data = weightAndHeight {
                return "W: \(String(format: "%.1f", data.weight)) kg, H: \(String(format: "%.1f", data.height)) cm"
            }
        case .lbm, .fm:
            if let data = weightAndHeight, let bf = bodyFat {
                return "W: \(String(format: "%.1f", data.weight)) kg, BF: \(String(format: "%.1f", bf))%"
            }
        case .ffmi:
            if let data = weightAndHeight, let bf = bodyFat {
                return "W: \(String(format: "%.1f", data.weight)) kg, H: \(String(format: "%.1f", data.height)) cm, BF: \(String(format: "%.1f", bf))%"
            }
        case .bmr:
            if let data = weightAndHeight, let bf = bodyFat {
                let lbm = data.weight * (1 - bf / 100)
                return "LBM: \(String(format: "%.1f", lbm)) kg"
            }
        case .bsa:
            if let data = weightAndHeight {
                return "W: \(String(format: "%.1f", data.weight)) kg, H: \(String(format: "%.1f", data.height)) cm"
            }
        default:
            return ""
        }
        return ""
    }
    
    var body: some View {
        HStack {
            // Left side - Icon and value
            HStack(spacing: 12) {
                // Use automated icon
                Image(systemName: entry.source.iconName)
                    .foregroundColor(.orange)
                
                let formattedValue = String(format: "%.1f", entry.value)
                    .replacingOccurrences(of: ".", with: ",")
                
                Text(formattedValue)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            if !sourceDataText.isEmpty {
                Text(sourceDataText)
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            
            Text(formatDate(entry.date))
                .foregroundColor(.gray)
                .font(.subheadline)
                .padding(.leading, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' H:mm"
        return formatter.string(from: date)
    }
} 