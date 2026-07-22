import Foundation

public enum DistributionAssetKind: String, CaseIterable, Codable, Hashable, Sendable {
    case pkgBackground
    case dmgBackground
    case dmgVolumeIcon

    var archiveBaseName: String {
        switch self {
        case .pkgBackground: return "pkg-background"
        case .dmgBackground: return "dmg-background"
        case .dmgVolumeIcon: return "volume-icon"
        }
    }
}

public enum InstallerConclusionAction: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case requireLogout
    case requireRestart

    public var title: String {
        switch self {
        case .none: return "No Action"
        case .requireLogout: return "Require Logout"
        case .requireRestart: return "Require Restart"
        }
    }

    var distributionValue: String {
        switch self {
        case .none: return "None"
        case .requireLogout: return "RequireLogout"
        case .requireRestart: return "RequireRestart"
        }
    }
}

public enum InstallerInstallationDomain: String, CaseIterable, Codable, Hashable, Sendable {
    case localSystem
    case currentUserHome

    public var title: String {
        switch self {
        case .localSystem: return "System"
        case .currentUserHome: return "Current User"
        }
    }
}

public enum InstallerBackgroundAlignment: String, CaseIterable, Codable, Hashable, Sendable {
    case center
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var title: String {
        rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }
}

public enum InstallerBackgroundScaling: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case toFit = "tofit"
    case proportional

    public var title: String {
        switch self {
        case .none: return "Actual Size"
        case .toFit: return "Fit"
        case .proportional: return "Proportional"
        }
    }
}

public enum DiskImageLayoutTemplate: String, CaseIterable, Codable, Hashable, Sendable {
    case template1
    case template2
    case custom

    public var title: String {
        switch self {
        case .template1: return "Template 1"
        case .template2: return "Template 2"
        case .custom: return "Custom"
        }
    }

    var preset: DiskImageLayoutPreset? {
        switch self {
        case .template1:
            // Source artwork: 1240 x 830 px at 144 DPI (2x = 620 x 415 pt).
            // Finder's WindowBounds includes its ~32 pt title bar, while Iloc
            // coordinates and the background use the content area.
            return DiskImageLayoutPreset(
                windowWidth: 620, windowHeight: 447, iconSize: 96,
                appIconX: 155, appIconY: 208,
                applicationsIconX: 465, applicationsIconY: 208
            )
        case .template2:
            return DiskImageLayoutPreset(
                windowWidth: 620, windowHeight: 447, iconSize: 96,
                appIconX: 313, appIconY: 104,
                applicationsIconX: 313, applicationsIconY: 312
            )
        case .custom:
            return nil
        }
    }

    func preset(singleIcon: Bool) -> DiskImageLayoutPreset? {
        guard singleIcon else { return preset }
        switch self {
        case .template1, .template2:
            return DiskImageLayoutPreset(
                windowWidth: 620, windowHeight: 447, iconSize: 96,
                appIconX: 313, appIconY: 208,
                applicationsIconX: 313, applicationsIconY: 208
            )
        case .custom:
            return nil
        }
    }
}

struct DiskImageLayoutPreset: Equatable, Sendable {
    let windowWidth: Int
    let windowHeight: Int
    let iconSize: Int
    let appIconX: Int
    let appIconY: Int
    let applicationsIconX: Int
    let applicationsIconY: Int
}

public struct InstallerSettings: Codable, Equatable, Sendable {
    public var title = ""
    public var identifier = ""
    public var version = ""

    public var showWelcome = true
    public var welcomeText = "Welcome to the installer."
    public var welcomeRTF: Data?
    public var showReadMe = false
    public var readMeText = ""
    public var readMeRTF: Data?
    public var showLicense = false
    public var licenseText = ""
    public var licenseRTF: Data?
    public var showConclusion = true
    public var conclusionText = "The installation was successful."
    public var conclusionRTF: Data?

    public var backgroundAssetName: String?
    public var backgroundAlignment: InstallerBackgroundAlignment = .center
    public var backgroundScaling: InstallerBackgroundScaling = .proportional
    public var conclusionAction: InstallerConclusionAction = .none

