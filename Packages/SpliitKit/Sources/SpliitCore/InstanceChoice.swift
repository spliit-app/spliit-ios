import Foundation

/// Which Spliit instance a new group will be created on, while the form is open.
///
/// A group's address belongs to the group rather than to the app, so this is a form field like
/// any other — and like the others it has to be able to hold something unfinished. Somebody
/// half-way through typing "spliit.exa" has not made a mistake yet, so the address is kept as
/// text and only becomes a URL once it parses as one.
public struct InstanceChoice: Equatable, Sendable {

    /// The instance chosen from the list, and what the group is created on unless an address is
    /// being typed instead.
    public var url: URL

    /// True once "Other server" has been chosen. It stays true while the address is unusable, so
    /// the field cannot disappear from under whoever is typing in it.
    public var isTypingAddress: Bool

    /// What has been typed so far, which is not a URL until it is.
    public var address: String

    public init(url: URL, isTypingAddress: Bool = false, address: String = "") {
        self.url = url
        self.isTypingAddress = isTypingAddress
        self.address = address
    }

    /// The instance to create on, or nil while the typed address isn't one.
    public var resolved: URL? {
        isTypingAddress ? SettingsStore.normalize(address) : url
    }

    public var isValid: Bool { resolved != nil }

    /// Takes an instance chosen from the list. Also the way back from a typed address.
    public mutating func use(_ url: URL) {
        self.url = url
        isTypingAddress = false
        address = ""
    }

    /// Switches to typing an address that isn't in the list yet — how a group on a server this
    /// device has never talked to gets created.
    public mutating func typeAddress() {
        isTypingAddress = true
    }
}
