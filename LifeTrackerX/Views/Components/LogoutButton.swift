import SwiftUI

struct LogoutButton: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isShowingConfirmation = false
    
    var body: some View {
        Button(action: {
            isShowingConfirmation = true
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Logout")
            }
            .foregroundColor(.red)
        }
        .alert("Logout", isPresented: $isShowingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Logout", role: .destructive) {
                Task {
                    await authViewModel.logout()
                }
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
    }
} 