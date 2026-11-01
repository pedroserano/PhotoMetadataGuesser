import Foundation

/// Finds undated photos that are probably from the same event (same day, same clothes, same room)
/// so their dates can agree, even when nobody grouped them.
///
/// Photos are compared by an image "fingerprint" (Vision's feature print: a unit-length vector, where
/// the Euclidean distance between two prints measures how different they look). Calibrated on a real
/// library: of photos taken on the same day, 17% are closer than 0.5 and 31% closer than 0.7; of photos
/// taken in different years, only 0.01% are closer than 0.5 and 0.44% closer than 0.7.
public enum EventLinks {
    public struct Link: Hashable, Sendable {
        public var assetID: String
        public var distance: Float
        /// 0…1: how strongly the other photo's clues should count for this one.
        public var weight: Double

        public init(assetID: String, distance: Float, weight: Double) {
            self.assetID = assetID
            self.distance = distance
            self.weight = weight
        }
    }

    // MARK: Fingerprints

    /// Packs a unit vector into one byte per element plus a scale (a 768-element print → 772 bytes).
    public static func pack(_ vector: [Float]) -> Data {
        let scale = max(vector.map(abs).max() ?? 0, 1e-9)
        var data = Data(count: 4 + vector.count)
        data.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: scale.bitPattern.littleEndian, as: UInt32.self)
            for (i, v) in vector.enumerated() {
                raw[4 + i] = UInt8(bitPattern: Int8(max(-127, min(127, (v / scale * 127).rounded()))))
            }
        }
        return data
    }

    public static func unpack(_ data: Data) -> [Float] {
        guard data.count > 4 else { return [] }
        return data.withUnsafeBytes { raw in
            let scale = Float(bitPattern: UInt32(littleEndian: raw.load(as: UInt32.self)))
            return (4..<data.count).map { Float(Int8(bitPattern: raw[$0])) / 127 * scale }
        }
    }

    public static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var sum: Float = 0
        for i in a.indices {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sum.squareRoot()
    }

    /// How much a match counts, from the calibration above. Sharing a recognized person makes a
    /// looser visual match believable.
    public static func weight(distance: Float, sharesPerson: Bool) -> Double? {
        switch distance {
        case ..<0.45: return 0.9
        case ..<0.6: return 0.7
        case ..<0.72: return 0.45
        case ..<0.82 where sharesPerson: return 0.35
        default: return nil
        }
    }

    // MARK: Finding links

    /// - Parameters:
    ///   - order: undated photos in library order (import time, then filename): scans of one roll or
    ///     album usually sit next to each other.
    ///   - prints: unpacked fingerprints.
    ///   - people: face groups or people seen in each photo; photos sharing someone are also compared.
    /// - Returns: up to `maxLinks` matches per photo, best first.
    public static func find(order: [String], prints: [String: [Float]], people: [String: Set<String>] = [:],
                            window: Int = 40, maxPeopleGroup: Int = 300, maxLinks: Int = 8) -> [String: [Link]] {
        var best: [String: [String: Link]] = [:]
        func consider(_ a: String, _ b: String) {
            guard a != b, best[a]?[b] == nil, let pa = prints[a], let pb = prints[b] else { return }
            let d = distance(pa, pb)
            let shared = !(people[a] ?? []).isDisjoint(with: people[b] ?? [])
            guard let w = weight(distance: d, sharesPerson: shared) else { return }
            best[a, default: [:]][b] = Link(assetID: b, distance: d, weight: w)
            best[b, default: [:]][a] = Link(assetID: a, distance: d, weight: w)
        }
        let withPrints = order.filter { prints[$0] != nil }
        for (i, a) in withPrints.enumerated() {
            for j in (i + 1)..<min(withPrints.count, i + 1 + window) { consider(a, withPrints[j]) }
        }
        var byPerson: [String: [String]] = [:]
        for (asset, who) in people where prints[asset] != nil {
            for p in who { byPerson[p, default: []].append(asset) }
        }
        // Someone who's in thousands of photos says little about which ones go together.
        for (_, assets) in byPerson where assets.count <= maxPeopleGroup {
            for i in assets.indices { for j in (i + 1)..<assets.count { consider(assets[i], assets[j]) } }
        }
        return best.mapValues { links in
            Array(links.values.sorted { $0.distance < $1.distance }.prefix(maxLinks))
        }
    }

    // MARK: Using links

    /// What a photo's matches add to it: their clues as extra log-likelihood, season votes, and dates.
    public struct Pull: Sendable {
        public var logLikelihood: [Double]
        public var seasonVotes: [Season: Double]
        public var exactDates: [DateEvidence]
        public var matchCount: Int
    }

    /// Each linked photo's pull from its matches, tempered so several near-copies don't count as several
    /// independent witnesses. Hard limits (a scan date, a birth year) stay with the photo they belong
    /// to, so one wrong match can't make a date impossible.
    public static func pulls(evidence: [String: [DateEvidence]], links: [String: [Link]],
                             options: EvidenceFusion.Options = .init()) -> [String: Pull] {
        var soft: [String: [Double]] = [:]
        func softLL(_ id: String) -> [Double]? {
            if let cached = soft[id] { return cached }
            guard let e = evidence[id] else { return nil }
            let ll = EvidenceFusion.combinedLogLikelihood(e.filter { !$0.isHardConstraint }, options: options)
            soft[id] = ll
            return ll
        }
        var out: [String: Pull] = [:]
        for (id, matches) in links where evidence[id] != nil {
            let usable = matches.filter { evidence[$0.assetID] != nil }
            guard !usable.isEmpty else { continue }
            let temper = 1 / Double(usable.count).squareRoot()
            var pull = Pull(logLikelihood: [Double](repeating: 0, count: options.maxYear - options.minYear + 1),
                            seasonVotes: [:], exactDates: [], matchCount: usable.count)
            for m in usable {
                guard let ll = softLL(m.assetID), let theirs = evidence[m.assetID] else { continue }
                let s = m.weight * temper
                for i in ll.indices { pull.logLikelihood[i] += ll[i] * s }
                for e in theirs where e.seasonWeight > 0 {
                    if let season = e.season { pull.seasonVotes[season, default: 0] += e.seasonWeight * s }
                }
                // A printed date on one photo of a roll is good for its close matches too.
                if m.weight >= 0.7 { pull.exactDates += theirs.filter { $0.exactMonth != nil && $0.hasYearInfo } }
            }
            out[id] = pull
        }
        return out
    }

    /// Estimates for linked photos (photos without links aren't returned).
    public static func estimates(evidence: [String: [DateEvidence]], links: [String: [Link]],
                                 options: EvidenceFusion.Options = .init()) -> [String: DateEstimate] {
        var out: [String: DateEstimate] = [:]
        for (id, pull) in pulls(evidence: evidence, links: links, options: options) {
            guard let own = evidence[id] else { continue }
            out[id] = EvidenceFusion.estimate(from: own, extraLogLikelihood: pull.logLikelihood,
                                              extraSeasonVotes: pull.seasonVotes,
                                              extraExactDateCandidates: pull.exactDates, options: options)
        }
        return out
    }
}
