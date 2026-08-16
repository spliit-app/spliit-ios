import AppIntents
import Foundation
import SpliitCore

/// A group, as Siri, Spotlight and the Shortcuts app see it.
///
/// Backed by the same recent-groups file the app reads, and by nothing else: Spliit has no
/// accounts, so the only groups this device can offer are the ones it has been told about. The
/// store is read fresh each time rather than shared with the running app, because an intent is
/// routinely resolved while the app is not running at all.
struct GroupEntity: AppEntity {

    let id: String
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Group")
    static let defaultQuery = GroupEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

extension GroupEntity {
    init(_ group: RecentGroup) {
        self.init(id: group.groupId, name: group.groupName)
    }
}

struct GroupEntityQuery: EntityQuery {

    @MainActor
    func entities(for identifiers: [GroupEntity.ID]) async throws -> [GroupEntity] {
        let wanted = Set(identifiers)
        return Self.remembered().filter { wanted.contains($0.id) }
    }

    /// What the Shortcuts app offers before anything has been typed: starred first, then the
    /// rest newest first — the home screen's order, so the first suggestion is the group the
    /// home screen also leads with.
    ///
    /// Archived groups are left out. Archiving is a request to stop being offered, and an
    /// unprompted suggestion is exactly the thing being declined; asking for one by name still
    /// finds it.
    @MainActor
    func suggestedEntities() async throws -> [GroupEntity] {
        let store = RecentGroupsStore(fileURL: RecentGroupsStore.defaultFileURL())
        return (store.starred + store.recent).map(GroupEntity.init)
    }

    /// `RecentGroupsStore` is main-actor isolated, like the rest of `SpliitCore`. Reading it is
    /// a small synchronous file decode, so hopping for it costs nothing an intent would notice.
    ///
    /// Archived groups are included here: a shortcut somebody already built, or a name they said
    /// out loud, is a request for that group and not a browse of what is on offer.
    @MainActor
    static func remembered() -> [GroupEntity] {
        RecentGroupsStore(fileURL: RecentGroupsStore.defaultFileURL())
            .groups
            .map(GroupEntity.init)
    }
}

extension GroupEntityQuery: EntityStringQuery {
    /// Matching by name, for "add an expense to weekend in lisbon" — spoken, so case and
    /// partial words are the norm rather than the exception.
    @MainActor
    func entities(matching string: String) async throws -> [GroupEntity] {
        Self.remembered().filter {
            $0.name.localizedCaseInsensitiveContains(string)
        }
    }
}
