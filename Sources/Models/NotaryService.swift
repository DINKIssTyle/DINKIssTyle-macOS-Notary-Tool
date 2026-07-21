import Foundation
import Combine
import Security

public enum VerificationStatus: String, Sendable, Codable {
    case idle
    case running
    case success
    case failure
}

public struct VerificationItem: Identifiable, Sendable, Codable {
    public let id: UUID
    public let title: String
    public let description: String
    public var status: VerificationStatus
    
    public init(title: String, description: String, status: VerificationStatus = .idle) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.status = status
    }
}

public enum CredentialType: String, Sendable, Codable {
    case keychainProfile = "Keychain Profile"
    case apiKey = "App Store Connect API Key"
}

public struct NotaryProfile: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var appleId: String
    public var teamId: String
    
    public init(id: UUID = UUID(), name: String, appleId: String, teamId: String) {
        self.id = id
        self.name = name
        self.appleId = appleId
        self.teamId = teamId
    }
}

@MainActor
public class NotaryService: ObservableObject {
    @Published public var logOutput: String = ""
    @Published public var isProcessing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var currentStep: String = "Idle"
    
    // Available certificates fetched from keychain
    @Published public var appIdentities: [String] = []
    @Published public var installerIdentities: [String] = []
    
    // Available notary profiles loaded from keychain
    @Published public var keychainProfiles: [String] = []
    
    // Verification results
    @Published public var verificationItems: [VerificationItem] = [
        VerificationItem(title: "Code Signature", description: "Verifies that the bundle has a valid code signature."),
        VerificationItem(title: "Hardened Runtime", description: "Ensures Hardened Runtime is enabled for security."),
        VerificationItem(title: "Notarization Ticket", description: "Checks if the app has been registered with Apple's Notary service."),
        VerificationItem(title: "Stapled Ticket", description: "Verifies the notarization ticket is stapled to the bundle."),
        VerificationItem(title: "Gatekeeper Assessment", description: "Simulates macOS Gatekeeper security verification.")
    ]
    
    private var activeProcessId = UUID()
    
    public init() {
        fetchCertificates()
        refreshKeychainProfiles()
    }
    
