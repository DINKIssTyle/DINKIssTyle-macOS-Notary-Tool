import SwiftUI
import UniformTypeIdentifiers

enum WorkflowActionPresentation {
    static func title(
        isApp: Bool,
        signApp: Bool,
        notarize: Bool,
        hasDistribution: Bool
    ) -> String {
        guard isApp else {
            return notarize ? "Notarize Package" : "Choose an Action"
        }

        if hasDistribution {
            switch (signApp, notarize) {
            case (true, true):
                return "Sign, Notarize & Create Distribution"
            case (true, false):
                return "Sign & Create Distribution"
            case (false, true):
                return "Notarize & Create Distribution"
            case (false, false):
                return "Create Distribution"
            }
        }

        switch (signApp, notarize) {
        case (true, true):
            return "Sign & Notarize"
        case (true, false):
            return "Sign App"
        case (false, true):
            return "Notarize App"
        case (false, false):
            return "Choose an Action"
        }
    }
}

enum WorkflowSigningPolicy {
    static func shouldSignInstaller(buildInstaller: Bool, notarize: Bool) -> Bool {
        buildInstaller && notarize
    }
}

struct NotaryView: View {
    @EnvironmentObject var service: NotaryService
    @EnvironmentObject private var documentOpenCoordinator: DocumentOpenCoordinator
    
    // File drop state
    @State private var selectedFile: URL? = nil
    @State private var isTargeted: Bool = false
    
    // Core parameters
    @State private var signAppBundle: Bool = false
    @State private var notarizeOutput: Bool = true
    @State private var selectedAppIdentity: String = ""
    
    @State private var distributionProject = DistributionProject()
    @State private var distributionAssets: [DistributionAssetKind: URL] = [:]
    @State private var extractedProjectDirectory: URL?
    @State private var projectSaveTask: Task<Void, Never>?
    @State private var projectIsReady = false
    @State private var hasProjectArchive = false
    @State private var projectStatus = ""
    @State private var pkgOptionsExpanded = true
    @State private var dmgOptionsExpanded = true
    @State private var pendingProjectArchiveURL: URL?
    @State private var lastHandledDocumentRequestID: UUID?
    
    // Credentials selection
    @State private var credentialType: CredentialType = .keychainProfile
    @State private var selectedProfile: String = ""
    @State private var isAlreadySigned: Bool = false
    
    // API Key credentials
    @State private var apiKeyId: String = ""
    @State private var apiIssuerId: String = ""
    @State private var apiKeyPath: String = ""
    
