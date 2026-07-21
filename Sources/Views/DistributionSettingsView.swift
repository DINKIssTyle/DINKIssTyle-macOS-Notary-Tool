import AppKit
import SwiftUI

struct InstallerCustomizationView: View {
    @Binding var settings: InstallerSettings
    let backgroundURL: URL?
    let chooseBackground: () -> Void
    let removeBackground: () -> Void

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

            installerPage("Welcome", isOn: $settings.showWelcome, text: $settings.welcomeText)
            installerPage("Read Me", isOn: $settings.showReadMe, text: $settings.readMeText)
            installerPage("License", isOn: $settings.showLicense, text: $settings.licenseText)
            installerPage("Conclusion", isOn: $settings.showConclusion, text: $settings.conclusionText)

            Divider()
            AssetPickerRow(
                title: "Installer Background",
                subtitle: "PNG, JPEG, TIFF",
                selectedURL: backgroundURL,
                choose: chooseBackground,
                remove: removeBackground
            )
            ReadOnlyTemplateButton(fileName: "PKG-Installer-BG-TEMP.psd")

            if backgroundURL != nil {
                HStack(spacing: 8) {
                    compactPicker("Alignment", selection: $settings.backgroundAlignment)
                    compactPicker("Scaling", selection: $settings.backgroundScaling)
                }
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
    }

    @ViewBuilder
    private func installerPage(_ title: String, isOn: Binding<Bool>, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: isOn)
                .font(.system(size: 10, weight: .medium))
            if isOn.wrappedValue {
                TextEditor(text: text)
                    .font(.system(size: 10))
                    .frame(height: title == "License" ? 90 : 62)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.18)))
            }
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

struct DiskImageCustomizationView: View {
    @Binding var settings: DiskImageSettings
    let canUseInstallerPackage: Bool
    let backgroundURL: URL?
    let volumeIconURL: URL?
    let chooseBackground: () -> Void
    let removeBackground: () -> Void
    let chooseVolumeIcon: () -> Void
    let removeVolumeIcon: () -> Void

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
                    ForEach(DiskImageLayoutTemplate.allCases, id: \.self) { template in
                        Text(template.title).tag(template)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: settings.layoutTemplate) { _ in
                    settings.applyLayoutTemplate()
                }
                if let templateFileName {
                    ReadOnlyTemplateButton(fileName: templateFileName)
                }
            }

            HStack(spacing: 8) {
                integerField("Window Width", value: $settings.windowWidth)
                integerField("Window Height", value: $settings.windowHeight)
                integerField("Icon Size", value: $settings.iconSize)
            }
            .disabled(!isCustomLayout)

            AssetPickerRow(
                title: "Window Background",
                subtitle: "PNG, JPEG, TIFF",
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
    }

    private var isCustomLayout: Bool {
        settings.layoutTemplate == .custom
    }

    private var templateFileName: String? {
        switch settings.layoutTemplate {
        case .template1: return "DMG-BG-TEMP1.psd"
        case .template2: return "DMG-BG-TEMP2.psd"
        case .custom: return nil
        }
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

private struct ReadOnlyTemplateButton: View {
    let fileName: String

    var body: some View {
        Button(action: openDocument) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.app")
                Text("Edit \(fileName) as an easy starting point for your background (opens read-only).")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9))
        .foregroundStyle(documentURL == nil ? Color.secondary : Color.accentColor)
        .disabled(documentURL == nil)
    }

    private var documentURL: URL? {
        let name = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        return Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Templates"
        )
    }

    private func openDocument() {
        guard let documentURL else { return }
        NSWorkspace.shared.open(documentURL)
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
