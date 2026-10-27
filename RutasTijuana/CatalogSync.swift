import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CatalogManifest: Codable, Equatable {
    let version: String
    let schemaVersion: Int
    let bytes: Int
    let sha256: String
    let downloadURL: URL
}
struct PublishedCatalog: Codable {
    struct Information: Codable {
        struct Field: Codable { let category: String; let label: String; let value: String }
        let description: String
        let fields: [Field]
    }
    struct Feature: Codable {
        let id: String
        let name: String
        let groupID: String
        let kind: CatalogFeature.Kind
        let color: String
        let geometry: CatalogGeometry
        let information: Information
    }
    let schemaVersion: Int
    let version: String
    let groups: [CatalogGroup]
    let features: [Feature]

    func catalog() throws -> RouteCatalog {
        guard schemaVersion == 2, !version.isEmpty else { throw CatalogSyncError.format }
        let converted = features.map { feature in
            CatalogFeature(id: feature.id, name: feature.name, groupID: feature.groupID, kind: feature.kind,
                color: feature.color, verified: false, geometry: feature.geometry,
                information: CatalogInformation(description: feature.information.description,
                    fields: feature.information.fields.map { .init(category: $0.category, label: $0.label,
                        value: $0.value, evidence: "", inferred: false) }))
        }
        let catalog = RouteCatalog(schemaVersion: 1, version: version, publishable: true, licenseStatus: "published", groups: groups, features: converted)
        _ = try RouteCatalog.decode(JSONEncoder().encode(catalog), allowPrivate: true)
        guard converted.allSatisfy({ feature in
            if feature.kind != .stop { return true }
            if case .point = feature.geometry { return true }
            return false
        }) else { throw CatalogSyncError.format }
        return catalog
    }
}
struct CatalogSnapshot { let version: String; let sha256: String; let data: Data }
protocol CatalogCache {
    func current() throws -> CatalogSnapshot?
    func replace(_ snapshot: CatalogSnapshot) throws
    func lastAttempt() throws -> Date?
    func recordAttempt(_ date: Date) throws
}
protocol CatalogTransport { func fetch(_ url: URL, limit: Int) async throws -> Data }
enum CatalogSyncError: Error { case format, integrity, address, response, tooLarge, storage }

struct CatalogSynchronizer {
    let transport: any CatalogTransport
    let cache: any CatalogCache
    let digest: (Data) -> String
    let allowLoopbackHTTP: Bool
    static let maximumBytes = 16 * 1024 * 1024

    func update(from endpoint: URL, force: Bool, now: Date = Date()) async throws -> RouteCatalog? {
        try Self.checkAddress(endpoint, allowLoopbackHTTP: allowLoopbackHTTP)
        if !force, let last = try cache.lastAttempt(), now.timeIntervalSince(last) >= 0,
           now.timeIntervalSince(last) < 86_400 { return nil }
        try cache.recordAttempt(now)
        let bytes = try await transport.fetch(endpoint, limit: 64 * 1024)
        guard bytes.count <= 64 * 1024 else { throw CatalogSyncError.tooLarge }
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: bytes)
        guard manifest.schemaVersion == 2, !manifest.version.isEmpty, manifest.bytes > 0,
              manifest.bytes <= Self.maximumBytes, manifest.sha256.count == 64,
              manifest.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw CatalogSyncError.format }
        guard let downloadURL = URL(string: manifest.downloadURL.absoluteString, relativeTo: endpoint)?.absoluteURL else { throw CatalogSyncError.address }
        try Self.checkAddress(downloadURL, allowLoopbackHTTP: allowLoopbackHTTP)
        guard endpoint.scheme == downloadURL.scheme, endpoint.host == downloadURL.host,
              endpoint.port == downloadURL.port else { throw CatalogSyncError.address }
        if let current = try cache.current(), current.version == manifest.version {
            guard current.sha256 == manifest.sha256, current.data.count == manifest.bytes,
                  digest(current.data) == manifest.sha256 else { throw CatalogSyncError.integrity }
            return try JSONDecoder().decode(PublishedCatalog.self, from: current.data).catalog()
        }
        let payload = try await transport.fetch(downloadURL, limit: manifest.bytes)
        guard payload.count == manifest.bytes, digest(payload) == manifest.sha256 else { throw CatalogSyncError.integrity }
        let decoded = try JSONDecoder().decode(PublishedCatalog.self, from: payload)
        guard decoded.version == manifest.version else { throw CatalogSyncError.integrity }
        let catalog = try decoded.catalog()
        try cache.replace(CatalogSnapshot(version: manifest.version, sha256: manifest.sha256, data: payload))
        return catalog
    }

    static func checkAddress(_ url: URL, allowLoopbackHTTP: Bool) throws {
        guard url.user == nil, url.password == nil, url.fragment == nil, url.host != nil else { throw CatalogSyncError.address }
        if url.scheme == "https" { return }
        guard allowLoopbackHTTP, url.scheme == "http", ["localhost","127.0.0.1","[::1]","::1"].contains(url.host!) else { throw CatalogSyncError.address }
    }
}

struct NetworkCatalogTransport: CatalogTransport {
    func fetch(_ url: URL, limit: Int) async throws -> Data { try await CatalogDownload.fetch(url, limit: limit) }
}
private final class CatalogDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?
    private var payload = Data()
    private let limit: Int
    private var failure: Error?
    private init(limit: Int) { self.limit = limit }
    static func fetch(_ url: URL, limit: Int) async throws -> Data {
        let download = CatalogDownload(limit: limit)
        return try await withCheckedThrowingContinuation { continuation in
            download.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 60
            config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: config, delegate: download, delegateQueue: queue)
            var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
            session.dataTask(with: request).resume()
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        failure = CatalogSyncError.address; completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= Int64(limit),
              (response.mimeType ?? "").lowercased() == "application/json" else {
            failure = CatalogSyncError.response; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard payload.count + data.count <= limit else { failure = CatalogSyncError.tooLarge; dataTask.cancel(); return }
        payload.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = continuation; self.continuation = nil
        if let error = failure ?? error { continuation?.resume(throwing: error) }
        else { continuation?.resume(returning: payload) }
        session.invalidateAndCancel()
    }
}
