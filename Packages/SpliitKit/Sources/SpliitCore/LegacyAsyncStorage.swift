import CryptoKit
import Foundation

/// Reads the key/value store the React Native app left behind, so an update from 1.1.0 keeps
/// the user's groups and their self-hosted address.
///
/// `@react-native-async-storage/async-storage` keeps a `manifest.json` mapping keys to values.
/// Values of 1024 characters or fewer sit inline in the manifest; longer ones have `null`
/// there and live in a sibling file named the lowercase hex MD5 of the key. A user with
/// roughly fifteen or more recent groups crosses that threshold, so both paths matter.
public struct LegacyAsyncStorage: Sendable {

    /// The largest value AsyncStorage keeps inline in the manifest; longer ones spill to a
    /// sidecar file. Public so test harnesses can reproduce the layout faithfully.
    public static let inlineValueLimit = 1024

    private let directories: [URL]

    /// - Parameter directories: candidate `RCTAsyncLocalStorage_V1` directories, most likely first.
    public init(directories: [URL]) {
        self.directories = directories
    }

    /// Every location AsyncStorage 1.23 may have used, newest convention first.
    ///
    /// The library moved from `Documents` to `Application Support/<bundle id>` and renamed the
    /// directory twice. It migrates old locations forward on launch, but probing them costs
    /// nothing and covers an install that somehow never ran a version that did.
    public static func standardLocations(
        bundleIdentifier: String,
        fileManager: FileManager = .default
    ) -> LegacyAsyncStorage {
        var candidates: [URL] = []

        if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            candidates.append(
                applicationSupport
                    .appending(path: bundleIdentifier)
                    .appending(path: "RCTAsyncLocalStorage_V1")
            )
        }

        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            for name in ["RCTAsyncLocalStorage_V1", "RNCAsyncLocalStorage_V1", "RCTAsyncLocalStorage"] {
                candidates.append(documents.appending(path: name))
            }
        }

        return LegacyAsyncStorage(directories: candidates)
    }

    /// The value stored under `key`, or nil if no legacy store holds one.
    public func value(forKey key: String) -> String? {
        for directory in directories {
            if let value = value(forKey: key, in: directory) {
                return value
            }
        }
        return nil
    }

    private func value(forKey key: String, in directory: URL) -> String? {
        let manifestURL = directory.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = manifest[key]
        else {
            return nil
        }

        if let inline = entry as? String {
            return inline
        }

        // A null entry means the value was too large to inline and sits in its own file.
        guard entry is NSNull else { return nil }
        let sidecarURL = directory.appending(path: Self.md5Hex(key))
        guard let sidecar = try? Data(contentsOf: sidecarURL) else { return nil }
        return String(data: sidecar, encoding: .utf8)
    }

    /// AsyncStorage names sidecar files after the MD5 of the key. Not a security use.
    public static func md5Hex(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
