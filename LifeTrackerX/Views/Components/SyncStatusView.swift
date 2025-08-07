import SwiftUI

struct SyncStatusView: View {
    @StateObject private var syncCoordinator = SyncCoordinator.shared
    
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
            let summary = syncCoordinator.getDataSummary()
            let totalPending = summary.pendingHealthKitSync + summary.pendingBackendSync
            if totalPending > 0 {
                Text("(\(totalPending))")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
            }
            
            // Sync indicator
            if syncCoordinator.overallStatus == .syncing {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private var networkStatusColor: Color {
        switch syncCoordinator.overallStatus {
        case .offline:
            return .red
        case .healthKitNotAuthorized, .notAuthenticated:
            return .orange
        case .synced:
            return .green
        default:
            return .blue
        }
    }
    
    private var syncStatusText: String {
        return syncCoordinator.statusDescription
    }
}

#Preview {
    SyncStatusView()
} 