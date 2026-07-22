import AppKit
import Foundation
import XCTest
@testable import DKST_macOS_Notary

final class DistributionProjectTests: XCTestCase {
    func testWorkflowButtonTitlesReflectSigningNotarizationAndDistribution() {
        XCTAssertEqual(
            WorkflowActionPresentation.title(
                isApp: true,
                signApp: true,
                notarize: false,
                hasDistribution: false,
                signInstaller: false
            ),
            "Sign App"
        )
        XCTAssertEqual(
            WorkflowActionPresentation.title(
                isApp: true,
                signApp: false,
                notarize: true,
                hasDistribution: false,
                signInstaller: false
            ),
            "Notarize App"
        )
        XCTAssertEqual(
            WorkflowActionPresentation.title(
                isApp: true,
                signApp: true,
                notarize: true,
                hasDistribution: true,
                signInstaller: false
            ),
            "Sign, Notarize & Create Distribution"
        )
        XCTAssertEqual(
            WorkflowActionPresentation.title(
                isApp: true,
                signApp: false,
                notarize: false,
                hasDistribution: true,
                signInstaller: true
            ),
            "Create Signed Distribution"
        )
        XCTAssertEqual(
            WorkflowActionPresentation.title(
                isApp: false,
                signApp: false,
                notarize: false,
                hasDistribution: false,
                signInstaller: false
            ),
            "Choose an Action"
        )
    }

    func testOlderInstallerSettingsUseSystemApplicationsDefaults() throws {
        let settings = try JSONDecoder().decode(InstallerSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.installationDomain, .localSystem)
        XCTAssertEqual(settings.installLocation, "/Applications")
    }

    func testOlderDiskImageSettingsDefaultToAppBundlePayload() throws {
        let settings = try JSONDecoder().decode(DiskImageSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.includeInstallerPackage)
        XCTAssertTrue(settings.includeApplicationsLink)
        XCTAssertEqual(settings.layoutTemplate, .custom)
    }

    func testDiskImageLayoutTemplatesUseHiDPIPointCoordinates() {
        var horizontal = DiskImageSettings()
        horizontal.layoutTemplate = .template1
        horizontal.applyLayoutTemplate()
        XCTAssertEqual(horizontal.windowWidth, 620)
        XCTAssertEqual(horizontal.windowHeight, 447)
        XCTAssertEqual(horizontal.iconSize, 96)
        XCTAssertEqual(horizontal.appIconX, 155)
        XCTAssertEqual(horizontal.appIconY, 208)
        XCTAssertEqual(horizontal.applicationsIconX, 465)
        XCTAssertEqual(horizontal.applicationsIconY, 208)

        var vertical = DiskImageSettings()
        vertical.layoutTemplate = .template2
        vertical.applyLayoutTemplate()
        XCTAssertEqual(vertical.windowWidth, 620)
        XCTAssertEqual(vertical.windowHeight, 447)
        XCTAssertEqual(vertical.iconSize, 96)
        XCTAssertEqual(vertical.appIconX, 313)
        XCTAssertEqual(vertical.appIconY, 104)
        XCTAssertEqual(vertical.applicationsIconX, 313)
        XCTAssertEqual(vertical.applicationsIconY, 312)

        var singleIcon = DiskImageSettings()
        singleIcon.layoutTemplate = .template1
        singleIcon.includeApplicationsLink = false
        singleIcon.applyLayoutTemplate(singleIcon: true)
        XCTAssertEqual(singleIcon.windowWidth, 620)
        XCTAssertEqual(singleIcon.windowHeight, 447)
        XCTAssertEqual(singleIcon.iconSize, 96)
        XCTAssertEqual(singleIcon.appIconX, 313)
        XCTAssertEqual(singleIcon.appIconY, 208)
        XCTAssertFalse(singleIcon.includeApplicationsLink)
    }

    func testPNGCanBeConvertedToICNS() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("icns-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Resources/Appicon.png")
        let outputURL = directory.appendingPathComponent("VolumeIcon.icns")
        try ICNSConverter.convertPNG(at: sourceURL, to: outputURL)

