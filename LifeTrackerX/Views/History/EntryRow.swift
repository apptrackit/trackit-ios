import SwiftUI

struct EntryRow: View {
    let entry: StatEntry
    let statType: StatType
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            // Left side - Icon and value
            HStack(spacing: 12) {
                // Different icon based on data source
                if entry.source == .appleHealth {
                    // Apple Health icon
                    Image("applehealthdark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else if entry.source == .automated {
                    // Automated calculations icon
                    Image(systemName: entry.source.iconName)
                        .foregroundColor(.orange)
                } else {
                    // Manual entry icon
                    Image(systemName: entry.source.iconName)
                        .foregroundColor(.blue)
                }
                
                let formattedValue = entry.value.truncatingRemainder(dividingBy: 1) == 0 ?
                    String(format: "%.0f", entry.value) :
                    String(format: "%.1f", entry.value)
                    .replacingOccurrences(of: ".", with: ",")
                
                Text(formattedValue)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Right side - Date
            Text(formatDate(entry.date))
                .foregroundColor(.gray)
                .font(.subheadline)
            
            // Chevron button for editable entries only
            if entry.source != .automated {
                Button(action: onEdit) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' H:mm"
        return formatter.string(from: date)
    }
}
