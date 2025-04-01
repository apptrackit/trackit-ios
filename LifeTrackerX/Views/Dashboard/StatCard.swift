import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    var statType: StatType?
    var isEditable: Bool = true
    var historyManager: StatsHistoryManager?
    
    @State private var showingHistoryView = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                
                if value == "No data" || value == "N/A" {
                    Text(value)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        let components = value.components(separatedBy: " ")
                        let numberPart = components[0]
                        
                        if let number = Double(numberPart) {
                            Text(String(format: number.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", number))
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text(numberPart)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        if components.count > 1 && title != "BMI" {
                            Text(components[1])
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.leading, 20)
            
            Spacer()
        }
        .frame(width: 159, height: 100, alignment: .leading)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(25)
        .padding(5)
        .onTapGesture {
            if isEditable && statType != nil {
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