        let data = try Data(contentsOf: outputURL)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "icns")
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertNotNil(NSImage(contentsOf: outputURL))
    }

    func testArchiveRoundTripIncludesAssets() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("dnt-test-\(UUID().uuidString)", isDirectory: true)
        let appURL = directory.appendingPathComponent("Test App.app", isDirectory: true)
        let backgroundURL = directory.appendingPathComponent("chosen-background.png")
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: backgroundURL)

        var project = DistributionProject()
        project.buildInstaller = true
        project.buildDiskImage = true
        project.installer.welcomeRTF = Data(#"{\rtf1\ansi Rich welcome}"#.utf8)
        project.diskImage.volumeName = "Test Volume"
        project.diskImage.windowWidth = 720
        project.diskImage.includeInstallerPackage = true
        project.diskImage.backgroundAssetName = backgroundURL.lastPathComponent

        let archiveURL = try DistributionProjectArchive.save(
            project,
            for: appURL,
            assetSources: [.dmgBackground: backgroundURL]
        )
        XCTAssertEqual(archiveURL.lastPathComponent, "Test App.dnt")

        let loaded = try XCTUnwrap(DistributionProjectArchive.load(for: appURL))
        defer { try? fileManager.removeItem(at: loaded.extractionDirectory) }
        XCTAssertEqual(loaded.project.diskImage.volumeName, "Test Volume")
        XCTAssertEqual(loaded.project.diskImage.windowWidth, 720)
        XCTAssertTrue(loaded.project.diskImage.includeInstallerPackage)
        XCTAssertEqual(loaded.project.installer.welcomeRTF, project.installer.welcomeRTF)
        XCTAssertTrue(fileManager.fileExists(atPath: try XCTUnwrap(loaded.assets[.dmgBackground]).path))
    }

    func testArchiveCanBeLoadedDirectlyFromAStoredCopy() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("dnt-portable-test-\(UUID().uuidString)", isDirectory: true)
        let buildDirectory = directory.appendingPathComponent("Build", isDirectory: true)
        let storageDirectory = directory.appendingPathComponent("Projects", isDirectory: true)
        let appURL = buildDirectory.appendingPathComponent("Portable App.app", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        var project = DistributionProject()
        project.buildDiskImage = true
        project.diskImage.volumeName = "Portable Volume"
        let adjacentArchiveURL = try DistributionProjectArchive.save(project, for: appURL, assetSources: [:])
        let storedArchiveURL = storageDirectory.appendingPathComponent("Portable App.dnt")
        try fileManager.copyItem(at: adjacentArchiveURL, to: storedArchiveURL)

        let loaded = try DistributionProjectArchive.load(from: storedArchiveURL)
        defer { try? fileManager.removeItem(at: loaded.extractionDirectory) }
        XCTAssertEqual(loaded.project.diskImage.volumeName, "Portable Volume")
        XCTAssertTrue(loaded.project.buildDiskImage)
    }

    func testDocumentOpenCoordinatorAcceptsOnlyDNTFiles() {
        let coordinator = DocumentOpenCoordinator()
        coordinator.open(URL(fileURLWithPath: "/tmp/Example.app"))
        XCTAssertNil(coordinator.request)

        coordinator.open(URL(fileURLWithPath: "/tmp/Example.dnt"))
        let request = coordinator.request
        XCTAssertEqual(request?.url.path, "/tmp/Example.dnt")

        if let request {
            coordinator.consume(request.id)
        }
        XCTAssertNil(coordinator.request)
    }

    func testDSStoreWriterCreatesPortableFinderRecords() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("dsstore-test-\(UUID().uuidString)", isDirectory: true)
        let backgroundDirectory = directory.appendingPathComponent(".background", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(at: backgroundDirectory, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: backgroundDirectory.appendingPathComponent("background.png"))
        try Data().write(to: directory.appendingPathComponent("Example.app"))
        try fileManager.createSymbolicLink(
            at: directory.appendingPathComponent("Applications"),
            withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
        )

        let layout = DSStoreWriter.Layout(
            windowWidth: 660,
            windowHeight: 400,
            iconSize: 96,
            payloadName: "Example.app",
            payloadX: 260,
            payloadY: 190,
            includeApplicationsLink: true,
            applicationsX: 480,
            applicationsY: 190,
            backgroundFileName: "background.png"
        )
        try DSStoreWriter.write(to: directory, volumeName: "Portable Test", layout: layout)

        let data = try Data(contentsOf: directory.appendingPathComponent(".DS_Store"))
        let records = try DSStoreWriter.inspect(data)
        XCTAssertTrue(data.starts(with: Data([0, 0, 0, 1]) + Data("Bud1".utf8)))
        XCTAssertTrue(records.contains { $0.fileName == "." && $0.code == "bwsp" })
        XCTAssertTrue(records.contains { $0.fileName == "." && $0.code == "icvp" })
        XCTAssertTrue(records.contains { $0.fileName == "." && $0.code == "icvl" && String(data: $0.data, encoding: .ascii) == "icnv" })
        XCTAssertTrue(records.contains { $0.fileName == "Example.app" && $0.code == "Iloc" })
        XCTAssertTrue(records.contains { $0.fileName == "Applications" && $0.code == "Iloc" })

        let icvp = try XCTUnwrap(records.first { $0.fileName == "." && $0.code == "icvp" })
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: icvp.data, format: nil) as? [String: Any])
        XCTAssertEqual((plist["backgroundType"] as? NSNumber)?.intValue, 2)
        XCTAssertNotNil(plist["backgroundImageAlias"] as? Data)
    }

    @MainActor
    func testCustomizedInstallerCanBeBuilt() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("pkg-test-\(UUID().uuidString)", isDirectory: true)
        let appURL = directory.appendingPathComponent("Test App.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let nestedAppURL = contentsURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Settings.app", isDirectory: true)
        let nestedContentsURL = nestedAppURL.appendingPathComponent("Contents", isDirectory: true)
        let nestedMacOSURL = nestedContentsURL.appendingPathComponent("MacOS", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        let executableURL = macOSURL.appendingPathComponent("TestApp")
        try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")).write(to: executableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.dinkisstyle.tests.test-app",
            "CFBundleName": "Test App",
            "CFBundleExecutable": "TestApp",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "123"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contentsURL.appendingPathComponent("Info.plist"))

        try fileManager.createDirectory(at: nestedMacOSURL, withIntermediateDirectories: true)
        let nestedExecutableURL = nestedMacOSURL.appendingPathComponent("Settings")
        try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")).write(to: nestedExecutableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nestedExecutableURL.path)
        let nestedInfo: [String: Any] = [
            "CFBundleIdentifier": "com.dinkisstyle.tests.test-app.settings",
            "CFBundleName": "Settings",
            "CFBundleExecutable": "Settings",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "123"
        ]
        let nestedPlist = try PropertyListSerialization.data(fromPropertyList: nestedInfo, format: .xml, options: 0)
        try nestedPlist.write(to: nestedContentsURL.appendingPathComponent("Info.plist"))

        var project = DistributionProject()
        project.buildInstaller = true
        project.installer.title = "Test Installer"
        project.installer.identifier = "com.dinkisstyle.tests.test-app.installer"
        project.installer.version = "1.2.3"
        project.installer.showWelcome = true
        project.installer.welcomeText = "Welcome & install <safely>."
        project.installer.showReadMe = true
        project.installer.readMeText = "Read me with an embedded image"
        let richReadMe = NSMutableAttributedString(string: "Embedded image: ")
        let readMeAttachment = NSTextAttachment()
        readMeAttachment.contents = try Data(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/Resources/Appicon.png")
        )
        readMeAttachment.fileType = "public.png"
        richReadMe.append(NSAttributedString(attachment: readMeAttachment))
        project.installer.readMeRTF = try richReadMe.data(
            from: NSRange(location: 0, length: richReadMe.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
        project.installer.showLicense = true
        project.installer.licenseText = "Styled license"
        let styledLicense = NSAttributedString(
            string: project.installer.licenseText,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.systemRed
            ]
        )
        project.installer.licenseRTF = try styledLicense.data(
            from: NSRange(location: 0, length: styledLicense.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        project.installer.conclusionAction = .requireLogout
        project.installer.installationDomain = .currentUserHome
        project.installer.installLocation = "/Library/Input Methods"

        let service = NotaryService()
        await service.startWorkflow(
            fileUrl: appURL,
            signAppIdentity: "-",
            packageToPkg: true,
            signPkgIdentity: nil,
            packageToDmg: false,
            packageToZip: false,
            distributionProject: project,
            distributionAssets: [:],
            performNotarization: false,
            credentialType: .keychainProfile,
            keychainProfile: "",
            apiKeyId: "",
            apiIssuerId: "",
            apiKeyPath: ""
        )

        let packageURL = directory.appendingPathComponent("Test App.pkg")
        XCTAssertTrue(fileManager.fileExists(atPath: packageURL.path), service.logOutput)
        XCTAssertTrue(service.logOutput.contains("Installer destination: Current User ~/Library/Input Methods"), service.logOutput)
        let domainInfo = try ShellManager.shared.runSync(
            executable: "/usr/sbin/installer",
            arguments: ["-dominfo", "-pkg", packageURL.path]
        )
        XCTAssertEqual(domainInfo.status, 0, domainInfo.output)
        XCTAssertTrue(domainInfo.output.contains("CurrentUserHomeDirectory"), domainInfo.output)
        let expandedPackageURL = directory.appendingPathComponent("Expanded.pkg", isDirectory: true)
        let expandResult = try ShellManager.shared.runSync(
            executable: "/usr/sbin/pkgutil",
            arguments: ["--expand", packageURL.path, expandedPackageURL.path]
        )
        XCTAssertEqual(expandResult.status, 0, expandResult.output)
        let distributionXML = try String(
            contentsOf: expandedPackageURL.appendingPathComponent("Distribution"),
            encoding: .utf8
        )
        XCTAssertTrue(distributionXML.contains(#"<license file="license.rtf" mime-type="text/rtf"/>"#), distributionXML)
        XCTAssertTrue(distributionXML.contains(#"<readme file="readme.rtfd" uti="com.apple.rtfd"/>"#), distributionXML)
        let packagedReadMeURL = expandedPackageURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("readme.rtfd", isDirectory: true)
        var isReadMeDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: packagedReadMeURL.path, isDirectory: &isReadMeDirectory))
        XCTAssertTrue(isReadMeDirectory.boolValue)
        let packagedReadMeWrapper = try FileWrapper(url: packagedReadMeURL, options: .immediate)
        let packagedReadMeData = try XCTUnwrap(packagedReadMeWrapper.serializedRepresentation)
        let packagedReadMe = try NSAttributedString(
            data: packagedReadMeData,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        )
        XCTAssertEqual(packagedReadMe.string, "Embedded image: \u{fffc}")
        XCTAssertNotNil(packagedReadMe.attribute(.attachment, at: packagedReadMe.length - 1, effectiveRange: nil))
        let licenseResourceURL = try XCTUnwrap(
            fileManager.enumerator(at: expandedPackageURL, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.lastPathComponent == "license.rtf" }
        )
        let packagedLicense = try NSAttributedString(
            data: Data(contentsOf: licenseResourceURL),
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(packagedLicense.string, "Styled license")
        let packagedFont = try XCTUnwrap(packagedLicense.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: packagedFont).contains(.boldFontMask))
        let packagedColor = try XCTUnwrap(
            (packagedLicense.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
                .usingColorSpace(.sRGB)
        )
        let expectedColor = try XCTUnwrap(NSColor.systemRed.usingColorSpace(.sRGB))
        XCTAssertEqual(packagedColor.redComponent, expectedColor.redComponent, accuracy: 0.01)
        XCTAssertEqual(packagedColor.greenComponent, expectedColor.greenComponent, accuracy: 0.01)
        XCTAssertEqual(packagedColor.blueComponent, expectedColor.blueComponent, accuracy: 0.01)
        let outerVerification = try ShellManager.shared.runSync(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path]
        )
        XCTAssertEqual(outerVerification.status, 0, outerVerification.output)
        let nestedVerification = try ShellManager.shared.runSync(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--strict", nestedAppURL.path]
        )
        XCTAssertEqual(nestedVerification.status, 0, nestedVerification.output)
        XCTAssertTrue(service.logOutput.contains("Signing: Contents/Resources/Settings.app"), service.logOutput)
        XCTAssertTrue(service.logOutput.contains("Embedded 1 RTFD Installer page resource(s)."), service.logOutput)
        XCTAssertEqual(service.currentStep, "Distribution Build Completed", service.logOutput)

        let nestedExecutable = try FileHandle(forWritingTo: nestedExecutableURL)
        try nestedExecutable.seekToEnd()
        try nestedExecutable.write(contentsOf: Data([0]))
        try nestedExecutable.close()
        let outerOnlyResign = try ShellManager.shared.runSync(
            executable: "/usr/bin/codesign",
            arguments: ["--force", "--options", "runtime", "-s", "-", appURL.path]
        )
        XCTAssertEqual(outerOnlyResign.status, 0, outerOnlyResign.output)
        let misleadingOuterVerification = try ShellManager.shared.runSync(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path]
        )
        XCTAssertEqual(misleadingOuterVerification.status, 0, misleadingOuterVerification.output)

        await service.verifyExistingSignature(targetPath: appURL.path)
        XCTAssertEqual(service.verificationItems[0].status, .failure, service.logOutput)
        XCTAssertTrue(service.logOutput.contains("Signature check: Contents/Resources/Settings.app"), service.logOutput)
    }

    @MainActor
    func testCustomizedDiskImageCanBeBuiltWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_DMG_TEST"] == "1" else {
            throw XCTSkip("DMG integration test is opt-in.")
        }

        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("dmg-test-\(UUID().uuidString)", isDirectory: true)
        let appURL = directory.appendingPathComponent("Test App.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let backgroundURL = directory.appendingPathComponent("dmg-background.png")
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        let executableURL = macOSURL.appendingPathComponent("TestApp")
        try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")).write(to: executableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.dinkisstyle.tests.test-app",
            "CFBundleName": "Test App",
            "CFBundleExecutable": "TestApp",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "123"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contentsURL.appendingPathComponent("Info.plist"))
        let sourceImageURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Resources/Appicon.png")
        try Data(contentsOf: sourceImageURL).write(to: backgroundURL)

        var project = DistributionProject()
        project.buildInstaller = true
        project.buildDiskImage = true
        project.diskImage.volumeName = "DKST DMG Test \(UUID().uuidString.prefix(6))"
        project.diskImage.layoutTemplate = .template1
        project.diskImage.applyLayoutTemplate()
        project.diskImage.includeInstallerPackage = true
        project.diskImage.backgroundAssetName = backgroundURL.lastPathComponent
        project.diskImage.volumeIconAssetName = backgroundURL.lastPathComponent

        let service = NotaryService()
        await service.startWorkflow(
            fileUrl: appURL,
            signAppIdentity: nil,
            packageToPkg: true,
            signPkgIdentity: nil,
            packageToDmg: true,
            packageToZip: false,
            distributionProject: project,
            distributionAssets: [.dmgBackground: backgroundURL, .dmgVolumeIcon: backgroundURL],
            performNotarization: false,
            credentialType: .keychainProfile,
            keychainProfile: "",
            apiKeyId: "",
            apiIssuerId: "",
            apiKeyPath: ""
        )

        let imageURL = directory.appendingPathComponent("Test App.dmg")
        XCTAssertTrue(fileManager.fileExists(atPath: imageURL.path), service.logOutput)
        XCTAssertTrue(fileManager.fileExists(atPath: directory.appendingPathComponent("Test App.pkg").path), service.logOutput)
        XCTAssertTrue(service.logOutput.contains("DMG payload: completed installer package"), service.logOutput)
        XCTAssertTrue(service.logOutput.contains("Verified: Finder layout, assets, and volume metadata"), service.logOutput)
        XCTAssertEqual(service.currentStep, "Distribution Build Completed", service.logOutput)
    }
}
