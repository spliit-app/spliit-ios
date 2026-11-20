import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

@Suite("Expense draft recovery")
@MainActor
struct ExpenseDraftStoreTests {
    private func fileURL() -> URL {
        URL.temporaryDirectory.appending(path: "expense-draft-\(UUID().uuidString)")
            .appending(path: "expense-draft.json")
    }

    private func snapshot(
        instance: String = "https://home.example.com/spliit/",
        phase: ExpenseDraftSnapshot.Phase = .editing
    ) throws -> ExpenseDraftSnapshot {
        ExpenseDraftSnapshot(
            instanceURL: try #require(URL(string: instance)),
            groupID: "same-group", groupName: "Weekend", editingExpenseID: "existing-expense",
            mintedExpenseID: "minted-expense",
            draft: ExpenseFormDraft(title: "Draft", amountText: "12,34", locale: Locale(identifier: "fr_FR")),
            phase: phase
        )
    }

    @Test("Raw invalid input, conversions, shares, documents and locale survive a restart")
    func rawDraftRoundTrip() throws {
        let file = fileURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let raw = ExpenseFormDraft(
            title: " ", expenseDate: Date(timeIntervalSince1970: 1_700_000_000),
            amountText: "12,,34", categoryID: 77, paidByID: nil, splitMode: .byPercentage,
            participants: [
                ParticipantShareDraft(id: "a", name: "Ana", isIncluded: true, valueText: " - "),
                ParticipantShareDraft(id: "b", name: "Bruno", isIncluded: false, valueText: ""),
            ],
            saveSplitAsDefault: true, isReimbursement: true, notes: "  unfinished\nnotes  ",
            locale: Locale(identifier: "fr_FR"), minorUnitDigits: 3,
            recurrenceRule: .monthly,
            documents: [ExpenseDocument(id: "doc", url: "https://home.example.com/photo", width: 20, height: 30)],
            groupCurrencyCode: "KWD", originalCurrencyCode: "JPY",
            originalAmountText: "not a number", conversionRateText: "1,2,3"
        )
        let record = ExpenseDraftSnapshot(
            instanceURL: try #require(URL(string: "https://home.example.com/spliit/")),
            groupID: "group", groupName: "Trip", mintedExpenseID: "stable-id", draft: raw
        )
        #expect(raw.formValues == nil)
        let store = ExpenseDraftStore(fileURL: file)
        #expect(store.save(record))
        let restored = ExpenseDraftStore(fileURL: file)
        #expect(restored.record == record)
        #expect(restored.record?.draft == raw)
        #expect(restored.failure == nil)
    }

    @Test("Snapshot creation freezes an autoupdating locale by its identifier")
    func freezesLocale() throws {
        let draft = ExpenseFormDraft(locale: .autoupdatingCurrent)
        let record = ExpenseDraftSnapshot(
            instanceURL: try #require(URL(string: "https://home.example.com/")),
            groupID: "group", groupName: "Trip", mintedExpenseID: "stable-id", draft: draft
        )
        #expect(record.draft.locale == Locale(identifier: draft.locale.identifier))
    }

    @Test("A submitting record and both expense IDs remain available after process reload")
    func retainsUncertainSubmission() throws {
        let file = fileURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let pending = try snapshot(phase: .submitting)
        #expect(ExpenseDraftStore(fileURL: file).save(pending))
        let restored = ExpenseDraftStore(fileURL: file)
        #expect(restored.record == pending)
        #expect(restored.record?.phase == .submitting)
        #expect(restored.record?.editingExpenseID == "existing-expense")
        #expect(restored.record?.mintedExpenseID == "minted-expense")
    }

    @Test("Only the current record can update or clear recovery data")
    func guardsRecordOwnership() throws {
        let file = fileURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ExpenseDraftStore(fileURL: file)
        let old = try snapshot()
        let newer = try snapshot()
        #expect(store.save(old))
        #expect(!store.save(newer))
        #expect(store.record == old)
        #expect(store.clear(id: old.id))
        #expect(store.clear(id: old.id))
        #expect(store.save(newer))
        #expect(!store.save(old))
        #expect(!store.clear(id: old.id))
        #expect(store.record == newer)
        #expect(ExpenseDraftStore(fileURL: file).record == newer)
        var updated = newer
        updated.draft.notes = "changed"
        updated.phase = .submitting
        #expect(store.save(updated))
        #expect(store.failure == nil)
        #expect(ExpenseDraftStore(fileURL: file).record == updated)
    }

    @Test("The same group ID on different instance base paths stays distinct")
    func retainsFullInstanceIdentity() throws {
        let first = try snapshot(instance: "https://home.example.com:8443/first?ignored=1#fragment")
        let second = try snapshot(instance: "https://home.example.com:8443/second")
        #expect(first.groupID == second.groupID)
        #expect(first.instanceURL.absoluteString == "https://home.example.com:8443/first/")
        #expect(second.instanceURL.absoluteString == "https://home.example.com:8443/second/")
        #expect(first.instanceURL != second.instanceURL)
        let decoded = try JSONDecoder().decode(ExpenseDraftSnapshot.self, from: JSONEncoder().encode(first))
        #expect(decoded.instanceURL == first.instanceURL)
    }

    @Test("A failed write leaves the previous record intact and exposes the error")
    func writeFailurePreservesRecord() throws {
        let root = fileURL().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "working")
        let file = directory.appending(path: "expense-draft.json")
        let store = ExpenseDraftStore(fileURL: file)
        let previous = try snapshot()
        #expect(store.save(previous))
        let bytes = try Data(contentsOf: file)
        let backup = root.appending(path: "backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        // A file where the directory belonged makes writes fail on both Apple and Android.
        try Data("blocked".utf8).write(to: directory)
        var pending = previous
        pending.phase = .submitting
        #expect(!store.save(pending))
        #expect(store.record == previous)
        #expect(store.failure != nil)
        #expect(try Data(contentsOf: backup.appending(path: "expense-draft.json")) == bytes)
    }

    @Test("An unreadable recovery file is neither discarded nor overwritten")
    func preservesUnreadableFile() throws {
        let file = fileURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("incomplete recovery data".utf8)
        try bytes.write(to: file)
        let store = ExpenseDraftStore(fileURL: file)
        #expect(store.record == nil)
        #expect(store.hasUnreadableFile)
        #expect(store.failure != nil)
        let replacement = try snapshot()
        #expect(!store.save(replacement))
        #expect(!store.clear(id: replacement.id))
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test("Explicit unreadable-file discard allows a new draft but cannot erase a readable one")
    func explicitlyDiscardsUnreadableFile() throws {
        let file = fileURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unreadable recovery data".utf8).write(to: file)
        let store = ExpenseDraftStore(fileURL: file)
        let replacement = try snapshot()
        #expect(!store.save(replacement))
        #expect(store.discardUnreadableFile())
        #expect(!store.hasUnreadableFile)
        #expect(store.failure == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.save(replacement))
        #expect(!store.discardUnreadableFile())
        #expect(store.record == replacement)
        #expect(ExpenseDraftStore(fileURL: file).record == replacement)
    }
}
