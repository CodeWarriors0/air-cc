import Foundation
import SQLite3

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class DatabaseStore {
    public let baseDirectory: URL
    public let databaseURL: URL
    public let blobsDirectory: URL

    private var db: OpaquePointer?
    private let lock = NSLock()

    public static func defaultBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("air-cc", isDirectory: true)
    }

    public init(baseDirectory: URL = DatabaseStore.defaultBaseDirectory()) throws {
        self.baseDirectory = baseDirectory
        self.databaseURL = baseDirectory.appendingPathComponent("clips.sqlite3")
        self.blobsDirectory = baseDirectory.appendingPathComponent("blobs", isDirectory: true)

        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)

        try openDatabase()
        try migrateSchema()
    }

    deinit {
        lock.lock()
        if let db {
            sqlite3_close(db)
        }
        lock.unlock()
    }

    private func openDatabase() throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error"
            if let handle { sqlite3_close(handle) }
            throw NSError(domain: "AirCC.DatabaseStore", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: msg])
        }
        self.db = handle
        executeRaw("PRAGMA journal_mode = WAL;")
        executeRaw("PRAGMA synchronous = NORMAL;")
        executeRaw("PRAGMA foreign_keys = ON;")
    }

    private func migrateSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content_hash TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            plain_text TEXT NOT NULL,
            rtf_data BLOB,
            html_data BLOB,
            thumbnail_data BLOB,
            blob_filename TEXT,
            file_paths_json TEXT,
            image_width INTEGER NOT NULL DEFAULT 0,
            image_height INTEGER NOT NULL DEFAULT 0,
            byte_size INTEGER NOT NULL DEFAULT 0,
            source_app_name TEXT,
            source_bundle_id TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            paste_count INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_pasted_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_clips_order ON clips(is_pinned DESC, updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_clips_kind ON clips(kind);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? "Schema migration failed"
            sqlite3_free(errMsg)
            throw NSError(domain: "AirCC.DatabaseStore", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @discardableResult
    private func executeRaw(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    @discardableResult
    public func upsertClip(_ payload: CapturedClipPayload, maxHistory: Int = 500) -> ClipItem? {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return nil }
        let now = Date().timeIntervalSince1970

        if let existing = fetchByHashLocked(payload.contentHash) {
            let updateSQL = """
            UPDATE clips
            SET updated_at = ?,
                source_app_name = COALESCE(?, source_app_name),
                source_bundle_id = COALESCE(?, source_bundle_id),
                rtf_data = COALESCE(?, rtf_data),
                html_data = COALESCE(?, html_data)
            WHERE id = ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, now)
                bindOptionalText(stmt, index: 2, value: payload.sourceAppName)
                bindOptionalText(stmt, index: 3, value: payload.sourceBundleID)
                bindOptionalBlob(stmt, index: 4, value: payload.rtfData)
                bindOptionalBlob(stmt, index: 5, value: payload.htmlData)
                sqlite3_bind_int64(stmt, 6, existing.id)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            return fetchByIDLocked(existing.id)
        }

        var blobFilename: String? = nil
        if let imageData = payload.imagePNGData, !imageData.isEmpty {
            let filename = "\(payload.contentHash).png"
            let fileURL = blobsDirectory.appendingPathComponent(filename)
            do {
                try imageData.write(to: fileURL, options: .atomic)
                blobFilename = filename
            } catch {
                return nil
            }
        }

        let filePathsJSON: String?
        if !payload.filePaths.isEmpty,
           let jsonData = try? JSONEncoder().encode(payload.filePaths) {
            filePathsJSON = String(data: jsonData, encoding: .utf8)
        } else {
            filePathsJSON = nil
        }

        let insertSQL = """
        INSERT INTO clips (
            content_hash, kind, title, plain_text, rtf_data, html_data,
            thumbnail_data, blob_filename, file_paths_json,
            image_width, image_height, byte_size,
            source_app_name, source_bundle_id,
            is_pinned, paste_count, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, index: 1, value: payload.contentHash)
        bindText(stmt, index: 2, value: payload.kind.rawValue)
        bindText(stmt, index: 3, value: payload.title)
        bindText(stmt, index: 4, value: payload.plainText)
        bindOptionalBlob(stmt, index: 5, value: payload.rtfData)
        bindOptionalBlob(stmt, index: 6, value: payload.htmlData)
        bindOptionalBlob(stmt, index: 7, value: payload.thumbnailPNGData)
        bindOptionalText(stmt, index: 8, value: blobFilename)
        bindOptionalText(stmt, index: 9, value: filePathsJSON)
        sqlite3_bind_int(stmt, 10, Int32(payload.imageWidth))
        sqlite3_bind_int(stmt, 11, Int32(payload.imageHeight))
        sqlite3_bind_int(stmt, 12, Int32(payload.byteSize))
        bindOptionalText(stmt, index: 13, value: payload.sourceAppName)
        bindOptionalText(stmt, index: 14, value: payload.sourceBundleID)
        sqlite3_bind_double(stmt, 15, now)
        sqlite3_bind_double(stmt, 16, now)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            return nil
        }
        let rowID = sqlite3_last_insert_rowid(db)
        pruneIfNeededLocked(maxHistory: maxHistory)
        return fetchByIDLocked(rowID)
    }

    public func pruneIfNeeded(maxHistory: Int) {
        lock.lock()
        defer { lock.unlock() }
        pruneIfNeededLocked(maxHistory: maxHistory)
    }

    private func pruneIfNeededLocked(maxHistory: Int) {
        guard let db, maxHistory > 0 else { return }
        let sql = """
        SELECT id, blob_filename
        FROM clips
        WHERE is_pinned = 0
        ORDER BY updated_at DESC
        LIMIT -1 OFFSET ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int(stmt, 1, Int32(maxHistory))

        var idsToDelete: [Int64] = []
        var blobsToDelete: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            idsToDelete.append(sqlite3_column_int64(stmt, 0))
            if let blob = columnOptionalString(stmt, index: 1) {
                blobsToDelete.append(blob)
            }
        }
        sqlite3_finalize(stmt)

        guard !idsToDelete.isEmpty else { return }
        let idList = idsToDelete.map(String.init).joined(separator: ",")
        executeRaw("DELETE FROM clips WHERE id IN (\(idList));")

        for blob in blobsToDelete {
            let url = blobsDirectory.appendingPathComponent(blob)
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func fetchClips(
        query: String = "",
        category: ClipFilterCategory = .all,
        limit: Int = 300
    ) -> [ClipItem] {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return [] }
        var conditions: [String] = []
        var bindings: [String] = []

        switch category {
        case .all:
            break
        case .pinned:
            conditions.append("is_pinned = 1")
        case .text:
            conditions.append("(kind = 'text' OR kind = 'rich_text')")
        case .image:
            conditions.append("kind = 'image'")
        case .files:
            conditions.append("kind = 'files'")
        }

        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        for token in tokens {
            let escaped = token
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let pattern = "%\(escaped)%"
            conditions.append("(plain_text LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\' OR COALESCE(source_app_name, '') LIKE ? ESCAPE '\\')")
            bindings.append(contentsOf: [pattern, pattern, pattern])
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = """
        SELECT id, content_hash, kind, title, plain_text, rtf_data, html_data,
               thumbnail_data, blob_filename, file_paths_json,
               image_width, image_height, byte_size,
               source_app_name, source_bundle_id,
               is_pinned, paste_count, created_at, updated_at, last_pasted_at
        FROM clips
        \(whereClause)
        ORDER BY is_pinned DESC, updated_at DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var bindIdx: Int32 = 1
        for value in bindings {
            bindText(stmt, index: bindIdx, value: value)
            bindIdx += 1
        }
        sqlite3_bind_int(stmt, bindIdx, Int32(limit))

        var items: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = readRow(stmt) {
                items.append(item)
            }
        }
        return items
    }

    @discardableResult
    public func togglePin(id: Int64) -> Bool? {
        lock.lock()
        defer { lock.unlock() }

        guard let db, let current = fetchByIDLocked(id) else { return nil }
        let newPinned = !current.isPinned
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE clips SET is_pinned = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, newPinned ? 1 : 0)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return newPinned
    }

    public func recordPaste(id: Int64, moveToTop: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return }
        let now = Date().timeIntervalSince1970
        let sql: String
        if moveToTop {
            sql = "UPDATE clips SET paste_count = paste_count + 1, last_pasted_at = ?, updated_at = ? WHERE id = ?;"
        } else {
            sql = "UPDATE clips SET paste_count = paste_count + 1, last_pasted_at = ? WHERE id = ?;"
        }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, now)
            if moveToTop {
                sqlite3_bind_double(stmt, 2, now)
                sqlite3_bind_int64(stmt, 3, id)
            } else {
                sqlite3_bind_int64(stmt, 2, id)
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    public func deleteClip(id: Int64) {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return }
        let existing = fetchByIDLocked(id)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        if let blob = existing?.blobFilename {
            let url = blobsDirectory.appendingPathComponent(blob)
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func clearUnpinned() {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return }
        var stmt: OpaquePointer?
        var blobs: [String] = []
        if sqlite3_prepare_v2(db, "SELECT blob_filename FROM clips WHERE is_pinned = 0 AND blob_filename IS NOT NULL;", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let blob = columnOptionalString(stmt, index: 0) {
                    blobs.append(blob)
                }
            }
        }
        sqlite3_finalize(stmt)

        executeRaw("DELETE FROM clips WHERE is_pinned = 0;")
        for blob in blobs {
            let url = blobsDirectory.appendingPathComponent(blob)
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func loadBlobData(for item: ClipItem) -> Data? {
        guard let filename = item.blobFilename else { return item.thumbnailData }
        let url = blobsDirectory.appendingPathComponent(filename)
        return (try? Data(contentsOf: url)) ?? item.thumbnailData
    }

    public func counts() -> (total: Int, pinned: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return (0, 0) }
        var stmt: OpaquePointer?
        var total = 0
        var pinned = 0
        let sql = "SELECT COUNT(*), COALESCE(SUM(CASE WHEN is_pinned = 1 THEN 1 ELSE 0 END), 0) FROM clips;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int64(stmt, 0))
                pinned = Int(sqlite3_column_int64(stmt, 1))
            }
        }
        sqlite3_finalize(stmt)
        return (total, pinned)
    }

    // MARK: - Private Row Helpers

    private func fetchByHashLocked(_ hash: String) -> ClipItem? {
        guard let db else { return nil }
        let sql = """
        SELECT id, content_hash, kind, title, plain_text, rtf_data, html_data,
               thumbnail_data, blob_filename, file_paths_json,
               image_width, image_height, byte_size,
               source_app_name, source_bundle_id,
               is_pinned, paste_count, created_at, updated_at, last_pasted_at
        FROM clips WHERE content_hash = ? LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, index: 1, value: hash)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return readRow(stmt)
        }
        return nil
    }

    private func fetchByIDLocked(_ id: Int64) -> ClipItem? {
        guard let db else { return nil }
        let sql = """
        SELECT id, content_hash, kind, title, plain_text, rtf_data, html_data,
               thumbnail_data, blob_filename, file_paths_json,
               image_width, image_height, byte_size,
               source_app_name, source_bundle_id,
               is_pinned, paste_count, created_at, updated_at, last_pasted_at
        FROM clips WHERE id = ? LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return readRow(stmt)
        }
        return nil
    }

    private func readRow(_ stmt: OpaquePointer?) -> ClipItem? {
        guard let stmt else { return nil }
        let id = sqlite3_column_int64(stmt, 0)
        let hash = columnString(stmt, index: 1)
        let kindRaw = columnString(stmt, index: 2)
        let kind = ClipKind(rawValue: kindRaw) ?? .text
        let title = columnString(stmt, index: 3)
        let plainText = columnString(stmt, index: 4)
        let rtfData = columnOptionalBlob(stmt, index: 5)
        let htmlData = columnOptionalBlob(stmt, index: 6)
        let thumbnailData = columnOptionalBlob(stmt, index: 7)
        let blobFilename = columnOptionalString(stmt, index: 8)
        let filePathsJSON = columnOptionalString(stmt, index: 9)
        let imageWidth = Int(sqlite3_column_int(stmt, 10))
        let imageHeight = Int(sqlite3_column_int(stmt, 11))
        let byteSize = Int(sqlite3_column_int(stmt, 12))
        let sourceAppName = columnOptionalString(stmt, index: 13)
        let sourceBundleID = columnOptionalString(stmt, index: 14)
        let isPinned = sqlite3_column_int(stmt, 15) != 0
        let pasteCount = Int(sqlite3_column_int(stmt, 16))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 17))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 18))
        let lastPastedAt: Date?
        if sqlite3_column_type(stmt, 19) != SQLITE_NULL {
            lastPastedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 19))
        } else {
            lastPastedAt = nil
        }

        let filePaths: [String]
        if let json = filePathsJSON,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            filePaths = decoded
        } else {
            filePaths = []
        }

        return ClipItem(
            id: id,
            contentHash: hash,
            kind: kind,
            title: title,
            plainText: plainText,
            rtfData: rtfData,
            htmlData: htmlData,
            thumbnailData: thumbnailData,
            blobFilename: blobFilename,
            filePaths: filePaths,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            byteSize: byteSize,
            sourceAppName: sourceAppName,
            sourceBundleID: sourceBundleID,
            isPinned: isPinned,
            pasteCount: pasteCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastPastedAt: lastPastedAt
        )
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        _ = value.withCString { cStr in
            sqlite3_bind_text(stmt, index, cStr, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            bindText(stmt, index: index, value: value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalBlob(_ stmt: OpaquePointer?, index: Int32, value: Data?) {
        if let value, !value.isEmpty {
            _ = value.withUnsafeBytes { rawBuffer in
                sqlite3_bind_blob(stmt, index, rawBuffer.baseAddress, Int32(rawBuffer.count), SQLITE_TRANSIENT_DESTRUCTOR)
            }
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnString(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let stmt, let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func columnOptionalString(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let stmt,
              sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: ptr)
    }

    private func columnOptionalBlob(_ stmt: OpaquePointer?, index: Int32) -> Data? {
        guard let stmt,
              sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let ptr = sqlite3_column_blob(stmt, index) else {
            return nil
        }
        let length = Int(sqlite3_column_bytes(stmt, index))
        guard length > 0 else { return nil }
        return Data(bytes: ptr, count: length)
    }
}