    var body: some View {
        EqualPanelSplitView {
            // Left Column: Drop Area & Configuration
            VStack(spacing: 16) {
                fileDropArea
                
                if isAlreadySigned && selectedFile != nil {
                    alreadySignedBanner
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        codeSignSection
                        notarizationSection
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
        } trailing: {
            // Right Column: Checklist & Logs
            VStack(spacing: 20) {
                checklistCard
                consoleOutputView
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.underPageBackgroundColor).opacity(0.4))
        }
        .onAppear {
            service.refreshKeychainProfiles()
            service.fetchCertificates()
            handlePendingDocumentRequest(documentOpenCoordinator.request)
        }
        .onChange(of: selectedFile) { file in
            let projectArchiveURL = pendingProjectArchiveURL
            pendingProjectArchiveURL = nil
            loadWorkflow(for: file, projectArchiveURL: projectArchiveURL)
        }
        .onChange(of: distributionProject) { _ in
            scheduleProjectSave()
        }
        .onReceive(documentOpenCoordinator.$request) { request in
            handlePendingDocumentRequest(request)
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

    private var notarizationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notarization", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: $notarizeOutput)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Text(notarizeOutput
                 ? "Reuse a valid existing app ticket, then notarize and staple newly created distribution files."
                 : "Skip Apple notarization. Code signing and local distribution builds remain available.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            HStack {
                Text("Distribution Formats")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
                if !projectStatus.isEmpty {
                    Label(projectStatus, systemImage: hasProjectArchive ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 8))
                        .foregroundStyle(hasProjectArchive ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }
            }
            
            // 1. PKG Option
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        if packageToPkg { withAnimation { pkgOptionsExpanded.toggle() } }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: packageToPkg && pkgOptionsExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                            Label("Build Installer (.pkg)", systemImage: "shippingbox")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if isApp {
                        Toggle("", isOn: $distributionProject.buildInstaller)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    } else {
                        Text("N/A")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if isApp && packageToPkg && pkgOptionsExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        if shouldSignInstallerPackage {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("PKG signing is included with notarization", systemImage: "signature")
                                    .font(.system(size: 10, weight: .medium))

                                Text("Developer ID Installer Certificate")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                
                                if service.installerIdentities.isEmpty {
                                    Text("No certificates found in keychain.")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.red)
                                } else {
                                    Picker("", selection: $distributionProject.installerIdentity) {
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
                        } else {
                            Label("Creates an unsigned local package", systemImage: "shippingbox")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                        InstallerCustomizationView(
                            settings: $distributionProject.installer,
                            backgroundURL: distributionAssets[.pkgBackground],
                            chooseBackground: { selectAsset(.pkgBackground) },
                            removeBackground: { removeAsset(.pkgBackground) }
                        )
                    }
                    .padding(.leading, 12)
                    .transition(.opacity)
                }
            }
            
            Divider()
            
            // 2. DMG Option
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        if packageToDmg { withAnimation { dmgOptionsExpanded.toggle() } }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: packageToDmg && dmgOptionsExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                            Label("Build Disk Image (.dmg)", systemImage: "externaldrive.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if isApp {
                        Toggle("", isOn: $distributionProject.buildDiskImage)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    } else {
                        Text("N/A")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                if isApp && packageToDmg && dmgOptionsExpanded {
                    DiskImageCustomizationView(
                        settings: $distributionProject.diskImage,
                        canUseInstallerPackage: packageToPkg,
                        backgroundURL: distributionAssets[.dmgBackground],
                        volumeIconURL: distributionAssets[.dmgVolumeIcon],
                        chooseBackground: { selectAsset(.dmgBackground) },
                        removeBackground: { removeAsset(.dmgBackground) },
                        chooseVolumeIcon: { selectAsset(.dmgVolumeIcon) },
                        removeVolumeIcon: { removeAsset(.dmgVolumeIcon) }
                    )
                    .transition(.opacity)
                }
            }
            
            Divider()
            
            // 3. ZIP Option
            HStack {
                Label("Build Zip Archive (.zip)", systemImage: "doc.zipper")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if isApp {
                    Toggle("", isOn: $distributionProject.buildZipArchive)
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

            if !shouldPerformNotarization {
                Label("Not required when notarization is disabled", systemImage: "key.slash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(localWorkflowCredentialNote)
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
        .frame(maxWidth: AppLayout.primaryActionWidth)
        .frame(maxWidth: .infinity, alignment: .center)
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

    private var packageToPkg: Bool { distributionProject.buildInstaller }
    private var selectedPkgIdentity: String { distributionProject.installerIdentity }
    private var packageToDmg: Bool { distributionProject.buildDiskImage }
    private var packageToZip: Bool { distributionProject.buildZipArchive }
    private var shouldSignInstallerPackage: Bool {
        WorkflowSigningPolicy.shouldSignInstaller(
            buildInstaller: packageToPkg,
            notarize: shouldPerformNotarization
        )
    }
    
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
        let isApp = selectedFile.pathExtension.lowercased() == "app"

        if isApp {
            guard signAppBundle || shouldPerformNotarization || hasDistributionSelection else { return true }

            if signAppBundle && selectedAppIdentity.isEmpty {
                return true
            }

            if shouldSignInstallerPackage && selectedPkgIdentity.isEmpty {
                return true
            }

            if shouldPerformNotarization {
                guard signAppBundle || isAlreadySigned else { return true }
                return !hasValidNotaryCredentials
            }

            return false
        }

        guard shouldPerformNotarization else { return true }
        return !hasValidNotaryCredentials
    }

    private var hasDistributionSelection: Bool {
        packageToPkg || packageToDmg || packageToZip
    }

    private var shouldPerformNotarization: Bool {
        selectedFile != nil && notarizeOutput
    }

    private var localWorkflowCredentialNote: String {
        if signAppBundle && hasDistributionSelection {
            return "The app will be signed and the selected distribution formats will be created locally."
        }
        if signAppBundle {
            return "The app will be code signed without Apple notarization."
        }
        return "The selected distribution formats will be created locally without Apple notarization."
    }

    private var hasValidNotaryCredentials: Bool {
        if credentialType == .keychainProfile {
            return !selectedProfile.isEmpty
        }
        return !apiKeyId.isEmpty && !apiIssuerId.isEmpty && !apiKeyPath.isEmpty
    }

    private var actionButtonTitle: String {
        guard let selectedFile else { return "Choose an Action" }
        return WorkflowActionPresentation.title(
            isApp: selectedFile.pathExtension.lowercased() == "app",
            signApp: signAppBundle,
            notarize: shouldPerformNotarization,
            hasDistribution: hasDistributionSelection
        )
    }

    private var actionButtonIcon: String {
        guard selectedFile != nil else { return "slider.horizontal.3" }
        if shouldPerformNotarization {
            return "checkmark.seal.fill"
        }
        if hasDistributionSelection && !signAppBundle {
            return "shippingbox.fill"
        }
        return signAppBundle ? "signature" : "slider.horizontal.3"
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
        notarizeOutput = true
        isAlreadySigned = false
    }

    private func loadWorkflow(for file: URL?, projectArchiveURL: URL? = nil) {
        projectSaveTask?.cancel()
        projectIsReady = false
        resetWorkflowState()
        distributionAssets = [:]
        hasProjectArchive = false
        projectStatus = ""

        if let extractedProjectDirectory {
            try? FileManager.default.removeItem(at: extractedProjectDirectory)
            self.extractedProjectDirectory = nil
        }

        guard let file else {
            distributionProject = DistributionProject()
            return
        }

        checkIfAlreadySigned(path: file.path)
        let isApp = file.pathExtension.lowercased() == "app"

        do {
            let loaded: LoadedDistributionProject?
            if let projectArchiveURL {
                loaded = try DistributionProjectArchive.load(from: projectArchiveURL)
            } else if isApp {
                loaded = try DistributionProjectArchive.load(for: file)
            } else {
                loaded = nil
            }

            if let loaded {
                distributionProject = loaded.project
                distributionAssets = loaded.assets
                extractedProjectDirectory = loaded.extractionDirectory
                hasProjectArchive = true
                let loadedArchiveURL = projectArchiveURL ?? DistributionProjectArchive.archiveURL(for: file)
                projectStatus = "Loaded \(loadedArchiveURL.lastPathComponent)"
            } else {
                distributionProject = isApp ? defaultProject(for: file) : DistributionProject()
            }
        } catch {
            distributionProject = isApp ? defaultProject(for: file) : DistributionProject()
            projectStatus = "Could not load .dnt"
            service.appendLog("Project load error: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            projectIsReady = true
        }
    }

    private func handlePendingDocumentRequest(_ request: DocumentOpenCoordinator.Request?) {
        guard let request, request.id != lastHandledDocumentRequestID else { return }
        lastHandledDocumentRequestID = request.id
        guard let claimedRequest = documentOpenCoordinator.consume(request.id) else { return }
        openProjectArchive(claimedRequest.url)
    }

    private func openProjectArchive(_ archiveURL: URL) {
        do {
            let validationResult = try DistributionProjectArchive.load(from: archiveURL)
            try? FileManager.default.removeItem(at: validationResult.extractionDirectory)
        } catch {
            showProjectAlert(
                title: "Unable to Open Project",
                message: "\(archiveURL.lastPathComponent) is not a valid DKST Notary project.\n\n\(error.localizedDescription)"
            )
            service.appendLog("Project open error: \(error.localizedDescription)")
            return
        }

        let targetName = archiveURL.deletingPathExtension().lastPathComponent
        let directory = archiveURL.deletingLastPathComponent()
        let appTargetURL = directory.appendingPathComponent(targetName).appendingPathExtension("app")
        let packageTargetURL = directory.appendingPathComponent(targetName).appendingPathExtension("pkg")
        let targetURL: URL?
        if FileManager.default.fileExists(atPath: appTargetURL.path) {
            // A .dnt is normally saved from its source app. Prefer it when a
            // generated package with the same name also exists beside it.
            targetURL = appTargetURL
        } else if FileManager.default.fileExists(atPath: packageTargetURL.path) {
            targetURL = packageTargetURL
        } else {
            targetURL = nil
        }

        if let targetURL {
            selectProjectTarget(targetURL, archiveURL: archiveURL)
        } else {
            chooseProjectTarget(for: archiveURL)
        }
    }

    private func chooseProjectTarget(for archiveURL: URL) {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Target"
        panel.message = "Choose the .app or .pkg associated with \(archiveURL.lastPathComponent)."
        panel.prompt = "Choose"
        panel.directoryURL = archiveURL.deletingLastPathComponent()
        panel.allowedContentTypes = [
            .applicationBundle,
            UTType(filenameExtension: "pkg")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let targetURL = panel.url else { return }
        let targetExtension = targetURL.pathExtension.lowercased()
        guard targetExtension == "app" || targetExtension == "pkg" else {
            showProjectAlert(
                title: "Unsupported Target",
                message: "Choose a macOS application (.app) or installer package (.pkg)."
            )
            return
        }

        do {
            guard let adjacentArchiveURL = try copyProjectArchiveIfNeeded(archiveURL, nextTo: targetURL) else {
                return
            }
            selectProjectTarget(targetURL, archiveURL: adjacentArchiveURL)
        } catch {
            showProjectAlert(
                title: "Unable to Copy Project",
                message: error.localizedDescription
            )
            service.appendLog("Project copy error: \(error.localizedDescription)")
        }
    }

    private func copyProjectArchiveIfNeeded(_ sourceURL: URL, nextTo targetURL: URL) throws -> URL? {
        let fileManager = FileManager.default
        let destinationURL = DistributionProjectArchive.archiveURL(for: targetURL)
        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return sourceURL
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "A Project Already Exists"
            alert.informativeText = "\(destinationURL.lastPathComponent) already exists next to the selected target."
            alert.addButton(withTitle: "Replace Existing")
            alert.addButton(withTitle: "Use Existing")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break
            case .alertSecondButtonReturn:
                return destinationURL
            default:
                return nil
            }
        }

        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
        service.appendLog("Copied project to \(destinationURL.path)")
        return destinationURL
    }

    private func selectProjectTarget(_ targetURL: URL, archiveURL: URL) {
        if selectedFile?.standardizedFileURL == targetURL.standardizedFileURL {
            loadWorkflow(for: targetURL, projectArchiveURL: archiveURL)
        } else {
            pendingProjectArchiveURL = archiveURL
            selectedFile = targetURL
        }
    }

    private func showProjectAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func defaultProject(for appURL: URL) -> DistributionProject {
        var project = DistributionProject()
        let appName = appURL.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: appURL)
        project.installer.title = appName
        project.installer.identifier = (bundle?.bundleIdentifier ?? "") + (bundle?.bundleIdentifier == nil ? "" : ".installer")
        project.installer.version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        project.installer.welcomeText = "Welcome to the \(appName) installer."
        project.installer.conclusionText = "\(appName) was installed successfully."
        project.diskImage.volumeName = appName
        return project
    }

    private func scheduleProjectSave() {
        guard projectIsReady,
              let targetURL = selectedFile,
              ["app", "pkg"].contains(targetURL.pathExtension.lowercased()),
              hasProjectArchive || packageToPkg || packageToDmg || packageToZip || !distributionAssets.isEmpty else { return }

        projectSaveTask?.cancel()
        projectSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            saveDistributionProject(for: targetURL)
        }
    }

    private func saveDistributionProject(for appURL: URL) {
        do {
            let url = try DistributionProjectArchive.save(
                distributionProject,
                for: appURL,
                assetSources: distributionAssets
            )
            hasProjectArchive = true
            projectStatus = "Saved \(url.lastPathComponent)"
        } catch {
            projectStatus = "Project save failed"
            service.appendLog("Project save error: \(error.localizedDescription)")
        }
    }

    private func selectAsset(_ kind: DistributionAssetKind) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        switch kind {
        case .dmgVolumeIcon:
            panel.allowedContentTypes = [UTType(filenameExtension: "icns"), .png].compactMap { $0 }
        case .pkgBackground, .dmgBackground:
            panel.allowedContentTypes = [.png, .jpeg, .tiff]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        distributionAssets[kind] = url
        switch kind {
        case .pkgBackground:
            distributionProject.installer.backgroundAssetName = url.lastPathComponent
        case .dmgBackground:
            distributionProject.diskImage.backgroundAssetName = url.lastPathComponent
        case .dmgVolumeIcon:
            distributionProject.diskImage.volumeIconAssetName = url.lastPathComponent
        }
        scheduleProjectSave()
    }

    private func removeAsset(_ kind: DistributionAssetKind) {
        distributionAssets[kind] = nil
        switch kind {
        case .pkgBackground:
            distributionProject.installer.backgroundAssetName = nil
        case .dmgBackground:
            distributionProject.diskImage.backgroundAssetName = nil
        case .dmgVolumeIcon:
            distributionProject.diskImage.volumeIconAssetName = nil
        }
        scheduleProjectSave()
    }
    
    private func checkIfAlreadySigned(path: String) {
        Task {
            do {
                let targetURL = URL(fileURLWithPath: path)
                let isValid: Bool
                if targetURL.pathExtension.lowercased() == "pkg" {
                    let (status, _) = try ShellManager.shared.runSync(
                        executable: "/usr/sbin/pkgutil",
                        arguments: ["--check-signature", path]
                    )
                    isValid = status == 0
                } else {
                    let targets = try CodeSigningSupport.signingTargets(in: targetURL)
                    isValid = try targets.allSatisfy { target in
                        var arguments = ["--verify", "--strict"]
                        if target.path == targetURL.path {
                            arguments.append("--deep")
                        }
                        arguments.append(target.path)
                        let (status, _) = try ShellManager.shared.runSync(
                            executable: "/usr/bin/codesign",
                            arguments: arguments
                        )
                        return status == 0
                    }
                }
                await MainActor.run {
                    self.isAlreadySigned = isValid
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

        if file.pathExtension.lowercased() == "app", packageToPkg || packageToDmg || packageToZip {
            projectSaveTask?.cancel()
            saveDistributionProject(for: file)
        }
        
        Task {
            await service.startWorkflow(
                fileUrl: file,
                signAppIdentity: signAppBundle ? selectedAppIdentity : nil,
                packageToPkg: packageToPkg,
                signPkgIdentity: shouldSignInstallerPackage ? selectedPkgIdentity : nil,
                packageToDmg: packageToDmg,
                packageToZip: packageToZip,
                distributionProject: distributionProject,
                distributionAssets: distributionAssets,
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
