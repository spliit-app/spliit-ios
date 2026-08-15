import Foundation

/// Identifiers the UI tests look for.
///
/// Kept in one place, and applied in the same commit that adds the view. Retrofitting
/// identifiers across a grown app is the thing that makes UI suites get abandoned.
///
/// **Put these on leaves, never on containers.** SwiftUI's `.accessibilityIdentifier` applies
/// to every descendant of the view it modifies, and an outer one silently replaces the
/// identifiers set inside it — so a screen-level identifier on a `NavigationStack` erases the
/// identifiers of every button beneath it. That is why there is no `screen` entry here:
/// to assert a screen is showing, look for something only that screen has.
enum AccessibilityID {

    enum GroupsList {
        static let createGroupButton = "groups.create"
        static let addByURLButton = "groups.addByURL"
        static let settingsButton = "groups.settings"
        static let loadFailed = "groups.loadFailed"

        static func rowTitle(_ groupID: String) -> String { "groups.row.\(groupID).title" }
        static func rowParticipants(_ groupID: String) -> String {
            "groups.row.\(groupID).participants"
        }
    }

    enum Settings {
        static let baseURLField = "settings.baseURL"
        static let resetButton = "settings.reset"
        static let doneButton = "settings.done"
        static let version = "settings.version"
    }
}
