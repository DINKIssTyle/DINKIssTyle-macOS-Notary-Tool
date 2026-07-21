import Foundation

enum CodeSigningSupport {
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
