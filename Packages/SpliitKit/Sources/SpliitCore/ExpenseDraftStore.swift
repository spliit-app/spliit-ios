import Foundation
import Observation
#if SKIP_BRIDGE
import SkipFuse
#endif

/// The raw form, including unfinished input, and the server it belongs to.
public struct ExpenseDraftSnapshot: Codable, Equatable, Identifiable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case editing
        /// The request may have reached the server. Recovery must not submit it automatically.
        case submitting
    }

    public let id: UUID
    public let instanceURL: URL
    public let groupID: String
    public let groupName: String
    public let editingExpenseID: String?
    public var mintedExpenseID: String
    public var draft: ExpenseFormDraft
    public var phase: Phase

    public init(
        id: UUID = UUID(),
        instanceURL: URL,
        groupID: String,
        groupName: String,
        editingExpenseID: String? = nil,
        mintedExpenseID: String,
        draft: ExpenseFormDraft,
        phase: Phase = .editing
    ) {
        self.id = id
        self.instanceURL = SettingsStore.normalize(instanceURL.absoluteString) ?? instanceURL
        self.groupID = groupID
        self.groupName = groupName
        self.editingExpenseID = editingExpenseID
        self.mintedExpenseID = mintedExpenseID
        var frozen = draft
        frozen.locale = Locale(identifier: draft.locale.identifier)
        self.draft = frozen
        self.phase = phase
    }
}

/// One device-local recovery record for the app's single expense form. Nothing is sent to cloud.
@MainActor
@Observable
public final class ExpenseDraftStore {
    public private(set) var record: ExpenseDraftSnapshot?
    public private(set) var failure: String?

    private let fileURL: URL
    // A file we could not read might hold a submitted expense. Never overwrite it as "empty".
    public private(set) var hasUnreadableFile = false

    public init(fileURL: URL = ExpenseDraftStore.defaultFileURL()) {
        self.fileURL = fileURL
        do {
            record = try JSONDecoder().decode(
                ExpenseDraftSnapshot.self, from: Data(contentsOf: fileURL)
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // No previous form to recover.
        } catch {
            hasUnreadableFile = true
            failure = error.localizedDescription
        }
    }

    public static func defaultFileURL() -> URL {
        RecentGroupsStore.defaultFileURL().deletingLastPathComponent()
            .appending(path: "expense-draft.json")
    }

    /// An old form may update its own record, but cannot replace a newer form's recovery data.
    @discardableResult
    public func save(_ snapshot: ExpenseDraftSnapshot) -> Bool {
        guard !hasUnreadableFile else { return false }
        guard record == nil || record?.id == snapshot.id else {
            failure = CocoaError(.fileWriteFileExists).localizedDescription
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            record = snapshot
            failure = nil
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    /// Late completion or dismissal of an old form must not clear its replacement.
    @discardableResult
    public func clear(id: UUID) -> Bool {
        guard !hasUnreadableFile else { return false }
        guard let record else {
            failure = nil
            return true
        }
        guard record.id == id else {
            failure = CocoaError(.fileWriteFileExists).localizedDescription
            return false
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Clearing an already removed file is harmless.
        } catch {
            failure = error.localizedDescription
            return false
        }
        self.record = nil
        failure = nil
        return true
    }

    /// Only after explicit user confirmation: an unreadable file has no UUID we can verify.
    /// Readable records must still be discarded through `clear(id:)`.
    @discardableResult
    public func discardUnreadableFile() -> Bool {
        guard hasUnreadableFile, record == nil else { return false }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // It may have been removed after the failed read.
        } catch {
            failure = error.localizedDescription
            return false
        }
        hasUnreadableFile = false
        failure = nil
        return true
    }
}
