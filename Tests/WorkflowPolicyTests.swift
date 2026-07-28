import XCTest
@testable import DKST_macOS_Notary

final class WorkflowPolicyTests: XCTestCase {
    func testInstallerSigningIsRequiredOnlyForNotarizedInstallerBuilds() {
        XCTAssertTrue(
            WorkflowSigningPolicy.shouldSignInstaller(
                buildInstaller: true,
                notarize: true
            )
        )
        XCTAssertFalse(
            WorkflowSigningPolicy.shouldSignInstaller(
                buildInstaller: true,
                notarize: false
            )
        )
        XCTAssertFalse(
            WorkflowSigningPolicy.shouldSignInstaller(
                buildInstaller: false,
                notarize: true
            )
        )
    }

    func testDiskImageSigningIsRequiredForNotarization() {
        XCTAssertTrue(
            WorkflowSigningPolicy.shouldSignDiskImage(
                buildDiskImage: true,
                notarize: true,
                requested: false
            )
        )
        XCTAssertTrue(
            WorkflowSigningPolicy.shouldSignDiskImage(
                buildDiskImage: true,
                notarize: false,
                requested: true
            )
        )
        XCTAssertFalse(
            WorkflowSigningPolicy.shouldSignDiskImage(
                buildDiskImage: false,
                notarize: true,
                requested: true
            )
        )
    }

    func testPreserveExistingRequiresAValidExistingTicket() {
        XCTAssertEqual(
            WorkflowNotarizationPolicy.appDecision(
                processingMode: .preserveExisting,
                notarizeApp: false,
                existingTicketIsValid: true
            ),
            .reuseExisting
        )
        XCTAssertEqual(
            WorkflowNotarizationPolicy.appDecision(
                processingMode: .preserveExisting,
                notarizeApp: false,
                existingTicketIsValid: false
            ),
            .rejectMissingExistingTicket
        )
    }

    func testResignAppNotarizationFollowsItsExplicitOption() {
        XCTAssertEqual(
            WorkflowNotarizationPolicy.appDecision(
                processingMode: .resignApp,
                notarizeApp: true,
                existingTicketIsValid: true
            ),
            .submitApp
        )
        XCTAssertEqual(
            WorkflowNotarizationPolicy.appDecision(
                processingMode: .resignApp,
                notarizeApp: false,
                existingTicketIsValid: true
            ),
            .skipApp
        )
    }

    func testLegacyDiskImageSettingsUseSafeSigningDefaults() throws {
        let data = Data(#"{"volumeName":"Legacy Disk"}"#.utf8)
        let settings = try JSONDecoder().decode(DiskImageSettings.self, from: data)

        XCTAssertTrue(settings.notarize)
        XCTAssertTrue(settings.signDiskImage)
        XCTAssertEqual(settings.signingIdentity, "")
        XCTAssertEqual(settings.volumeName, "Legacy Disk")
    }

    func testLegacyInstallerSettingsDefaultToSignedNotarizedDistribution() throws {
        let data = Data(#"{"title":"Legacy Installer"}"#.utf8)
        let settings = try JSONDecoder().decode(InstallerSettings.self, from: data)

        XCTAssertTrue(settings.notarize)
        XCTAssertEqual(settings.title, "Legacy Installer")
        XCTAssertFalse(settings.includePreinstallScript)
        XCTAssertNil(settings.preinstallScript)
        XCTAssertFalse(settings.includePostinstallScript)
        XCTAssertNil(settings.postinstallScript)
    }

    func testInstallerScriptTemplatesProvideExecutableShellStructure() {
        for script in [InstallerScriptKind.preinstall, .postinstall] {
            XCTAssertTrue(script.defaultSource.hasPrefix("#!/bin/sh\n"))
            XCTAssertTrue(script.defaultSource.contains("set -e"))
            XCTAssertTrue(script.defaultSource.hasSuffix("exit 0"))
        }
    }

    func testAnExplicitlyEmptiedInstallerScriptRemainsEmpty() throws {
        var settings = InstallerSettings()
        settings.includePreinstallScript = true
        settings.preinstallScript = ""

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(InstallerSettings.self, from: encoded)

        XCTAssertTrue(decoded.includePreinstallScript)
        XCTAssertNotNil(decoded.preinstallScript)
        XCTAssertEqual(decoded.preinstallScript, "")
    }

    func testVersionThreeProjectArchiveLoadsAsCurrentVersion() throws {
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dnt")
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        var project = DistributionProject()
        project.formatVersion = 3
        project.diskImage.volumeName = "Legacy Disk"
        let data = try JSONEncoder().encode(project)
        try data.write(to: archiveURL.appendingPathComponent("project.json"))

        let loaded = try DistributionProjectArchive.load(from: archiveURL)

        XCTAssertEqual(loaded.project.formatVersion, DistributionProject.currentFormatVersion)
        XCTAssertEqual(loaded.project.diskImage.volumeName, "Legacy Disk")
    }

    func testDiskImageAlwaysUsesTheLatestAvailablePayload() {
        XCTAssertEqual(
            DistributionPipelinePolicy.diskImagePayload(buildInstaller: false),
            .app
        )
        XCTAssertEqual(
            DistributionPipelinePolicy.diskImagePayload(buildInstaller: true),
            .installerPackage
        )
    }

    func testDisablingInstallerRestoresTheFullDiskImageTemplateSet() {
        let includesApplicationsLink =
            DiskImageLayoutPolicy.includesApplicationsLinkAfterInstallerToggle(
                includesInstaller: false
            )

        XCTAssertTrue(includesApplicationsLink)
        XCTAssertEqual(
            DiskImageLayoutPolicy.availableTemplates(
                includesInstaller: false,
                includesApplicationsLink: includesApplicationsLink
            ),
            Array(DiskImageLayoutTemplate.allCases)
        )
    }

    func testZipAlwaysWrapsTheFinalDistributionArtifact() {
        XCTAssertEqual(
            DistributionPipelinePolicy.zipPayload(
                buildInstaller: false,
                buildDiskImage: false
            ),
            .app
        )
        XCTAssertEqual(
            DistributionPipelinePolicy.zipPayload(
                buildInstaller: true,
                buildDiskImage: false
            ),
            .installerPackage
        )
        XCTAssertEqual(
            DistributionPipelinePolicy.zipPayload(
                buildInstaller: true,
                buildDiskImage: true
            ),
            .diskImage
        )
        XCTAssertEqual(
            DistributionPipelinePolicy.zipPayload(
                buildInstaller: false,
                buildDiskImage: true
            ),
            .diskImage
        )
    }

}
