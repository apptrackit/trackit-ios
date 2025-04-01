import SwiftUI

struct AddEntryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @State private var value: String = ""
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Text("Add \(statType.title) Entry")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                    
                    VStack(alignment: .leading) {
                        Text("\(statType.title) (\(statType.unit))")
                            .foregroundColor(.white)
                        TextField("Value in \(statType.unit)", text: $value)
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
                        DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
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
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Invalid Date"), message: Text("You cannot add entries for future dates."), dismissButton: .default(Text("OK")))
        }
    }
    
    private func saveEntry() {
        guard let valueDouble = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
        if date <= Date() {
            let entry = StatEntry(date: date, value: valueDouble, type: statType)
            historyManager.addEntry(entry)
            dismiss()
        } else {
            showAlert = true
        }
    }
}
