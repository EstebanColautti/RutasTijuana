import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

protocol CatalogMediaCache {
    func contains(_ asset: CatalogAsset, digest: (Data) -> String) throws -> Bool
    func store(_ data: Data, asset: CatalogAsset, digest: (Data) -> String) throws
    func collect(keeping ids: Set<String>) throws
}

final class FileCatalogMediaCache: CatalogMediaCache {
    let directory: URL
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var url = directory; try url.setResourceValues(excluded)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
    }
    func url(for id: String) -> URL? {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return directory.appendingPathComponent(id + ".jpg")
    }
    func contains(_ asset: CatalogAsset, digest: (Data) -> String) throws -> Bool {
        guard asset.isValid, let url = url(for: asset.id), let data = try? Data(contentsOf: url) else { return false }
        return data.count == asset.bytes && digest(data) == asset.sha256
    }
    func store(_ data: Data, asset: CatalogAsset, digest: (Data) -> String) throws {
        guard asset.isValid, data.count == asset.bytes, digest(data) == asset.sha256,
              data.starts(with: [0xff, 0xd8, 0xff]), data.suffix(2) == Data([0xff, 0xd9]),
              let url = url(for: asset.id) else { throw CatalogSyncError.integrity }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              asset.width.map({ $0 == width }) ?? true, asset.height.map({ $0 == height }) ?? true
        else { throw CatalogSyncError.format }
        #endif
        try data.write(to: url, options: .atomic)
    }
    func collect(keeping ids: Set<String>) throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let id = file.deletingPathExtension().lastPathComponent
            if file.pathExtension == "jpg", url(for: id) != nil, !ids.contains(id) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }
}

struct CatalogPackage: Sendable {
    let snapshot: CatalogSnapshot
    let assets: [(CatalogAsset, Data)]

    static func read(at directory: URL, digest: (Data) -> String) throws -> CatalogPackage {
        let manifestData = try limited(directory.appendingPathComponent("manifest.json"), bytes: 64 * 1024)
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: manifestData)
        guard manifest.schemaVersion == 2, manifest.bytes > 0, manifest.bytes <= CatalogSynchronizer.maximumBytes,
              manifest.downloadURL.relativeString == "catalog.json" else { throw CatalogSyncError.format }
        let payload = try limited(directory.appendingPathComponent("catalog.json"), bytes: manifest.bytes)
        guard payload.count == manifest.bytes else { throw CatalogSyncError.integrity }
        let snapshot = CatalogSnapshot(version: manifest.version, sha256: manifest.sha256, data: payload)
        let catalog = try snapshot.validated(digest: digest)
        let descriptors = manifest.assets ?? []
        guard Set(descriptors.map(\.id)).count == descriptors.count,
              Set(catalog.features.flatMap { $0.media ?? [] }) == Set(descriptors.map(\.id)) else { throw CatalogSyncError.format }
        var total = payload.count
        let assets = try descriptors.map { asset -> (CatalogAsset, Data) in
            guard asset.isValid, asset.downloadURL.relativeString == "media/\(asset.id).jpg" else { throw CatalogSyncError.format }
            total += asset.bytes
            guard total <= 32 * 1024 * 1024 else { throw CatalogSyncError.tooLarge }
            let data = try limited(directory.appendingPathComponent("media/\(asset.id).jpg"), bytes: asset.bytes)
            guard data.count == asset.bytes, digest(data) == asset.sha256 else { throw CatalogSyncError.integrity }
            return (asset, data)
        }
        let expected = Set(["catalog.json", "manifest.json"] + descriptors.map { "media/\($0.id).jpg" })
        let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        while let url = entries?.nextObject() as? URL {
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isSymbolicLink != true else { throw CatalogSyncError.format }
            if attributes.isRegularFile == true {
                let relative = String(url.path.dropFirst(directory.path.count + 1))
                guard expected.contains(relative) else { throw CatalogSyncError.format }
            }
        }
        return CatalogPackage(snapshot: snapshot, assets: assets)
    }
    private static func limited(_ url: URL, bytes: Int) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= bytes else { throw CatalogSyncError.tooLarge }
        return try Data(contentsOf: url)
    }
}
