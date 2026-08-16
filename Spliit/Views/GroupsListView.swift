import SpliitAPI
import SpliitCore
import SwiftUI

/// The home screen: the groups this device remembers, with participant counts and dates
/// fetched from the instance.
///
/// The list itself is local — Spliit has no accounts — so it renders immediately and the
/// server details fill in. A server that can't be reached costs detail, not the list.
struct GroupsListView: View {

    @Environment(AppModel.self) private var app
    @State private var model = GroupsListModel()
    @State private var path: [String] = []
    @State private var sheet: Sheet?
    @State private var linkFailure: String?
    private var router: Router { Router.shared }

    private enum Sheet: String, Identifiable {
        case settings, createGroup, addByURL
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: String.self) { groupID in
                    // The standard push, deliberately. A zoom from the row into the group was
                    // tried here and read as showy next to it: the push is the movement iOS uses
                    // to say "deeper in", and the group screen is exactly that rather than an
                    // expansion of the row.
                    GroupDetailView(groupID: groupID)
                }
                .toolbar { toolbarContent }
                .sheet(item: $sheet, content: sheetContent)
                .trackScreen(.home)
        }
        .task(id: reloadToken) {
            await model.load(ids: app.recentGroups.groups.map(\.groupId), using: app.client)
        }
        // An intent can land before this view exists — a cold launch from Spotlight — or while
        // it is already on screen, so the destination is read on appearance and on every change
        // rather than only once.
        .onAppear {
            openRoutedGroup()
            if let url = router.takePendingURL() { open(url) }
        }
        .onChange(of: router.destination) { openRoutedGroup() }
        .onOpenURL { open($0) }
        .alert(
            "Couldn’t open that link",
            isPresented: .constant(linkFailure != nil)
        ) {
            Button("OK", role: .cancel) { linkFailure = nil }
        } message: {
            Text(linkFailure ?? "")
        }
    }

    /// A group link that arrived from somewhere else — a message, Safari, the old app's URL
    /// scheme.
    ///
    /// A link to a group this device already knows just opens it. A link to one it does not is
    /// how people are let into a group in the first place, so it is checked against the server
    /// and remembered before opening — the same thing "Add by link" does, without the typing.
    private func open(_ url: URL) {
        guard case .group(let id)? = IncomingLink.parse(
            url,
            knownOrigins: IncomingLink.knownOrigins(baseURL: app.settings.baseURL)
        ) else {
            return
        }

        if app.recentGroups.groups.contains(where: { $0.groupId == id }) {
            router.go(to: .group(id: id))
            openRoutedGroup()
            return
        }

        Task { await join(id) }
    }

    private func join(_ groupID: String) async {
        do {
            guard let group = try await app.client.call(Spliit.group(id: groupID)).group else {
                linkFailure = String(
                    localized: "That group isn’t on \(app.settings.baseURL.host() ?? "this instance")."
                )
                return
            }
            app.recentGroups.remember(
                RecentGroup(groupId: group.id, groupName: group.name)
            )
            router.go(to: .group(id: group.id))
            openRoutedGroup()
        } catch {
            linkFailure = error.localizedDescription
        }
    }

    /// Pushes the group an intent asked for, leaving the rest of the destination for the group
    /// screen to collect once it is there.
    ///
    /// Only groups this device remembers. The entity query offers nothing else, so a stranger
    /// here is a shortcut built against a group that has since been removed from the list —
    /// and following it would strand someone on a group screen with nothing to show, which is
    /// not what they asked for by saying a name the app no longer knows.
    private func openRoutedGroup() {
        guard let groupID = router.groupToOpen() else { return }
        guard app.recentGroups.groups.contains(where: { $0.groupId == groupID }) else {
            router.clear()
            return
        }
        if path.last != groupID {
            path = [groupID]
        }
    }

    /// Reloads when the remembered groups change, or when the instance is switched.
    private var reloadToken: String {
        app.recentGroups.groups.map(\.groupId).joined(separator: ",")
            + "@" + app.settings.baseURL.absoluteString
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { sheet = .settings }
                .accessibilityIdentifier(AccessibilityID.GroupsList.settingsButton)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Create group", systemImage: "plus") { sheet = .createGroup }
                    .accessibilityIdentifier(AccessibilityID.GroupsList.createGroupButton)
                Button("Add by link", systemImage: "link") { sheet = .addByURL }
                    .accessibilityIdentifier(AccessibilityID.GroupsList.addByURLButton)
            } label: {
                Label("Add group", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .createGroup:
            CreateGroupView { group in
                app.recentGroups.remember(group)
                path = [group.groupId]
            }
        case .addByURL:
            AddGroupByURLView { group in
                app.recentGroups.remember(group)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.recentGroups.groups.isEmpty {
            // No title: the welcome screen already names the app twice, in the mark and in its
            // own heading, and "Groups" over an empty screen labels a list that isn't there.
            // Verbatim rather than a localised empty string, so the catalogue stays clean.
            emptyState
                .navigationTitle(Text(verbatim: ""))
        } else {
            groupList
                .navigationTitle("Groups")
        }
    }

    private var emptyState: some View {
        EmptyState(
            art: .logo,
            title: Text("Welcome to Spliit"),
            description: Text("Create a group to start splitting expenses with friends, or add one that was shared with you.")
        ) {
            VStack(spacing: 12) {
                Button("Create group") { sheet = .createGroup }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.GroupsList.createGroupButton)

                Button("Add group by link") { sheet = .addByURL }
                    .accessibilityIdentifier(AccessibilityID.GroupsList.addByURLButton)
            }
        }
    }

    private var groupList: some View {
        List {
            if let message = model.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .accessibilityIdentifier(AccessibilityID.GroupsList.loadFailed)
                }
            }

            // Three sections, each one absent until it has something in it — so a list with
            // nothing starred or archived looks exactly as it did before any of this existed.
            // The headers are the only thing that says a group is starred or archived: a badge
            // on the row as well would say it twice, and iOS doesn't mark a pinned note either.
            if !app.recentGroups.starred.isEmpty {
                Section("Starred") {
                    ForEach(app.recentGroups.starred) { row(for: $0) }
                }
            }

            if !app.recentGroups.recent.isEmpty {
                Section("Recent groups") {
                    ForEach(app.recentGroups.recent) { row(for: $0) }
                }
            }

            if !app.recentGroups.archived.isEmpty {
                Section("Archived") {
                    ForEach(app.recentGroups.archived) { row(for: $0) }
                }
            }
        }
        .refreshable {
            await model.load(
                ids: app.recentGroups.groups.map(\.groupId), using: app.client
            )
        }
    }

    /// A group, and the three things that can be done to it.
    ///
    /// Star and archive sit on opposite edges because they are opposite acts, and the same three
    /// actions are in a long-press menu because a swipe action nobody swipes for is a feature
    /// nobody has. Archive is the outermost trailing action, so a full swipe archives rather than
    /// removes: removing is the one thing here with no way back but the original link.
    private func row(for group: RecentGroup) -> some View {
        NavigationLink(value: group.groupId) {
            GroupRow(group: group, summary: model.summaries[group.groupId])
        }
        .swipeActions(edge: .leading) {
            starButton(group)
        }
        .swipeActions(edge: .trailing) {
            archiveButton(group)
            removeButton(group)
        }
        .contextMenu {
            starButton(group)
            archiveButton(group)
            removeButton(group)
        }
    }

    private func starButton(_ group: RecentGroup) -> some View {
        Button(
            group.isStarred ? "Unstar" : "Star",
            systemImage: group.isStarred ? "star.slash" : "star"
        ) {
            app.recentGroups.setStarred(!group.isStarred, groupId: group.groupId)
        }
        .tint(.yellow)
        .accessibilityIdentifier(AccessibilityID.GroupsList.rowStarButton(group.groupId))
        .accessibilityLabel(
            group.isStarred
                ? Text("Unstar \(group.groupName)")
                : Text("Star \(group.groupName)")
        )
    }

    private func archiveButton(_ group: RecentGroup) -> some View {
        Button(
            group.isArchived ? "Unarchive" : "Archive",
            systemImage: group.isArchived ? "tray.and.arrow.up" : "archivebox"
        ) {
            app.recentGroups.setArchived(!group.isArchived, groupId: group.groupId)
        }
        // Grey rather than a colour of its own: archiving is how a group is asked to stop
        // asking for attention.
        .tint(.gray)
        .accessibilityIdentifier(AccessibilityID.GroupsList.rowArchiveButton(group.groupId))
        .accessibilityLabel(
            group.isArchived
                ? Text("Unarchive \(group.groupName)")
                : Text("Archive \(group.groupName)")
        )
    }

    private func removeButton(_ group: RecentGroup) -> some View {
        Button("Remove", systemImage: "trash", role: .destructive) {
            app.recentGroups.forget(groupId: group.groupId)
        }
        .accessibilityIdentifier(AccessibilityID.GroupsList.rowRemoveButton(group.groupId))
        // Read on its own, "Remove" sounds like it deletes the group. It only forgets it here,
        // and there is no way back but the link.
        .accessibilityLabel(Text("Remove \(group.groupName) from this list"))
    }
}

