import Foundation
import SQLite3

/// Manages a standalone SQLite FTS5 full-text search index.
///
/// Maintains a separate FTS5 database that mirrors transcript text from Core Data.
/// This enables much faster full-text search than Core Data's CONTAINS predicate,
/// especially for hundreds of sessions with thousands of segments.
final class FTS5Manager {

    struct FTSMatch {
        let segmentId: UUID
        let sessionId: UUID
        let snippet: String
        let rank: Double
    }

    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.lifememo.fts5", qos: .userInitiated)

    // Store the transient destructor constant for sqlite3_bind_text.
    // SQLITE_TRANSIENT tells SQLite to make its own copy of the string data.
    private static let sqliteTransient = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self
    )

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let ftsDir = appSupport.appendingPathComponent("LifeMemo/FTS", isDirectory: true)
        try? FileManager.default.createDirectory(at: ftsDir, withIntermediateDirectories: true)
        self.dbPath = ftsDir.appendingPathComponent("search_index.sqlite").path

        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("FTS5Manager: Failed to open database at \(dbPath)")
            return
        }
    }

    private func createTables() {
        let createFTS = """
        CREATE VIRTUAL TABLE IF NOT EXISTS segments_fts USING fts5(
            segment_id UNINDEXED,
            session_id UNINDEXED,
            text,
            tokenize='unicode61 remove_diacritics 2'
        );
        """

        let createMeta = """
        CREATE TABLE IF NOT EXISTS index_meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """

        execute(createFTS)
        execute(createMeta)
    }

    // MARK: - Indexing

    func indexSegment(segmentId: UUID, sessionId: UUID, text: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            // Delete existing entry if any
            let deleteSql = "DELETE FROM segments_fts WHERE segment_id = ?;"
            var deleteStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(
                    deleteStmt, 1,
                    segmentId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_step(deleteStmt)
            }
            sqlite3_finalize(deleteStmt)

            // Insert new entry
            let insertSql = """
            INSERT INTO segments_fts (segment_id, session_id, text)
            VALUES (?, ?, ?);
            """
            var insertStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(
                    insertStmt, 1,
                    segmentId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_bind_text(
                    insertStmt, 2,
                    sessionId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_bind_text(
                    insertStmt, 3,
                    text, -1,
                    Self.sqliteTransient
                )
                sqlite3_step(insertStmt)
            }
            sqlite3_finalize(insertStmt)
        }
    }

    func removeSegment(segmentId: UUID) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "DELETE FROM segments_fts WHERE segment_id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(
                    stmt, 1,
                    segmentId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func removeSession(sessionId: UUID) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "DELETE FROM segments_fts WHERE session_id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(
                    stmt, 1,
                    sessionId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Search

    func search(query: String, sessionId: UUID? = nil, limit: Int = 50) -> [FTSMatch] {
        queue.sync { [weak self] () -> [FTSMatch] in
            guard let self, let db = self.db else { return [] }

            let ftsQuery = sanitizeFTSQuery(query)
            guard !ftsQuery.isEmpty else { return [] }

            let sql: String
            if sessionId != nil {
                sql = """
                SELECT segment_id, session_id,
                       snippet(segments_fts, 2, '<b>', '</b>', '...', 32),
                       rank
                FROM segments_fts
                WHERE segments_fts MATCH ? AND session_id = ?
                ORDER BY rank
                LIMIT ?;
                """
            } else {
                sql = """
                SELECT segment_id, session_id,
                       snippet(segments_fts, 2, '<b>', '</b>', '...', 32),
                       rank
                FROM segments_fts
                WHERE segments_fts MATCH ?
                ORDER BY rank
                LIMIT ?;
                """
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return []
            }

            sqlite3_bind_text(stmt, 1, ftsQuery, -1, Self.sqliteTransient)

            if let sessionId {
                sqlite3_bind_text(
                    stmt, 2,
                    sessionId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_bind_int(stmt, 3, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 2, Int32(limit))
            }

            var results: [FTSMatch] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let segIdRaw = sqlite3_column_text(stmt, 0),
                      let sesIdRaw = sqlite3_column_text(stmt, 1),
                      let snippetRaw = sqlite3_column_text(stmt, 2) else { continue }

                let segIdStr = String(cString: segIdRaw)
                let sesIdStr = String(cString: sesIdRaw)
                let snippetStr = String(cString: snippetRaw)

                guard let segId = UUID(uuidString: segIdStr),
                      let sesId = UUID(uuidString: sesIdStr) else { continue }

                let rank = sqlite3_column_double(stmt, 3)
                results.append(FTSMatch(
                    segmentId: segId,
                    sessionId: sesId,
                    snippet: snippetStr,
                    rank: rank
                ))
            }

            sqlite3_finalize(stmt)
            return results
        }
    }

    // MARK: - Rebuild Index

    func rebuildIndex(segments: [(segmentId: UUID, sessionId: UUID, text: String)]) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            self.execute("DELETE FROM segments_fts;")

            let sql = """
            INSERT INTO segments_fts (segment_id, session_id, text)
            VALUES (?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return
            }

            self.execute("BEGIN TRANSACTION;")

            for segment in segments {
                sqlite3_bind_text(
                    stmt, 1,
                    segment.segmentId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_bind_text(
                    stmt, 2,
                    segment.sessionId.uuidString, -1,
                    Self.sqliteTransient
                )
                sqlite3_bind_text(
                    stmt, 3,
                    segment.text, -1,
                    Self.sqliteTransient
                )

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let errMsg = sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown"
                    print("FTS5Manager: insert failed during rebuild: \(errMsg)")
                }
                sqlite3_reset(stmt)
            }

            self.execute("COMMIT;")
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Helpers

    private func sanitizeFTSQuery(_ query: String) -> String {
        // FTS5 special characters need quoting.
        // Split on whitespace, strip punctuation, quote each term.
        let terms = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else { return "" }

        // Use implicit AND by quoting each term individually.
        return terms.map { "\"\($0)\"" }.joined(separator: " ")
    }

    private func execute(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let msg = errMsg {
                print("FTS5Manager SQL error: \(String(cString: msg))")
                sqlite3_free(msg)
            }
        }
    }
}
