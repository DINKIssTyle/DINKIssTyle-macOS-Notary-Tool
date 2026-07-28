import SwiftUI
import UniformTypeIdentifiers

private enum NotaryPreferenceKeys {
    static let credentialType = "preferred_notary_credential_type"
    static let keychainProfile = "preferred_notary_keychain_profile"
}

private final class NotaryInputOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values?.isDirectory == true, values?.isPackage != true {
            return true
        }
        return ["app", "pkg", "dnt"].contains(url.pathExtension.lowercased())
    }
}

enum WorkflowSigningPolicy {
    static func shouldSignInstaller(buildInstaller: Bool, notarize: Bool) -> Bool {
        buildInstaller && notarize
    }

    static func shouldSignDiskImage(
        buildDiskImage: Bool,
        notarize: Bool,
        requested: Bool
    ) -> Bool {
        buildDiskImage && (notarize || requested)
    }
}

struct NotaryView: View {
    @EnvironmentObject var service: NotaryService
    @EnvironmentObject private var documentOpenCoordinator: DocumentOpenCoordinator
    
    // File drop state
    @State private var selectedFile: URL? = nil
    @State private var selectedFileIcon: NSImage? = nil
    @State private var isTargeted: Bool = false
    
    // Core parameters
    @State private var appProcessingMode: AppProcessingMode = .preserveExisting
    @State private var notarizeApp: Bool = false
    @State private var notarizeSelectedPackage: Bool = true
    @State private var selectedAppIdentity: String = ""
    
    @State private var distributionProject = DistributionProject()
    @State private var distributionAssets: [DistributionAssetKind: URL] = [:]
    @State private var projectSaveTask: Task<Void, Never>?
    @State private var projectIsReady = false
    @State private var hasProjectArchive = false
    @State private var projectStatus = ""
    @State private var pkgOptionsExpanded = true
    @State private var dmgOptionsExpanded = true
    @State private var pendingProjectArchiveURL: URL?
    @State private var pendingProjectTargetRelink = false
    @State private var activeProjectArchiveURL: URL?
    @State private var lastHandledDocumentRequestID: UUID?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    
    // Credentials selection
    @State private var credentialType: CredentialType = .keychainProfile
    @State private var selectedProfile: String = ""
    @State private var isAlreadySigned: Bool = false
    @State private var signatureCheckCompleted: Bool = false
    
    // API Key credentials
    @State private var apiKeyId: String = ""
    @State private var apiIssuerId: String = ""
    @State private var apiKeyPath: String = ""
    @State private var credentialsExpanded = false
    
