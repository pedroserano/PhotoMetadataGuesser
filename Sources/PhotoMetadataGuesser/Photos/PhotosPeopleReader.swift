import Foundation
import SQLite3

/// A named person from the Photos library's People album and the photos they're tagged in.
struct TaggedPerson: Codable, Hashable, Identifiable {
    /// The Photos library's own identifier for the person.
    var id: String
    var name: String
    /// PhotoKit local identifiers, biggest face first (the best candidates for reference photos).
    var assetIDs: [String]
    /// The Contacts card Photos linked this person to (a `CNContact` identifier), if any.
    var contactID: String?
    /// What Photos saved to find that card again (it can come from another device, where IDs differ).
    var contactMatch: ContactMatch?
}

/// Photos' own record of a linked contact (`ZCONTACTMATCHINGDICTIONARY`).
struct ContactMatch: Codable, Hashable {
    var identifiers: [String] = []
    var emails: [String] = []
    var phones: [String] = []
    var firstName: String?
    var lastName: String?

    /// Unpacks Photos' keyed archive. Unknown or missing fields are simply left empty.
    init?(archive: Data) {
        guard let any = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self], from: archive),
            let dict = any as? [String: Any] else { return nil }
        func strings(_ key: String) -> [String] {
            (dict[key] as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        }
        if let id = dict["contact-identifier"] as? String, !id.isEmpty { identifiers.append(id) }
        emails = strings("email-addresses")
        phones = strings("phone-numbers")
        firstName = (dict["first-name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        lastName = (dict["last-name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A face Photos detected in one photo. Position is in the displayed (oriented) image, 0–1 from the
/// top-left; `size` is roughly the face's width as a fraction of the image diagonal.
struct DetectedFace: Codable, Hashable {
    /// Photos' person (or unnamed face group) this face belongs to, if any.
    var clusterID: String?
    var name: String?
    var x: Double
    var y: Double
    var size: Double
    /// Photos' rough age group (see `PeopleClues.faceAgeGroup`), 0 when unknown.
    var ageType: Int
}

/// Reads face tags from a Photos library.
///
/// PhotoKit has no public API for People, so this reads the library's database directly, read-only,
/// the same way tools like osxphotos do. Only names and photo identifiers are read; nothing is changed.
enum PhotosPeopleReader {
    enum ReadError: LocalizedError {
        case notALibrary
        case cannotOpen(String)
        case unexpectedFormat(String)

        var errorDescription: String? {
            switch self {
            case .notALibrary: return "That isn’t a Photos library. Choose the file ending in “.photoslibrary”."
            case let .cannotOpen(detail): return "Couldn’t open the Photos library’s database (\(detail))."
            case let .unexpectedFormat(detail):
                return "This version of Photos stores people in a way this app doesn’t understand yet (\(detail))."
            }
        }
    }

    /// Named people and their photos, plus every detected face in the photos listed in `facesFor`.
    static func read(libraryURL: URL, facesFor assetIDs: Set<String> = []) throws -> (people: [TaggedPerson], faces: [String: [DetectedFace]]) {
        let handle = try open(libraryURL)
        defer { sqlite3_close(handle) }
        let people = try readPeople(handle)
        let faces = assetIDs.isEmpty ? [:] : try readFaces(handle, for: assetIDs)
        return (people, faces)
    }

    private static func open(_ libraryURL: URL) throws -> OpaquePointer {
        let db = libraryURL.appendingPathComponent("database/Photos.sqlite")
        guard FileManager.default.fileExists(atPath: db.path) else { throw ReadError.notALibrary }

        // Read-only first so recent changes still in the write-ahead log are seen; if the sandbox
        // won't allow that, open the main file as immutable (may miss the last few minutes of tags).
        var handle: OpaquePointer?
        var opened = false
        for query in ["mode=ro", "immutable=1"] {
            var components = URLComponents(url: db, resolvingAgainstBaseURL: false)!
            components.scheme = "file"
            components.query = query
            if sqlite3_open_v2(components.string, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
               sqlite3_exec(handle, "SELECT count(*) FROM ZPERSON", nil, nil, nil) == SQLITE_OK {
                opened = true
                break
            }
            sqlite3_close(handle)
            handle = nil
        }
        guard opened, let handle else { throw ReadError.cannotOpen("permission denied or file busy") }
        sqlite3_busy_timeout(handle, 5000)
        return handle
    }

    private static func readPeople(_ handle: OpaquePointer) throws -> [TaggedPerson] {
        // Column names changed across macOS versions (ZPERSON → ZPERSONFORFACE, ZASSET → ZASSETFORFACE).
        let faceColumns = columns(of: "ZDETECTEDFACE", in: handle)
        guard let personColumn = ["ZPERSONFORFACE", "ZPERSON"].first(where: faceColumns.contains),
              let assetColumn = ["ZASSETFORFACE", "ZASSET"].first(where: faceColumns.contains) else {
            throw ReadError.unexpectedFormat("no face-to-person link")
        }
        let personColumns = columns(of: "ZPERSON", in: handle)
        let merged = personColumns.contains("ZMERGETARGETPERSON") ? "AND p.ZMERGETARGETPERSON IS NULL" : ""
        let hidden = faceColumns.contains("ZHIDDEN") ? "AND coalesce(f.ZHIDDEN, 0) = 0" : ""
        let size = faceColumns.contains("ZSIZE") ? "coalesce(f.ZSIZE, 0)" : "0"
        let trashed = columns(of: "ZASSET", in: handle).contains("ZTRASHEDSTATE") ? "AND coalesce(a.ZTRASHEDSTATE, 0) = 0" : ""
        let uuid = personColumns.contains("ZPERSONUUID") ? "p.ZPERSONUUID" : "CAST(p.Z_PK AS TEXT)"
        let contact = personColumns.contains("ZPERSONURI") ? "nullif(trim(p.ZPERSONURI), '')" : "NULL"
        let matching = personColumns.contains("ZCONTACTMATCHINGDICTIONARY") ? "p.ZCONTACTMATCHINGDICTIONARY" : "NULL"

        let sql = """
            SELECT \(uuid), coalesce(nullif(trim(p.ZFULLNAME), ''), trim(p.ZDISPLAYNAME)), a.ZUUID, \(size), \(contact), \(matching)
            FROM ZPERSON p
            JOIN ZDETECTEDFACE f ON f.\(personColumn) = p.Z_PK
            JOIN ZASSET a ON a.Z_PK = f.\(assetColumn)
            WHERE coalesce(nullif(trim(p.ZFULLNAME), ''), nullif(trim(p.ZDISPLAYNAME), '')) IS NOT NULL
            \(merged) \(hidden) \(trashed)
            ORDER BY 1, 4 DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ReadError.unexpectedFormat(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        var byID: [String: TaggedPerson] = [:]
        var order: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let name = text(statement, 1), let asset = text(statement, 2) else { continue }
            let localID = asset + "/L0/001"
            if byID[id] == nil {
                var match: ContactMatch?
                if let bytes = sqlite3_column_blob(statement, 5) {
                    match = ContactMatch(archive: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 5))))
                }
                byID[id] = TaggedPerson(id: id, name: name, assetIDs: [], contactID: text(statement, 4), contactMatch: match)
                order.append(id)
            }
            if byID[id]!.assetIDs.last != localID { byID[id]!.assetIDs.append(localID) }
        }
        return order.compactMap { id in
            byID[id].map { p in
                var seen = Set<String>()
                return TaggedPerson(id: p.id, name: p.name, assetIDs: p.assetIDs.filter { seen.insert($0).inserted },
                                    contactID: p.contactID, contactMatch: p.contactMatch)
            }
        }
    }

    private static func readFaces(_ handle: OpaquePointer, for assetIDs: Set<String>) throws -> [String: [DetectedFace]] {
        let faceColumns = columns(of: "ZDETECTEDFACE", in: handle)
        guard let personColumn = ["ZPERSONFORFACE", "ZPERSON"].first(where: faceColumns.contains),
              let assetColumn = ["ZASSETFORFACE", "ZASSET"].first(where: faceColumns.contains),
              ["ZCENTERX", "ZCENTERY", "ZSIZE"].allSatisfy(faceColumns.contains) else {
            throw ReadError.unexpectedFormat("no face positions")
        }
        let personColumns = columns(of: "ZPERSON", in: handle)
        let uuid = personColumns.contains("ZPERSONUUID") ? "ZPERSONUUID" : "CAST(Z_PK AS TEXT)"
        // A person merged into another is shown as that other person.
        let target = personColumns.contains("ZMERGETARGETPERSON") ? "LEFT JOIN ZPERSON t ON t.Z_PK = p.ZMERGETARGETPERSON" : ""
        let pick = { (column: String) in target.isEmpty ? "p.\(column)" : "coalesce(t.\(column), p.\(column))" }
        let name = "coalesce(nullif(trim(\(pick("ZFULLNAME"))), ''), nullif(trim(\(pick("ZDISPLAYNAME"))), ''))"
        let age = faceColumns.contains("ZAGETYPE") ? "coalesce(f.ZAGETYPE, 0)" : "0"
        let hidden = faceColumns.contains("ZHIDDEN") ? "WHERE coalesce(f.ZHIDDEN, 0) = 0" : ""
        let sql = """
            SELECT a.ZUUID, \(pick(uuid)), \(name), f.ZCENTERX, f.ZCENTERY, f.ZSIZE, \(age)
            FROM ZDETECTEDFACE f
            JOIN ZASSET a ON a.Z_PK = f.\(assetColumn)
            LEFT JOIN ZPERSON p ON p.Z_PK = f.\(personColumn)
            \(target)
            \(hidden)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ReadError.unexpectedFormat(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var out: [String: [DetectedFace]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let asset = text(statement, 0) else { continue }
            let localID = asset + "/L0/001"
            guard assetIDs.contains(localID) else { continue }
            let size = sqlite3_column_double(statement, 5)
            guard size > 0 else { continue }
            // Photos measures y from the bottom.
            out[localID, default: []].append(DetectedFace(
                clusterID: text(statement, 1), name: text(statement, 2),
                x: sqlite3_column_double(statement, 3), y: 1 - sqlite3_column_double(statement, 4),
                size: size, ageType: Int(sqlite3_column_int(statement, 6))))
        }
        return out
    }

    private static func columns(of table: String, in db: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var out = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, 1) { out.insert(name) }
        }
        return out
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let c = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: c)
    }
}
