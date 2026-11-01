import Foundation
import SQLite3
import XCTest
@testable import PhotoMetadataGuesser

final class PhotosPeopleReaderTests: XCTestCase {
    /// Builds a tiny library with the same tables Photos uses (current column names).
    func makeLibrary() throws -> URL {
        let lib = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Test \(UUID().uuidString).photoslibrary")
        try FileManager.default.createDirectory(at: lib.appendingPathComponent("database"), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(lib.appendingPathComponent("database/Photos.sqlite").path, &db), SQLITE_OK)
        let sql = """
            CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, ZFULLNAME TEXT, ZDISPLAYNAME TEXT, ZPERSONUUID TEXT, ZMERGETARGETPERSON INTEGER);
            CREATE TABLE ZASSET (Z_PK INTEGER PRIMARY KEY, ZUUID TEXT, ZTRASHEDSTATE INTEGER);
            CREATE TABLE ZDETECTEDFACE (Z_PK INTEGER PRIMARY KEY, ZPERSONFORFACE INTEGER, ZASSETFORFACE INTEGER, ZHIDDEN INTEGER, ZSIZE REAL, ZCENTERX REAL, ZCENTERY REAL, ZAGETYPE INTEGER);
            INSERT INTO ZPERSON VALUES (1, 'Rose Smith', 'Rose', 'P-ROSE', NULL), (2, '', 'Dad', 'P-DAD', NULL),
                                       (3, '', '', 'P-UNNAMED', NULL), (4, 'Rose Smith', '', 'P-OLD', 1);
            INSERT INTO ZASSET VALUES (1, 'A1', 0), (2, 'A2', 0), (3, 'A3', 1);
            INSERT INTO ZDETECTEDFACE VALUES (1, 1, 1, 0, 0.1, 0.25, 0.8, 3), (2, 1, 2, 0, 0.3, 0.5, 0.5, 3),
                                             (3, 2, 1, 0, 0.2, 0.7, 0.4, 5), (4, 2, 3, 0, 0.2, 0.5, 0.5, 5),
                                             (5, 3, 2, 0, 0.2, 0.5, 0.5, 1), (6, 4, 2, 0, 0.2, 0.5, 0.5, 3),
                                             (7, 2, 2, 1, 0.2, 0.5, 0.5, 5);
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        return lib
    }

    func testReadsNamedPeopleAndTheirPhotos() throws {
        let people = try PhotosPeopleReader.read(libraryURL: try makeLibrary()).people
        let byName = Dictionary(uniqueKeysWithValues: people.map { ($0.name, $0) })
        XCTAssertEqual(Set(byName.keys), ["Rose Smith", "Dad"], "unnamed and merged people are skipped")
        XCTAssertEqual(byName["Rose Smith"]?.assetIDs, ["A2/L0/001", "A1/L0/001"], "biggest face first")
        XCTAssertEqual(byName["Dad"]?.assetIDs, ["A1/L0/001"], "trashed photos and hidden faces are skipped")
    }

    func testReadsFacesForRequestedPhotosOnly() throws {
        let faces = try PhotosPeopleReader.read(libraryURL: try makeLibrary(), facesFor: ["A1/L0/001"]).faces
        XCTAssertEqual(Array(faces.keys), ["A1/L0/001"])
        let a1 = faces["A1/L0/001"] ?? []
        XCTAssertEqual(a1.count, 2)
        let rose = a1.first { $0.name == "Rose Smith" }
        XCTAssertEqual(rose?.clusterID, "P-ROSE")
        XCTAssertEqual(rose?.ageType, 3)
        XCTAssertEqual(rose?.x ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertEqual(rose?.y ?? 0, 0.2, accuracy: 1e-9, "flipped to measure from the top")
    }

    func testRejectsFoldersThatAreNotLibraries() {
        XCTAssertThrowsError(try PhotosPeopleReader.read(libraryURL: URL(fileURLWithPath: NSTemporaryDirectory())))
    }
}

final class ContactLinkTests: XCTestCase {
    func testDecodesPhotosContactRecord() throws {
        let record: NSDictionary = ["contact-identifier": "ABC-123:ABPerson", "email-addresses": ["rose@example.com"],
                                    "phone-numbers": ["+1 555 0100"], "first-name": "Rose", "last-name": "", "version": 2]
        let data = try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
        let match = try XCTUnwrap(ContactMatch(archive: data))
        XCTAssertEqual(match.identifiers, ["ABC-123:ABPerson"])
        XCTAssertEqual(match.emails, ["rose@example.com"])
        XCTAssertEqual(match.phones, ["+1 555 0100"])
        XCTAssertEqual(match.firstName, "Rose")
        XCTAssertNil(match.lastName)
    }

    /// Contacts identifiers include the ":ABPerson" suffix; stripping it made every lookup fail.
    func testLinkKeepsFullIdentifiers() {
        var tagged = TaggedPerson(id: "P1", name: "Rose", assetIDs: [], contactID: "XYZ-9:ABPerson")
        tagged.contactMatch = nil
        XCTAssertEqual(ContactBirthdays.Link(tagged).identifiers, ["XYZ-9:ABPerson"])
    }
}

final class ShowInPhotosTests: XCTestCase {
    /// The full identifier, slashes encoded, is what makes Photos select the photo.
    func testLinkUsesFullEncodedIdentifier() {
        XCTAssertEqual(ShowInPhotos.url(for: "61B4A2C0-1D2E-4F00-9A8B-0123456789AB/L0/001")?.absoluteString,
                       "photos://asset?identifier=61B4A2C0-1D2E-4F00-9A8B-0123456789AB%2FL0%2F001")
    }
}
