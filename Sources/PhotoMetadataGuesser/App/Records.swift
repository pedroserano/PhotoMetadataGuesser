import Foundation
import DateGuessCore

/// A photo the scan found without a trustworthy date.
struct UndatedPhoto: Codable, Identifiable, Hashable {
    var id: String
    var reason: UndatedReason
    var libraryDate: Date?
    var format: FormatInfo
    var albums: [String]

    var filename: String { format.originalFilename ?? "Untitled" }
}

struct ScanOptions: Codable, Hashable {
    /// Read each original file's header to find photos whose date is only the import/scan time.
    var deepCheck = true
    /// Photos with GPS come from phones/cameras with clocks: trust their dates.
    var skipGPSTagged = true
    /// Download originals from iCloud when they aren't on this Mac (slow, uses bandwidth).
    var allowICloudDownloads = false
    var includeScreenshots = false
    /// Albums whose photos should all be treated as undated (PhotoKit collection identifiers).
    var undatedAlbumIDs: [String] = []
    var dateRangeRules: [DateRangeRule] = []
}

struct ScanSnapshot: Codable {
    var lastScan: Date?
    var totalAssets = 0
    var undated: [String: UndatedPhoto] = [:]
    /// Deep-checked photos that turned out to have a real capture date (lets re-scans skip them).
    var checkedDatedIDs: Set<String> = []
    var unverifiableCount = 0
}

/// Everything learned about one photo during estimation (before groups/people are applied).
struct PhotoAnalysis: Codable, Hashable {
    var assetID: String
    var localEvidence: [DateEvidence]
    var aiEvidence: [DateEvidence]
    var aiError: String?
    var usedAI: Bool
    var analyzedAt: Date
    /// Who Claude recognized. Matched to your people at estimate time, so edits to people apply
    /// without re-analyzing. Nil for analyses saved before this was kept.
    var aiPeople: [AIPhotoResult.PersonSighting]? = nil
    /// Image fingerprint, carried from the engine to `AppState.featurePrints` (not saved here).
    var featurePrint: Data? = nil
    /// Which version of the on-device checks produced `localEvidence` (nil means version 1).
    var localVersion: Int? = nil

    /// Bump when on-device rules change so existing photos are checked again (Claude's findings are kept).
    /// 2: exact scene labels (Santa and Christmas trees mean winter).
    static let currentLocalVersion = 2

    var isCurrent: Bool { (localVersion ?? 1) >= Self.currentLocalVersion }

    /// Clues from the photo itself, with people matched against the current list.
    func evidence(people: [PersonInfo]) -> [DateEvidence] {
        guard let aiPeople else { return localEvidence + aiEvidence }
        return localEvidence + aiEvidence.filter { $0.source != .person }
            + AIEvidenceMapper.peopleEvidence(aiPeople, people: people)
    }
}

/// The user's choices for one photo on the review screen.
struct ReviewDecision: Codable, Hashable {
    var selected = false
    var overrideYear: Int?
    var overrideSeason: Season?
    var ignored = false
}

struct JournalEntry: Codable, Hashable {
    var assetID: String
    var previousDate: Date?
    var newDate: Date
}

/// One "Apply" click, kept so it can be undone.
struct ApplyBatch: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var entries: [JournalEntry]
    var failures: [String: String] = [:]
    var undone = false
}

struct AppSettings: Codable, Hashable {
    var ai = AISettings()
    var scan = ScanOptions()
    var allowExactMonth = true
    /// When you type a birthday, also save it to the person's linked Contacts card. Off unless turned on.
    var writeBirthdaysToContacts: Bool?
    /// No guesses before this year: the user knows their library has no older photos.
    var earliestYear: Int?
    /// The user chose "Not Now" when setup asked for the Photos library.
    var skippedLibrarySetup: Bool?
    /// The user chose "Not Now" when setup asked for Contacts access.
    var skippedContactsSetup: Bool?
}

/// A fused estimate ready for review.
struct ComputedEstimate: Hashable {
    var estimate: DateEstimate
    var evidence: [DateEvidence]
    var groupName: String?
    /// Look-alike undated photos that were dated together with this one.
    var matches: [String] = []
}
