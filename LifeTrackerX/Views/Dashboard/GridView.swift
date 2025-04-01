import SwiftUI

struct GridView: View {
    let weight: Double?
    let height: Double?
    let bmi: Double?
    let bodyFat: Double?
    @ObservedObject var historyManager: StatsHistoryManager
    
    var body: some View {
        VStack {
            HStack {
                StatCard(title: "Weight",
                         value: weight != nil ? String(format: "%.1f kg", weight!) : "No data",
                         statType: .weight,
                         historyManager: historyManager)
                
                StatCard(title: "Height",
                         value: height != nil ? String(format: "%.0f cm", height!) : "No data",
                         statType: .height,
                         historyManager: historyManager)
            }
            HStack {
                StatCard(title: "BMI",
                         value: bmi != nil ? String(format: "%.1f", bmi!) : "N/A",
                         isEditable: false)
                
                StatCard(title: "Body Fat",
                         value: bodyFat != nil ? String(format: "%.1f %%", bodyFat!) : "No data",
                         statType: .bodyFat,
                         historyManager: historyManager)
            }
        }
    }
}