    public var installationDomain: InstallerInstallationDomain = .localSystem
    public var installLocation = "/Applications"

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case title, identifier, version
        case showWelcome, welcomeText, welcomeRTF, showReadMe, readMeText, readMeRTF
        case showLicense, licenseText, licenseRTF, showConclusion, conclusionText, conclusionRTF
        case backgroundAssetName, backgroundAlignment, backgroundScaling, conclusionAction
        case installationDomain, installLocation
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? title
        identifier = try values.decodeIfPresent(String.self, forKey: .identifier) ?? identifier
        version = try values.decodeIfPresent(String.self, forKey: .version) ?? version
        showWelcome = try values.decodeIfPresent(Bool.self, forKey: .showWelcome) ?? showWelcome
        welcomeText = try values.decodeIfPresent(String.self, forKey: .welcomeText) ?? welcomeText
        welcomeRTF = try values.decodeIfPresent(Data.self, forKey: .welcomeRTF)
        showReadMe = try values.decodeIfPresent(Bool.self, forKey: .showReadMe) ?? showReadMe
        readMeText = try values.decodeIfPresent(String.self, forKey: .readMeText) ?? readMeText
        readMeRTF = try values.decodeIfPresent(Data.self, forKey: .readMeRTF)
        showLicense = try values.decodeIfPresent(Bool.self, forKey: .showLicense) ?? showLicense
        licenseText = try values.decodeIfPresent(String.self, forKey: .licenseText) ?? licenseText
        licenseRTF = try values.decodeIfPresent(Data.self, forKey: .licenseRTF)
        showConclusion = try values.decodeIfPresent(Bool.self, forKey: .showConclusion) ?? showConclusion
        conclusionText = try values.decodeIfPresent(String.self, forKey: .conclusionText) ?? conclusionText
        conclusionRTF = try values.decodeIfPresent(Data.self, forKey: .conclusionRTF)
        backgroundAssetName = try values.decodeIfPresent(String.self, forKey: .backgroundAssetName)
        backgroundAlignment = try values.decodeIfPresent(InstallerBackgroundAlignment.self, forKey: .backgroundAlignment) ?? backgroundAlignment
        backgroundScaling = try values.decodeIfPresent(InstallerBackgroundScaling.self, forKey: .backgroundScaling) ?? backgroundScaling
        conclusionAction = try values.decodeIfPresent(InstallerConclusionAction.self, forKey: .conclusionAction) ?? conclusionAction
        installationDomain = try values.decodeIfPresent(InstallerInstallationDomain.self, forKey: .installationDomain) ?? installationDomain
        installLocation = try values.decodeIfPresent(String.self, forKey: .installLocation) ?? installLocation
    }
}

public struct DiskImageSettings: Codable, Equatable, Sendable {
    public var layoutTemplate: DiskImageLayoutTemplate = .custom
    public var volumeName = ""
    public var windowWidth = 660
    public var windowHeight = 400
    public var iconSize = 96

    public var includeInstallerPackage = false
    public var centerAppIcon = false
    public var appIconX = 180
    public var appIconY = 190
    public var includeApplicationsLink = true
    public var applicationsIconX = 480
    public var applicationsIconY = 190

    public var backgroundAssetName: String?
    public var volumeIconAssetName: String?

    public init() {}

    public mutating func applyLayoutTemplate(singleIcon: Bool = false) {
        guard let preset = layoutTemplate.preset(singleIcon: singleIcon) else { return }
        windowWidth = preset.windowWidth
        windowHeight = preset.windowHeight
        iconSize = preset.iconSize
        centerAppIcon = false
        appIconX = preset.appIconX
        appIconY = preset.appIconY
        if !singleIcon {
            includeApplicationsLink = true
        }
        applicationsIconX = preset.applicationsIconX
        applicationsIconY = preset.applicationsIconY
    }

    private enum CodingKeys: String, CodingKey {
        case layoutTemplate
        case volumeName, windowWidth, windowHeight, iconSize
        case includeInstallerPackage, centerAppIcon, appIconX, appIconY
        case includeApplicationsLink, applicationsIconX, applicationsIconY
        case backgroundAssetName, volumeIconAssetName
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        layoutTemplate = try values.decodeIfPresent(DiskImageLayoutTemplate.self, forKey: .layoutTemplate) ?? .custom
        volumeName = try values.decodeIfPresent(String.self, forKey: .volumeName) ?? volumeName
        windowWidth = try values.decodeIfPresent(Int.self, forKey: .windowWidth) ?? windowWidth
        windowHeight = try values.decodeIfPresent(Int.self, forKey: .windowHeight) ?? windowHeight
        iconSize = try values.decodeIfPresent(Int.self, forKey: .iconSize) ?? iconSize
        includeInstallerPackage = try values.decodeIfPresent(Bool.self, forKey: .includeInstallerPackage) ?? false
        centerAppIcon = try values.decodeIfPresent(Bool.self, forKey: .centerAppIcon) ?? centerAppIcon
        appIconX = try values.decodeIfPresent(Int.self, forKey: .appIconX) ?? appIconX
        appIconY = try values.decodeIfPresent(Int.self, forKey: .appIconY) ?? appIconY
        includeApplicationsLink = try values.decodeIfPresent(Bool.self, forKey: .includeApplicationsLink) ?? includeApplicationsLink
        applicationsIconX = try values.decodeIfPresent(Int.self, forKey: .applicationsIconX) ?? applicationsIconX
        applicationsIconY = try values.decodeIfPresent(Int.self, forKey: .applicationsIconY) ?? applicationsIconY
        backgroundAssetName = try values.decodeIfPresent(String.self, forKey: .backgroundAssetName)
        volumeIconAssetName = try values.decodeIfPresent(String.self, forKey: .volumeIconAssetName)
    }
}

