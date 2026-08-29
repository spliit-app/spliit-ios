import Foundation

/// The Spliit router, as procedures the client can call.
///
/// ```swift
/// let response = try await client.call(Spliit.group(id: "abc"))
/// ```
public enum Spliit {

    // MARK: - Groups

    public struct GroupsListInput: Encodable, Sendable {
        public let groupIds: [String]
    }

    public struct GroupsListResponse: Decodable, Sendable {
        public let groups: [GroupSummary]
    }

    /// Fetches the groups behind a set of IDs. Unknown IDs are silently absent from the
    /// result, which is how a group deleted server-side shows up.
    public static func groups(
        ids: [String]
    ) -> TRPCProcedure<GroupsListInput, GroupsListResponse> {
        .query("groups.list", GroupsListInput(groupIds: ids))
    }

    public struct GroupIDInput: Encodable, Sendable {
        public let groupId: String
    }

    public struct GroupResponse: Decodable, Sendable {
        /// Null when no group has this ID.
        public let group: Group?
    }

    public static func group(id: String) -> TRPCProcedure<GroupIDInput, GroupResponse> {
        .query("groups.get", GroupIDInput(groupId: id))
    }

    public struct GroupDetailsResponse: Decodable, Sendable {
        public let group: Group
        /// Participants who appear on at least one expense, and so can't be removed.
        public let participantsWithExpenses: [String]
    }

    public static func groupDetails(
        id: String
    ) -> TRPCProcedure<GroupIDInput, GroupDetailsResponse> {
        .query("groups.getDetails", GroupIDInput(groupId: id))
    }

    public struct CreateGroupInput: Encodable, Sendable {
        public let groupFormValues: GroupFormValues
    }

    public struct CreateGroupResponse: Decodable, Sendable {
        public let groupId: String
    }

    public static func createGroup(
        _ values: GroupFormValues
    ) -> TRPCProcedure<CreateGroupInput, CreateGroupResponse> {
        .mutation("groups.create", CreateGroupInput(groupFormValues: values))
    }

    public struct UpdateGroupInput: Encodable, Sendable {
        public let groupId: String
        public let groupFormValues: GroupFormValues
        /// Who to credit in the activity log. See `Spliit.createExpense(groupId:_:by:)`.
        public let participantId: String?
    }

    public static func updateGroup(
        id: String,
        values: GroupFormValues,
        by participantId: String? = nil
    ) -> TRPCProcedure<UpdateGroupInput, TRPCVoid> {
        .mutation(
            "groups.update",
            UpdateGroupInput(
                groupId: id, groupFormValues: values, participantId: participantId
            )
        )
    }

    // MARK: - Expenses

    public struct ExpensesListInput: Encodable, Sendable {
        public let groupId: String
        public let cursor: Int?
        public let limit: Int?
        /// Case-insensitive substring match on the expense title.
        public let filter: String?
    }

    public struct ExpensesListResponse: Decodable, Sendable {
        public let expenses: [ExpenseListItem]
        public let hasMore: Bool
        public let nextCursor: Int
    }

    public static func expenses(
        groupId: String,
        cursor: Int = 0,
        limit: Int = 20,
        filter: String? = nil
    ) -> TRPCProcedure<ExpensesListInput, ExpensesListResponse> {
        .query(
            "groups.expenses.list",
            ExpensesListInput(groupId: groupId, cursor: cursor, limit: limit, filter: filter)
        )
    }

    public struct ExpenseIDInput: Encodable, Sendable {
        public let groupId: String
        public let expenseId: String
    }

    public struct ExpenseResponse: Decodable, Sendable {
        public let expense: ExpenseDetails
    }

    public static func expense(
        groupId: String,
        expenseId: String
    ) -> TRPCProcedure<ExpenseIDInput, ExpenseResponse> {
        .query("groups.expenses.get", ExpenseIDInput(groupId: groupId, expenseId: expenseId))
    }

    public struct CreateExpenseInput: Encodable, Sendable {
        public let groupId: String
        public let expenseFormValues: ExpenseFormValues
        public let participantId: String?
    }

    public struct ExpenseIDResponse: Decodable, Sendable {
        public let expenseId: String
    }

    /// - Parameter participantId: who the activity log should say did this. Optional on the
    ///   server and nil by default here, which records the change as having been made by
    ///   "someone" — an honest answer for a phone whose owner has not said who they are.
    public static func createExpense(
        groupId: String,
        _ values: ExpenseFormValues,
        by participantId: String? = nil
    ) -> TRPCProcedure<CreateExpenseInput, ExpenseIDResponse> {
        .mutation(
            "groups.expenses.create",
            CreateExpenseInput(
                groupId: groupId, expenseFormValues: values, participantId: participantId
            )
        )
    }

    public struct UpdateExpenseInput: Encodable, Sendable {
        public let groupId: String
        public let expenseId: String
        public let expenseFormValues: ExpenseFormValues
        public let participantId: String?
    }

