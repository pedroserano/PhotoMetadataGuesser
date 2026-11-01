import XCTest
@testable import DateGuessCore

final class TextCluesTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!

    func years(_ e: [DateEvidence]) -> [ClosedRange<Int>] {
        e.compactMap { ev in
            guard let lo = ev.yearLow, let hi = ev.yearHigh else { return nil }
            return lo...hi
        }
    }

    func testFullDateInFilename() {
        let e = TextClues.evidence(fromFilename: "IMG_20190704_153012.jpg", now: now)
        let full = e.first { $0.exactDay != nil }
        XCTAssertEqual(full?.yearLow, 2019)
        XCTAssertEqual(full?.exactMonth, 7)
        XCTAssertEqual(full?.exactDay, 4)
    }

    func testCameraCounterIsNotAYear() {
        XCTAssertTrue(years(TextClues.evidence(fromFilename: "IMG_1987.JPG", now: now)).isEmpty)
        XCTAssertTrue(years(TextClues.evidence(fromFilename: "DSC_2001.jpg", now: now)).isEmpty)
        XCTAssertTrue(years(TextClues.evidence(fromFilename: "Scan_1985.jpg", now: now)).isEmpty)
    }

    func testBareYearAndDecade() {
        XCTAssertEqual(years(TextClues.evidence(fromAlbumName: "Grandma 1965", now: now)), [1965...1965])
        XCTAssertEqual(years(TextClues.evidence(fromAlbumName: "Late 70s", now: now)), [1976...1979])
        XCTAssertEqual(years(TextClues.evidence(fromHint: "the 1950s", now: now)), [1950...1959])
        XCTAssertEqual(years(TextClues.evidence(fromHint: "circa 1975", now: now)), [1973...1977])
    }

    func testHolidayWithTwoDigitYear() {
        let e = TextClues.evidence(fromFilename: "xmas 85 tree.jpg", now: now)
        XCTAssertEqual(years(e), [1985...1985])
        XCTAssertTrue(e.contains { $0.exactMonth == 12 && $0.season == .winter })
    }

    func testMonthNameYear() {
        let e = TextClues.evidence(fromAlbumName: "July 1979 Lake trip", now: now)
        XCTAssertTrue(e.contains { $0.yearLow == 1979 && $0.exactMonth == 7 })
        // "Dec 12" is a day, not a year.
        XCTAssertTrue(years(TextClues.evidence(fromAlbumName: "Party Dec 12", now: now)).isEmpty)
    }

    func testRange() {
        XCTAssertEqual(years(TextClues.evidence(fromAlbumName: "Photos 1975-1980", now: now)), [1975...1980])
    }

    func testFutureYearIgnored() {
        XCTAssertTrue(years(TextClues.evidence(fromAlbumName: "Plans 2099", now: now)).isEmpty)
    }

    func testFacebookTimestamp() {
        let e = TextClues.evidence(fromFilename: "FB_IMG_1541234567890.jpg", now: now)
        XCTAssertEqual(e.first?.yearLow, 2018)
        XCTAssertEqual(e.first?.exactMonth, 11)
    }
}

final class FusionTests: XCTestCase {
    let options = EvidenceFusion.Options(maxYear: 2026)

    func testAgreeingCluesNarrow() {
        let evidence = [
            DateEvidence(source: .aiOverall, summary: "", yearLow: 1970, yearHigh: 1980, peakYear: 1975, weight: 0.8),
            DateEvidence(source: .colorTone, summary: "", yearLow: 1958, yearHigh: 1985, peakYear: 1972, weight: 0.3),
        ]
        let est = EvidenceFusion.estimate(from: evidence, options: options)
        XCTAssert((1972...1977).contains(est.year), "\(est.year)")
        XCTAssertGreaterThanOrEqual(est.yearLow, 1965)
        XCTAssertLessThanOrEqual(est.yearHigh, 1985)
    }

