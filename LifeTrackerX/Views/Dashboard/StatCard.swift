import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    var statType: StatType?
    var isEditable: Bool = true
    var historyManager: StatsHistoryManager?
    
    @State private var showingHistoryView = false
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background with chart
            HStack {
                Spacer()
                if title == "BMI" && value != "N/A",
                   let manager = historyManager,
                   let type = statType {
                    MiniChartView(historyManager: manager, statType: type)
                        .padding(.trailing, 20)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                
                if value == "No data" || value == "N/A" {
                    Text(value)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                } else if title == "BMI" {
                    // Direct display for BMI with large font
                    Text(value)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .zIndex(1) // Ensure text is on top
                } else {
                    // For other stats with units
                    let components = value.components(separatedBy: " ")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(components[0])
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .zIndex(1) // Ensure text is on top
                        
                        if components.count > 1 {
                            Text(components[1])
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.leading, 20)
        }
        .frame(width: 159, height: 100, alignment: .leading)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(25)
        .padding(5)
        .onTapGesture {
            if statType != nil {
                showingHistoryView = true
            }
        }
        .sheet(isPresented: $showingHistoryView) {
            if let type = statType, let manager = historyManager {
                HistoryView(historyManager: manager, statType: type)
            }
        }
    }
}
