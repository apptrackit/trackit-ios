import SwiftUI

struct TrackDataView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var selectedType: StatType = .weight
    @State private var value: String = ""
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Text("Track New Data")
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .padding()
                    
                    Picker("Select Data Type", selection: $selectedType) {
                        ForEach(StatType.allCases.filter { !$0.isCalculated }) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    .colorScheme(.dark)
                    
                    VStack(alignment: .leading) {
                        Text("\(selectedType.title) (\(selectedType.unit))")
                            .foregroundColor(.white)
                        TextField("Value in \(selectedType.unit)", text: $value)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    .padding()
                    
                    VStack(alignment: .leading) {
                        Text("Date")
                            .foregroundColor(.white)
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(WheelDatePickerStyle())
                            .labelsHidden()
                            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                            .cornerRadius(10)
                            .colorScheme(.dark)
                    }
                    .padding()
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .cornerRadius(10)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveEntry()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding()
                    
                    Spacer()
                }
                .padding()
            }
        }
    }
    
    private func saveEntry() {
        guard let valueDouble = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
        let entry = StatEntry(date: date, value: valueDouble, type: selectedType)
        historyManager.addEntry(entry)
        dismiss()
    }
}