    public static func updateExpense(
        groupId: String,
        expenseId: String,
        _ values: ExpenseFormValues,
        by participantId: String? = nil
    ) -> TRPCProcedure<UpdateExpenseInput, ExpenseIDResponse> {
        .mutation(
            "groups.expenses.update",
            UpdateExpenseInput(
                groupId: groupId,
                expenseId: expenseId,
                expenseFormValues: values,
                participantId: participantId
            )
        )
    }

    /// Deliberately not `ExpenseIDInput`: `groups.expenses.get` is a query and has no
    /// `participantId` to give, and one input shared by a read and a write would carry a field
    /// that means nothing on half its call sites.
    public struct DeleteExpenseInput: Encodable, Sendable {
        public let groupId: String
        public let expenseId: String
        public let participantId: String?
    }

    public static func deleteExpense(
        groupId: String,
        expenseId: String,
        by participantId: String? = nil
    ) -> TRPCProcedure<DeleteExpenseInput, TRPCVoid> {
        .mutation(
            "groups.expenses.delete",
            DeleteExpenseInput(
                groupId: groupId, expenseId: expenseId, participantId: participantId
            )
        )
    }

    // MARK: - Balances

    public struct BalancesResponse: Decodable, Sendable {
        /// Keyed by participant ID. Participants with no activity are absent.
        public let balances: [String: Balance]
        public let reimbursements: [Reimbursement]
    }

    public static func balances(
        groupId: String
    ) -> TRPCProcedure<GroupIDInput, BalancesResponse> {
        .query("groups.balances.list", GroupIDInput(groupId: groupId))
    }

    // MARK: - Stats

    public struct GroupStatsInput: Encodable, Sendable {
        public let groupId: String
        /// Whose spending and share to answer for. Left out, the server answers neither.
        public let participantId: String?
    }

    /// The only endpoint that knows what anybody actually paid.
    ///
    /// `groups.balances.list` looks like it does and does not: the `paid` and `paidFor` it
    /// returns are derived from the suggested payments rather than from the expenses. These
    /// three are summed over the expenses themselves, with reimbursements excluded from all of
    /// them.
    public struct GroupStatsResponse: Decodable, Sendable, Equatable {
        /// Minor units. Negative when the group has taken in more than it has spent.
        public let totalGroupSpendings: Int
        /// Minor units — the total of the expenses this participant paid. Absent when the
        /// request named nobody.
        public let totalParticipantSpendings: Int?
        /// **The one amount in the API that is not an integer**, and it has to stay `Double`
        /// even though today's server sends a whole number.
        ///
        /// Until the web app's *Shares* change (2026-08-13) an evenly split expense was divided
        /// in floating-point and the sum rounded to two decimals, so a third of 10.00 arrived as
        /// 3.33 minor units and a fraction — a third of 42.50 across three people summed to
        /// `1416.67`. Since that change every share is apportioned in whole minor units and the
        /// total needs no rounding, which is what the current release and `spliit.app` both
        /// send. Self-hosted instances lag, and `Int` cannot decode `1416.67` — it throws, and
        /// takes the whole screen with it. So the wire type is the older, wider one and the
        /// rounding happens on the way to the display. Absent when the request named nobody.
        public let totalParticipantShare: Double?

        public init(
            totalGroupSpendings: Int,
            totalParticipantSpendings: Int? = nil,
            totalParticipantShare: Double? = nil
        ) {
            self.totalGroupSpendings = totalGroupSpendings
            self.totalParticipantSpendings = totalParticipantSpendings
            self.totalParticipantShare = totalParticipantShare
        }
    }

    /// - Note: the web app's `main` has since folded this into a wider `groups.stats.overview`
    ///   that also returns spending by month, participant and category. Nothing serves it yet —
    ///   neither `spliit.app` nor the published image — so calling it today would 404 for every
    ///   user. `upstream-drift` is what will say when that changes.
    public static func stats(
        groupId: String,
        participantId: String? = nil
    ) -> TRPCProcedure<GroupStatsInput, GroupStatsResponse> {
        .query(
            "groups.stats.get",
            GroupStatsInput(groupId: groupId, participantId: participantId)
        )
    }

    // MARK: - Activity

    public struct ActivitiesListInput: Encodable, Sendable {
        public let groupId: String
        public let cursor: Int?
        public let limit: Int?
    }

    public struct ActivitiesListResponse: Decodable, Sendable {
        public let activities: [Activity]
        public let hasMore: Bool
        public let nextCursor: Int
    }

    /// The group's activity log, newest first. Paged the same way the expense list is — an
    /// offset cursor rather than a key, which is what the server offers.
    public static func activities(
        groupId: String,
        cursor: Int = 0,
        limit: Int = 20
    ) -> TRPCProcedure<ActivitiesListInput, ActivitiesListResponse> {
        .query(
            "groups.activities.list",
            ActivitiesListInput(groupId: groupId, cursor: cursor, limit: limit)
        )
    }

    // MARK: - Categories

    public struct CategoriesResponse: Decodable, Sendable {
        public let categories: [ExpenseCategory]
    }

    public static func categories() -> TRPCProcedure<NoInput, CategoriesResponse> {
        .query("categories.list", NoInput())
    }
}