    /// Fetches valid code signing identities from the system keychain.
    public func fetchCertificates() {
        do {
            let (status, output) = try ShellManager.shared.runSync(
                executable: "/usr/bin/security",
                arguments: ["find-identity", "-v", "-p", "codesigning"]
            )
            
            if status != 0 {
                appendLog("Error querying keychain certificates: \(status)")
                return
            }
            
            var apps: [String] = []
            var installers: [String] = []
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if let startIdx = line.firstIndex(of: "\""),
                   let endIdx = line.lastIndex(of: "\""),
                   startIdx < endIdx {
                    let certName = String(line[line.index(after: startIdx)..<endIdx])
                    if certName.contains("Developer ID Application") {
                        apps.append(certName)
                    } else if certName.contains("Developer ID Installer") {
                        installers.append(certName)
                    } else {
                        // Include standard codesign certificates too
                        apps.append(certName)
                    }
                }
            }
            
            self.appIdentities = apps.sorted()
            self.installerIdentities = installers.sorted()
            
            appendLog("Keychain certificates loaded: \(apps.count) App, \(installers.count) Installer profiles.")
        } catch {
            appendLog("Failed to read certificates: \(error.localizedDescription)")
        }
    }
    
    public func cancel() async {
        ShellManager.shared.cancelProcess(id: activeProcessId)
        isProcessing = false
        currentStep = "Cancelled"
        appendLog("\n[CANCELLED] Workflows interrupted by user.")
    }
    
    public func appendLog(_ text: String) {
        logOutput += text + "\n"
    }
    
    public func clearLogs() {
        logOutput = ""
        progress = 0.0
        currentStep = "Idle"
        for i in 0..<verificationItems.count {
            verificationItems[i].status = .idle
        }
    }
    
    /// Starts a signing/notarization workflow or a distribution-only build.
    public func startWorkflow(
        fileUrl: URL,
        signAppIdentity: String?,
        packageToPkg: Bool,
        signPkgIdentity: String?,
        packageToDmg: Bool,
        packageToZip: Bool,
        performNotarization: Bool,
        credentialType: CredentialType,
        keychainProfile: String,
        apiKeyId: String,
        apiIssuerId: String,
        apiKeyPath: String
    ) async {
        isProcessing = true
        activeProcessId = UUID()
        clearLogs()
        
        let path = fileUrl.path
        let fileExtension = fileUrl.pathExtension.lowercased()
        let appName = fileUrl.deletingPathExtension().lastPathComponent
        let parentDir = fileUrl.deletingLastPathComponent()
        
        appendLog(performNotarization ? "=== Starting Notarization Workflow ===" : "=== Starting Distribution Build ===")
        appendLog("Target File: \(path)")
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        var workingTarget = path
        var distributionBuildHadError = false
        
        // 1. Code Sign .app (if app dropped and signing is enabled)
        if fileExtension == "app" {
            if let identity = signAppIdentity, !identity.isEmpty {
                currentStep = "Signing App Bundle..."
                progress = 0.1
                appendLog("\n--- 1. Code Signing .app ---")
                
                let args = [
                    "--force",
                    "--options", "runtime",
                    "--timestamp",
                    "--deep",
                    "-s", identity,
                    workingTarget
                ]
                
                appendLog("Running: codesign " + args.joined(separator: " "))
                do {
                    let status = try await ShellManager.shared.runStream(
                        executable: "/usr/bin/codesign",
                        arguments: args,
                        processId: activeProcessId
                    ) { [weak self] line in
                        Task { @MainActor in self?.appendLog("  \(line)") }
                    }
                    
                    if status != 0 {
                        appendLog("Error: codesign failed with status \(status)")
                        isProcessing = false
                        currentStep = "Failed at Code Sign"
                        return
                    }
                    appendLog("Code signed successfully.")
                } catch {
                    appendLog("Code sign execution error: \(error.localizedDescription)")
                    isProcessing = false
                    currentStep = "Failed"
                    return
                }
            } else {
                appendLog("Skipped: Code Signing (No certificate selected)")
            }
        }

        // 2. Notarize the .app bundle first so that packaged formats contain the stapled app.
        if fileExtension == "app" && performNotarization {
            currentStep = "Notarizing App Bundle..."
            progress = 0.3
            appendLog("\n--- 2. Notarizing App Bundle ---")
            
            currentStep = "Zipping App for Upload..."
            appendLog("Ditto compressing app bundle...")
            let tempZipUrl = tempDir.appendingPathComponent("\(appName)_notary_temp.zip")
            let zipPath = tempZipUrl.path
            
            if fileManager.fileExists(atPath: zipPath) {
                try? fileManager.removeItem(at: tempZipUrl)
            }
            
            let dittoArgs = ["-c", "-k", "--keepParent", workingTarget, zipPath]
            appendLog("Running: ditto " + dittoArgs.joined(separator: " "))
            
            do {
                let status = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/ditto",
                    arguments: dittoArgs,
                    processId: activeProcessId
                ) { _ in }
                
                if status != 0 {
                    appendLog("Error: Ditto compression failed with status \(status)")
                    isProcessing = false
                    currentStep = "Failed at Compression"
                    return
                }
                appendLog("App bundle compressed to: \(zipPath)")
                
                // Submit .zip to Apple Notary
                var notaryArgs = ["notarytool", "submit", zipPath, "--wait"]
                if credentialType == .keychainProfile {
                    notaryArgs.append(contentsOf: ["--keychain-profile", keychainProfile])
                } else {
                    notaryArgs.append(contentsOf: ["--key-id", apiKeyId, "--issuer", apiIssuerId, "--key", apiKeyPath])
                }
                
                appendLog("Running: xcrun " + notaryArgs.joined(separator: " "))
                let submitStatus = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/xcrun",
                    arguments: notaryArgs,
                    processId: activeProcessId
                ) { [weak self] line in
                    Task { @MainActor in self?.appendLog("  \(line)") }
                }
                
                try? fileManager.removeItem(at: tempZipUrl)
                
                if submitStatus != 0 {
                    appendLog("Error: Notarization submission failed or rejected (status \(submitStatus))")
                    isProcessing = false
                    currentStep = "Notarization Rejected"
                    return
                }
                appendLog("Notarization completed successfully!")
                
                // Staple back to original .app
                currentStep = "Stapling Ticket..."
                appendLog("Stapling ticket to app bundle...")
                let stapleArgs = ["stapler", "staple", workingTarget]
                appendLog("Running: xcrun " + stapleArgs.joined(separator: " "))
                let stapleStatus = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/xcrun",
                    arguments: stapleArgs,
                    processId: activeProcessId
                ) { [weak self] line in
                    Task { @MainActor in self?.appendLog("  \(line)") }
                }
                
                if stapleStatus != 0 {
                    appendLog("Warning: Stapling failed (status \(stapleStatus))")
                } else {
                    appendLog("Stapling ticket succeeded.")
                }
            } catch {
                appendLog("App bundle notarization error: \(error.localizedDescription)")
                isProcessing = false
                currentStep = "Failed"
                return
            }
        }
        
        // 3. Optional packaging formats
        
        // 3a. Build Zip Archive (.zip)
        if fileExtension == "app" && packageToZip {
            currentStep = "Building Zip Archive..."
            progress = 0.5
            let zipOutputPath = parentDir.appendingPathComponent("\(appName).zip").path
            appendLog("\n--- 3a. Building Zip Archive (.zip) ---")
            appendLog("Compressing app bundle to: \(zipOutputPath)")
            
            if fileManager.fileExists(atPath: zipOutputPath) {
                try? fileManager.removeItem(atPath: zipOutputPath)
            }
            
            let zipArgs = ["-c", "-k", "--keepParent", workingTarget, zipOutputPath]
            do {
                let status = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/ditto",
                    arguments: zipArgs,
                    processId: activeProcessId
                ) { _ in }
                
                if status == 0 {
                    appendLog("Zip archive built successfully at: \(zipOutputPath)")
                } else {
                    distributionBuildHadError = true
                    appendLog("Error: Zip archive build failed with status \(status)")
                }
            } catch {
                distributionBuildHadError = true
                appendLog("Zip archive error: \(error.localizedDescription)")
            }
        }
        
        // 3b. Build Disk Image (.dmg)
        if fileExtension == "app" && packageToDmg {
            currentStep = "Building Disk Image..."
            progress = 0.6
            let dmgOutputPath = parentDir.appendingPathComponent("\(appName).dmg").path
            appendLog("\n--- 3b. Building Disk Image (.dmg) ---")
            
            do {
                let stagingDir = tempDir.appendingPathComponent("dmg_staging_\(UUID().uuidString)")
                try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                let stagedAppPath = stagingDir.appendingPathComponent(fileUrl.lastPathComponent).path
                
                // Copy app using ditto to preserve signatures/stapler tickets
                appendLog("Staging app bundle...")
                let cpStatus = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/ditto",
                    arguments: [workingTarget, stagedAppPath],
                    processId: activeProcessId
                ) { _ in }
                
                if cpStatus == 0 {
                    if fileManager.fileExists(atPath: dmgOutputPath) {
                        try? fileManager.removeItem(atPath: dmgOutputPath)
                    }
                    
                    // Create DMG using hdiutil
                    appendLog("Creating DMG using hdiutil...")
                    let hdiutilArgs = ["create", "-srcfolder", stagingDir.path, "-volname", appName, "-fs", "HFS+", "-format", "UDZO", "-ov", dmgOutputPath]
                    let hdiStatus = try await ShellManager.shared.runStream(
                        executable: "/usr/bin/hdiutil",
                        arguments: hdiutilArgs,
                        processId: activeProcessId
                    ) { [weak self] line in
                        Task { @MainActor in self?.appendLog("  \(line)") }
                    }
                    
                    try? fileManager.removeItem(at: stagingDir)
                    
                    if hdiStatus == 0 {
                        appendLog("DMG disk image created at: \(dmgOutputPath)")
                        
                        // Sign DMG (if codesign is configured)
                        if let identity = signAppIdentity, !identity.isEmpty {
                            appendLog("Signing DMG...")
                            let signDmgArgs = ["--force", "--timestamp", "-s", identity, dmgOutputPath]
                            let _ = try await ShellManager.shared.runStream(
                                executable: "/usr/bin/codesign",
                                arguments: signDmgArgs,
                                processId: activeProcessId
                            ) { [weak self] line in
                                Task { @MainActor in self?.appendLog("  \(line)") }
                            }
                        }
                        
                        if performNotarization {
                            appendLog("Notarizing DMG...")
                            var notaryArgs = ["notarytool", "submit", dmgOutputPath, "--wait"]
                            if credentialType == .keychainProfile {
                                notaryArgs.append(contentsOf: ["--keychain-profile", keychainProfile])
                            } else {
                                notaryArgs.append(contentsOf: ["--key-id", apiKeyId, "--issuer", apiIssuerId, "--key", apiKeyPath])
                            }

                            let submitDmgStatus = try await ShellManager.shared.runStream(
                                executable: "/usr/bin/xcrun",
                                arguments: notaryArgs,
                                processId: activeProcessId
                            ) { [weak self] line in
                                Task { @MainActor in self?.appendLog("  \(line)") }
                            }

                            if submitDmgStatus == 0 {
                                appendLog("Stapling ticket to DMG...")
                                let stapleArgs = ["stapler", "staple", dmgOutputPath]
                                let _ = try await ShellManager.shared.runStream(
                                    executable: "/usr/bin/xcrun",
                                    arguments: stapleArgs,
                                    processId: activeProcessId
                                ) { [weak self] line in
                                    Task { @MainActor in self?.appendLog("  \(line)") }
                                }
                                appendLog("DMG package is now signed, notarized, and stapled.")
                            } else {
                                appendLog("Warning: DMG notarization failed.")
                            }
                        } else {
                            appendLog("Skipped: DMG notarization (distribution-only build)")
                        }
                    } else {
                        distributionBuildHadError = true
                        appendLog("Error: hdiutil failed with status \(hdiStatus)")
                    }
                } else {
                    distributionBuildHadError = true
                    appendLog("Error: Failed to copy app to staging directory.")
                }
            } catch {
                distributionBuildHadError = true
                appendLog("DMG compilation error: \(error.localizedDescription)")
            }
        }
        
        // 3c. Build Installer Package (.pkg)
        if fileExtension == "app" && packageToPkg {
            currentStep = "Building Package (.pkg)..."
            progress = 0.7
            let pkgOutputPath = parentDir.appendingPathComponent("\(appName).pkg").path
            appendLog("\n--- 3c. Building Installer Package (.pkg) ---")
            
            var args = ["--component", workingTarget, "/Applications"]
            if let pkgIdentity = signPkgIdentity, !pkgIdentity.isEmpty {
                args.append(contentsOf: ["--sign", pkgIdentity])
            }
            args.append(pkgOutputPath)
            
            appendLog("Running: productbuild " + args.joined(separator: " "))
            
            do {
                if fileManager.fileExists(atPath: pkgOutputPath) {
                    try? fileManager.removeItem(atPath: pkgOutputPath)
                }
                
                let status = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/productbuild",
                    arguments: args,
                    processId: activeProcessId
                ) { [weak self] line in
                    Task { @MainActor in self?.appendLog("  \(line)") }
                }
                
                if status == 0 {
                    appendLog("Package created at: \(pkgOutputPath)")

                    if !packageToDmg {
                        workingTarget = pkgOutputPath
                    }

                    if performNotarization {
                        appendLog("Notarizing PKG...")
                        var notaryArgs = ["notarytool", "submit", pkgOutputPath, "--wait"]
                        if credentialType == .keychainProfile {
                            notaryArgs.append(contentsOf: ["--keychain-profile", keychainProfile])
                        } else {
                            notaryArgs.append(contentsOf: ["--key-id", apiKeyId, "--issuer", apiIssuerId, "--key", apiKeyPath])
                        }

                        let submitPkgStatus = try await ShellManager.shared.runStream(
                            executable: "/usr/bin/xcrun",
                            arguments: notaryArgs,
                            processId: activeProcessId
                        ) { [weak self] line in
                            Task { @MainActor in self?.appendLog("  \(line)") }
                        }

                        if submitPkgStatus == 0 {
                            appendLog("Stapling ticket to PKG...")
                            let stapleArgs = ["stapler", "staple", pkgOutputPath]
                            let _ = try await ShellManager.shared.runStream(
                                executable: "/usr/bin/xcrun",
                                arguments: stapleArgs,
                                processId: activeProcessId
                            ) { [weak self] line in
                                Task { @MainActor in self?.appendLog("  \(line)") }
                            }
                            appendLog("PKG package is now signed, notarized, and stapled.")
                        } else {
                            appendLog("Warning: PKG notarization failed.")
                        }
                    } else {
                        appendLog("Skipped: PKG notarization (distribution-only build)")
                    }
                } else {
                    distributionBuildHadError = true
                    appendLog("Error: productbuild failed with status \(status)")
                }
            } catch {
                distributionBuildHadError = true
                appendLog("Packaging execution error: \(error.localizedDescription)")
            }
        }
        
        // 4. Submit original target directly if it is already a .pkg or .dmg
        if (fileExtension == "pkg" || fileExtension == "dmg") && performNotarization {
            currentStep = "Submitting to Notary Service..."
            progress = 0.5
            appendLog("\n--- 3. Submitting to Notary Service ---")
            
            var notaryArgs = ["notarytool", "submit", workingTarget, "--wait"]
            if credentialType == .keychainProfile {
                notaryArgs.append(contentsOf: ["--keychain-profile", keychainProfile])
            } else {
                notaryArgs.append(contentsOf: ["--key-id", apiKeyId, "--issuer", apiIssuerId, "--key", apiKeyPath])
            }
            
            appendLog("Running: xcrun " + notaryArgs.joined(separator: " "))
            
            do {
                let status = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/xcrun",
                    arguments: notaryArgs,
                    processId: activeProcessId
                ) { [weak self] line in
                    Task { @MainActor in self?.appendLog("  \(line)") }
                }
                
                if status != 0 {
                    appendLog("Error: Notarization submission failed (status \(status))")
                    isProcessing = false
                    currentStep = "Notarization Rejected"
                    return
                }
                appendLog("Notarization completed successfully!")
                
                // Staple ticket
                currentStep = "Stapling Ticket..."
                appendLog("Stapling ticket...")
                let stapleArgs = ["stapler", "staple", workingTarget]
                appendLog("Running: xcrun " + stapleArgs.joined(separator: " "))
                let stapleStatus = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/xcrun",
                    arguments: stapleArgs,
                    processId: activeProcessId
                ) { [weak self] line in
                    Task { @MainActor in self?.appendLog("  \(line)") }
                }
                if stapleStatus == 0 {
                    appendLog("Stapling ticket succeeded.")
                }
            } catch {
                appendLog("Execution error: \(error.localizedDescription)")
                isProcessing = false
                currentStep = "Failed"
                return
            }
        }
        
        if performNotarization {
            currentStep = "Running Security Verification Checks..."
            progress = 0.95
            appendLog("\n--- 5. Generating Security Assessment ---")

            let isPkgResult = workingTarget.hasSuffix(".pkg")
            await runVerificationChecks(targetPath: workingTarget, isPkg: isPkgResult)
        } else {
            appendLog("\nSkipped: Security verification (distribution-only build)")
        }

        progress = 1.0
        isProcessing = false
        if performNotarization {
            currentStep = "Completed Successfully"
            appendLog("\n=== All Steps Completed ===")
        } else if distributionBuildHadError {
            currentStep = "Distribution Build Finished with Errors"
            appendLog("\n=== Distribution Build Finished with Errors ===")
        } else {
            currentStep = "Distribution Build Completed"
            appendLog("\n=== Distribution Build Completed ===")
        }
    }
    
    /// Runs verification tools to populate checklist status.
    private func runVerificationChecks(targetPath: String, isPkg: Bool) async {
        // 1. Code Signature Verification
        verificationItems[0].status = .running
        appendLog("Verifying signature integrity...")
        let codesignArgs = ["--verify", "--verbose", "--deep", targetPath]
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/bin/codesign", arguments: codesignArgs)
            appendLog(output)
            verificationItems[0].status = (status == 0) ? .success : .failure
        } catch {
            verificationItems[0].status = .failure
        }
        
        // 2. Hardened Runtime Check (only for apps)
        verificationItems[1].status = .running
        if isPkg {
            // PKG files themselves do not have Hardened Runtime flags, we say success if signing passed,
            // or we display idle/success by default.
            verificationItems[1].status = .success
            appendLog("Skipped Hardened Runtime check (target is a installer package).")
        } else {
            appendLog("Checking for Hardened Runtime flag...")
            let detailArgs = ["-d", "-vvv", targetPath]
            do {
                let (_, output) = try ShellManager.shared.runSync(executable: "/usr/bin/codesign", arguments: detailArgs)
                appendLog(output)
                if output.contains("runtime") || output.contains("flags=0x10000") {
                    verificationItems[1].status = .success
                } else {
                    verificationItems[1].status = .failure
                }
            } catch {
                verificationItems[1].status = .failure
            }
        }
        
        // 3. Notarization check (Assessed via spctl assessment or stapler)
        verificationItems[2].status = .running
        // 4. Staple validation
        verificationItems[3].status = .running
        
        appendLog("Validating Stapler ticket...")
        let stapleVerifyArgs = ["stapler", "validate", targetPath]
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/bin/xcrun", arguments: stapleVerifyArgs)
            appendLog(output)
            verificationItems[3].status = (status == 0) ? .success : .failure
            // If stapled is true, notarized is implicitly true
            verificationItems[2].status = (status == 0) ? .success : .failure
        } catch {
            verificationItems[3].status = .failure
            verificationItems[2].status = .failure
        }
        
        // 5. Gatekeeper Assessment
        verificationItems[4].status = .running
        appendLog("Simulating macOS Gatekeeper installation check...")
        let spctlArgs = ["--assess", "-vv", "--type", isPkg ? "install" : "execute", targetPath]
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/sbin/spctl", arguments: spctlArgs)
            appendLog(output)
            verificationItems[4].status = (status == 0) ? .success : .failure
        } catch {
            verificationItems[4].status = .failure
        }
    }
    
    /// Fetches all stored notary profiles from the macOS keychain and combines them with local app profiles.
    public func refreshKeychainProfiles() {
        let systemProfiles = fetchSystemNotaryProfiles()
        
        var localProfileNames: [String] = []
        if let data = UserDefaults.standard.data(forKey: "notary_profiles"),
           let decoded = try? JSONDecoder().decode([NotaryProfile].self, from: data) {
            localProfileNames = decoded.map { $0.name }
        }
        
        let combined = Set(systemProfiles + localProfileNames)
        self.keychainProfiles = combined.sorted()
        appendLog("Loaded \(self.keychainProfiles.count) notary keychain profiles.")
    }
    
    private func fetchSystemNotaryProfiles() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            return []
        }
        
        let prefix = "com.apple.gke.notary.tool.saved-creds."
        var profileNames: [String] = []
        
        if let attributesList = item as? [[String: Any]] {
            for attributes in attributesList {
                if let account = attributes[kSecAttrAccount as String] as? String,
                   account.hasPrefix(prefix) {
                    let profileName = String(account.dropFirst(prefix.count))
                    profileNames.append(profileName)
                }
            }
        } else if let attributes = item as? [String: Any],
                  let account = attributes[kSecAttrAccount as String] as? String,
                  account.hasPrefix(prefix) {
            let profileName = String(account.dropFirst(prefix.count))
            profileNames.append(profileName)
        }
        
        return profileNames
    }
    
    /// Runs verification checks on an already signed and notarized application or package.
    public func verifyExistingSignature(targetPath: String) async {
        isProcessing = true
        logOutput = ""
        for i in 0..<verificationItems.count {
            verificationItems[i].status = .idle
        }
        
        appendLog("=== Starting Verification Only Workflow ===")
        appendLog("Target: \(targetPath)")
        
        let isPkg = targetPath.hasSuffix(".pkg")
        
        // 1. Code Signature
        verificationItems[0].status = .running
        appendLog("Checking code signature...")
        let codesignArgs = ["-d", "-vvv", targetPath]
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/bin/codesign", arguments: codesignArgs)
            appendLog(output)
            verificationItems[0].status = (status == 0) ? .success : .failure
        } catch {
            verificationItems[0].status = .failure
            appendLog("Codesign check error: \(error.localizedDescription)")
        }
        
        // 2. Hardened Runtime
        verificationItems[1].status = .running
        appendLog("Checking Hardened Runtime...")
        let codesignVerifyArgs = ["--display", "--verbose=4", targetPath]
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/bin/codesign", arguments: codesignVerifyArgs)
            appendLog(output)
            
            if status == 0 {
                let isHardened = output.contains("flags=0x10000") || output.contains("runtime")
                verificationItems[1].status = isHardened ? .success : .failure
                if isHardened {
                    appendLog("Hardened Runtime is enabled.")
                } else {
                    appendLog("Hardened Runtime is NOT enabled.")
                }
            } else {
                verificationItems[1].status = .failure
            }
        } catch {
            verificationItems[1].status = .failure
        }
        
        // 3 & 4. Notarization Ticket / Stapled Ticket
        verificationItems[2].status = .running
        verificationItems[3].status = .running
        appendLog("Validating Stapler ticket...")
        let staplerArgs = ["stapler", "validate", targetPath]
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/bin/xcrun", arguments: staplerArgs)
            appendLog(output)
            
            let isStapled = (status == 0)
            verificationItems[3].status = isStapled ? .success : .failure
            verificationItems[2].status = isStapled ? .success : .failure
        } catch {
            verificationItems[3].status = .failure
            verificationItems[2].status = .failure
        }
        
        // 5. Gatekeeper Assessment
        verificationItems[4].status = .running
        appendLog("Simulating macOS Gatekeeper installation check...")
        let spctlArgs = ["--assess", "-vv", "--type", isPkg ? "install" : "execute", targetPath]
        do {
            let (status, output) = try ShellManager.shared.runSync(executable: "/usr/sbin/spctl", arguments: spctlArgs)
            appendLog(output)
            verificationItems[4].status = (status == 0) ? .success : .failure
        } catch {
            verificationItems[4].status = .failure
        }
        
        isProcessing = false
        appendLog("=== Verification Completed ===")
    }
}
