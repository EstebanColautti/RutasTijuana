#if canImport(SQLite3)
import Foundation
import SQLite3

final class SQLiteCatalogCache: CatalogCache {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw CatalogSyncError.storage }
        do {
            try execute("PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA secure_delete=ON;")
            guard try scalar("PRAGMA user_version") <= 1 else { throw CatalogSyncError.storage }
            try execute("CREATE TABLE IF NOT EXISTS snapshots(version TEXT PRIMARY KEY, hash TEXT NOT NULL, payload BLOB NOT NULL, sequence INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); PRAGMA user_version=1;")
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.deletingLastPathComponent().path)
            #endif
            var directory = url.deletingLastPathComponent(); var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        } catch { sqlite3_close(database); database = nil; throw error }
    }
    deinit { sqlite3_close(database) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw CatalogSyncError.storage }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CatalogSyncError.storage }
        return statement
    }
    private func scalar(_ sql: String) throws -> Int {
        let s = try statement(sql); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw CatalogSyncError.storage }
        return Int(sqlite3_column_int64(s, 0))
    }
    func current() throws -> CatalogSnapshot? {
        let s = try statement("SELECT version,hash,payload FROM snapshots ORDER BY sequence DESC LIMIT 1"); defer { sqlite3_finalize(s) }
        let result = sqlite3_step(s)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let version = sqlite3_column_text(s,0), let hash = sqlite3_column_text(s,1), let bytes = sqlite3_column_blob(s,2) else { throw CatalogSyncError.storage }
        return CatalogSnapshot(version: String(cString: version), sha256: String(cString: hash), data: Data(bytes: bytes, count: Int(sqlite3_column_bytes(s,2))))
    }
    func replace(_ snapshot: CatalogSnapshot) throws {
        guard snapshot.data.count <= CatalogSynchronizer.maximumBytes else { throw CatalogSyncError.tooLarge }
        try execute("BEGIN IMMEDIATE")
        do {
            let sequence = try scalar("SELECT COALESCE(MAX(sequence),0)+1 FROM snapshots")
            let s = try statement("INSERT OR REPLACE INTO snapshots(version,hash,payload,sequence) VALUES(?,?,?,?)")
            defer { sqlite3_finalize(s) }
            sqlite3_bind_text(s,1,snapshot.version,-1,transient); sqlite3_bind_text(s,2,snapshot.sha256,-1,transient)
            let bound = snapshot.data.withUnsafeBytes { sqlite3_bind_blob(s,3,$0.baseAddress,Int32(snapshot.data.count),transient) }
            guard bound == SQLITE_OK else { throw CatalogSyncError.storage }
            sqlite3_bind_int64(s,4,Int64(sequence))
            guard sqlite3_step(s) == SQLITE_DONE else { throw CatalogSyncError.storage }
            try execute("DELETE FROM snapshots WHERE version NOT IN (SELECT version FROM snapshots ORDER BY sequence DESC LIMIT 2)")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func lastAttempt() throws -> Date? {
        let s = try statement("SELECT value FROM metadata WHERE key='lastAttempt'"); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW, let text = sqlite3_column_text(s,0), let value = Double(String(cString:text)) else { return nil }
        return Date(timeIntervalSince1970: value)
    }
    func recordAttempt(_ date: Date) throws {
        let s = try statement("INSERT OR REPLACE INTO metadata(key,value) VALUES('lastAttempt',?)"); defer { sqlite3_finalize(s) }
        sqlite3_bind_text(s,1,String(date.timeIntervalSince1970),-1,transient)
        guard sqlite3_step(s) == SQLITE_DONE else { throw CatalogSyncError.storage }
    }
}
#endif
