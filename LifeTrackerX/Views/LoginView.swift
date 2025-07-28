import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var isRegisterMode = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case username
        case email
        case password
        case confirmPassword
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
                    
                    // Mode Toggle
                    Picker("Mode", selection: $isRegisterMode) {
                        Text("Login").tag(false)
                        Text("Register").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 30)
                    
                    // Form
                    VStack(spacing: 15) {
                        // Username Field
                        CustomTextField(
                            text: $username,
                            placeholder: "Username",
                            isSecure: false,
                            returnKeyType: .next
                        ) {
                            if isRegisterMode {
                                focusedField = .email
                            } else {
                                focusedField = .password
                            }
                        }
                        .frame(height: 44)
                        
                        // Email Field (only for register)
                        if isRegisterMode {
                            CustomTextField(
                                text: $email,
                                placeholder: "Email",
                                isSecure: false,
                                returnKeyType: .next
                            ) {
                                focusedField = .password
                            }
                            .frame(height: 44)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        }
                        
                        // Password Field
                        HStack {
                            CustomTextField(
                                text: $password,
                                placeholder: "Password",
                                isSecure: !isPasswordVisible,
                                returnKeyType: isRegisterMode ? .next : .done
                            ) {
                                if isRegisterMode {
                                    focusedField = .confirmPassword
                                } else {
                                    focusedField = nil
                                    Task {
                                        await authViewModel.login(username: username, password: password)
                                    }
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
                        
                        // Confirm Password Field (only for register)
                        if isRegisterMode {
                            HStack {
                                CustomTextField(
                                    text: $confirmPassword,
                                    placeholder: "Confirm Password",
                                    isSecure: !isConfirmPasswordVisible,
                                    returnKeyType: .done
                                ) {
                                    focusedField = nil
                                    if validateForm() {
                                        Task {
                                            await authViewModel.register(username: username, email: email, password: password)
                                        }
                                    }
                                }
                                .frame(height: 44)
                                
                                Button(action: {
                                    isConfirmPasswordVisible.toggle()
                                }) {
                                    Image(systemName: isConfirmPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                            }
                        }
                        
                        // Error Message
                        if let errorMessage = authViewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        // Action Button
                        Button(action: {
                            focusedField = nil
                            if isRegisterMode {
                                if validateForm() {
                                    Task {
                                        await authViewModel.register(username: username, email: email, password: password)
                                    }
                                } else {
                                    // Show validation error
                                    authViewModel.errorMessage = "Please fill all fields correctly. Password must be at least 6 characters and passwords must match."
                                }
                            } else {
                                Task {
                                    await authViewModel.login(username: username, password: password)
                                }
                            }
                        }) {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text(isRegisterMode ? "Create Account" : "Login")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isRegisterMode ? Color.green : Color.blue)
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
                hideKeyboard()
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
            .onChange(of: isRegisterMode) { _ in
                // Clear form when switching modes
                username = ""
                email = ""
                password = ""
                confirmPassword = ""
                authViewModel.errorMessage = nil
                hideKeyboard()
            }
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func validateForm() -> Bool {
        guard isRegisterMode else { return true }
        
        // Basic validation
        guard !username.isEmpty else { return false }
        guard !email.isEmpty else { return false }
        guard !password.isEmpty else { return false }
        guard !confirmPassword.isEmpty else { return false }
        guard password == confirmPassword else { return false }
        guard password.count >= 6 else { return false }
        
        // Email validation - more permissive regex
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        guard emailPredicate.evaluate(with: email) else { return false }
        
        return true
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthViewModel())
    }
} 