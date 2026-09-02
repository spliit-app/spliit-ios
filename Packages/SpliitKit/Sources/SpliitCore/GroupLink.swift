import Foundation

/// A group link somebody handed over on purpose: pasted into the app, or held up to the camera
/// as a QR code.
///
/// Deliberately more permissive than ``IncomingLink``, and the difference is the point. A link
/// the system opens arrives unsolicited, so it is checked against the instances this device is
/// entitled to open links for. A link someone types out, or points a camera at, was *chosen* —
/// the only question left is which group it names, and whether that group exists is answered by
/// looking it up rather than by reading the host.
///
/// It names two things, not one. A group ID means nothing without the server that issued it, and
/// taking the instance from the link is how somebody is let into a group on a server this device
/// has never talked to — which is most of what self-hosting is.
///
/// The shapes that reach here, all naming the same group:
///
/// ```
/// https://spliit.app/groups/<id>
/// https://spliit.app/groups/<id>/expenses?ref=share   what the web app's QR code encodes
/// https://home.example.com/spliit/groups/<id>         self-hosted, in a subdirectory
/// <id>                                                what people paste out of an address bar
/// ```
public struct GroupLink: Equatable, Sendable {

    public let groupID: String

    /// The instance the link names, or nil for a bare ID — which names none, and can only mean
    /// wherever the app points by default.
    public let instanceURL: URL?

    /// The group a URL names, or nil for a URL that names none — and for anything that is not a
    /// URL at all.
    ///
    /// This is the strict reading, and it is the one a scanned code gets. Anything can be
    /// printed on a QR code, and a bare word off a Wi-Fi sticker is not somebody's group.
    public init?(url text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host() != nil,
              let id = Self.groupID(in: url)
        else {
            return nil
        }
        groupID = id
        instanceURL = Self.instanceURL(of: url)
    }

    /// The group a pasted value names: a URL, or the bare ID people tend to paste when they copy
    /// from the address bar of a group they already have open.
    public init?(pastedText text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A link copied out of an address bar often arrives without its scheme, and
        // "spliit.example.com/groups/x" parses as a path with no host at all. Only ever assumed
        // for something with a slash in it: "https://" in front of a bare ID would make the ID
        // the hostname.
        let candidate = trimmed.contains("://") || !trimmed.contains("/")
            ? trimmed
            : "https://\(trimmed)"

        if let link = GroupLink(url: candidate) {
            self = link
            return
        }

        // A bare ID: no slashes, no spaces.
        guard !trimmed.contains("/"), !trimmed.contains(" ") else { return nil }
        groupID = trimmed
        instanceURL = nil
    }

    static func groupID(in url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "groups"),
              components.indices.contains(index + 1)
        else {
            return nil
        }
        let id = components[index + 1]
        return id.isEmpty ? nil : id
    }

    /// The instance a group link belongs to: everything before `/groups/…`, so an instance served
    /// from a subdirectory keeps it.
    static func instanceURL(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let index = url.pathComponents.firstIndex(of: "groups")
        else {
            return nil
        }
        let prefix = url.pathComponents[..<index].filter { $0 != "/" }
        components.path = "/" + prefix.joined(separator: "/") + (prefix.isEmpty ? "" : "/")
        components.query = nil
        components.fragment = nil
        // Lowercased, so a link somebody typed with a capital letter doesn't become a second
        // instance sitting beside the one it is.
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.url
    }
}
