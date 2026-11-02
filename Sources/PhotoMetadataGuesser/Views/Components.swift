import AppKit
import Photos
import SwiftUI
import DateGuessCore

// Views keep their local state in plain `State<T>` properties (`var _x = State(...)` plus an
// `x` accessor) instead of `@State`. Newer SDKs implement `@State` as a macro whose plugin ships
// only with full Xcode, so `@State` breaks builds that use just the Command Line Tools.

/// System colors throughout, so the app follows the accent color and appearance set in System Settings.
enum Theme {
    static let accent = Color.accentColor
    static let background = Color(nsColor: .windowBackgroundColor)

    static func color(for level: ConfidenceLevel) -> Color {
        switch level {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        }
    }

    static func color(for season: Season) -> Color {
        switch season {
        case .winter: return .blue
        case .spring: return .green
        case .summer: return .yellow
        case .fall: return .orange
        }
    }
}

/// A plain grouped box, like the sections in System Settings.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            if let title {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
        }
    }
}

// MARK: Thumbnails

@MainActor
@Observable
final class ThumbnailLoader {
    var image: NSImage?
    @ObservationIgnored private var requestID: PHImageRequestID?
    @ObservationIgnored private var loadedID: String?

    func load(_ assetID: String, side: CGFloat) {
        guard loadedID != assetID else { return }
        cancel()
        loadedID = assetID
        image = nil
        guard let asset = PhotoLibraryService.shared.asset(for: assetID) else { return }
        requestID = PhotoLibraryService.shared.requestThumbnail(for: asset, side: side) { [weak self] img in
            guard let img else { return }
            Task { @MainActor in
                guard self?.loadedID == assetID else { return }
                self?.image = img
            }
        }
    }

    func cancel() {
        if let requestID { PhotoLibraryService.shared.cancel(requestID) }
        requestID = nil
        loadedID = nil
    }
}

struct AssetThumbnail: View {
    var assetID: String
    /// Width in points; `.infinity` fills the available width.
    var side: CGFloat
    var height: CGFloat?
    var cornerRadius: CGFloat = 10
    var _loader = State<ThumbnailLoader>(initialValue: ThumbnailLoader())
    private var loader: ThumbnailLoader { get { _loader.wrappedValue } nonmutating set { _loader.wrappedValue = newValue } }

    private var requestSide: CGFloat { side.isFinite ? max(side, height ?? side) : max(320, height ?? 320) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // The image is an overlay on a fixed-size base so its cropped-off part can't stretch the layout
        // or catch clicks meant for neighboring views (clipShape alone only clips the drawing).
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(maxWidth: side.isFinite ? side : .infinity)
            .frame(width: side.isFinite ? side : nil, height: height ?? (side.isFinite ? side : 180))
            .overlay {
                if let image = loader.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .onAppear { loader.load(assetID, side: requestSide) }
            .onDisappear { loader.cancel() }
            .onChange(of: assetID) { _, new in loader.load(new, side: requestSide) }
    }
}

/// A larger, aspect-fit preview.
struct AssetPreview: View {
    var assetID: String
    var maxSide: CGFloat
    var _loader = State<ThumbnailLoader>(initialValue: ThumbnailLoader())
    private var loader: ThumbnailLoader { get { _loader.wrappedValue } nonmutating set { _loader.wrappedValue = newValue } }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .frame(width: maxSide, height: maxSide * 0.7)
            }
        }
        .frame(maxWidth: maxSide, maxHeight: maxSide)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { loader.load(assetID, side: maxSide) }
        .onDisappear { loader.cancel() }
    }
}

// MARK: Estimate display

struct ConfidenceBadge: View {
    var estimate: DateEstimate

    var body: some View {
        let level = estimate.confidenceLevel
        Circle()
            .fill(Theme.color(for: level))
            .frame(width: 8, height: 8)
            .help("\(level.displayName) confidence: about \(Int(estimate.confidence * 100))% likely to be within 2 years")
    }
}

struct SeasonIcon: View {
    var season: Season

    var body: some View {
        Image(systemName: season.symbolName)
            .foregroundStyle(Theme.color(for: season))
    }
}

/// The list of clues behind an estimate.
struct EvidenceList: View {
    var evidence: [DateEvidence]

    var body: some View {
        let used = evidence.filter { $0.hasYearInfo || $0.seasonWeight > 0 }
            .sorted { ($0.isHardConstraint ? 1 : $0.weight) + $0.seasonWeight * 0.3 > ($1.isHardConstraint ? 1 : $1.weight) + $1.seasonWeight * 0.3 }
        let notes = evidence.filter { !($0.hasYearInfo || $0.seasonWeight > 0) }
        VStack(alignment: .leading, spacing: 10) {
            if used.isEmpty && notes.isEmpty {
                Text("No clues were found for this photo. The guess is a placeholder — set the year yourself or leave it unchecked.")
                    .foregroundStyle(.secondary)
            }
            ForEach(used) { row($0, strong: true) }
            if !notes.isEmpty {
                Text("Other observations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(notes) { row($0, strong: false) }
            }
        }
    }

    private func row(_ e: DateEvidence, strong: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: e.source.symbolName)
                .frame(width: 18)
                .foregroundStyle(strong ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.summary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(e.source.displayName)
                    if let range = e.yearRangeText, e.hasYearInfo { Text("· \(range)") }
                    if let s = e.season, e.seasonWeight > 0 { Text("· \(s.displayName)") }
                    if e.isHardConstraint { Text("· certain") }
                    else if e.weight > 0 { StrengthDots(value: e.weight) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct StrengthDots: View {
    var value: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Circle()
                    .fill(Double(i) < value * 5 ? Theme.accent : Color.secondary.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .help("Clue strength")
    }
}

extension Date {
    var shortDay: String { formatted(date: .abbreviated, time: .omitted) }
}

/// A number field that updates as you type. (A `TextField(value:format:)` only commits on Return or
/// when focus leaves, so a typed year was easy to lose by clicking somewhere else.)
struct NumberField: View {
    var title: String
    @Binding var value: Int?
    var range: ClosedRange<Int>
    var width: CGFloat = 64
    @State private var draft = ""

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .onAppear { draft = value.map { String($0) } ?? "" }
            .onChange(of: value) { _, new in
                let text = new.map { String($0) } ?? ""
                if text != draft.filter(\.isNumber) { draft = text }
            }
            .onChange(of: draft) { _, text in
                let digits = text.filter(\.isNumber)
                if digits.isEmpty { if value != nil { value = nil } }
                else if let n = Int(digits), range.contains(n), n != value { value = n }
            }
    }
}