    func testPrintedDateWins() {
        let evidence = [
            DateEvidence(source: .aiOverall, summary: "", yearLow: 1975, yearHigh: 1985, peakYear: 1980, weight: 0.6),
            DateEvidence(source: .printedDate, summary: "", yearLow: 1983, yearHigh: 1983, peakYear: 1983, weight: 0.93,
                         season: .summer, seasonWeight: 0.95, exactMonth: 7),
        ]
        let est = EvidenceFusion.estimate(from: evidence, options: options)
        XCTAssertEqual(est.year, 1983)
        XCTAssertEqual(est.month, 7)
        XCTAssertTrue(est.usedExactMonth)
        XCTAssertEqual(est.confidenceLevel, .high)
    }

    func testHardConstraint() {
        let evidence = [
            DateEvidence(source: .aiOverall, summary: "", yearLow: 1960, yearHigh: 1975, peakYear: 1965, weight: 0.7),
            PeopleClues.presence(of: PersonInfo(name: "Ann", birthYear: 1970))!,
        ]
        let est = EvidenceFusion.estimate(from: evidence, options: options)
        XCTAssertGreaterThanOrEqual(est.year, 1970)
    }

    func testSeasonMapping() {
        let e = [DateEvidence(source: .scene, summary: "", season: .fall, seasonWeight: 0.6)]
        let est = EvidenceFusion.estimate(from: e, options: options)
        XCTAssertEqual(est.season, .fall)
        XCTAssertEqual(est.month, 9)
        let none = EvidenceFusion.estimate(from: [], options: options)
        XCTAssertEqual(none.month, 6)
        XCTAssertTrue(none.seasonIsDefault)
        XCTAssertFalse(none.hasAnyEvidence)
        XCTAssertEqual(none.confidenceLevel, .low)
    }

    func testHolidaySetsMonth() {
        let e = [
            DateEvidence(source: .album, summary: "", yearLow: 1985, yearHigh: 1985, weight: 0.75),
            DateEvidence(source: .filename, summary: "", season: .winter, seasonWeight: 0.6, exactMonth: 12),
        ]
        let est = EvidenceFusion.estimate(from: e, options: options)
        XCTAssertEqual(est.year, 1985)
        XCTAssertEqual(est.month, 12)
    }

    func testPeopleAge() {
        let person = PersonInfo(name: "Ben", birthYear: 1960)
        let e = [PeopleClues.age(of: person, ageLow: 8, ageHigh: 10, matchConfidence: 0.9)!]
        let est = EvidenceFusion.estimate(from: e, options: options)
        XCTAssert((1967...1971).contains(est.year), "\(est.year)")
    }

    func testSameEventGroupSharesDate() {
        let members = [
            GroupFusion.Member(assetID: "a", evidence: [DateEvidence(source: .aiOverall, summary: "", yearLow: 1970, yearHigh: 1976, peakYear: 1973, weight: 0.7)]),
            GroupFusion.Member(assetID: "b", evidence: [DateEvidence(source: .aiOverall, summary: "", yearLow: 1972, yearHigh: 1978, peakYear: 1975, weight: 0.7)]),
            GroupFusion.Member(assetID: "c", evidence: []),
        ]
        let hint = TextClues.evidence(fromHint: "summer of 1974")
        let result = GroupFusion.estimates(members: members, groupEvidence: hint, kind: .sameEvent, options: options)
        XCTAssertEqual(Set(result.values.map(\.year)), [1974])
        XCTAssertEqual(result["c"]?.season, .summer)
    }

    func testSameEraNudges() {
        let members = [
            GroupFusion.Member(assetID: "a", evidence: [DateEvidence(source: .aiOverall, summary: "", yearLow: 1960, yearHigh: 1990, weight: 0.5)]),
            GroupFusion.Member(assetID: "b", evidence: [DateEvidence(source: .printedDate, summary: "", yearLow: 1968, yearHigh: 1968, weight: 0.93)]),
        ]
        let result = GroupFusion.estimates(members: members, groupEvidence: [], kind: .sameEra, options: options)
        XCTAssertEqual(result["b"]?.year, 1968)
        XCTAssert((1964...1972).contains(result["a"]!.year), "\(result["a"]!.year)")
    }
}

