import SwiftUI

struct EditEntryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var entry: StatEntry
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    
    init(historyManager: StatsHistoryManager, entry: StatEntry) {
        self.historyManager = historyManager
        self._entry = State(initialValue: entry)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Text("Edit \(entry.type.title) Entry")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                    
                    VStack(alignment: .leading) {
                        Text("\(entry.type.title) (\(entry.type.unit))")
                            .foregroundColor(.white)
                        TextField("Value", value: $entry.value, formatter: NumberFormatter())
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
                        DatePicker("", selection: $entry.date, in: ...Date(), displayedComponents: .date)
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
            Alert(title: Text("Invalid Date"), message: Text("You cannot edit entries to future dates."), dismissButton: .default(Text("OK")))
        }
    }
    
    private func saveEntry() {
        if entry.date <= Date() {
            historyManager.updateEntry(entry)
            dismiss()
        } else {
            showAlert = true
        }
    }
}
