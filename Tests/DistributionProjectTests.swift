import AppKit
import Foundation
import XCTest
@testable import DKST_macOS_Notary

final class DistributionProjectTests: XCTestCase {
    func testOlderDiskImageSettingsDefaultToAppBundlePayload() throws {
        let settings = try JSONDecoder().decode(DiskImageSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.includeInstallerPackage)
        XCTAssertTrue(settings.includeApplicationsLink)
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
        XCTAssertTrue(fileManager.fileExists(atPath: try XCTUnwrap(loaded.assets[.dmgBackground]).path))
    }

    @MainActor
    func testCustomizedInstallerCanBeBuilt() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("pkg-test-\(UUID().uuidString)", isDirectory: true)
        let appURL = directory.appendingPathComponent("Test App.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
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

        var project = DistributionProject()
        project.buildInstaller = true
        project.installer.title = "Test Installer"
        project.installer.identifier = "com.dinkisstyle.tests.test-app.installer"
        project.installer.version = "1.2.3"
        project.installer.showWelcome = true
        project.installer.welcomeText = "Welcome & install <safely>."
        project.installer.showLicense = true
        project.installer.licenseText = "Example license"
        project.installer.conclusionAction = .requireLogout

        let service = NotaryService()
        await service.startWorkflow(
            fileUrl: appURL,
            signAppIdentity: nil,
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
        XCTAssertEqual(service.currentStep, "Distribution Build Completed", service.logOutput)
    }

    @MainActor
    func testCustomizedDiskImageCanBeBuiltWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_DMG_TEST"] == "1" else {
            throw XCTSkip("Finder-driven DMG integration test is opt-in.")
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
        project.diskImage.windowWidth = 540
        project.diskImage.windowHeight = 340
        project.diskImage.centerAppIcon = true
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
        XCTAssertEqual(service.currentStep, "Distribution Build Completed", service.logOutput)
    }
}
