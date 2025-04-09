import SwiftUI

struct PhotoHistoryView: View {
    let category: PhotoCategory
    @ObservedObject var photoManager: ProgressPhotoManager
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var selectedPhoto: ProgressPhoto?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack {
                Text("Photo History")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 5) {
                    Image(systemName: "photo.stack.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("\(photoManager.getPhotos(for: category).count) photos")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            
            let groupedPhotos = photoManager.getPhotosByDate(category: category)
            
            if groupedPhotos.isEmpty {
                EmptyStateView(category: category)
            } else {
                // Group by date
                ForEach(groupedPhotos.keys.sorted(by: >), id: \.self) { date in
                    if let photos = groupedPhotos[date] {
                        DateGroupHeader(date: date)
                            .padding(.horizontal)
                        
                        // Photos grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(photos) { photo in
                                PhotoThumbnail(photo: photo) {
                                    selectedPhoto = photo
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(
                photo: photo,
                photoManager: photoManager,
                historyManager: historyManager
            )
        }
    }
}

struct DateGroupHeader: View {
    let date: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDate(date))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Divider()
                .background(Color.gray.opacity(0.5))
        }
        .padding(.top, 16)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct PhotoThumbnail: View {
    let photo: ProgressPhoto
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let uiImage = photo.image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipped()
                        .cornerRadius(12)
                }
                
                // Metadata overlay
                HStack {
                    if let weight = photo.associatedMeasurements?.first(where: { $0.type == .weight })?.value {
                        Text("\(String(format: "%.1f", weight)) kg")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                }
                .padding(8)
            }
            .frame(height: 150)
        }
    }
}

struct PhotoDetailView: View {
    let photo: ProgressPhoto
    @ObservedObject var photoManager: ProgressPhotoManager
    @ObservedObject var historyManager: StatsHistoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Photo
                        if let image = photo.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 500)
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                        
                        // Date and category
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatDate(photo.date))
                                    .font(.title3)
                                    .foregroundColor(.white)
                                
                                HStack {
                                    Image(systemName: photo.category.iconName)
                                        .foregroundColor(.blue)
                                    
                                    Text(photo.category.name)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        // Measurements
                        MeasurementDetailView(
                            photo: photo,
                            historyManager: historyManager
                        )
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showEditSheet = true }) {
                            Label("Edit Photo", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive, action: { showDeleteAlert = true }) {
                            Label("Delete Photo", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPhotoView(
                    photo: photo,
                    photoManager: photoManager,
                    historyManager: historyManager,
                    onSave: { dismiss() }
                )
            }
            .alert("Delete Photo", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    photoManager.deletePhoto(id: photo.id)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this photo? This action cannot be undone.")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
} 