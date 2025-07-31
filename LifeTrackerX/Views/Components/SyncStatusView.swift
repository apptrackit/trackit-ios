import SwiftUI

struct SyncStatusView: View {
    @StateObject private var syncManager = MetricSyncManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Network status indicator
            Circle()
                .fill(networkStatusColor)
                .frame(width: 8, height: 8)
            
            // Sync status text
            Text(syncStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Pending operations count
            if syncManager.pendingOperationsCount > 0 {
                Text("(\(syncManager.pendingOperationsCount))")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var networkStatusColor: Color {
        if syncManager.isOnline {
            return .green
        } else {
            return .red
        }
    }
    
    private var syncStatusText: String {
        if !syncManager.isOnline {
            return "Offline"
        }
        
        switch syncManager.syncStatus {
        case .pending:
            return "Pending"
        case .inProgress:
            return "Syncing..."
        case .completed:
            return "Synced"
        case .failed:
            return "Sync Failed"
        }
    }
}

#Preview {
    SyncStatusView()
} 