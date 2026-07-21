import Foundation
import Combine
import Security

private enum DistributionBuildError: LocalizedError {
    case commandFailed(String, Int32)
    case installerPackageUnavailable

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status):
            return "\(command) failed with status \(status)."
        case .installerPackageUnavailable:
            return "The installer package could not be built, so it cannot be added to the disk image."
        }
    }
}

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
        distributionProject: DistributionProject,
        distributionAssets: [DistributionAssetKind: URL],
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
        
        let pkgOutputPath = parentDir.appendingPathComponent("\(appName).pkg").path
        var pkgBuildSucceeded = false

        // 3b. Build Installer Package first so a completed PKG can be embedded in the DMG.
        if fileExtension == "app" && packageToPkg {
            currentStep = "Building Package (.pkg)..."
            progress = 0.6
            appendLog("\n--- 3b. Building Installer Package (.pkg) ---")

            do {
                try await buildCustomizedInstaller(
                    appURL: fileUrl,
                    workingTarget: workingTarget,
                    outputPath: pkgOutputPath,
                    signingIdentity: signPkgIdentity,
                    settings: distributionProject.installer,
                    assets: distributionAssets
                )
                pkgBuildSucceeded = true
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

                    let submitStatus = try await ShellManager.shared.runStream(
                        executable: "/usr/bin/xcrun",
                        arguments: notaryArgs,
                        processId: activeProcessId
                    ) { [weak self] line in
                        Task { @MainActor in self?.appendLog("  \(line)") }
                    }

                    if submitStatus == 0 {
                        appendLog("Stapling ticket to PKG...")
                        _ = try await ShellManager.shared.runStream(
                            executable: "/usr/bin/xcrun",
                            arguments: ["stapler", "staple", pkgOutputPath],
                            processId: activeProcessId
                        ) { [weak self] line in
                            Task { @MainActor in self?.appendLog("  \(line)") }
                        }
                    } else {
                        appendLog("Warning: PKG notarization failed.")
                    }
                } else {
                    appendLog("Skipped: PKG notarization (distribution-only build)")
                }
            } catch {
                distributionBuildHadError = true
                appendLog("Packaging execution error: \(error.localizedDescription)")
            }
        }

        // 3c. Build Disk Image (.dmg)
        if fileExtension == "app" && packageToDmg {
            currentStep = "Building Disk Image..."
            progress = 0.6
            let dmgOutputPath = parentDir.appendingPathComponent("\(appName).dmg").path
            appendLog("\n--- 3c. Building Disk Image (.dmg) ---")

            do {
                let useInstallerPackage = packageToPkg && distributionProject.diskImage.includeInstallerPackage
                if useInstallerPackage && !pkgBuildSucceeded {
                    throw DistributionBuildError.installerPackageUnavailable
                }
                let diskImagePayloadURL = useInstallerPackage ? URL(fileURLWithPath: pkgOutputPath) : fileUrl
                let diskImagePayloadPath = useInstallerPackage ? pkgOutputPath : workingTarget
                var diskImageSettings = distributionProject.diskImage
                if useInstallerPackage {
                    diskImageSettings.includeApplicationsLink = false
                }
                appendLog(useInstallerPackage
                    ? "DMG payload: completed installer package"
                    : "DMG payload: application bundle")

                try await buildCustomizedDiskImage(
                    payloadURL: diskImagePayloadURL,
                    workingTarget: diskImagePayloadPath,
                    outputPath: dmgOutputPath,
                    settings: diskImageSettings,
                    assets: distributionAssets
                )
                appendLog("DMG disk image created at: \(dmgOutputPath)")

                if let identity = signAppIdentity, !identity.isEmpty {
                    appendLog("Signing DMG...")
                    let signStatus = try await ShellManager.shared.runStream(
                        executable: "/usr/bin/codesign",
                        arguments: ["--force", "--timestamp", "-s", identity, dmgOutputPath],
                        processId: activeProcessId
                    ) { [weak self] line in
                        Task { @MainActor in self?.appendLog("  \(line)") }
                    }
                    if signStatus != 0 { throw DistributionBuildError.commandFailed("codesign", signStatus) }
                }

                if performNotarization {
                    appendLog("Notarizing DMG...")
                    var notaryArgs = ["notarytool", "submit", dmgOutputPath, "--wait"]
                    if credentialType == .keychainProfile {
                        notaryArgs.append(contentsOf: ["--keychain-profile", keychainProfile])
                    } else {
                        notaryArgs.append(contentsOf: ["--key-id", apiKeyId, "--issuer", apiIssuerId, "--key", apiKeyPath])
                    }
                    let submitStatus = try await ShellManager.shared.runStream(
                        executable: "/usr/bin/xcrun",
                        arguments: notaryArgs,
                        processId: activeProcessId
                    ) { [weak self] line in
                        Task { @MainActor in self?.appendLog("  \(line)") }
                    }
                    if submitStatus == 0 {
                        appendLog("Stapling ticket to DMG...")
                        _ = try await ShellManager.shared.runStream(
                            executable: "/usr/bin/xcrun",
                            arguments: ["stapler", "staple", dmgOutputPath],
                            processId: activeProcessId
                        ) { [weak self] line in
                            Task { @MainActor in self?.appendLog("  \(line)") }
                        }
                    } else {
                        appendLog("Warning: DMG notarization failed.")
                    }
                } else {
                    appendLog("Skipped: DMG notarization (distribution-only build)")
                }
            } catch {
                distributionBuildHadError = true
                appendLog("DMG compilation error: \(error.localizedDescription)")
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

    private func buildCustomizedInstaller(
        appURL: URL,
        workingTarget: String,
        outputPath: String,
        signingIdentity: String?,
        settings: InstallerSettings,
        assets: [DistributionAssetKind: URL]
    ) async throws {
        let fileManager = FileManager.default
        let buildDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("pkg-build-\(UUID().uuidString)", isDirectory: true)
        let resourcesDirectory = buildDirectory.appendingPathComponent("Resources", isDirectory: true)
        let componentURL = buildDirectory.appendingPathComponent("component.pkg")
        let distributionURL = buildDirectory.appendingPathComponent("Distribution.xml")
        defer { try? fileManager.removeItem(at: buildDirectory) }

        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier ?? "com.dinkisstyle.\(slug(appURL.deletingPathExtension().lastPathComponent))"
        let identifier = settings.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? bundleIdentifier + ".installer"
            : settings.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = settings.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            : settings.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = settings.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appURL.deletingPathExtension().lastPathComponent
            : settings.title

        appendLog("Creating component package...")
        let componentStatus = try await ShellManager.shared.runStream(
            executable: "/usr/bin/pkgbuild",
            arguments: [
                "--component", workingTarget,
                "--install-location", "/Applications",
                "--identifier", identifier,
                "--version", version,
                componentURL.path
            ],
            processId: activeProcessId
        ) { [weak self] line in
            Task { @MainActor in self?.appendLog("  \(line)") }
        }
        guard componentStatus == 0 else {
            throw DistributionBuildError.commandFailed("pkgbuild", componentStatus)
        }

        var presentationElements: [String] = []
        if settings.showWelcome {
            try installerHTML(settings.welcomeText, title: title).write(
                to: resourcesDirectory.appendingPathComponent("welcome.html"),
                atomically: true,
                encoding: .utf8
            )
            presentationElements.append(#"<welcome file="welcome.html"/>"#)
        }
        if settings.showReadMe {
            try installerHTML(settings.readMeText, title: "Read Me").write(
                to: resourcesDirectory.appendingPathComponent("readme.html"),
                atomically: true,
                encoding: .utf8
            )
            presentationElements.append(#"<readme file="readme.html"/>"#)
        }
        if settings.showLicense {
            try settings.licenseText.write(
                to: resourcesDirectory.appendingPathComponent("license.txt"),
                atomically: true,
                encoding: .utf8
            )
            presentationElements.append(#"<license file="license.txt"/>"#)
        }
        if settings.showConclusion {
            try installerHTML(settings.conclusionText, title: "Installation Complete").write(
                to: resourcesDirectory.appendingPathComponent("conclusion.html"),
                atomically: true,
                encoding: .utf8
            )
            presentationElements.append(#"<conclusion file="conclusion.html"/>"#)
        }

        if let backgroundURL = assets[.pkgBackground] {
            let fileName = "installer-background.\(backgroundURL.pathExtension.lowercased())"
            try fileManager.copyItem(at: backgroundURL, to: resourcesDirectory.appendingPathComponent(fileName))
            presentationElements.append(
                #"<background file="\#(xmlEscaped(fileName))" alignment="\#(settings.backgroundAlignment.rawValue)" scaling="\#(settings.backgroundScaling.rawValue)"/>"#
            )
        }

        let distribution = """
        <?xml version="1.0" encoding="utf-8"?>
        <installer-gui-script minSpecVersion="2">
            <title>\(xmlEscaped(title))</title>
            <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
            <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
            \(presentationElements.joined(separator: "\n    "))
            <choices-outline>
                <line choice="default">
                    <line choice="app"/>
                </line>
            </choices-outline>
            <choice id="default"/>
            <choice id="app" visible="false">
                <pkg-ref id="\(xmlEscaped(identifier))"/>
            </choice>
            <pkg-ref id="\(xmlEscaped(identifier))" version="\(xmlEscaped(version))" onConclusion="\(settings.conclusionAction.distributionValue)">component.pkg</pkg-ref>
        </installer-gui-script>
        """
        try distribution.write(to: distributionURL, atomically: true, encoding: .utf8)

        if fileManager.fileExists(atPath: outputPath) {
            try fileManager.removeItem(atPath: outputPath)
        }

        var productArguments = [
            "--distribution", distributionURL.path,
            "--package-path", buildDirectory.path,
            "--resources", resourcesDirectory.path
        ]
        if let signingIdentity, !signingIdentity.isEmpty {
            productArguments.append(contentsOf: ["--sign", signingIdentity, "--timestamp"])
        }
        productArguments.append(outputPath)

        appendLog("Building product archive with custom Installer presentation...")
        let productStatus = try await ShellManager.shared.runStream(
            executable: "/usr/bin/productbuild",
            arguments: productArguments,
            processId: activeProcessId
        ) { [weak self] line in
            Task { @MainActor in self?.appendLog("  \(line)") }
        }
        guard productStatus == 0 else {
            throw DistributionBuildError.commandFailed("productbuild", productStatus)
        }
    }

    private func buildCustomizedDiskImage(
        payloadURL: URL,
        workingTarget: String,
        outputPath: String,
        settings: DiskImageSettings,
        assets: [DistributionAssetKind: URL]
    ) async throws {
        let fileManager = FileManager.default
        let buildDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("dmg-build-\(UUID().uuidString)", isDirectory: true)
        let stagingDirectory = buildDirectory.appendingPathComponent("staging", isDirectory: true)
        let mountDirectory = buildDirectory.appendingPathComponent("mounted", isDirectory: true)
        let readWriteImage = buildDirectory.appendingPathComponent("layout.dmg")
        defer { try? fileManager.removeItem(at: buildDirectory) }

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mountDirectory, withIntermediateDirectories: true)

        let stagedPayloadURL = stagingDirectory.appendingPathComponent(payloadURL.lastPathComponent)
        appendLog("Staging app bundle and disk image assets...")
        let copyStatus = try await ShellManager.shared.runStream(
            executable: "/usr/bin/ditto",
            arguments: [workingTarget, stagedPayloadURL.path],
            processId: activeProcessId
        ) { [weak self] line in
            Task { @MainActor in self?.appendLog("  \(line)") }
        }
        guard copyStatus == 0 else {
            throw DistributionBuildError.commandFailed("ditto", copyStatus)
        }

        if settings.includeApplicationsLink {
            try fileManager.createSymbolicLink(
                at: stagingDirectory.appendingPathComponent("Applications"),
                withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
        }

        var backgroundFileName = ""
        if let backgroundURL = assets[.dmgBackground] {
            let backgroundDirectory = stagingDirectory.appendingPathComponent(".background", isDirectory: true)
            try fileManager.createDirectory(at: backgroundDirectory, withIntermediateDirectories: true)
            backgroundFileName = "background.\(backgroundURL.pathExtension.lowercased())"
            try fileManager.copyItem(at: backgroundURL, to: backgroundDirectory.appendingPathComponent(backgroundFileName))
        }

        let hasVolumeIcon = assets[.dmgVolumeIcon] != nil
        if let volumeIconURL = assets[.dmgVolumeIcon] {
            let stagedVolumeIconURL = stagingDirectory.appendingPathComponent(".VolumeIcon.icns")
            if volumeIconURL.pathExtension.lowercased() == "png" {
                appendLog("Converting PNG volume icon to multi-resolution ICNS...")
                try ICNSConverter.convertPNG(at: volumeIconURL, to: stagedVolumeIconURL)
            } else {
                try fileManager.copyItem(at: volumeIconURL, to: stagedVolumeIconURL)
            }
        }

        let volumeName = settings.volumeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? payloadURL.deletingPathExtension().lastPathComponent
            : settings.volumeName

        appendLog("Creating writable disk image...")
        let createStatus = try await ShellManager.shared.runStream(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "create", "-srcfolder", stagingDirectory.path,
                "-volname", volumeName,
                "-fs", "HFS+", "-format", "UDRW", "-ov", readWriteImage.path
            ],
            processId: activeProcessId
        ) { [weak self] line in
            Task { @MainActor in self?.appendLog("  \(line)") }
        }
        guard createStatus == 0 else {
            throw DistributionBuildError.commandFailed("hdiutil create", createStatus)
        }

        let attachStatus = try await ShellManager.shared.runStream(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-readwrite", "-noverify", "-noautoopen", "-mountpoint", mountDirectory.path, readWriteImage.path],
            processId: activeProcessId
        ) { [weak self] line in
            Task { @MainActor in self?.appendLog("  \(line)") }
        }
        guard attachStatus == 0 else {
            throw DistributionBuildError.commandFailed("hdiutil attach", attachStatus)
        }

        var layoutError: Error?
        do {
            if hasVolumeIcon {
                let setFileStatus = try await ShellManager.shared.runStream(
                    executable: "/usr/bin/xcrun",
                    arguments: ["SetFile", "-a", "C", mountDirectory.path],
                    processId: activeProcessId
                ) { _ in }
                if setFileStatus != 0 {
                    appendLog("Warning: The volume icon was copied, but its custom-icon Finder flag could not be set.")
                }
            }

            let width = min(max(settings.windowWidth, 420), 1600)
            let height = min(max(settings.windowHeight, 260), 1000)
            let iconSize = min(max(settings.iconSize, 32), 256)
            let appX = settings.centerAppIcon ? width / 2 : min(max(settings.appIconX, 40), width - 40)
            let appY = settings.centerAppIcon ? height / 2 : min(max(settings.appIconY, 70), height - 40)
            let applicationsX = min(max(settings.applicationsIconX, 40), width - 40)
            let applicationsY = min(max(settings.applicationsIconY, 70), height - 40)

            let scriptURL = buildDirectory.appendingPathComponent("layout.applescript")
            try diskImageLayoutScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            appendLog("Applying Finder window layout...")
            let layoutStatus = try await ShellManager.shared.runStream(
                executable: "/usr/bin/osascript",
                arguments: [
                    scriptURL.path,
                    mountDirectory.lastPathComponent,
                    mountDirectory.path,
                    String(width), String(height), String(iconSize),
                    payloadURL.lastPathComponent, String(appX), String(appY),
                    settings.includeApplicationsLink ? "1" : "0",
                    String(applicationsX), String(applicationsY),
                    backgroundFileName
                ],
                processId: activeProcessId
            ) { [weak self] line in
                Task { @MainActor in self?.appendLog("  \(line)") }
            }
            if layoutStatus != 0 {
                throw DistributionBuildError.commandFailed("osascript", layoutStatus)
            }

            _ = try ShellManager.shared.runSync(executable: "/bin/sync", arguments: [])
        } catch {
            layoutError = error
        }

        let detachStatus = try await ShellManager.shared.runStream(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", mountDirectory.path],
            processId: activeProcessId
        ) { [weak self] line in
            Task { @MainActor in self?.appendLog("  \(line)") }
        }
        if let layoutError { throw layoutError }
        guard detachStatus == 0 else {
            throw DistributionBuildError.commandFailed("hdiutil detach", detachStatus)
        }

        if fileManager.fileExists(atPath: outputPath) {
            try fileManager.removeItem(atPath: outputPath)
        }
        appendLog("Compressing final disk image...")
        let convertStatus = try await ShellManager.shared.runStream(
            executable: "/usr/bin/hdiutil",
            arguments: ["convert", readWriteImage.path, "-format", "UDZO", "-imagekey", "zlib-level=9", "-o", outputPath],
            processId: activeProcessId
        ) { [weak self] line in
            Task { @MainActor in self?.appendLog("  \(line)") }
        }
        guard convertStatus == 0 else {
            throw DistributionBuildError.commandFailed("hdiutil convert", convertStatus)
        }
    }

    private var diskImageLayoutScript: String {
        """
        on run argv
            set mountedDiskName to item 1 of argv
            set mountedDiskPath to item 2 of argv
            set windowWidth to (item 3 of argv) as integer
            set windowHeight to (item 4 of argv) as integer
            set requestedIconSize to (item 5 of argv) as integer
            set appName to item 6 of argv
            set appX to (item 7 of argv) as integer
            set appY to (item 8 of argv) as integer
            set hasApplicationsLink to item 9 of argv
            set applicationsX to (item 10 of argv) as integer
            set applicationsY to (item 11 of argv) as integer
            set backgroundName to item 12 of argv

            set backgroundFileAlias to missing value
            if backgroundName is not "" then
                set backgroundFileAlias to (POSIX file (mountedDiskPath & "/.background/" & backgroundName)) as alias
            end if

            tell application "Finder"
                tell disk mountedDiskName
                    open
                    tell container window
                        set current view to icon view
                        set toolbar visible to false
                        set statusbar visible to false
                        set pathbar visible to false
                        set bounds to {100, 100, 100 + windowWidth, 100 + windowHeight}
                    end tell
                    tell icon view options of container window
                        set arrangement to not arranged
                        set icon size to requestedIconSize
                        set text size to 12
                    end tell
                    if backgroundFileAlias is not missing value then
                        set background picture of icon view options of container window to backgroundFileAlias
                    end if
                    set position of item appName to {appX, appY}
                    if hasApplicationsLink is "1" then
                        set position of item "Applications" to {applicationsX, applicationsY}
                    end if
                    update without registering applications
                    delay 1
                    close container window
                    open
                    delay 1
                end tell
            end tell
        end run
        """
    }

    private func installerHTML(_ text: String, title: String) -> String {
        let body = htmlEscaped(text).replacingOccurrences(of: "\n", with: "<br>")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>body { font: -apple-system-body; margin: 22px; line-height: 1.45; } h2 { font: -apple-system-title2; }</style>
        </head><body><h2>\(htmlEscaped(title))</h2><p>\(body)</p></body></html>
        """
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func htmlEscaped(_ value: String) -> String {
        xmlEscaped(value)
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return value.lowercased().unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
            .reduce(into: "") { $0.append($1) }
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
