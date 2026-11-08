#if canImport(Combine) && canImport(CryptoKit) && canImport(SQLite3)
import Foundation
import Combine
import CryptoKit

@MainActor
final class CatalogRepository: ObservableObject {
    static let shared = CatalogRepository()
    @Published private(set) var catalog: RouteCatalog?
    @Published private(set) var isUpdating = false
    @Published private(set) var message: String?
    private var cache: SQLiteCatalogCache?
    private var images: FileCatalogMediaCache?
    private var opened = false
    private let endpoint: URL?
    private let fixture: Bool
    private let bundleEnabled: Bool
    private let testing: Bool

    private init() {
        #if DEBUG
        testing = ProcessInfo.processInfo.arguments.contains { $0 == "--ui-testing" || $0 == "--offline" || $0.hasPrefix("--catalog-") }
        fixture = ProcessInfo.processInfo.arguments.contains("--catalog-persistence-sample")
        bundleEnabled = !testing || ProcessInfo.processInfo.arguments.contains("--catalog-bundle-sample")
        #else
        testing = false; fixture = false; bundleEnabled = true
        #endif
        endpoint = testing ? nil : (Bundle.main.object(forInfoDictionaryKey: "CatalogManifestURL") as? String)
            .flatMap { $0.isEmpty || $0.contains("$(") ? nil : URL(string: $0) }
    }
    func imageURL(for id: String) -> URL? {
        guard let url = images?.url(for: id), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    func open() async {
        guard !opened else { await update(force: false); return }
        opened = true
        do {
            let name = fixture ? "CatalogTests" : testing ? "CatalogUITests" : "Catalog"
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(name, isDirectory: true)
            let cache = try SQLiteCatalogCache(url: directory.appendingPathComponent("catalog.sqlite"))
            self.cache = cache
            images = try FileCatalogMediaCache(directory: directory.appendingPathComponent("media", isDirectory: true))
            let migration = "catalog-content-clean-1-" + name
            if !UserDefaults.standard.bool(forKey: migration) {
                try cache.remove(versions: Set(try cache.snapshots().map(\.version)))
                try images?.collect(keeping: [])
                UserDefaults.standard.set(true, forKey: migration)
            }
            #if DEBUG
            if fixture, try cache.current() == nil {
                let sample = PublishedCatalog(schemaVersion: 2, version: "persistence-sample", groups: RouteCatalog.sample.groups,
                    features: RouteCatalog.sample.features.map { .init(id: $0.id, name: $0.name, groupID: $0.groupID,
                        kind: $0.kind, color: $0.color, geometry: $0.geometry, information: .init(description: "", fields: [])) })
                let data = try JSONEncoder().encode(sample)
                try cache.replace(.init(version: sample.version, sha256: Self.digest(data), data: data))
            }
            #endif
            let snapshots = try cache.snapshots()
            catalog = await Task.detached(priority: .userInitiated) {
                snapshots.lazy.compactMap { try? $0.validated(digest: Self.digest) }.first
            }.value
            if bundleEnabled, let directory = Bundle.main.url(forResource: "Catalog", withExtension: "bundle") {
                do {
                    let package = try await Task.detached(priority: .userInitiated) {
                        try CatalogPackage.read(at: directory, digest: Self.digest)
                    }.value
                    for (asset, data) in package.assets {
                        if try images?.contains(asset, digest: Self.digest) != true {
                            try images?.store(data, asset: asset, digest: Self.digest)
                        }
                    }
                    if catalog == nil {
                        try cache.replace(package.snapshot)
                        catalog = try package.snapshot.validated(digest: Self.digest)
                    }
                } catch {
                    if catalog == nil { message = "No se pudo abrir el catálogo incluido. Puedes volver a intentar." }
                }
            }
            collectImages()
        } catch { message = "No se pudo abrir el catálogo guardado." }
        if !fixture { await update(force: false) }
    }
    func update(force: Bool) async {
        guard !isUpdating, !fixture else { return }
        guard let endpoint, let cache else {
            if force { message = catalog == nil ? "No hay un servicio de actualización configurado." : "Estás consultando el catálogo guardado." }
            return
        }
        isUpdating = true; defer { isUpdating = false }
        do {
            #if DEBUG
            let localHTTP = true
            #else
            let localHTTP = false
            #endif
            let sync = CatalogSynchronizer(transport: NetworkCatalogTransport(), cache: cache,
                digest: Self.digest, allowLoopbackHTTP: localHTTP, mediaCache: images)
            if let updated = try await sync.update(from: endpoint, force: force) { catalog = updated; message = nil; collectImages() }
        } catch {
            if let snapshots = try? cache.snapshots(), !snapshots.contains(where: { $0.version == catalog?.version }) {
                catalog = await Task.detached(priority: .userInitiated) {
                    snapshots.lazy.compactMap { try? $0.validated(digest: Self.digest) }.first
                }.value
            }
            if force || catalog == nil {
                message = catalog == nil ? "No se pudo descargar el catálogo. Puedes volver a intentarlo." : "No se pudo actualizar. Se conserva el catálogo guardado."
            }
        }
    }
    private func collectImages() {
        guard let snapshots = try? cache?.snapshots() else { return }
        let ids = snapshots.compactMap { try? $0.validated(digest: Self.digest) }.flatMap { $0.features.flatMap { $0.media ?? [] } }
        try? images?.collect(keeping: Set(ids))
    }
    nonisolated private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
