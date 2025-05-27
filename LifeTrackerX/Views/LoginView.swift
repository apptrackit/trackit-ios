import SwiftUI
import UIKit

struct CustomTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSecure: Bool
    var returnKeyType: UIReturnKeyType
    var onSubmit: () -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.isSecureTextEntry = isSecure
        textField.returnKeyType = returnKeyType
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.borderStyle = .roundedRect
        textField.clearButtonMode = .whileEditing
        textField.backgroundColor = .systemBackground
        textField.tintColor = .systemBlue
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Only update text if it's different to avoid cursor position reset
        if uiView.text != text {
            uiView.text = text
        }
        // Update secure text entry state
        uiView.isSecureTextEntry = isSecure
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CustomTextField
        
        init(_ parent: CustomTextField) {
            self.parent = parent
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let text = textField.text,
               let textRange = Range(range, in: text) {
                let updatedText = text.replacingCharacters(in: textRange, with: string)
                parent.text = updatedText
            }
            return true
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var focusedField: Field?
    
    enum Field {
        case username
        case password
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer()
                        .frame(height: 50)
                    
                    // Logo or App Name
                    Text("TrackIt")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // Login Form
                    VStack(spacing: 15) {
                        // Username Field
                        CustomTextField(
                            text: $username,
                            placeholder: "Username",
                            isSecure: false,
                            returnKeyType: .next
                        ) {
                            focusedField = .password
                        }
                        .frame(height: 44)
                        
                        // Password Field
                        HStack {
                            CustomTextField(
                                text: $password,
                                placeholder: "Password",
                                isSecure: !isPasswordVisible,
                                returnKeyType: .done
                            ) {
                                focusedField = nil
                                Task {
                                    await authViewModel.login(username: username, password: password)
                                }
                            }
                            .frame(height: 44)
                            
                            Button(action: {
                                isPasswordVisible.toggle()
                            }) {
                                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                        
                        // Error Message
                        if let errorMessage = authViewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        // Login Button
                        Button(action: {
                            focusedField = nil
                            Task {
                                await authViewModel.login(username: username, password: password)
                            }
                        }) {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Login")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .disabled(authViewModel.isLoading)
                    }
                    .padding(.horizontal, 30)
                    
                    Spacer()
                        .frame(height: keyboardHeight > 0 ? keyboardHeight : 50)
                }
                .padding()
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onTapGesture {
                focusedField = nil
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .onAppear {
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                    if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                        keyboardHeight = keyboardFrame.height
                    }
                }
                
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                    keyboardHeight = 0
                }
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthViewModel())
    }
} 