private struct GroupRow: View {
    let group: RecentGroup
    let summary: GroupSummary?

    var body: some View {
        AdaptiveHStack(verticalAlignment: .top, spacing: 12) {
            // A group is the app's top-level object and used to be the plainest thing on screen.
            // Seeding on the ID rather than the name keeps a group's colour across a rename.
            Monogram(name: group.groupName, seed: group.groupId, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.groupName)
                    .font(.system(.headline, design: .rounded))
                    .accessibilityIdentifier(AccessibilityID.GroupsList.rowTitle(group.groupId))

                AdaptiveHStack(spacing: 12) {
                    Label(participantText, systemImage: "person.2")
                        .accessibilityIdentifier(
                            AccessibilityID.GroupsList.rowParticipants(group.groupId)
                        )
                    if let createdAt = summary?.createdAt {
                        Label(createdAt.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                            .accessibilityLabel(
                                Text("Created \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.compact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var participantText: String {
        guard let count = summary?.participantCount else { return "…" }
        return count == 1 ? "1 participant" : "\(count) participants"
    }
}

/// Fetches the server-side detail for the remembered groups.
@Observable
final class GroupsListModel {

    private(set) var summaries: [String: GroupSummary] = [:]
    private(set) var errorMessage: String?

    func load(ids: [String], using client: TRPCClient) async {
        guard !ids.isEmpty else {
            summaries = [:]
            errorMessage = nil
            return
        }

        do {
            let response = try await client.call(Spliit.groups(ids: ids))
            summaries = Dictionary(uniqueKeysWithValues: response.groups.map { ($0.id, $0) })
            errorMessage = nil
        } catch {
            // The names are stored locally, so the list is still usable — say what's missing
            // rather than replacing everything with an error screen.
            errorMessage = String(
                localized: "Couldn’t reach the server, so group details may be out of date."
            )
        }
    }
}
