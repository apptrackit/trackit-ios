import SwiftUI

struct EditEntryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var entry: StatEntry
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @FocusState private var isValueFieldFocused: Bool
    
    init(historyManager: StatsHistoryManager, entry: StatEntry) {
        self.historyManager = historyManager
        self._entry = State(initialValue: entry)
    }
    
    private var canSave: Bool {
        entry.value > 0
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Metric Type Icon
                        VStack(spacing: 16) {
                            Circle()
                                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: entry.type.iconName)
                                        .font(.system(size: 32))
                                        .foregroundColor(.purple)
                                )
                            
                            Text(entry.type.title)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 40)
                        
                        // Form Fields - Unified Box
                        VStack(spacing: 0) {
                            // Date Field
                            HStack {
                                Text("Date")
                                    .foregroundColor(.white)
                                Spacer()
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundColor(showingDatePicker ? .blue : .white)
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
                                DatePicker("", selection: $entry.date, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .colorScheme(.dark)
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
                                    .foregroundColor(.white)
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .foregroundColor(showingTimePicker ? .blue : .white)
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
                                DatePicker("", selection: $entry.date, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .colorScheme(.dark)
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
                                Text(entry.type.unit)
                                    .foregroundColor(.white)
                                Spacer()
                                TextField("", value: $entry.value, formatter: NumberFormatter())
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                                    .focused($isValueFieldFocused)
                            }
                            .padding()
                        }
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
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
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        saveEntry()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(canSave ? .white : .gray)
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
                Alert(title: Text("Invalid Date"), message: Text("You cannot edit entries to future dates."), dismissButton: .default(Text("OK")))
            }
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
