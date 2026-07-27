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

    func testWorkflowTitleIncludesSelectedOperations() {
        XCTAssertEqual(
            WorkflowActionPresentation.title(
                isApp: true,
                signApp: true,
                notarize: true,
                hasDistribution: true
            ),
            "Sign, Notarize & Create Distribution"
        )
        XCTAssertEqual(
            WorkflowActionPresentation.title(
                isApp: false,
                signApp: false,
                notarize: true,
                hasDistribution: false
            ),
            "Notarize Package"
        )
    }
}
