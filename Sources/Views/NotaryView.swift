import SwiftUI
import UniformTypeIdentifiers

struct NotaryView: View {
    @EnvironmentObject var service: NotaryService
    
    // File drop state
    @State private var selectedFile: URL? = nil
    @State private var isTargeted: Bool = false
    
    // Core parameters
    @State private var signAppBundle: Bool = false
    @State private var selectedAppIdentity: String = ""
    
    @State private var packageToPkg: Bool = false
    @State private var signPkgBundle: Bool = false
    @State private var selectedPkgIdentity: String = ""
    @State private var packageToDmg: Bool = false
    @State private var packageToZip: Bool = false
    
    // Credentials selection
    @State private var credentialType: CredentialType = .keychainProfile
    @State private var selectedProfile: String = ""
    @State private var isAlreadySigned: Bool = false
    
    // API Key credentials
    @State private var apiKeyId: String = ""
    @State private var apiIssuerId: String = ""
    @State private var apiKeyPath: String = ""
    
    var body: some View {
        HSplitView {
            // Left Column: Drop Area & Configuration
            VStack(spacing: 16) {
                fileDropArea
                
                if isAlreadySigned && selectedFile != nil {
                    alreadySignedBanner
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        codeSignSection
                        packagingSection
                        credentialsSection
                    }
                    .padding(.trailing, 2)
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                actionSection
            }
            .padding(20)
            .frame(width: AppLayout.workPanelWidth)
            
            // Right Column: Checklist & Logs
            VStack(spacing: 20) {
                checklistCard
                consoleOutputView
            }
            .padding(20)
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.underPageBackgroundColor).opacity(0.4))
        }
        .onAppear {
            service.refreshKeychainProfiles()
            service.fetchCertificates()
        }
        .onChange(of: selectedFile) { file in
            resetWorkflowState()
            if let file = file {
                checkIfAlreadySigned(path: file.path)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var fileDropArea: some View {
        Group {
            if let file = selectedFile {
                HStack(spacing: 12) {
                    Image(systemName: file.pathExtension.lowercased() == "pkg" ? "shippingbox.fill" : "macwindow.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(file.path)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: { selectedFile = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(isTargeted ? .blue : .secondary)
                    
                    Text("Drag & Drop .app or .pkg")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Supports macOS application bundle or installer package")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(isTargeted ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isTargeted ? Color.blue : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                )
                .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                        if let data = data as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            let ext = url.pathExtension.lowercased()
                            if ext == "app" || ext == "pkg" {
                                DispatchQueue.main.async {
                                    self.selectedFile = url
                                }
                            }
                        }
                    }
                    return true
                }
            }
        }
    }
    
    private var codeSignSection: some View {
        let fileType = selectedFile?.pathExtension.lowercased() ?? "app"
        let isApp = fileType == "app"
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Code Signing", systemImage: "signature")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if isApp {
                    Toggle("", isOn: $signAppBundle)
                        .toggleStyle(.switch)
                        .labelsHidden()
                } else {
                    Text("N/A for .pkg")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                }
            }
            
            if isApp && signAppBundle {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Developer ID Application Cert")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    if service.appIdentities.isEmpty {
                        Text("No Developer ID Application certificates found in keychain.")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    } else {
                        Picker("", selection: $selectedAppIdentity) {
                            Text("Select certificate...").tag("")
                            ForEach(service.appIdentities, id: \.self) { cert in
                                Text(cert).tag(cert)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var packagingSection: some View {
        let fileType = selectedFile?.pathExtension.lowercased() ?? "app"
        let isApp = fileType == "app"
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Distribution Formats")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            // 1. PKG Option
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Build Installer (.pkg)", systemImage: "shippingbox")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if isApp {
                        Toggle("", isOn: $packageToPkg)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    } else {
                        Text("N/A")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if isApp && packageToPkg {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Sign Installer Package", isOn: $signPkgBundle)
                            .font(.system(size: 10))
                        
                        if signPkgBundle {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Developer ID Installer Certificate")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                
                                if service.installerIdentities.isEmpty {
                                    Text("No certificates found in keychain.")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.red)
                                } else {
                                    Picker("", selection: $selectedPkgIdentity) {
                                        Text("Select certificate...").tag("")
                                        ForEach(service.installerIdentities, id: \.self) { cert in
                                            Text(cert).tag(cert)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .transition(.opacity)
                }
            }
            
            Divider()
            
            // 2. DMG Option
            HStack {
                Label("Build Disk Image (.dmg)", systemImage: "externaldrive.fill")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if isApp {
                    Toggle("", isOn: $packageToDmg)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                } else {
                    Text("N/A")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // 3. ZIP Option
            HStack {
                Label("Build Zip Archive (.zip)", systemImage: "doc.zipper")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if isApp {
                    Toggle("", isOn: $packageToZip)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                } else {
                    Text("N/A")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notary Credentials", systemImage: "key.viewfinder")
                .font(.subheadline)
                .fontWeight(.semibold)

            if isDistributionOnly {
                Label("Not required for distribution-only builds", systemImage: "shippingbox")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("The selected formats will be created without notarization.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Picker("Auth Type", selection: $credentialType) {
                    ForEach([CredentialType.keychainProfile, CredentialType.apiKey], id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if credentialType == .keychainProfile {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keychain Profile")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if service.keychainProfiles.isEmpty {
                            Text("No profiles found. Add one in Notary Profiles tab.")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        } else {
                            Picker("", selection: $selectedProfile) {
                                Text("Select profile...").tag("")
                                ForEach(service.keychainProfiles, id: \.self) { profile in
                                    Text(profile).tag(profile)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key ID")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            TextField("e.g. 2X9V8A34L9", text: $apiKeyId)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Issuer ID")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            TextField("e.g. 57246542-96b5-4a37-90a8-b6177e6822c9", text: $apiIssuerId)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private Key File (.p8)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("AuthKey_*.p8", text: $apiKeyPath)
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse...") {
                                    selectPrivateKeyFile()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var actionSection: some View {
        HStack {
            if service.isProcessing {
                Button(action: {
                    Task { await service.cancel() }
                }) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("Cancel Operation")
                            .fontWeight(.bold)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: startExecution) {
                    HStack {
                        Image(systemName: actionButtonIcon)
                        Text(actionButtonTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFile == nil || isStartDisabled)
            }
        }
    }
    
    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Verification Checklist Report", systemImage: "checklist.checked")
                .font(.headline)
            
            VStack(spacing: 0) {
                ForEach(service.verificationItems) { item in
                    HStack(spacing: 12) {
                        statusIcon(for: item.status)
                            .font(.system(size: 16))
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(item.description)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    
                    if item.id != service.verificationItems.last?.id {
                        Divider()
                            .opacity(0.5)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var consoleOutputView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Process Logs", systemImage: "terminal.fill")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if service.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
                
                Button(action: service.clearLogs) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(service.logOutput.isEmpty ? "Console idle. Logs will stream here..." : service.logOutput)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(service.logOutput.isEmpty ? Color.secondary : Color.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                }
                .onChange(of: service.logOutput) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .background(Color.black.opacity(0.75))
        }
        .frame(maxHeight: .infinity)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    
    private func statusIcon(for status: VerificationStatus) -> some View {
        switch status {
        case .idle:
            return AnyView(Image(systemName: "circle")
                .foregroundStyle(.secondary))
        case .running:
            return AnyView(ProgressView()
                .controlSize(.small))
        case .success:
            return AnyView(Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green))
        case .failure:
            return AnyView(Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red))
        }
    }
    
    private var isStartDisabled: Bool {
        guard let selectedFile else { return true }

        if selectedFile.pathExtension.lowercased() == "app" {
            guard signAppBundle || hasDistributionSelection else { return true }

            if signAppBundle && selectedAppIdentity.isEmpty {
                return true
            }

            if packageToPkg && signPkgBundle && selectedPkgIdentity.isEmpty {
                return true
            }

            if !shouldPerformNotarization {
                return false
            }
        }

        return !hasValidNotaryCredentials
    }

    private var hasDistributionSelection: Bool {
        packageToPkg || packageToDmg || packageToZip
    }

    private var shouldPerformNotarization: Bool {
        guard let selectedFile else { return false }
        return selectedFile.pathExtension.lowercased() != "app" || signAppBundle
    }

    private var isDistributionOnly: Bool {
        selectedFile?.pathExtension.lowercased() == "app"
            && hasDistributionSelection
            && !signAppBundle
    }

    private var hasValidNotaryCredentials: Bool {
        if credentialType == .keychainProfile {
            return !selectedProfile.isEmpty
        }
        return !apiKeyId.isEmpty && !apiIssuerId.isEmpty && !apiKeyPath.isEmpty
    }

    private var actionButtonTitle: String {
        guard let selectedFile else { return "Choose an Action" }

        if selectedFile.pathExtension.lowercased() != "app" {
            return "Notarize Package"
        }

        switch (signAppBundle, hasDistributionSelection) {
        case (true, true):
            return "Sign, Notarize & Package"
        case (true, false):
            return "Sign & Notarize"
        case (false, true):
            return signPkgBundle ? "Sign & Create Distribution" : "Create Distribution"
        case (false, false):
            return "Choose an Action"
        }
    }

    private var actionButtonIcon: String {
        guard let selectedFile else {
            return "slider.horizontal.3"
        }
        if isDistributionOnly {
            return "shippingbox.fill"
        }
        return signAppBundle || selectedFile.pathExtension.lowercased() != "app"
            ? "checkmark.shield.fill"
            : "slider.horizontal.3"
    }

    
    private func selectPrivateKeyFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType(filenameExtension: "p8")].compactMap { $0 }
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            self.apiKeyPath = url.path
        }
    }
    
    private func resetWorkflowState() {
        service.clearLogs()
        signAppBundle = false
        packageToPkg = false
        signPkgBundle = false
        packageToDmg = false
        packageToZip = false
        isAlreadySigned = false
    }
    
    private func checkIfAlreadySigned(path: String) {
        Task {
            do {
                let (status, _) = try ShellManager.shared.runSync(
                    executable: "/usr/bin/codesign",
                    arguments: ["-d", path]
                )
                await MainActor.run {
                    self.isAlreadySigned = (status == 0)
                }
            } catch {
                await MainActor.run {
                    self.isAlreadySigned = false
                }
            }
        }
    }
    
    private var alreadySignedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(.purple)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Already Signed")
                    .font(.system(size: 11, weight: .bold))
                Text("This file has a code signature. You can run checks directly.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Verify Only") {
                if let file = selectedFile {
                    Task {
                        await service.verifyExistingSignature(targetPath: file.path)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.purple)
            .disabled(service.isProcessing)
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func startExecution() {
        guard let file = selectedFile else { return }
        
        Task {
            await service.startWorkflow(
                fileUrl: file,
                signAppIdentity: signAppBundle ? selectedAppIdentity : nil,
                packageToPkg: packageToPkg,
                signPkgIdentity: (packageToPkg && signPkgBundle) ? selectedPkgIdentity : nil,
                packageToDmg: packageToDmg,
                packageToZip: packageToZip,
                performNotarization: shouldPerformNotarization,
                credentialType: credentialType,
                keychainProfile: selectedProfile,
                apiKeyId: apiKeyId,
                apiIssuerId: apiIssuerId,
                apiKeyPath: apiKeyPath
            )
        }
    }
}
