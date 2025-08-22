import SwiftUI

struct GridView: View {
    let weight: Double?
    let height: Double?
    let bmi: Double?
    let bodyFat: Double?
    @ObservedObject var historyManager: StatsHistoryManager
    @AppStorage("preferredWeightUnit") private var preferredWeightUnit: String = "kg"
    
    private var formattedBMI: String {
        if let bmi = bmi {
            let value = String(format: "%.1f", bmi)
            print("📊 Formatting BMI value: \(bmi) -> '\(value)'")
            return value
        }
        print("📊 No current BMI value available")
        return "N/A"
    }
    
    var body: some View {
        VStack {
            HStack {
                StatCard(title: "Weight",
                         value: weight != nil ? formattedWeight(weight!) : "No data",
                         statType: .weight,
                         historyManager: historyManager)
                
                StatCard(title: "Height",
                         value: height != nil ? String(format: "%.0f cm", height!) : "No data",
                         statType: .height,
                         historyManager: historyManager)
            }
            HStack {
                StatCard(title: "BMI",
                         value: formattedBMI,
                         statType: .bmi,
                         isEditable: false,
                         historyManager: historyManager)
                    .onAppear {
                        print("📊 Passing BMI value to StatCard: '\(formattedBMI)'")
                    }
                
                StatCard(title: "Body Fat",
                         value: bodyFat != nil ? (bodyFat!.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f %%", bodyFat!) : String(format: "%.1f %%", bodyFat!)) : "No data",
                         statType: .bodyFat,
                         historyManager: historyManager)
            }
        }
        .onAppear {
            // Debug BMI data
            let entries = historyManager.getEntries(for: .bmi)
            print("📊 All BMI entries:")
            for entry in entries.prefix(5) {
                print("📊 BMI: \(entry.value) on \(entry.date)")
            }
        }
    }
}

private extension GridView {
    func formattedWeight(_ kg: Double) -> String {
        let value = preferredWeightUnit == "lb" ? kg * 2.20462262 : kg
        let number = value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(number) \(preferredWeightUnit == "lb" ? "lb" : "kg")"
    }
}
