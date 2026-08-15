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
    /// ISO-4217, when known. Not editable in Milestone 1, but preserved across an edit so
    /// saving a group from the app doesn't silently drop what the web app set.
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

    // MARK: - Validation

    public enum Problem: Equatable, Sendable {
        case nameTooShort
        case nameTooLong
        case currencyMissing
        case currencyTooLong
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
            currencyCode: currencyCode,
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
