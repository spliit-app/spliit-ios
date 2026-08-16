import Foundation
import SpliitAPI

/// A participant being edited. `id` is local identity for SwiftUI's sake; `serverID` is set
/// only for participants that already exist on the server.
public struct ParticipantDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var serverID: String?
    public var name: String

    public init(id: UUID = UUID(), serverID: String? = nil, name: String = "") {
        self.id = id
        self.serverID = serverID
        self.name = name
    }
}

/// The group form's state, plus the validation the server would apply.
///
/// Validation mirrors `groupFormSchema` in the web app. Checking here means the user sees the
/// problem next to the field instead of as a failed request, but the server stays the
/// authority — a rejected mutation is still surfaced.
public struct GroupFormDraft: Equatable, Sendable {

    public var name: String
    /// A free-text symbol like "$" or "CHF"; this is what amounts are displayed with.
    public var currency: String
    /// ISO-4217, when the group has one. Picking a currency sets this and `currency` together;
    /// nil is what "custom symbol" means, and it is how groups made before codes existed stay
    /// legal. The web app writes an empty string for the same state.
    public var currencyCode: String?
    public var information: String
    public var participants: [ParticipantDraft]

    public init(
        name: String = "",
        currency: String = "$",
        currencyCode: String? = nil,
        information: String = "",
        participants: [ParticipantDraft] = [
            ParticipantDraft(name: "John"),
            ParticipantDraft(name: "Jane"),
            ParticipantDraft(name: "Jack"),
        ]
    ) {
        self.name = name
        self.currency = currency
        self.currencyCode = currencyCode
        self.information = information
        self.participants = participants
    }

    /// A new group, denominated in the currency the device is set to — the answer for most
    /// groups, and one the picker is there to change for the rest. Falls back to the dollar,
    /// which is what the web app defaults to when nothing else says otherwise.
    public init(newGroupIn locale: Locale) {
        let currency = Currency.device(in: locale)
        self.init(currency: currency?.symbol ?? "$", currencyCode: currency?.code)
    }

    /// Builds a draft for editing an existing group.
    public init(editing group: Group) {
        self.init(
            name: group.name,
            currency: group.currency,
            currencyCode: group.currencyCode,
            information: group.information ?? "",
            participants: group.participants.map {
                ParticipantDraft(serverID: $0.id, name: $0.name)
            }
        )
    }

    // MARK: - Currency

    /// True when the group carries only a symbol: either it predates ISO codes, or the user
    /// chose to type their own. The symbol is theirs to edit in that state and nobody else's.
    public var usesCustomSymbol: Bool {
        currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    /// The currency the group is set to, or nil when it has none the system recognises.
    public func selectedCurrency(in locale: Locale = .autoupdatingCurrent) -> Currency? {
        currencyCode.flatMap { Currency.named($0, in: locale) }
    }

    /// Picking a currency sets the symbol too — the code is what the amounts are in, and a code
    /// that disagreed with the symbol beside every amount would be worse than no code at all.
    public mutating func use(_ currency: Currency) {
        currencyCode = currency.code
        self.currency = currency.symbol
    }

    /// Drops the ISO code and keeps the symbol, which is now the user's to edit.
    public mutating func useCustomSymbol() {
        currencyCode = nil
    }

    // MARK: - Validation

    public enum Problem: Equatable, Sendable {
        case nameTooShort
        case nameTooLong
        case currencyMissing
        case currencyTooLong
        case currencyCodeInvalid
        case noParticipants
        case participantNameTooShort(ParticipantDraft.ID)
        case participantNameTooLong(ParticipantDraft.ID)
        case duplicateParticipantName(ParticipantDraft.ID)
    }

    public var problems: [Problem] {
        var problems: [Problem] = []

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.count < 2 { problems.append(.nameTooShort) }
        if trimmedName.count > 50 { problems.append(.nameTooLong) }

        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCurrency.isEmpty { problems.append(.currencyMissing) }
        if trimmedCurrency.count > 5 { problems.append(.currencyTooLong) }

        // The picker cannot produce anything else, but an instance could have stored one — and
        // the server would reject the save with a message about a field the form doesn't show.
        if !usesCustomSymbol, currencyCode?.count != 3 { problems.append(.currencyCodeInvalid) }

        if participants.isEmpty { problems.append(.noParticipants) }

        // The server reports a duplicate against the *later* of the two, so the first
        // occurrence stays unmarked. Matching that keeps the errors where a user expects them.
        var seen: Set<String> = []
        for participant in participants {
            let trimmed = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 2 { problems.append(.participantNameTooShort(participant.id)) }
            if trimmed.count > 50 { problems.append(.participantNameTooLong(participant.id)) }
            if !trimmed.isEmpty, seen.contains(trimmed) {
                problems.append(.duplicateParticipantName(participant.id))
            }
            seen.insert(trimmed)
        }

        return problems
    }

    public var isValid: Bool { problems.isEmpty }

    public func problems(forParticipant id: ParticipantDraft.ID) -> [Problem] {
        problems.filter {
            switch $0 {
            case .participantNameTooShort(let target),
                 .participantNameTooLong(let target),
                 .duplicateParticipantName(let target):
                target == id
            default:
                false
            }
        }
    }

    // MARK: - Submission

    /// The payload to send. Only call this once `isValid` is true.
    public var formValues: GroupFormValues {
        let trimmedInformation = information.trimmingCharacters(in: .whitespacesAndNewlines)
        return GroupFormValues(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            information: trimmedInformation.isEmpty ? nil : trimmedInformation,
            currency: currency.trimmingCharacters(in: .whitespacesAndNewlines),
            // Empty rather than nil, and this is load-bearing: a nil optional is left out of
            // the JSON entirely, which reaches the server as `undefined` and tells Prisma to
            // leave the column alone. A group being moved off its ISO code would keep it. The
            // web app writes an empty string here for the same state.
            currencyCode: usesCustomSymbol ? "" : currencyCode,
            participants: participants.map {
                .init(id: $0.serverID, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
    }
}

extension GroupFormDraft.Problem {
    /// Wording follows the web app's error messages so the two don't drift apart.
    public var message: String {
        switch self {
        case .nameTooShort:
            String(localized: "Enter at least two characters.", bundle: Bundle.module)
        case .nameTooLong:
            String(localized: "Enter at most 50 characters.", bundle: Bundle.module)
        case .currencyMissing:
            String(localized: "Enter at least one character.", bundle: Bundle.module)
        case .currencyTooLong:
            String(localized: "Enter at most five characters.", bundle: Bundle.module)
        case .currencyCodeInvalid:
            String(
                localized: "This group’s currency code isn’t valid. Pick a currency, or choose a custom symbol.",
                bundle: Bundle.module
            )
        case .noParticipants:
            String(localized: "A group needs at least one participant.", bundle: Bundle.module)
        case .participantNameTooShort:
            String(localized: "Enter at least two characters.", bundle: Bundle.module)
        case .participantNameTooLong:
            String(localized: "Enter at most 50 characters.", bundle: Bundle.module)
        case .duplicateParticipantName:
            String(localized: "Another participant already has this name.", bundle: Bundle.module)
        }
    }
}
