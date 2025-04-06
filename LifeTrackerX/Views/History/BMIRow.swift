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
    
    var body: some View {
        HStack {
            // Left side - Icon and value
            HStack(spacing: 12) {
                // Different icon based on data source
                if entry.source == .appleHealth {
                    // Apple Health icon
                    Image("applehealthdark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    // BMI value
                    Text(String(format: "%.1f", entry.value))
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    // Weight and height values
                    if let values = weightAndHeight {
                        Text("\(String(format: "%.1f", values.weight)) kg × \(String(format: "%.1f", values.height)) cm")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
            
            // Right side - Date
            Text(formatDate(entry.date))
                .foregroundColor(.gray)
                .font(.subheadline)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' H:mm"
        return formatter.string(from: date)
    }
} 