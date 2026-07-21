import SwiftUI

struct KeychainView: View {
    @EnvironmentObject var service: NotaryService
    @State private var profiles: [NotaryProfile] = []
    @State private var mode: Int = 0 // 0: Register New, 1: Link Existing
    
    // Form fields
    @State private var profileName: String = ""
    @State private var appleId: String = ""
    @State private var teamId: String = ""
    @State private var appPassword: String = ""
    
    @State private var isStoring: Bool = false
    @State private var statusMessage: String = ""
    @State private var isSuccessStatus: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notary Keychain Profiles")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Manage Apple Developer credentials securely stored in your macOS Keychain.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "key.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            
            Divider()
            
            HSplitView {
                // Left Panel: Form to Register Profile
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Picker("", selection: $mode) {
                            Text("Register New").tag(0)
                            Text("Link Existing").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 4)
                        
                        if mode == 0 {
                            // MODE 0: REGISTER NEW
                            Text("Register New Profile")
                                .font(.headline)
                                .padding(.bottom, 2)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Profile Name")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                TextField("e.g. MyCompanyNotaryProfile", text: $profileName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Apple ID (Email)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                TextField("e.g. developer@company.com", text: $appleId)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Apple Developer Team ID")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                TextField("e.g. A1B2C3D4E5", text: $teamId)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("App-Specific Password")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                SecureField("xxxx-xxxx-xxxx-xxxx", text: $appPassword)
                                    .textFieldStyle(.roundedBorder)
                                Text("Generate at [appleid.apple.com](https://appleid.apple.com)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            // MODE 1: LINK EXISTING
                            Text("Link Existing Profile")
                                .font(.headline)
                                .padding(.bottom, 2)
                            
                            Text("If you already ran 'notarytool store-credentials' in the terminal, simply enter the profile name here to link it to the app.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Profile Name")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                TextField("e.g. DKST-notary", text: $profileName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        if !statusMessage.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: isSuccessStatus ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(isSuccessStatus ? .green : .red)
                                Text(statusMessage)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSuccessStatus ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                        
                        if mode == 0 {
                            Button(action: {
                                Task {
                                    await registerProfile()
                                }
                            }) {
                                HStack {
                                    Spacer()
                                    if isStoring {
                                        ProgressView()
                                            .controlSize(.small)
                                            .padding(.trailing, 4)
                                    }
                                    Image(systemName: "plus.circle.fill")
                                    Text("Register to System Keychain")
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isStoring || profileName.isEmpty || appleId.isEmpty || teamId.isEmpty || appPassword.isEmpty)
                        } else {
                            Button(action: linkExistingProfile) {
                                HStack {
                                    Spacer()
                                    Image(systemName: "link.badge.plus")
                                    Text("Link Profile to App")
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(profileName.isEmpty)
                        }
                        
                        Spacer()
                    }
                    .padding(24)
                }
                .frame(width: AppLayout.workPanelWidth)
                
                // Right Panel: Stored Profiles List
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved Profiles (\(profiles.count))")
                        .font(.headline)
                        .padding(24)
                    
                    if profiles.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "key.slash.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            Text("No profiles stored yet")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text("Add your Apple developer credentials on the left to get started.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                    } else {
                        List {
                            ForEach(profiles) { profile in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name)
                                            .font(.headline)
                                        HStack(spacing: 12) {
                                            Label(profile.appleId, systemImage: "envelope")
                                            Label("Team: \(profile.teamId)", systemImage: "person.2")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 12) {
                                        Button("Verify") {
                                            Task {
                                                await testProfileConnection(profile: profile)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button(action: {
                                            deleteProfile(profile)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadProfiles)
    }
    
    private func loadProfiles() {
        service.refreshKeychainProfiles()
        
        var loadedLocal: [NotaryProfile] = []
        if let data = UserDefaults.standard.data(forKey: "notary_profiles"),
           let decoded = try? JSONDecoder().decode([NotaryProfile].self, from: data) {
            loadedLocal = decoded
        }
        
        // Merge auto-detected keychain profiles
        for name in service.keychainProfiles {
            if !loadedLocal.contains(where: { $0.name == name }) {
                let detectedProfile = NotaryProfile(name: name, appleId: "System Keychain Entry", teamId: "Auto-detected")
                loadedLocal.append(detectedProfile)
            }
        }
        
        self.profiles = loadedLocal
    }
    
    private func registerProfile() async {
        isStoring = true
        statusMessage = "Registering with notarytool..."
        isSuccessStatus = true
        
        let args = [
            "notarytool", "store-credentials", profileName,
            "--apple-id", appleId,
            "--team-id", teamId,
            "--password", appPassword
        ]
        
        do {
            let status = try await ShellManager.shared.runStream(
                executable: "/usr/bin/xcrun",
                arguments: args
            ) { line in
                print("notarytool keychain log: \(line)")
            }
            
            if status == 0 {
                // Success - Save to app profiles in UserDefaults
                let newProfile = NotaryProfile(name: profileName, appleId: appleId, teamId: teamId)
                
                var currentLocal: [NotaryProfile] = []
                if let data = UserDefaults.standard.data(forKey: "notary_profiles"),
                   let decoded = try? JSONDecoder().decode([NotaryProfile].self, from: data) {
                    currentLocal = decoded
                }
                
                if !currentLocal.contains(where: { $0.name == profileName }) {
                    currentLocal.append(newProfile)
                    if let encoded = try? JSONEncoder().encode(currentLocal) {
                        UserDefaults.standard.set(encoded, forKey: "notary_profiles")
                    }
                }
                
                statusMessage = "Successfully registered '\(profileName)' to keychain!"
                isSuccessStatus = true
                
                // Clear form fields
                profileName = ""
                appleId = ""
                teamId = ""
                appPassword = ""
                
                // Reload & Sync
                loadProfiles()
            } else {
                statusMessage = "Failed to store credentials (exit code \(status))."
                isSuccessStatus = false
            }
        } catch {
            statusMessage = "Shell Execution Error: \(error.localizedDescription)"
            isSuccessStatus = false
        }
        isStoring = false
    }
    
    private func testProfileConnection(profile: NotaryProfile) async {
        statusMessage = "Verifying profile '\(profile.name)' connection..."
        isSuccessStatus = true
        
        let args = ["notarytool", "history", "--keychain-profile", profile.name, "--count", "1"]
        
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/bin/xcrun", arguments: args)
            if status == 0 {
                statusMessage = "Profile '\(profile.name)' is valid and online! Connected to Apple services."
                isSuccessStatus = true
            } else {
                statusMessage = "Profile validation failed. Details: \n\(output)"
                isSuccessStatus = false
            }
        } catch {
            statusMessage = "Verification Error: \(error.localizedDescription)"
            isSuccessStatus = false
        }
    }
    
    private func deleteProfile(_ profile: NotaryProfile) {
        // Remove from local profiles
        var currentLocal: [NotaryProfile] = []
        if let data = UserDefaults.standard.data(forKey: "notary_profiles"),
           let decoded = try? JSONDecoder().decode([NotaryProfile].self, from: data) {
            currentLocal = decoded
        }
        currentLocal.removeAll { $0.name == profile.name }
        if let encoded = try? JSONEncoder().encode(currentLocal) {
            UserDefaults.standard.set(encoded, forKey: "notary_profiles")
        }
        
        // Re-load to update list
        loadProfiles()
        
        statusMessage = "Profile '\(profile.name)' removed from local list. Keychain record remains intact."
        isSuccessStatus = true
    }
    
    private func linkExistingProfile() {
        guard !profileName.isEmpty else { return }
        
        let newProfile = NotaryProfile(name: profileName, appleId: "Linked Profile", teamId: "Keychain")
        
        var currentLocal: [NotaryProfile] = []
        if let data = UserDefaults.standard.data(forKey: "notary_profiles"),
           let decoded = try? JSONDecoder().decode([NotaryProfile].self, from: data) {
            currentLocal = decoded
        }
        
        if !currentLocal.contains(where: { $0.name == profileName }) {
            currentLocal.append(newProfile)
            if let encoded = try? JSONEncoder().encode(currentLocal) {
                UserDefaults.standard.set(encoded, forKey: "notary_profiles")
            }
            statusMessage = "Profile '\(profileName)' linked successfully!"
            isSuccessStatus = true
            
            // Clear field
            profileName = ""
            
            // Reload & Sync
            loadProfiles()
        } else {
            statusMessage = "Profile '\(profileName)' is already in the list."
            isSuccessStatus = false
        }
    }
}