final class DetectionTests: XCTestCase {
    func testMissingAndDefaultDates() {
        XCTAssertEqual(UndatedDetector.fastCheck(creationDate: nil), .missingDate)
        XCTAssertEqual(UndatedDetector.fastCheck(creationDate: Date(timeIntervalSince1970: 0)), .implausibleDate)
        XCTAssertNil(UndatedDetector.fastCheck(creationDate: Date(timeIntervalSince1970: 1_000_000_123)))
    }

    func testEmbedded() {
        XCTAssertEqual(UndatedDetector.embeddedCheck(EmbeddedDateInfo()), .noCaptureDateInFile)
        XCTAssertNil(UndatedDetector.embeddedCheck(EmbeddedDateInfo(dateTimeOriginal: "2004:06:01 10:00:00", make: "Canon")))
        XCTAssertEqual(UndatedDetector.embeddedCheck(EmbeddedDateInfo(dateTimeOriginal: "2020:01:01 10:00:00",
                                                                      dateTimeDigitized: "2020:01:01 10:00:00",
                                                                      make: "EPSON", model: "FastFoto FF-680W")), .scannerDate)
    }

    func testFormatClues() {
        let heic = FormatClues.evidence(for: FormatInfo(originalFilename: "IMG_0001.HEIC", uniformTypeIdentifier: "public.heic"))
        XCTAssertTrue(heic.contains { $0.isHardConstraint && $0.yearLow == 2017 })
        XCTAssertEqual(FormatClues.iPhoneReleaseYear("iPhone 6s Plus"), 2015)
        XCTAssertEqual(FormatClues.iPhoneReleaseYear("iPhone XR"), 2018)
        XCTAssertEqual(FormatClues.iPhoneReleaseYear("iPhone 11 Pro"), 2019)
    }

    func testGroupSuggestions() {
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        let candidates = (1...6).map { i in
            GroupCandidate(assetID: "id\(i)", filename: String(format: "Scan_%04d.jpg", i),
                           libraryDate: base.addingTimeInterval(Double(i) * 30), albums: i < 3 ? ["Box 3"] : [])
        }
        let suggestions = GroupSuggester.suggest(candidates)
        XCTAssertTrue(suggestions.contains { $0.assetIDs.count == 6 })
        XCTAssertTrue(suggestions.contains { $0.title == "Box 3" && $0.assetIDs.count == 2 })
    }
}

final class VisualTests: XCTestCase {
    func image(width: Int, height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let i = (y * width + x) * 4
                out[i] = r; out[i + 1] = g; out[i + 2] = b
            }
        }
        return out
    }

    func testMonochromeWithWhiteBorder() {
        let w = 100, h = 100
        let px = image(width: w, height: h) { x, y in
            if x < 6 || x >= 94 || y < 6 || y >= 94 { return (250, 250, 250) }
            let v = UInt8((x * 2 + y) % 200 + 20)
            return (v, v, v)
        }
        let s = ImageStatistics.compute(rgba: px, width: w, height: h)
        XCTAssertTrue(s.isMonochrome)
        XCTAssertEqual(s.border.tone, .light)
        XCTAssertGreaterThanOrEqual(s.border.sidesWithBorder, 3)
        XCTAssertTrue(VisualClues.evidence(from: s).contains { $0.source == .colorTone })
    }

    func testColorful() {
        let px = image(width: 64, height: 48) { x, y in (UInt8(x * 4), UInt8(y * 5), UInt8(255 - x * 3)) }
        let s = ImageStatistics.compute(rgba: px, width: 64, height: 48)
        XCTAssertFalse(s.isMonochrome)
        XCTAssertFalse(s.isSepia)
    }
}

