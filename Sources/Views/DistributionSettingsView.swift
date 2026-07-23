import AppKit
import SwiftUI

private enum InstallerPageKind: String, Identifiable {
    case welcome
    case readMe
    case license
    case conclusion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .readMe: return "Read Me"
        case .license: return "License"
        case .conclusion: return "Conclusion"
        }
    }
}

struct InstallerCustomizationView: View {
    @Binding var settings: InstallerSettings
    let backgroundURL: URL?
    let chooseBackground: () -> Void
    let removeBackground: () -> Void
    let editTemplate: (String) -> Void
    @State private var editingPage: InstallerPageKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                compactTextField("Installer Title", text: $settings.title, prompt: "App name")

                HStack(spacing: 8) {
                    compactTextField("Package Identifier", text: $settings.identifier, prompt: "From app bundle")
                    compactTextField("Version", text: $settings.version, prompt: "From app bundle")
                        .frame(width: 105)
                }
            }

            Divider()
            Text("Installer Pages")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("RTF and RTFD are supported. Paste rich text with embedded images into the fields below.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            installerPage(
                .welcome, isOn: $settings.showWelcome,
                text: $settings.welcomeText, rtfData: $settings.welcomeRTF
            )
            installerPage(
                .readMe, isOn: $settings.showReadMe,
                text: $settings.readMeText, rtfData: $settings.readMeRTF
            )
            installerPage(
                .license, isOn: $settings.showLicense,
                text: $settings.licenseText, rtfData: $settings.licenseRTF
            )
            installerPage(
                .conclusion, isOn: $settings.showConclusion,
                text: $settings.conclusionText, rtfData: $settings.conclusionRTF
            )

            Divider()
            AssetPickerRow(
                title: "Installer Background Override",
                subtitle: "Uses the project PSD by default",
                selectedURL: backgroundURL,
                choose: chooseBackground,
                remove: removeBackground
            )
            ProjectTemplateButton(
                fileName: DistributionProjectArchive.pkgTemplateName,
                open: editTemplate
            )

            HStack(spacing: 8) {
                compactPicker("Alignment", selection: $settings.backgroundAlignment)
                compactPicker("Scaling", selection: $settings.backgroundScaling)
            }

            compactPicker("After Installation", selection: $settings.conclusionAction)

            Divider()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    compactPicker("Installation Scope", selection: $settings.installationDomain)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Install Location")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            if settings.installationDomain == .currentUserHome {
                                Text("~")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            TextField("/Applications", text: $settings.installLocation)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10))
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced Options")
                    .font(.system(size: 10, weight: .semibold))
            }

            Text("The progress and summary pages are controlled by macOS Installer. The optional content pages above are included only when enabled.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .padding(.top, 2)
        .sheet(item: $editingPage) { page in
            InstallerPageEditorSheet(
                pageTitle: page.title,
                initialText: pageText(page),
                initialRTFData: pageRTFData(page)
            ) { text, rtfData in
                savePage(page, text: text, rtfData: rtfData)
            }
        }
    }

    @ViewBuilder
    private func installerPage(
        _ page: InstallerPageKind,
        isOn: Binding<Bool>,
        text: Binding<String>,
        rtfData: Binding<Data?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Toggle(page.title, isOn: isOn)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                if isOn.wrappedValue {
                    Button("Edit…") {
                        editingPage = page
                    }
                    .controlSize(.small)
                }
            }
            if isOn.wrappedValue {
                RichTextEditor(text: text, rtfData: rtfData, isEditable: false)
                    .frame(height: page == .license ? 90 : 62)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.18)))
            }
        }
    }

    private func pageText(_ page: InstallerPageKind) -> String {
        switch page {
        case .welcome: return settings.welcomeText
        case .readMe: return settings.readMeText
        case .license: return settings.licenseText
        case .conclusion: return settings.conclusionText
        }
    }

    private func pageRTFData(_ page: InstallerPageKind) -> Data? {
        switch page {
        case .welcome: return settings.welcomeRTF
        case .readMe: return settings.readMeRTF
        case .license: return settings.licenseRTF
        case .conclusion: return settings.conclusionRTF
        }
    }

    private func savePage(_ page: InstallerPageKind, text: String, rtfData: Data?) {
        switch page {
        case .welcome:
            settings.welcomeText = text
            settings.welcomeRTF = rtfData
        case .readMe:
            settings.readMeText = text
            settings.readMeRTF = rtfData
        case .license:
            settings.licenseText = text
            settings.licenseRTF = rtfData
        case .conclusion:
            settings.conclusionText = text
            settings.conclusionRTF = rtfData
        }
    }

    private func compactTextField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
        }
    }

    private func compactPicker<T>(_ title: String, selection: Binding<T>) -> some View where T: CaseIterable & Hashable, T.AllCases: RandomAccessCollection, T.AllCases.Element == T {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { value in
                    Text(displayName(value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayName<T>(_ value: T) -> String {
        if let value = value as? InstallerConclusionAction { return value.title }
        if let value = value as? InstallerBackgroundAlignment { return value.title }
        if let value = value as? InstallerBackgroundScaling { return value.title }
        if let value = value as? InstallerInstallationDomain { return value.title }
        return String(describing: value)
    }
}

private struct InstallerPageEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pageTitle: String
    let onSave: (String, Data?) -> Void
    @StateObject private var editingContext = RichTextEditingContext()
    @State private var draftText: String
    @State private var draftRTFData: Data?

    init(
        pageTitle: String,
        initialText: String,
        initialRTFData: Data?,
        onSave: @escaping (String, Data?) -> Void
    ) {
        self.pageTitle = pageTitle
        self.onSave = onSave
        _draftText = State(initialValue: initialText)
        _draftRTFData = State(initialValue: initialRTFData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(pageTitle)")
                .font(.title3)
                .fontWeight(.semibold)

            RichTextFormattingToolbar(context: editingContext)

            RichTextEditor(
                text: $draftText,
                rtfData: $draftRTFData,
                editingContext: editingContext
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.22)))

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(draftText, draftRTFData)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 900, idealWidth: 1020, minHeight: 520, idealHeight: 600)
        .interactiveDismissDisabled()
    }
}

