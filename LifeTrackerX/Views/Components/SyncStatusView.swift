import SwiftUI

struct SyncStatusView: View {
    @StateObject private var syncManager = MetricSyncManager.shared
    @State private var showDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main status bar
            HStack(spacing: 8) {
                // Network status indicator
                Circle()
                    .fill(networkStatusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(networkStatusColor.opacity(0.3), lineWidth: 8)
                            .scaleEffect(syncManager.syncStatus.isSyncing ? 1.5 : 1)
                            .opacity(syncManager.syncStatus.isSyncing ? 0 : 1)
                            .animation(
                                syncManager.syncStatus.isSyncing ?
                                Animation.easeOut(duration: 1).repeatForever(autoreverses: false) : .default,
                                value: syncManager.syncStatus.isSyncing
                            )
                    )
                
                // Sync status text
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncStatusText)
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    if let lastSync = syncManager.lastSyncTimestamp {
                        Text("Last: \(lastSync, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Pending operations count
                if syncManager.pendingOperationsCount > 0 {
                    Label("\(syncManager.pendingOperationsCount)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .labelStyle(.titleAndIcon)
                }
                
                // Manual sync button
                Button(action: {
                    syncManager.forceSync()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(syncManager.syncStatus.isSyncing ? .secondary : .accentColor)
                        .rotationEffect(.degrees(syncManager.syncStatus.isSyncing ? 360 : 0))
                        .animation(
                            syncManager.syncStatus.isSyncing ?
                            Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default,
                            value: syncManager.syncStatus.isSyncing
                        )
                }
                .disabled(syncManager.syncStatus.isSyncing)
                
                // Expand/collapse button
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        showDetails.toggle()
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Progress bar (shown during sync)
            if syncManager.syncStatus.isSyncing && syncManager.syncProgress > 0 {
                ProgressView(value: syncManager.syncProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Detailed status (expandable)
            if showDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    // Network status
                    HStack {
                        Label(syncManager.isOnline ? "Online" : "Offline", 
                              systemImage: syncManager.isOnline ? "wifi" : "wifi.slash")
                            .font(.caption)
                            .foregroundColor(syncManager.isOnline ? .green : .red)
                        
                        Spacer()
                    }
                    
                    // Sync status details
                    if case .failed(let error) = syncManager.syncStatus {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                    
                    // Pending operations
                    if syncManager.pendingOperationsCount > 0 {
                        Label("\(syncManager.pendingOperationsCount) pending operations", 
                              systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    // Last sync timestamp
                    if let lastSync = syncManager.lastSyncTimestamp {
                        Label("Last sync: \(lastSync, formatter: dateFormatter)", 
                              systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Label("Never synced", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var networkStatusColor: Color {
        if !syncManager.isOnline {
            return .red
        }
        
        switch syncManager.syncStatus {
        case .idle:
            return .gray
        case .syncing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .orange
        }
    }
    
    private var syncStatusText: String {
        if !syncManager.isOnline {
            return "Offline"
        }
        
        switch syncManager.syncStatus {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .completed:
            return "Synced"
        case .failed:
            return "Sync Failed"
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// Compact version for toolbar
struct CompactSyncStatusView: View {
    @StateObject private var syncManager = MetricSyncManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            // Sync icon if syncing
            if syncManager.syncStatus.isSyncing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(360))
                    .animation(
                        Animation.linear(duration: 1).repeatForever(autoreverses: false),
                        value: syncManager.syncStatus.isSyncing
                    )
            }
            
            // Pending count
            if syncManager.pendingOperationsCount > 0 {
                Text("\(syncManager.pendingOperationsCount)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        if !syncManager.isOnline {
            return .red
        }
        
        switch syncManager.syncStatus {
        case .idle:
            return .gray
        case .syncing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .orange
        }
    }
}

#Preview("Full View") {
    VStack {
        SyncStatusView()
            .padding()
        
        Spacer()
    }
}

#Preview("Compact View") {
    CompactSyncStatusView()
        .padding()
} 