final class ClaudeParsingTests: XCTestCase {
    func testParseResponse() throws {
        let inner = """
        {"photos":[{"photo_id":"P1","best_year":1974,"year_low":1970,"year_high":1978,"confidence":0.7,
        "season":"summer","season_confidence":0.8,"season_reason":"beach","is_scanned_print":true,
        "printed_or_written_date":{"text":"JUL 74","year":1974,"month":7},
        "clues":[{"category":"clothing_fashion","observation":"bell-bottoms","year_low":1968,"year_high":1978}],
        "people":[{"name":"Ann","apparent_age_low":4,"apparent_age_high":6,"match_confidence":0.8}],
        "summary":"1970s beach snapshot"}]}
        """
        let outer: [String: Any] = [
            "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": inner]],
            "stop_reason": "end_turn",
            "usage": ["input_tokens": 1000, "output_tokens": 500],
        ]
        let data = try JSONSerialization.data(withJSONObject: outer)
        let (results, usage) = try ClaudeClient.parse(data)
        XCTAssertEqual(usage.inputTokens, 1000)
        let r = try XCTUnwrap(results["P1"])
        XCTAssertEqual(r.printedOrWrittenDate?.month, 7)

        let people = [PersonInfo(name: "Ann", birthYear: 1969)]
        let evidence = AIEvidenceMapper.evidence(from: r, people: people, libraryDate: nil)
        let est = EvidenceFusion.estimate(from: evidence, options: .init(maxYear: 2026))
        XCTAssertEqual(est.year, 1974)
        XCTAssertEqual(est.month, 7)
    }

    func testRefusal() throws {
        let outer: [String: Any] = ["content": [] as [Any], "stop_reason": "refusal", "stop_details": ["category": "other"]]
        let data = try JSONSerialization.data(withJSONObject: outer)
        XCTAssertThrowsError(try ClaudeClient.parse(data))
    }

    func testRequestBodyIsValidJSON() throws {
        let client = ClaudeClient(apiKey: "x", settings: AISettings(enabled: true))
        let body = client.requestBody(photos: [AIPhotoInput(promptID: "P1", context: "Filename: a.jpg", jpegData: Data([1, 2, 3]))],
                                      references: [AIReferenceImage(personName: "Ann", note: "age 10", jpegData: Data([4]))],
                                      groupContext: nil)
        let data = try JSONSerialization.data(withJSONObject: body)
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
    }
}

final class PeopleAndProvenanceTests: XCTestCase {
    let rose = PersonInfo(name: "Grandma Rose", birthYear: 1930)
    let john = PersonInfo(name: "John Smith", birthYear: 1952)

    func testNameMatching() {
        let people = [rose, john]
        XCTAssertEqual(PersonMatcher.match("grandma rose", in: people)?.id, rose.id)
        XCTAssertEqual(PersonMatcher.match("John Smith (Dad)", in: people)?.id, john.id)
        XCTAssertEqual(PersonMatcher.match("John", in: people)?.id, john.id)
        XCTAssertEqual(PersonMatcher.match("Grandma Rosé", in: people)?.id, rose.id)
        XCTAssertNil(PersonMatcher.match("Uncle Bob", in: people))
        // Ambiguous first names don't match anyone.
        XCTAssertNil(PersonMatcher.match("John", in: people + [PersonInfo(name: "John Doe", birthYear: 1980)]))
    }

    func testSightingsUseCurrentPeople() {
        let sighting = AIPhotoResult.PersonSighting(name: "John", apparentAgeLow: 9, apparentAgeHigh: 11, matchConfidence: 0.8)
        XCTAssertTrue(AIEvidenceMapper.peopleEvidence([sighting], people: []).isEmpty)
        let evidence = AIEvidenceMapper.peopleEvidence([sighting], people: [john])
        XCTAssertEqual(evidence.count, 2)
        let estimate = EvidenceFusion.estimate(from: evidence)
        XCTAssertTrue((1960...1964).contains(estimate.year), "\(estimate.year)")
    }

