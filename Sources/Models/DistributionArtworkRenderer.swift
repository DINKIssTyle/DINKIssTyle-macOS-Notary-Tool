import AppKit
import Foundation

struct PreparedDistributionAssets {
    let assets: [DistributionAssetKind: URL]
    let temporaryDirectory: URL?
}

enum DistributionArtworkRenderer {
    static func prepare(
        project: DistributionProject,
        assets: [DistributionAssetKind: URL],
        projectArchiveURL: URL?
    ) throws -> PreparedDistributionAssets {
        var sourceAssets = assets

        if let projectArchiveURL {
            if project.buildInstaller, sourceAssets[.pkgBackground] == nil {
                sourceAssets[.pkgBackground] = try DistributionProjectArchive.templateURL(
                    named: DistributionProjectArchive.pkgTemplateName,
                    in: projectArchiveURL
                )
            }
            if project.buildDiskImage,
               sourceAssets[.dmgBackground] == nil,
               let templateName = DistributionProjectArchive.dmgTemplateName(
                   for: project.diskImage,
                   canUseInstallerPackage: project.buildInstaller
               ) {
                sourceAssets[.dmgBackground] = try DistributionProjectArchive.templateURL(
                    named: templateName,
                    in: projectArchiveURL
                )
            }
        }

        let psdAssets = sourceAssets.filter { _, url in
            url.pathExtension.lowercased() == "psd"
        }
        guard !psdAssets.isEmpty else {
            return PreparedDistributionAssets(assets: sourceAssets, temporaryDirectory: nil)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dnt-artwork-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            for (kind, sourceURL) in psdAssets {
                let outputURL = temporaryDirectory
                    .appendingPathComponent(kind.archiveBaseName)
                    .appendingPathExtension("png")
                try renderPSD(at: sourceURL, to: outputURL)
                sourceAssets[kind] = outputURL
            }
            return PreparedDistributionAssets(
                assets: sourceAssets,
                temporaryDirectory: temporaryDirectory
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    static func renderPSD(at sourceURL: URL, to outputURL: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var renderingError: Error?
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try renderCoordinatedPSD(at: coordinatedURL, to: outputURL)
            } catch {
                renderingError = error
            }
        }
        if let renderingError { throw renderingError }
        if let coordinationError { throw coordinationError }
    }

    private static func renderCoordinatedPSD(at sourceURL: URL, to outputURL: URL) throws {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [NSLocalizedDescriptionKey: "Could not render \(sourceURL.lastPathComponent). Save the PSD with compatibility enabled and try again."]
            )
        }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: "Could not convert \(sourceURL.lastPathComponent) to PNG."]
            )
        }
        try pngData.write(to: outputURL, options: .atomic)
    }
}
