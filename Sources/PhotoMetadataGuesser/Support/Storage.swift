import Foundation

/// Saves app data as JSON files in Application Support. Writes happen off the main thread.
final class JSONStore: @unchecked Sendable {
    static let shared = JSONStore()

    let directory: URL
    private let queue = DispatchQueue(label: "PhotoMetadataGuesser.store", qos: .utility)

    init() {
        if let custom = ProcessInfo.processInfo.environment["PDG_DATA_DIR"], !custom.isEmpty {
            // Used by tests so they never touch real app data.
            directory = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            directory = base.appendingPathComponent("PhotoMetadataGuesser", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent("\(name).json") }

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Encodable & Sendable>(_ value: T, to name: String) {
        let target = url(name)
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: target, options: .atomic)
        }
    }

    /// Binary property list: much smaller than JSON for raw `Data` values like image fingerprints.
    func loadBinary<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(name).plist")) else { return nil }
        return try? PropertyListDecoder().decode(T.self, from: data)
    }

    func saveBinary<T: Encodable & Sendable>(_ value: T, to name: String) {
        let target = directory.appendingPathComponent("\(name).plist")
        queue.async {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: target, options: .atomic)
        }
    }

    /// Blocks until queued writes finish (used at quit).
    func flush() { queue.sync {} }
}