struct DiskImageCustomizationView: View {
    @Binding var settings: DiskImageSettings
    let canUseInstallerPackage: Bool
    let backgroundURL: URL?
    let volumeIconURL: URL?
    let chooseBackground: () -> Void
    let removeBackground: () -> Void
    let chooseVolumeIcon: () -> Void
    let removeVolumeIcon: () -> Void
    let editTemplate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canUseInstallerPackage {
                Toggle("Put Installer Package in DMG", isOn: $settings.includeInstallerPackage)
                    .font(.system(size: 10, weight: .medium))
                Text("Replaces the app bundle in the disk image with the completed .pkg installer.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            labeledTextField("Volume Name", text: $settings.volumeName, prompt: "App name")

            VStack(alignment: .leading, spacing: 4) {
                Text("Layout Preset")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.layoutTemplate) {
                    ForEach(availableTemplates, id: \.self) { template in
                        Text(template.title).tag(template)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: settings.layoutTemplate) { _ in
                    settings.applyLayoutTemplate(singleIcon: isSingleIconLayout)
                }
                if let templateFileName {
                    ProjectTemplateButton(fileName: templateFileName, open: editTemplate)
                }
            }

            HStack(spacing: 8) {
                integerField("Window Width", value: $settings.windowWidth)
                integerField("Window Height", value: $settings.windowHeight)
                integerField("Icon Size", value: $settings.iconSize)
            }
            .disabled(!isCustomLayout)

            AssetPickerRow(
                title: isCustomLayout ? "Window Background" : "Window Background Override",
                subtitle: isCustomLayout ? "PNG, JPEG, TIFF" : "Uses the project PSD by default",
                selectedURL: backgroundURL,
                choose: chooseBackground,
                remove: removeBackground
            )
            AssetPickerRow(
                title: "Mounted Volume Icon",
                subtitle: "ICNS or PNG",
                selectedURL: volumeIconURL,
                choose: chooseVolumeIcon,
                remove: removeVolumeIcon
            )

            Divider()
            if isCustomLayout {
                Toggle(settings.includeInstallerPackage && canUseInstallerPackage ? "Center Installer Icon" : "Center App Icon", isOn: $settings.centerAppIcon)
                    .font(.system(size: 10, weight: .medium))
            }

            if !settings.centerAppIcon {
                HStack(spacing: 8) {
                    integerField(settings.includeInstallerPackage && canUseInstallerPackage ? "Installer X" : "App X", value: $settings.appIconX)
                    integerField(settings.includeInstallerPackage && canUseInstallerPackage ? "Installer Y" : "App Y", value: $settings.appIconY)
                }
                .disabled(!isCustomLayout)
            }

            if !(settings.includeInstallerPackage && canUseInstallerPackage) {
                Toggle("Add Applications Shortcut", isOn: $settings.includeApplicationsLink)
                    .font(.system(size: 10, weight: .medium))
                if settings.includeApplicationsLink {
                    HStack(spacing: 8) {
                        integerField("Applications X", value: $settings.applicationsIconX)
                        integerField("Applications Y", value: $settings.applicationsIconY)
                    }
                    .disabled(!isCustomLayout)
                }
            }

            Text("Coordinates are measured from the top-left of the Finder window. Values outside the window are clamped during the build.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .padding(.top, 2)
        .onAppear(perform: synchronizeLayoutMode)
        .onChange(of: isSingleIconLayout) { _ in
            synchronizeLayoutMode()
        }
    }

    private var isCustomLayout: Bool {
        settings.layoutTemplate == .custom
    }

    private var isSingleIconLayout: Bool {
        (settings.includeInstallerPackage && canUseInstallerPackage) || !settings.includeApplicationsLink
    }

    private var availableTemplates: [DiskImageLayoutTemplate] {
        isSingleIconLayout ? [.template1, .custom] : Array(DiskImageLayoutTemplate.allCases)
    }

    private var templateFileName: String? {
        switch settings.layoutTemplate {
        case .template1: return isSingleIconLayout ? "DMG-BG-TEMP0.psd" : "DMG-BG-TEMP1.psd"
        case .template2: return "DMG-BG-TEMP2.psd"
        case .custom: return nil
        }
    }

    private func synchronizeLayoutMode() {
        if isSingleIconLayout && settings.layoutTemplate == .template2 {
            settings.layoutTemplate = .template1
        }
        settings.applyLayoutTemplate(singleIcon: isSingleIconLayout)
    }

    private func labeledTextField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
        }
    }

    private func integerField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProjectTemplateButton: View {
    let fileName: String
    let open: (String) -> Void

    var body: some View {
        Button { open(fileName) } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.app")
                Text("Edit \(fileName) in this project.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9))
        .foregroundStyle(Color.accentColor)
    }
}

private struct AssetPickerRow: View {
    let title: String
    let subtitle: String
    let selectedURL: URL?
    let choose: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 10, weight: .medium))
                    Text(selectedURL?.lastPathComponent ?? subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(selectedURL == nil ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                Spacer()
                if selectedURL != nil {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Button("Choose…", action: choose)
                    .controlSize(.small)
            }
        }
    }
}
