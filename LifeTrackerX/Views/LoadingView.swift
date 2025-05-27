import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "figure.run")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                
                Text("TrackIt")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
    }
}

#Preview {
    LoadingView()
} 