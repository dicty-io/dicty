import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @Binding var userEmail: String?
    @Binding var isPro: Bool
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Glassmorphism background
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            Color(colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.05))
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 18) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .foregroundColor(.sageGreen)
                    
                    Text(isRegistering ? "Create Dicty Account" : "Sign In to Dicty")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Sign in to sync your workspace and access Dicty Cloud.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 6)

                // Segmented Toggle
                Picker("", selection: $isRegistering) {
                    Text("Sign In").tag(false)
                    Text("Create Account").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 20)

                // Input Fields
                VStack(spacing: 12) {
                    TextField("Email Address", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal, 20)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                if let success = successMessage {
                    VStack(spacing: 4) {
                        Text(success)
                            .font(.caption)
                            .foregroundColor(.sageGreen)
                            .multilineTextAlignment(.center)
                        
                        if isLoading {
                            Button(action: {
                                EngineClient.shared.stopOAuthLoopbackPolling()
                                isLoading = false
                                successMessage = nil
                                errorMessage = nil
                            }) {
                                Text("Cancel")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .underline()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Primary Action Button
                Button(action: performAuth) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        }
                        Text(isRegistering ? "Register Account" : "Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.sageGreen)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .padding(.horizontal, 20)

                // Divider
                HStack {
                    VStack { Divider() }
                    Text("OR")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    VStack { Divider() }
                }
                .padding(.horizontal, 20)

                // Real Google Button
                Button(action: performRealGoogleLogin) {
                    HStack {
                        Image(systemName: "g.circle.fill")
                            .font(.title3)
                        Text("Sign in with Google")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.08))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoading)
                .padding(.horizontal, 20)
                
                #if DEBUG
                Button(action: {
                    if let token = NSPasteboard.general.string(forType: .string) {
                        let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                        if cleanedToken.count > 20 { // Basic check for a JWT token
                            let engine = EngineClient.shared
                            engine.handleOAuthToken(cleanedToken)
                        }
                    }
                }) {
                    Text("Dev Mode: Paste Google Token")
                        .font(.caption)
                        .foregroundColor(.sageGreen)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 2)
                #endif

                Spacer()

                // Footer
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                    Text("Offline Mode Support: Account status is cached securely on this device.")
                        .font(.footnote)
                }
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
            }
            .padding(20)

            // Close (X) button
            Button(action: {
                self.presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.secondary.opacity(0.8))
                    .padding(14)
            }
            .buttonStyle(PlainButtonStyle())
            .keyboardShortcut(.cancelAction)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 380, height: 490)
        .onExitCommand {
            self.presentationMode.wrappedValue.dismiss()
        }
        .onChange(of: isLoggedIn) { _, newValue in
            if newValue {
                EngineClient.shared.stopOAuthLoopbackPolling()
                if successMessage == nil {
                    successMessage = "Google Sign-In Successful!"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .onDisappear {
            EngineClient.shared.stopOAuthLoopbackPolling()
        }
    }

    private func performAuth() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        let endpoint = isRegistering ? "/auth/register" : "/auth/login"
        let url = EngineEndpoint.shared.url(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                    errorMessage = "No response from server."
                    return
                }

                if httpResponse.statusCode == 200 {
                    if let res = try? JSONDecoder().decode(AuthResponsePayload.self, from: data) {
                        // 1. Save JWT token in SecretsManager
                        SecretsManager.saveSecret(res.token, forKey: "dicty_jwt_token")
                        
                        // 2. Cache credentials in UserDefaults for offline resiliency
                        let defaults = UserDefaults.standard
                        defaults.set(true, forKey: "cachedIsLoggedIn")
                        defaults.set(res.email, forKey: "cachedUserEmail")
                        defaults.set(res.is_pro, forKey: "cachedIsPro")
                        if let expires = res.planExpiresAt {
                            defaults.set(expires, forKey: "cachedPlanExpiresAt")
                        }
                        
                        // 3. Update view bindings
                        self.isLoggedIn = true
                        self.userEmail = res.email
                        self.isPro = res.is_pro
                        
                        // 4. Update EngineClient shared instance
                        let engine = EngineClient.shared
                        engine.isLoggedIn = true
                        engine.userEmail = res.email
                        engine.isPro = res.is_pro
                        engine.computeBalance = res.compute_balance ?? 0
                        engine.subscriptionTier = res.subscription_tier ?? "free"
                        engine.planExpiresAt = res.planExpiresAt
                        engine.offlineMode = false
                        
                        // 5. Automatically enable Dicty Cloud if Pro and no custom API key
                        if res.is_pro && !engine.hasCustomAPIKey {
                            defaults.set("dicty_cloud", forKey: "llmProvider")
                        }
                        
                        // 6. Notify local backend engine of token
                        let localTokenUrl = EngineEndpoint.shared.url("/auth/token")
                        var tReq = URLRequest(url: localTokenUrl)
                        tReq.httpMethod = "POST"
                        tReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        let tBody = ["token": res.token]
                        tReq.httpBody = try? JSONSerialization.data(withJSONObject: tBody)
                        EngineEndpoint.shared.session.dataTask(with: tReq).resume()
                        
                        TelemetryClient.shared.track("user_authenticated", properties: [
                            "is_pro": res.is_pro
                        ])
                        
                        self.successMessage = "Successfully authenticated!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.presentationMode.wrappedValue.dismiss()
                        }
                    } else {
                        errorMessage = "Failed to parse response."
                    }
                } else {
                    if let errPayload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
                        errorMessage = errPayload.detail
                    } else {
                        errorMessage = "Error (Status \(httpResponse.statusCode))"
                    }
                }
            }
        }.resume()
    }

    private func performRealGoogleLogin() {
        isLoading = true
        errorMessage = nil
        successMessage = "Waiting for browser authentication..."
        
        EngineClient.shared.startOAuthLoopbackPolling()
        
        guard let url = URL(string: "\(CloudConfig.baseURL)/auth/google?source=mac") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct AuthResponsePayload: Codable {
    let token: String
    let email: String
    let is_pro: Bool
    let compute_balance: Int?
    let subscription_tier: String?
    let planExpiresAt: String?
}

struct ErrorPayload: Codable {
    let detail: String
}

struct AccountSettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var showingLoginModal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dicty Account & Subscription")
                .font(.title2)
                .fontWeight(.bold)

            if engineClient.isLoggedIn, let email = engineClient.userEmail {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Signed in as")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(email)
                                    .font(.headline)
                            }
                            Spacer()
                            if engineClient.isPro {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                    Text(engineClient.subscriptionTier == "early_supporter" ? "LIFETIME PRO" : "PRO")
                                        .fontWeight(.bold)
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.sageGreen.opacity(0.15))
                                .foregroundColor(.sageGreen)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.sageGreen.opacity(0.3), lineWidth: 1)
                                )
                            } else {
                                Text(engineClient.subscriptionTier.uppercased())
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.15))
                                    .foregroundColor(.secondary)
                                    .cornerRadius(12)
                            }
                        }

                        if engineClient.isPro {
                            Divider()
                            
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("RENEWAL / EXPIRATION")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    
                                    if engineClient.subscriptionTier == "early_supporter" {
                                        Text("Lifetime Access • Never expires")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.sageGreen)
                                    } else if let expires = engineClient.planExpiresAt, !expires.isEmpty {
                                        Text(formattedExpirationDate(expires))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text("Active Subscription")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                    }
                                }
                                Spacer()
                                Button(action: {
                                    engineClient.fetchAuthStatus(force: true)
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Refresh status")
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                    // Credit Balance & Limits Explanation
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Compute Balance")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Text("\(engineClient.computeBalance) Credits")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.sageGreen)
                            }
                            Spacer()
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.sageGreen.opacity(0.5))
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How Dicty Cloud works:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Label("$1 equals 1,000 compute credits.", systemImage: "dollarsign.circle")
                            Label("Credits are dynamically deducted in real-time based on your transcription length or text AI usage.", systemImage: "chart.line.down.circle")
                            Label("Example: 1 minute of dictation uses approximately 12 credits.", systemImage: "mic.circle")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.sageGreen)
                        Text("All features unlocked: 100% Free & Open Source")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            engineClient.fetchAuthStatus(force: true)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Refresh")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.sageGreen.opacity(0.15))
                            .foregroundColor(.sageGreen)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(16)
                    .background(Color.sageGreen.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sageGreen.opacity(0.15), lineWidth: 1)
                    )

                    if engineClient.offlineMode {
                        HStack {
                            Image(systemName: "wifi.slash")
                            Text("Offline Mode Active — Credentials cached locally from OS Keyring.")
                                .font(.footnote)
                        }
                        .foregroundColor(.secondary)
                    }

                    Button(action: {
                        engineClient.logoutAccount()
                    }) {
                        Text("Log Out")
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("You are not currently signed in.")
                        .font(.headline)
                    Text("Sign in or register a Dicty account for Dicty Cloud, custom AI routing, and workspace sync.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        showingLoginModal = true
                    }) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                            Text("Sign In / Register Account")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.sageGreen)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .sheet(isPresented: $showingLoginModal) {
                        LoginView(isLoggedIn: $engineClient.isLoggedIn, userEmail: $engineClient.userEmail, isPro: $engineClient.isPro)
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            if engineClient.isLoggedIn {
                engineClient.fetchAuthStatus(force: true)
            }
        }
    }

    private func formattedExpirationDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFormatter.date(from: dateString)
        
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: dateString)
        }
        
        if date == nil {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = df.date(from: dateString)
        }
        
        if date == nil {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            date = df.date(from: dateString)
        }
        
        if let validDate = date {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .none
            let formatted = displayFormatter.string(from: validDate)
            return validDate > Date() ? "Renews on \(formatted)" : "Expired on \(formatted)"
        }
        
        return dateString
    }
}