    var body: some View {
        EqualPanelSplitView {
            // Left Column: Drop Area & Configuration
            VStack(spacing: 16) {
                fileDropArea
                
                if selectedFile != nil {
                    verificationBanner
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        codeSignSection
                        packagingSection
                        if requiresNotaryCredentials {
                            credentialsSection
                        }
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
            restoreNotaryCredentialPreference()
            handlePendingDocumentRequest(documentOpenCoordinator.request)
        }
        .onChange(of: service.keychainProfiles) { _ in
            selectPreferredNotaryProfileIfNeeded()
        }
        .onChange(of: selectedProfile) { profile in
            guard !profile.isEmpty else { return }
            UserDefaults.standard.set(profile, forKey: NotaryPreferenceKeys.keychainProfile)
        }
        .onChange(of: credentialType) { type in
            UserDefaults.standard.set(type.rawValue, forKey: NotaryPreferenceKeys.credentialType)
            if type == .keychainProfile {
                selectPreferredNotaryProfileIfNeeded()
            }
        }
        .onChange(of: appProcessingMode) { mode in
            notarizeApp = mode == .resignApp
        }
        .onChange(of: selectedFile) { file in
            let projectArchiveURL = pendingProjectArchiveURL
            let shouldRelinkTarget = pendingProjectTargetRelink
            pendingProjectArchiveURL = nil
            pendingProjectTargetRelink = false
            loadWorkflow(for: file, projectArchiveURL: projectArchiveURL)
            if shouldRelinkTarget, let file {
                saveDistributionProject(for: file)
            }
        }
        .onChange(of: distributionProject) { _ in
            scheduleProjectSave()
        }
        .onReceive(documentOpenCoordinator.$request) { request in
            handlePendingDocumentRequest(request)
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                Label(toastMessage, systemImage: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var fileDropArea: some View {
        Group {
            if let file = selectedFile {
                HStack(spacing: 12) {
                    Group {
                        if let selectedFileIcon {
                            Image(nsImage: selectedFileIcon)
                                .resizable()
                                .scaledToFit()
                                .accessibilityLabel(Text("\(file.lastPathComponent) icon"))
                        } else {
                            Image(systemName: file.pathExtension.lowercased() == "pkg" ? "shippingbox.fill" : "macwindow.on.rectangle")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(width: 42, height: 42)
                    
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
                Button(action: chooseNotaryTarget) {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(isTargeted ? .blue : .secondary)

                        Text("Drag & Drop .app, .pkg, or .dnt")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("or click to choose from Finder")
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
                }
                .buttonStyle(.plain)
                .help("Choose a macOS app, installer package, or DKST Notary project")
                .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                        if let data = data as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            let ext = url.pathExtension.lowercased()
                            if ext == "app" || ext == "pkg" || ext == "dnt" {
                                DispatchQueue.main.async {
                                    self.openNotaryInput(url)
                                }
                            }
                        }
                    }
                    return true
                }
            }
        }
    }

    private func chooseNotaryTarget() {
        let panel = NSOpenPanel()
        let panelDelegate = NotaryInputOpenPanelDelegate()
        panel.title = "Choose App, Installer Package, or Project"
        panel.message = "Choose a macOS application (.app), installer package (.pkg), or DKST Notary project (.dnt)."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [
            .applicationBundle,
            UTType(filenameExtension: "pkg"),
            UTType(exportedAs: "com.dinkisstyle.notarytool.dnt-project", conformingTo: .package)
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.delegate = panelDelegate

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openNotaryInput(url)
    }

    private func openNotaryInput(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "app", "pkg":
            guard isSupportedProjectTarget(url) else {
                showProjectAlert(
                    title: "Unsupported Target",
                    message: "Choose an existing macOS application (.app) or installer package (.pkg)."
                )
                return
            }
            selectedFile = url
        case "dnt":
            openProjectArchive(url)
        default:
            showProjectAlert(
                title: "Unsupported File",
                message: "Choose a .app, .pkg, or .dnt file."
            )
        }
    }
    
    private var codeSignSection: some View {
        let fileType = selectedFile?.pathExtension.lowercased() ?? "app"
        let isApp = fileType == "app"
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(isApp ? "Application Processing" : "Package Processing", systemImage: "signature")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if isApp {
                Picker("", selection: $appProcessingMode) {
                    ForEach(AppProcessingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(appProcessingMode == .preserveExisting
                     ? "Keep the exported app untouched. Its existing signature and stapled notarization ticket must validate."
                     : (notarizeApp
                        ? "Re-sign and notarize the app again before creating distribution files."
                        : "Re-sign the app before creating local distribution files."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Toggle("Notarize & Staple Selected PKG", isOn: $notarizeSelectedPackage)
                    .font(.system(size: 10, weight: .medium))

                Text("The existing package is submitted as-is. Its contents are not rebuilt or modified.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if isApp && signAppBundle {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Notarize Re-signed App", isOn: $notarizeApp)
                        .font(.system(size: 10, weight: .medium))

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
                        if packageToPkg {
                            Text(notarizeInstaller ? "Sign + Notarize" : "Local")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(notarizeInstaller ? Color.green : Color.secondary)
                        }
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
                        Toggle(
                            "Sign & Notarize PKG",
                            isOn: $distributionProject.installer.notarize
                        )
                        .font(.system(size: 10, weight: .medium))

                        if shouldSignInstallerPackage {
                            VStack(alignment: .leading, spacing: 4) {
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
                            removeBackground: { removeAsset(.pkgBackground) },
                            editTemplate: openProjectTemplate
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
                        if packageToDmg {
                            Text(notarizeDiskImage ? "Sign + Notarize" : "Local")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(notarizeDiskImage ? Color.green : Color.secondary)
                        }
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
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "Sign & Notarize DMG",
                            isOn: $distributionProject.diskImage.notarize
                        )
                        .font(.system(size: 10, weight: .medium))
                        .onChange(of: distributionProject.diskImage.notarize) { enabled in
                            if enabled {
                                distributionProject.diskImage.signDiskImage = true
                            }
                        }

                        HStack {
                            Toggle(
                                "Sign Disk Image",
                                isOn: $distributionProject.diskImage.signDiskImage
                            )
                            .font(.system(size: 10, weight: .medium))
                            .disabled(notarizeDiskImage)

                            Spacer()

                            if notarizeDiskImage {
                                Text("Required for notarization")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if shouldSignDiskImage {
                            Text("Developer ID Application Certificate")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)

                            if service.appIdentities.isEmpty {
                                Text("No Developer ID Application certificates found in keychain.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.red)
                            } else {
                                Picker("", selection: $distributionProject.diskImage.signingIdentity) {
                                    Text("Select certificate...").tag("")
                                    ForEach(service.appIdentities, id: \.self) { cert in
                                        Text(cert).tag(cert)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .controlSize(.small)
                            }
                        }

                        Text("The disk image is signed independently. The app inside it is not re-signed or modified.")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)

                    Divider()

                    DiskImageCustomizationView(
                        settings: $distributionProject.diskImage,
                        canUseInstallerPackage: packageToPkg,
                        backgroundURL: distributionAssets[.dmgBackground],
                        volumeIconURL: distributionAssets[.dmgVolumeIcon],
                        chooseBackground: { selectAsset(.dmgBackground) },
                        removeBackground: { removeAsset(.dmgBackground) },
                        chooseVolumeIcon: { selectAsset(.dmgVolumeIcon) },
                        removeVolumeIcon: { removeAsset(.dmgVolumeIcon) },
                        editTemplate: openProjectTemplate
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
                    if packageToZip {
                        Text("Contains \(zipPayloadLabel)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
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
            if isApp && packageToZip {
                Text("Created last. The ZIP contains the final \(zipPayloadLabel) artifact.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack {
                Label("Notarization Account", systemImage: "key.viewfinder")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(credentialsExpanded ? "Done" : "Change…") {
                    withAnimation {
                        credentialsExpanded.toggle()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            if hasValidNotaryCredentials {
                Label(notaryCredentialSummary, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Label("Choose an account before starting", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }

            Text("Used for: \(notarizationTargetSummary)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if credentialsExpanded || !hasValidNotaryCredentials {
                Divider()

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
        .onAppear {
            if !hasValidNotaryCredentials {
                credentialsExpanded = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var signAppBundle: Bool { appProcessingMode == .resignApp }
    private var packageToPkg: Bool { distributionProject.buildInstaller }
    private var selectedPkgIdentity: String { distributionProject.installerIdentity }
    private var packageToDmg: Bool { distributionProject.buildDiskImage }
    private var packageToZip: Bool { distributionProject.buildZipArchive }
    private var zipPayloadLabel: String {
        switch DistributionPipelinePolicy.zipPayload(
            buildInstaller: packageToPkg,
            buildDiskImage: packageToDmg
        ) {
        case .app: return "APP"
        case .installerPackage: return "PKG"
        case .diskImage: return "DMG"
        }
    }
    private var shouldSignInstallerPackage: Bool {
        WorkflowSigningPolicy.shouldSignInstaller(
            buildInstaller: packageToPkg,
            notarize: notarizeInstaller
        )
    }
    private var shouldSignDiskImage: Bool {
        WorkflowSigningPolicy.shouldSignDiskImage(
            buildDiskImage: packageToDmg,
            notarize: notarizeDiskImage,
            requested: distributionProject.diskImage.signDiskImage
        )
    }
    private var notarizeInstaller: Bool {
        packageToPkg && distributionProject.installer.notarize
    }
    private var notarizeDiskImage: Bool {
        packageToDmg && distributionProject.diskImage.notarize
    }
    private var notarizeDirectPackage: Bool {
        selectedFile?.pathExtension.lowercased() == "pkg" && notarizeSelectedPackage
    }
    private var requiresNotaryCredentials: Bool {
        notarizeApp || notarizeInstaller || notarizeDiskImage || notarizeDirectPackage
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
            guard signAppBundle || requiresNotaryCredentials || hasDistributionSelection else { return true }

            if appProcessingMode == .preserveExisting && !isAlreadySigned {
                return true
            }

            if signAppBundle && selectedAppIdentity.isEmpty {
                return true
            }

            if shouldSignInstallerPackage && selectedPkgIdentity.isEmpty {
                return true
            }

            if shouldSignDiskImage && distributionProject.diskImage.signingIdentity.isEmpty {
                return true
            }

            if requiresNotaryCredentials {
                guard signAppBundle || isAlreadySigned else { return true }
                return !hasValidNotaryCredentials
            }

            return false
        }

        guard notarizeDirectPackage else { return true }
        return !hasValidNotaryCredentials
    }

    private var hasDistributionSelection: Bool {
        packageToPkg || packageToDmg || packageToZip
    }

    private var hasValidNotaryCredentials: Bool {
        if credentialType == .keychainProfile {
            return service.keychainProfiles.contains(selectedProfile)
        }
        return !apiKeyId.isEmpty && !apiIssuerId.isEmpty && !apiKeyPath.isEmpty
    }

    private var notaryCredentialSummary: String {
        switch credentialType {
        case .keychainProfile:
            return "Keychain Profile: \(selectedProfile)"
        case .apiKey:
            return "App Store Connect API Key: \(apiKeyId)"
        }
    }

    private var notarizationTargetSummary: String {
        var targets: [String] = []
        if notarizeApp { targets.append("re-signed app") }
        if notarizeInstaller { targets.append("PKG") }
        if notarizeDiskImage { targets.append("DMG") }
        if notarizeDirectPackage { targets.append("selected PKG") }
        return targets.joined(separator: ", ")
    }

    private var actionButtonTitle: String {
        guard let selectedFile else { return "Choose an Action" }
        guard selectedFile.pathExtension.lowercased() == "app" else {
            return notarizeDirectPackage ? "Notarize Selected PKG" : "Choose an Action"
        }

        let selectedOutputCount = [packageToPkg, packageToDmg, packageToZip].filter { $0 }.count
        if selectedOutputCount == 1, packageToPkg {
            return notarizeInstaller ? "Create & Notarize PKG" : "Create PKG"
        }
        if selectedOutputCount == 1, packageToDmg {
            return notarizeDiskImage ? "Create & Notarize DMG" : "Create DMG"
        }
        if selectedOutputCount == 1, packageToZip {
            return notarizeApp ? "Notarize App & Create ZIP" : "Create ZIP"
        }
        if selectedOutputCount > 1 {
            return requiresNotaryCredentials ? "Create & Notarize Distribution" : "Create Distribution"
        }
        if signAppBundle {
            return notarizeApp ? "Re-sign & Notarize App" : "Re-sign App"
        }
        return "Choose an Action"
    }

    private var actionButtonIcon: String {
        guard selectedFile != nil else { return "slider.horizontal.3" }
        if requiresNotaryCredentials {
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

    private func restoreNotaryCredentialPreference() {
        if let rawValue = UserDefaults.standard.string(forKey: NotaryPreferenceKeys.credentialType),
           let savedType = CredentialType(rawValue: rawValue) {
            credentialType = savedType
        }
        selectPreferredNotaryProfileIfNeeded()
    }

    private func selectPreferredNotaryProfileIfNeeded() {
        guard credentialType == .keychainProfile else { return }
        if service.keychainProfiles.contains(selectedProfile) {
            return
        }

        let preferred = UserDefaults.standard.string(
            forKey: NotaryPreferenceKeys.keychainProfile
        )
        if let preferred, service.keychainProfiles.contains(preferred) {
            selectedProfile = preferred
        } else if service.keychainProfiles.count == 1 {
            selectedProfile = service.keychainProfiles[0]
        } else {
            selectedProfile = ""
            if requiresNotaryCredentials {
                credentialsExpanded = true
            }
        }
    }
    
    private func resetWorkflowState() {
        service.clearLogs()
        appProcessingMode = .preserveExisting
        notarizeApp = false
        notarizeSelectedPackage = true
        isAlreadySigned = false
        signatureCheckCompleted = false
    }

    private func loadWorkflow(for file: URL?, projectArchiveURL: URL? = nil) {
        projectSaveTask?.cancel()
        projectIsReady = false
        resetWorkflowState()
        selectedFileIcon = file.map { NSWorkspace.shared.icon(forFile: $0.path) }
        distributionAssets = [:]
        hasProjectArchive = false
        projectStatus = ""
        activeProjectArchiveURL = nil

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
                hasProjectArchive = true
                let loadedArchiveURL = projectArchiveURL ?? DistributionProjectArchive.archiveURL(for: file)
                activeProjectArchiveURL = loadedArchiveURL
                projectStatus = "Loaded \(loadedArchiveURL.lastPathComponent)"
            } else {
                distributionProject = isApp ? defaultProject(for: file) : DistributionProject()
                if isApp {
                    chooseInitialProjectLocationIfNeeded(for: file)
                }
            }
        } catch {
            distributionProject = isApp ? defaultProject(for: file) : DistributionProject()
            projectStatus = "Could not load .dnt"
            service.appendLog("Project load error: \(error.localizedDescription)")
            if isApp {
                chooseInitialProjectLocationIfNeeded(for: file)
            }
        }

        applySingleAvailableSigningIdentities()

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
        let loadedProject: LoadedDistributionProject
        do {
            loadedProject = try DistributionProjectArchive.load(from: archiveURL)
        } catch {
            showProjectAlert(
                title: "Unable to Open Project",
                message: "\(archiveURL.lastPathComponent) is not a valid DKST Notary project.\n\n\(error.localizedDescription)"
            )
            service.appendLog("Project open error: \(error.localizedDescription)")
            return
        }
        let savedTargetURL = DistributionProjectArchive.targetURL(for: loadedProject.project)
        let targetURL = savedTargetURL.flatMap { savedURL in
            isSupportedProjectTarget(savedURL) ? savedURL : nil
        }

        if let targetURL {
            selectProjectTarget(targetURL, archiveURL: archiveURL, shouldRelinkTarget: false)
        } else {
            chooseProjectTarget(for: archiveURL, expectedTargetURL: savedTargetURL)
        }
    }

    private func isSupportedProjectTarget(_ url: URL) -> Bool {
        let targetExtension = url.pathExtension.lowercased()
        var isDirectory: ObjCBool = false
        guard ["app", "pkg"].contains(targetExtension),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return targetExtension != "app" || isDirectory.boolValue
    }

    private func chooseProjectTarget(for archiveURL: URL, expectedTargetURL: URL?) {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Target"
        panel.message = "Choose the .app or .pkg associated with \(archiveURL.lastPathComponent)."
        panel.prompt = "Choose"
        if let expectedDirectory = expectedTargetURL?.deletingLastPathComponent(),
           FileManager.default.fileExists(atPath: expectedDirectory.path) {
            panel.directoryURL = expectedDirectory
        } else {
            panel.directoryURL = archiveURL.deletingLastPathComponent()
        }
        panel.allowedContentTypes = [
            .applicationBundle,
            UTType(filenameExtension: "pkg")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let targetURL = panel.url else {
            resetToInitialScreen()
            return
        }
        let targetExtension = targetURL.pathExtension.lowercased()
        guard targetExtension == "app" || targetExtension == "pkg" else {
            showProjectAlert(
                title: "Unsupported Target",
                message: "Choose a macOS application (.app) or installer package (.pkg)."
            )
            return
        }

        selectProjectTarget(targetURL, archiveURL: archiveURL, shouldRelinkTarget: true)
    }

    private func resetToInitialScreen() {
        pendingProjectArchiveURL = nil
        pendingProjectTargetRelink = false
        if selectedFile == nil {
            loadWorkflow(for: nil)
        } else {
            selectedFile = nil
        }
    }

    private func selectProjectTarget(
        _ targetURL: URL,
        archiveURL: URL,
        shouldRelinkTarget: Bool
    ) {
        if selectedFile?.standardizedFileURL == targetURL.standardizedFileURL {
            loadWorkflow(for: targetURL, projectArchiveURL: archiveURL)
            if shouldRelinkTarget {
                saveDistributionProject(for: targetURL)
            }
        } else {
            pendingProjectArchiveURL = archiveURL
            pendingProjectTargetRelink = shouldRelinkTarget
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

    private func applySingleAvailableSigningIdentities() {
        if selectedAppIdentity.isEmpty, service.appIdentities.count == 1 {
            selectedAppIdentity = service.appIdentities[0]
        }
        if distributionProject.installerIdentity.isEmpty,
           service.installerIdentities.count == 1 {
            distributionProject.installerIdentity = service.installerIdentities[0]
        }
        if distributionProject.diskImage.signingIdentity.isEmpty,
           service.appIdentities.count == 1 {
            distributionProject.diskImage.signingIdentity = service.appIdentities[0]
        }
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

    @discardableResult
    private func saveDistributionProject(for appURL: URL) -> URL? {
        if activeProjectArchiveURL == nil,
           DistributionProjectLocationPolicy.requiresUserSelectedLocation(for: appURL) {
            guard let selectedURL = chooseProjectArchiveLocation(for: appURL) else {
                projectStatus = "Project save cancelled"
                return nil
            }
            activeProjectArchiveURL = selectedURL
        }

        do {
            let url = try DistributionProjectArchive.save(
                distributionProject,
                for: appURL,
                at: activeProjectArchiveURL,
                assetSources: distributionAssets
            )
            activeProjectArchiveURL = url
            hasProjectArchive = true
            projectStatus = "Saved \(url.lastPathComponent)"
            return url
        } catch {
            projectStatus = "Project save failed"
            service.appendLog("Project save error: \(error.localizedDescription)")
            return nil
        }
    }

    private func chooseInitialProjectLocationIfNeeded(for appURL: URL) {
        guard DistributionProjectLocationPolicy.requiresUserSelectedLocation(for: appURL) else { return }
        if let selectedURL = chooseProjectArchiveLocation(for: appURL) {
            activeProjectArchiveURL = selectedURL
            projectStatus = "Project will be saved to \(selectedURL.lastPathComponent)"
        } else {
            projectStatus = "Choose a project location before saving"
        }
    }

    private func chooseProjectArchiveLocation(for appURL: URL) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Choose Project Location"
        panel.message = "The selected app is in an Applications folder. Choose where to save its DKST Notary project."
        panel.prompt = "Save"
        panel.nameFieldStringValue = appURL.deletingPathExtension().lastPathComponent + ".dnt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "dnt")].compactMap { $0 }
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, var url = panel.url else { return nil }
        if url.pathExtension.lowercased() != "dnt" {
            url.appendPathExtension("dnt")
        }
        return url
    }

    private func openProjectTemplate(_ fileName: String) {
        guard let targetURL = selectedFile,
              targetURL.pathExtension.lowercased() == "app" else { return }

        projectSaveTask?.cancel()
        if fileName == DistributionProjectArchive.pkgTemplateName {
            distributionAssets[.pkgBackground] = nil
            distributionProject.installer.backgroundAssetName = nil
        } else {
            distributionAssets[.dmgBackground] = nil
            distributionProject.diskImage.backgroundAssetName = nil
        }
        saveDistributionProject(for: targetURL)
        guard let archiveURL = activeProjectArchiveURL else { return }

        do {
            let templateURL = try DistributionProjectArchive.templateURL(
                named: fileName,
                in: archiveURL
            )
            guard NSWorkspace.shared.open(templateURL) else {
                throw CocoaError(.fileNoSuchFile)
            }
            showToast("Remember to save your PSD changes before building.")
        } catch {
            showProjectAlert(
                title: "Unable to Open Template",
                message: error.localizedDescription
            )
            service.appendLog("Template open error: \(error.localizedDescription)")
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            toastMessage = message
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                toastMessage = nil
            }
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
                    self.signatureCheckCompleted = true
                }
            } catch {
                await MainActor.run {
                    self.isAlreadySigned = false
                    self.signatureCheckCompleted = true
                }
            }
        }
    }
    
    private var verificationBanner: some View {
        let isPkg = selectedFile?.pathExtension.lowercased() == "pkg"
        let itemName = isPkg ? "PKG" : "App"

        return HStack(spacing: 10) {
            Image(systemName: signatureCheckCompleted
                  ? (isAlreadySigned ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                  : "hourglass")
                .font(.system(size: 16))
                .foregroundStyle(signatureCheckCompleted
                                 ? (isAlreadySigned ? Color.green : Color.orange)
                                 : Color.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(signatureCheckCompleted
                     ? (isAlreadySigned ? "Signature Detected" : "Signature Not Valid")
                     : "Checking Signature…")
                    .font(.system(size: 11, weight: .bold))
                Text("Verify the \(itemName) signature, hardened runtime, notarization ticket, and Gatekeeper status.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Verify \(itemName)") {
                if let file = selectedFile {
                    Task {
                        await service.verifyExistingSignature(targetPath: file.path)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
            guard saveDistributionProject(for: file) != nil else { return }
        }

        let usesProjectPSD = (packageToPkg && distributionAssets[.pkgBackground] == nil)
            || (packageToDmg
                && distributionAssets[.dmgBackground] == nil
                && distributionProject.diskImage.layoutTemplate != .custom)
        if usesProjectPSD {
            showToast("Remember to save your PSD changes before building.")
        }

        let project = distributionProject
        let assets = distributionAssets
        let archiveURL = activeProjectArchiveURL
        
        Task {
            let preparedAssets: PreparedDistributionAssets
            do {
                preparedAssets = try DistributionArtworkRenderer.prepare(
                    project: project,
                    assets: assets,
                    projectArchiveURL: archiveURL
                )
            } catch {
                showProjectAlert(
                    title: "Unable to Prepare Background Artwork",
                    message: error.localizedDescription
                )
                service.appendLog("Background artwork error: \(error.localizedDescription)")
                return
            }
            defer {
                if let temporaryDirectory = preparedAssets.temporaryDirectory {
                    try? FileManager.default.removeItem(at: temporaryDirectory)
                }
            }

            await service.startWorkflow(
                fileUrl: file,
                appProcessingMode: appProcessingMode,
                signAppIdentity: signAppBundle ? selectedAppIdentity : nil,
                packageToPkg: packageToPkg,
                signPkgIdentity: shouldSignInstallerPackage ? selectedPkgIdentity : nil,
                packageToDmg: packageToDmg,
                signDmgIdentity: shouldSignDiskImage
                    ? distributionProject.diskImage.signingIdentity
                    : nil,
                packageToZip: packageToZip,
                distributionProject: project,
                distributionAssets: preparedAssets.assets,
                notarizeApp: notarizeApp,
                notarizePkg: notarizeInstaller || notarizeDirectPackage,
                notarizeDmg: notarizeDiskImage,
                credentialType: credentialType,
                keychainProfile: selectedProfile,
                apiKeyId: apiKeyId,
                apiIssuerId: apiIssuerId,
                apiKeyPath: apiKeyPath
            )
        }
    }
}
