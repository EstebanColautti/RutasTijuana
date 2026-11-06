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
    private var opened = false
    private let endpoint: URL?
    private let fixture: Bool

    private init() {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains { $0 == "--ui-testing" || $0 == "--offline" || $0.hasPrefix("--catalog-") }
        #else
        let testing = false
        #endif
        endpoint = testing ? nil : (Bundle.main.object(forInfoDictionaryKey: "CatalogManifestURL") as? String).flatMap { $0.isEmpty || $0.contains("$(") ? nil : URL(string: $0) }
        #if DEBUG
        fixture = ProcessInfo.processInfo.arguments.contains("--catalog-persistence-sample")
        #else
        fixture = false
        #endif
    }
    func open() async {
        guard !opened else { await update(force: false); return }
        opened = true
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(fixture ? "CatalogTests" : "Catalog", isDirectory: true)
            cache = try SQLiteCatalogCache(url: directory.appendingPathComponent("catalog.sqlite"))
            #if DEBUG
            if fixture, try cache?.current() == nil {
                let sample = PublishedCatalog(schemaVersion: 2, version: "persistence-sample", groups: RouteCatalog.sample.groups,
                    features: RouteCatalog.sample.features.map { .init(id: $0.id, name: $0.name, groupID: $0.groupID,
                        kind: $0.kind, color: $0.color, geometry: $0.geometry, information: .init(description: "", fields: [])) })
                let data = try JSONEncoder().encode(sample)
                try cache?.replace(.init(version: sample.version, sha256: Self.digest(data), data: data))
            }
            #endif
            let snapshots = try cache?.snapshots() ?? []
            for snapshot in snapshots {
                if let saved = try? snapshot.validated(digest: Self.digest) {
                    catalog = saved
                    break
                }
            }
            if catalog == nil && !snapshots.isEmpty { message = "No se pudo abrir el catálogo guardado." }
            if !fixture, let newest = snapshots.first, catalog?.version != newest.version {
                await update(force: true)
                return
            }
        } catch { message = "No se pudo abrir el catÃ¡logo guardado." }
        if !fixture { await update(force: false) }
    }
    func update(force: Bool) async {
        guard !isUpdating, !fixture else { return }
        guard let endpoint, let cache else {
            if force { message = "El servicio de catÃ¡logo no estÃ¡ configurado." }
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
                digest: Self.digest, allowLoopbackHTTP: localHTTP)
            if let updated = try await sync.update(from: endpoint, force: force) { catalog = updated; message = nil }
        } catch {
            if let snapshots = try? cache.snapshots(), !snapshots.contains(where: { $0.version == catalog?.version }) {
                catalog = snapshots.lazy.compactMap { try? $0.validated(digest: Self.digest) }.first
            }
            message = catalog == nil ? "No se pudo descargar el catÃ¡logo. Puedes volver a intentarlo." : "No se pudo actualizar. Se conserva el catÃ¡logo guardado." }
    }
    nonisolated private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
