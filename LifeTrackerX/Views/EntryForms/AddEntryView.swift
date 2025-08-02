import SwiftUI

struct AddEntryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @State private var value: String = ""
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    @FocusState private var isValueFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(statType.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveEntry()
                        }
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    }
                    .padding()
                    
                    // Metric Type Icon
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: statType.iconName)
                                    .font(.system(size: 32))
                                    .foregroundColor(.purple)
                            )
                        
                        Text(statType.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 40)
                    
                    // Form Fields
                    VStack(spacing: 0) {
                        // Date Field
                        HStack {
                            Text("Date")
                                .foregroundColor(.white)
                            Spacer()
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onTapGesture {
                            // This will show the date picker
                        }
                        .overlay(
                            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .opacity(0.1)
                        )
                        
                        Spacer().frame(height: 16)
                        
                        // Time Field
                        HStack {
                            Text("Time")
                                .foregroundColor(.white)
                            Spacer()
                            Text(date.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onTapGesture {
                            // This will show the time picker
                        }
                        .overlay(
                            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .opacity(0.1)
                        )
                        
                        Spacer().frame(height: 16)
                        
                        // Value Field
                        HStack {
                            Text(statType.unit)
                                .foregroundColor(.white)
                            Spacer()
                            TextField("", text: $value)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.trailing)
                                .focused($isValueFieldFocused)
                        }
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            // Auto-focus the value field when the view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isValueFieldFocused = true
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
