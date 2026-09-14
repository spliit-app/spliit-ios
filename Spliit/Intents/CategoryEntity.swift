import AppIntents
import Foundation
import SpliitAPI
import SpliitCore

/// An expense category, as the Shortcuts app sees it.
///
/// Identified by the server's own ID. Categories are seeded by a migration that fixes every ID,
/// so "Groceries" is 9 on spliit.app and on every self-hosted instance alike — which is what
/// makes an ID stored in a shortcut still mean the same thing months later, and what lets the
/// form use it without a lookup.
struct CategoryEntity: AppEntity {

    let id: Int
    let grouping: String
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static let defaultQuery = CategoryEntityQuery()

    /// The same word and the same glyph the form's picker shows, with the heading it sits under
    /// as the subtitle — "Groceries" alone is clear, "Entertainment" is a heading and a category
    /// both, and the subtitle is what tells the two apart in a flat list.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(category.displayName)",
            subtitle: "\(ExpenseCategory.displayHeading(grouping))",
            image: .init(systemName: ExpenseCategoryIcon.symbol(grouping: grouping, name: name))
        )
    }

    var category: ExpenseCategory {
        ExpenseCategory(id: id, grouping: grouping, name: name)
    }
}

extension CategoryEntity {
    init(_ category: ExpenseCategory) {
        self.init(id: category.id, grouping: category.grouping, name: category.name)
    }
}

/// Answers from the server, every time. Categories are the one thing here that this device does
/// not keep a copy of, and they belong to an instance: the picker in the Shortcuts app asks the
/// instance the chosen group is on, or the default one until a group is chosen, and so does the
/// resolution that runs the shortcut — so the ID handed to the form is one that server returned
/// a moment ago.
///
/// An instance that cannot be reached answers with nothing, which the Shortcuts app shows as an
/// empty list or an unresolved category. There is nothing better to say: the expense the
/// shortcut is about to write needs that same server.
struct CategoryEntityQuery: EntityQuery {

    /// The group already chosen in the action, when there is one. What makes the category list
    /// come from the right server rather than the app's default.
    @IntentParameterDependency<AddExpenseIntent>(\.$group)
    var addExpense

    func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
        let wanted = Set(identifiers)
        return try await categories().filter { wanted.contains($0.id) }.map(CategoryEntity.init)
    }

    /// The whole list, in the order the form's picker shows it.
    func suggestedEntities() async throws -> [CategoryEntity] {
        try await ExpenseCategory.grouped(categories())
            .flatMap(\.categories)
            .map(CategoryEntity.init)
    }

    private func categories() async throws -> [ExpenseCategory] {
        try await TRPCClient(baseURL: instanceURL).call(Spliit.categories()).categories
    }

    /// Read fresh, like `GroupEntityQuery` reads the groups: a query is routinely run while the
    /// app is not.
    @MainActor
    private var instanceURL: URL {
        let settings = SettingsStore()
        guard let groupID = addExpense?.group.id else { return settings.defaultInstanceURL }
        return RecentGroupsStore(fileURL: RecentGroupsStore.defaultFileURL())
            .instanceURL(forGroup: groupID) ?? settings.defaultInstanceURL
    }
}

extension CategoryEntityQuery: EntityStringQuery {
    /// Matching what the picker's search field was given, against the translated name — the
    /// word on screen — and the server's English, so "groceries" finds "Épicerie" on a French
    /// phone as well as the other way round.
    func entities(matching string: String) async throws -> [CategoryEntity] {
        try await suggestedEntities().filter {
            $0.category.displayName.localizedCaseInsensitiveContains(string)
                || $0.name.localizedCaseInsensitiveContains(string)
        }
    }
}