    func testScanDateIsUpperLimit() {
        let scanned = Calendar.current.date(from: DateComponents(year: 2019, month: 3, day: 2))!
        let limit = ProvenanceClues.libraryDateLimit(reason: .noCaptureDateInFile, libraryDate: scanned)
        XCTAssertEqual(limit?.yearHigh, 2019)
        XCTAssertNil(ProvenanceClues.libraryDateLimit(reason: .missingDate, libraryDate: scanned))
        // A clue that says "2020s" can't push a 2019 scan past its scan year.
        let late = DateEvidence(source: .aiOverall, summary: "", yearLow: 2018, yearHigh: 2024, peakYear: 2022, weight: 0.8)
        let estimate = EvidenceFusion.estimate(from: [late, limit!])
        XCTAssertLessThanOrEqual(estimate.year, 2019)
        XCTAssertLessThanOrEqual(estimate.yearHigh, 2019)
    }
}

final class FaceAgeGroupTests: XCTestCase {
    let kid = PersonInfo(name: "Sam", birthYear: 1975)

    func testBabyFaceDatesPhotoToFirstYears() {
        let e = PeopleClues.faceAgeGroup(of: kid, type: 1)!
        let estimate = EvidenceFusion.estimate(from: [e, PeopleClues.presence(of: kid)!])
        XCTAssertTrue((1975...1976).contains(estimate.year), "\(estimate.year)")
    }

    func testYoungChildIsEarlyChildhood() {
        let e = PeopleClues.faceAgeGroup(of: kid, type: 2)!
        XCTAssertEqual(e.yearLow, 1976)
        XCTAssertEqual(e.yearHigh, 1981)
    }

    func testUnknownGroupsAndMissingBirthYearSayNothing() {
        XCTAssertNil(PeopleClues.faceAgeGroup(of: kid, type: 0))
        XCTAssertNil(PeopleClues.faceAgeGroup(of: kid, type: 4))
        XCTAssertNil(PeopleClues.faceAgeGroup(of: PersonInfo(name: "X", birthYear: nil), type: 1))
    }
}

final class EventLinksTests: XCTestCase {
    func unit(_ v: [Float]) -> [Float] {
        let n = v.map { $0 * $0 }.reduce(0, +).squareRoot()
        return v.map { $0 / n }
    }

    func testPackingKeepsDistances() {
        let a = unit((0..<768).map { Float(sin(Double($0))) })
        let b = unit((0..<768).map { Float(sin(Double($0)) + 0.3 * cos(Double($0) * 3)) })
        let exact = EventLinks.distance(a, b)
        let packed = EventLinks.distance(EventLinks.unpack(EventLinks.pack(a)), EventLinks.unpack(EventLinks.pack(b)))
        XCTAssertEqual(packed, exact, accuracy: 0.02)
        XCTAssertEqual(EventLinks.pack(a).count, 772)
    }

    func testCalibratedWeights() {
        XCTAssertEqual(EventLinks.weight(distance: 0.3, sharesPerson: false), 0.9)
        XCTAssertNil(EventLinks.weight(distance: 0.78, sharesPerson: false))
        XCTAssertEqual(EventLinks.weight(distance: 0.78, sharesPerson: true), 0.35)
        XCTAssertNil(EventLinks.weight(distance: 1.0, sharesPerson: true))
    }

    func testFindsNeighborsAndSharedPeopleOnly() {
        let base = unit([1, 0, 0, 0]), near = unit([1, 0.3, 0, 0]), far = unit([0, 1, 0, 0])
        let prints = ["a": base, "b": near, "c": far, "z": near]
        // "z" is far away in library order, so it's only compared because it shares a person with "a".
        let order = ["a", "b", "c"] + (0..<50).map { "x\($0)" } + ["z"]
        let links = EventLinks.find(order: order, prints: prints, people: ["a": ["rose"], "z": ["rose"]], window: 5)
        XCTAssertEqual(Set(links["a"]?.map(\.assetID) ?? []), ["b", "z"])
        XCTAssertNil(links["c"])
    }