public struct DistributionProject: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion = DistributionProject.currentFormatVersion
    public var buildInstaller = false
    public var signInstaller = false
    public var installerIdentity = ""
    public var buildDiskImage = false
    public var buildZipArchive = false
    public var installer = InstallerSettings()
    public var diskImage = DiskImageSettings()

    public init() {}
}

public struct LoadedDistributionProject {
    public let project: DistributionProject
    public let assets: [DistributionAssetKind: URL]
    public let extractionDirectory: URL
}

public enum DistributionProjectArchive {
    private static let manifestName = "project.json"
    private static let assetsDirectoryName = "Assets"

    public static func archiveURL(for appURL: URL) -> URL {
        appURL.deletingLastPathComponent()
            .appendingPathComponent(appURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("dnt")
    }

    public static func save(
        _ project: DistributionProject,
        for appURL: URL,
        assetSources: [DistributionAssetKind: URL]
    ) throws -> URL {
        let fileManager = FileManager.default
        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("dnt-save-\(UUID().uuidString)", isDirectory: true)
        let assetsDirectory = stagingDirectory.appendingPathComponent(assetsDirectoryName, isDirectory: true)
        let outputURL = archiveURL(for: appURL)
        let temporaryArchive = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")

        defer {
            try? fileManager.removeItem(at: stagingDirectory)
            try? fileManager.removeItem(at: temporaryArchive)
        }

        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        var savedProject = project
        for kind in DistributionAssetKind.allCases {
            guard let sourceURL = assetSources[kind] else {
                setAssetName(nil, kind: kind, project: &savedProject)
                continue
            }

            let fileName = kind.archiveBaseName + "." + sourceURL.pathExtension.lowercased()
            let destinationURL = assetsDirectory.appendingPathComponent(fileName)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            setAssetName(fileName, kind: kind, project: &savedProject)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(savedProject)
        try manifestData.write(to: stagingDirectory.appendingPathComponent(manifestName), options: .atomic)

        let result = try ShellManager.shared.runSync(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", stagingDirectory.path, temporaryArchive.path]
        )
        guard result.status == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: result.output])
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: temporaryArchive)
        } else {
            try fileManager.moveItem(at: temporaryArchive, to: outputURL)
        }
        return outputURL
    }

    public static func load(for appURL: URL) throws -> LoadedDistributionProject? {
        let archiveURL = archiveURL(for: appURL)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else { return nil }

        let extractionDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("dnt-load-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        do {
            let result = try ShellManager.shared.runSync(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path]
            )
            guard result.status == 0 else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: result.output])
            }

            let manifestURL = extractionDirectory.appendingPathComponent(manifestName)
            let project = try JSONDecoder().decode(DistributionProject.self, from: Data(contentsOf: manifestURL))
            guard project.formatVersion <= DistributionProject.currentFormatVersion else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            var assets: [DistributionAssetKind: URL] = [:]
            for kind in DistributionAssetKind.allCases {
                guard let name = assetName(kind: kind, project: project) else { continue }
                let assetURL = extractionDirectory
                    .appendingPathComponent(assetsDirectoryName, isDirectory: true)
                    .appendingPathComponent(name)
                if fileManager.fileExists(atPath: assetURL.path) {
                    assets[kind] = assetURL
                }
            }
            return LoadedDistributionProject(project: project, assets: assets, extractionDirectory: extractionDirectory)
        } catch {
            try? fileManager.removeItem(at: extractionDirectory)
            throw error
        }
    }

    private static func assetName(kind: DistributionAssetKind, project: DistributionProject) -> String? {
        switch kind {
        case .pkgBackground: return project.installer.backgroundAssetName
        case .dmgBackground: return project.diskImage.backgroundAssetName
        case .dmgVolumeIcon: return project.diskImage.volumeIconAssetName
        }
    }

    private static func setAssetName(_ name: String?, kind: DistributionAssetKind, project: inout DistributionProject) {
        switch kind {
        case .pkgBackground: project.installer.backgroundAssetName = name
        case .dmgBackground: project.diskImage.backgroundAssetName = name
        case .dmgVolumeIcon: project.diskImage.volumeIconAssetName = name
        }
    }
}
