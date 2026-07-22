import Foundation

enum CodeSigningSupport {
    struct IdentityNames: Equatable {
        let applications: [String]
        let installers: [String]
    }

    private static let codeBundleExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "inputmethod", "mdimporter",
        "plugin", "prefpane", "qlgenerator", "saver", "service", "workflow", "xpc"
    ]

    static func signingTargets(in rootURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard isDirectory.boolValue else { return [rootURL] }

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var machOBinaries: [URL] = []
        var nestedBundles: [URL] = []
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: Set(resourceKeys))
            if values.isSymbolicLink == true { continue }

            if values.isDirectory == true {
                if codeBundleExtensions.contains(itemURL.pathExtension.lowercased()) {
                    nestedBundles.append(itemURL)
                }
            } else if values.isRegularFile == true,
                      isMachOBinary(itemURL, fileManager: fileManager) {
                machOBinaries.append(itemURL)
            }
        }

        let deepestFirst: (URL, URL) -> Bool = {
            let leftDepth = $0.pathComponents.count
            let rightDepth = $1.pathComponents.count
            return leftDepth == rightDepth ? $0.path < $1.path : leftDepth > rightDepth
        }
        machOBinaries.sort(by: deepestFirst)
        nestedBundles.sort(by: deepestFirst)

        var seen = Set<String>()
        return (machOBinaries + nestedBundles + [rootURL]).filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
    }

    /// Returns the selected item followed by the outermost containing app, when
    /// the item is nested inside another app bundle. The ticket is stapled to the
    /// outermost item being distributed, so an embedded app can legitimately rely
    /// on the ticket stapled to its containing distribution bundle.
    static func stapleValidationTargets(for targetURL: URL) -> [URL] {
        let target = targetURL.standardizedFileURL
        var ancestor = target.deletingLastPathComponent()
        var outermostContainingApp: URL?

        while ancestor.path != "/" {
            if ancestor.pathExtension.lowercased() == "app" {
                outermostContainingApp = ancestor
            }

            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { break }
            ancestor = parent
        }

        guard let outermostContainingApp,
              outermostContainingApp.path != target.path else {
            return [target]
        }
        return [target, outermostContainingApp]
    }

    static func isNotarizedGatekeeperAssessment(status: Int32, output: String) -> Bool {
        status == 0 && output.range(of: "source=Notarized", options: .caseInsensitive) != nil
    }

    static func canReuseAppNotarization(wasResigned: Bool, staplerStatus: Int32) -> Bool {
        !wasResigned && staplerStatus == 0
    }

    static func identityNames(codeSigningOutput: String, basicOutput: String) -> IdentityNames {
        let codeSigningNames = validIdentityNames(in: codeSigningOutput)
        let basicNames = validIdentityNames(in: basicOutput)

        return IdentityNames(
            applications: Array(Set(codeSigningNames.filter {
                !$0.contains("Developer ID Installer")
            })).sorted(),
            installers: Array(Set(basicNames.filter {
                $0.contains("Developer ID Installer")
            })).sorted()
        )
    }

    private static func validIdentityNames(in output: String) -> [String] {
        output.components(separatedBy: .newlines).compactMap { line in
            guard !line.contains("CSSMERR_") && !line.contains("errSec") else { return nil }
            guard let start = line.firstIndex(of: "\""),
                  let end = line.lastIndex(of: "\""),
                  start < end else { return nil }
            return String(line[line.index(after: start)..<end])
        }
    }

    private static func isMachOBinary(_ url: URL, fileManager: FileManager) -> Bool {
        let extensionName = url.pathExtension.lowercased()
        guard fileManager.isExecutableFile(atPath: url.path) || extensionName == "dylib" || extensionName == "so" else {
            return false
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }

        let magic = Array(data)
        return magic == [0xfe, 0xed, 0xfa, 0xce]
            || magic == [0xce, 0xfa, 0xed, 0xfe]
            || magic == [0xfe, 0xed, 0xfa, 0xcf]
            || magic == [0xcf, 0xfa, 0xed, 0xfe]
            || magic == [0xca, 0xfe, 0xba, 0xbe]
            || magic == [0xbe, 0xba, 0xfe, 0xca]
            || magic == [0xca, 0xfe, 0xba, 0xbf]
            || magic == [0xbf, 0xba, 0xfe, 0xca]
    }
}