    func testMatchPullsDateButNotHardLimits() {
        let printed = DateEvidence(source: .printedDate, summary: "", yearLow: 1978, yearHigh: 1978, peakYear: 1978,
                                   weight: 0.93, season: .summer, seasonWeight: 0.95, exactMonth: 7)
        let scanLimit = DateEvidence(source: .libraryDate, summary: "", yearHigh: 1950, weight: 1, isHardConstraint: true)
        let vague = DateEvidence(source: .colorTone, summary: "", yearLow: 1958, yearHigh: 1985, peakYear: 1972, weight: 0.3)
        let evidence = ["roll1": [printed, scanLimit], "roll2": [vague]]
        let links = ["roll2": [EventLinks.Link(assetID: "roll1", distance: 0.3, weight: 0.9)]]
        let e = EventLinks.estimates(evidence: evidence, links: links)["roll2"]!
        XCTAssertEqual(e.year, 1978, "the printed date on its look-alike carries over")
        XCTAssertEqual(e.month, 7)
    }
}

final class EarliestYearTests: XCTestCase {
    func testNoGuessBeforeEarliestYear() {
        let sepia = DateEvidence(source: .colorTone, summary: "", yearLow: 1860, yearHigh: 1935, peakYear: 1905, weight: 0.5)
        let e = EvidenceFusion.estimate(from: [sepia, ProvenanceClues.earliestYear(1950)])
        XCTAssertGreaterThanOrEqual(e.year, 1950)
        XCTAssertGreaterThanOrEqual(e.yearLow, 1950)
    }
}

final class CameraPeriodTests: XCTestCase {
    func testCameraNames() {
        XCTAssertEqual(CameraClues.name(make: "Canon", model: "Canon PowerShot S100"), "Canon PowerShot S100")
        XCTAssertEqual(CameraClues.name(make: "NIKON CORPORATION", model: "NIKON D70"), "NIKON D70")
        XCTAssertEqual(CameraClues.name(make: "Apple", model: "iPhone 6"), "Apple iPhone 6")
        XCTAssertNil(CameraClues.name(make: " ", model: nil))
    }

    func testRememberedCameraYearsDateItsPhotos() {
        let info = FormatInfo(cameraMake: "Canon", cameraModel: "Canon PowerShot S100")
        let period = CameraPeriod(id: "canon powershot s100", fromYear: 2004, toYear: 2009)
        let e = try! XCTUnwrap(CameraClues.evidence(for: info, periods: [period]))
        XCTAssertEqual(e.yearLow, 2004)
        XCTAssertEqual(e.yearHigh, 2009)
        let estimate = EvidenceFusion.estimate(from: [e])
        XCTAssertTrue((2004...2009).contains(estimate.year))
    }

    func testScannersAreNotCameras() {
        let scan = FormatInfo(cameraMake: "EPSON", cameraModel: "FastFoto FF-680W")
        XCTAssertNil(CameraClues.camera(of: scan))
    }
}

final class SceneSeasonTests: XCTestCase {
    func testSantaMeansWinterEvenWhenVisionIsUnsure() {
        let e = SceneClues.evidence(fromLabels: [("santa_claus", 0.25), ("beach", 0.2)])
        let estimate = EvidenceFusion.estimate(from: e)
        XCTAssertEqual(estimate.season, .winter)
        XCTAssertEqual(estimate.month, 12)
    }

    func testChristmasTreeBeatsSummerScenery() {
        let e = SceneClues.evidence(fromLabels: [("christmas_tree", 0.5), ("pool", 0.4)])
        XCTAssertEqual(EvidenceFusion.estimate(from: e).season, .winter)
    }

    func testPartialWordsDontMatch() {
        // "jetski" used to match "ski", and "juice" would match "ice".
        let e = SceneClues.evidence(fromLabels: [("jetski", 0.8), ("juice", 0.9)])
        XCTAssertEqual(e.map(\.season), [.summer])
    }

    func testSantaInFilename() {
        let e = TextClues.evidence(fromFilename: "Santa visit 1979.jpg")
        XCTAssertTrue(e.contains { $0.season == .winter && $0.exactMonth == 12 })
    }
}
