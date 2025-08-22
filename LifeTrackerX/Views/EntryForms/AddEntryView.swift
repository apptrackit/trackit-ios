import SwiftUI

struct AddEntryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @State private var value: String = ""
    @State private var date = Date()
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    @FocusState private var isValueFieldFocused: Bool
    @AppStorage("preferredWeightUnit") private var preferredWeightUnit: String = "kg"
    
    private var canSave: Bool {
        !value.isEmpty && Double(value.replacingOccurrences(of: ",", with: ".")) != nil
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Metric Type Icon
                        VStack(spacing: 16) {
                            Circle()
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: statType.iconName)
                                        .font(.system(size: 32))
                                        .foregroundColor(.purple)
                                )
                            
                            Text(statType.title)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 40)
                        
                        // Form Fields - Unified Box
                        VStack(spacing: 0) {
                            // Date Field
                            HStack {
                                Text("Date")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundColor(showingDatePicker ? .blue : .primary)
                            }
                            .padding()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isValueFieldFocused = false
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showingDatePicker.toggle()
                                    if showingDatePicker {
                                        showingTimePicker = false
                                    }
                                }
                            }
                            
                            // Inline Date Picker
                            if showingDatePicker {
                                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .padding()
                                    .transition(.opacity)
                            }
                            
                            // Separator Line
                            if !showingDatePicker {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                            
                            // Time Field
                            HStack {
                                Text("Time")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(date.formatted(date: .omitted, time: .shortened))
                                    .foregroundColor(showingTimePicker ? .blue : .primary)
                            }
                            .padding()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isValueFieldFocused = false
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showingTimePicker.toggle()
                                    if showingTimePicker {
                                        showingDatePicker = false
                                    }
                                }
                            }
                            
                            // Inline Time Picker
                            if showingTimePicker {
                                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .padding()
                                    .transition(.opacity)
                            }
                            
                            // Separator Line
                            if !showingTimePicker {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                            
                            // Value Field
                            HStack {
                                Text(statType == .weight ? (preferredWeightUnit == "lb" ? "lb" : "kg") : statType.unit)
                                    .foregroundColor(.primary)
                                Spacer()
                                TextField("", text: $value)
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.trailing)
                                    .focused($isValueFieldFocused)
                            }
                            .padding()
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal)
                        
                        Spacer()
                            .frame(height: 50)
                    }
                }
            }
            .navigationBarTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        saveEntry()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(canSave ? .primary : .gray)
                            .frame(width: 32, height: 32)
                            .background(canSave ? .blue : .gray.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .disabled(!canSave)
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
    }
    
    private func saveEntry() {
        guard let valueDouble = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
        if date <= Date() {
            // Convert to kg for storage if needed
            let storedValue = (statType == .weight && preferredWeightUnit == "lb") ? (valueDouble / 2.20462262) : valueDouble
            let entry = StatEntry(date: date, value: storedValue, type: statType)
            historyManager.addEntry(entry)
            dismiss()
        } else {
            showAlert = true
        }
    }
} 