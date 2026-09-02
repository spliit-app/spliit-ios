import Foundation

/// A group link somebody handed over on purpose: pasted into the app, or held up to the camera
/// as a QR code.
///
/// Deliberately more permissive than ``IncomingLink``, and the difference is the point. A link
/// the system opens arrives unsolicited, so it is checked against the instances this device is
/// entitled to open links for. A link someone types out, or points a camera at, was *chosen* —
/// the only question left is which group it names, and whether that group is on the instance the
/// app is pointed at is answered by looking it up rather than by reading the host.
///
/// The shapes that reach here, all naming the same group:
///
/// ```
/// https://spliit.app/groups/<id>
/// https://spliit.app/groups/<id>/expenses?ref=share   what the web app's QR code encodes
/// <id>                                                what people paste out of an address bar
/// ```
public enum GroupLink {

    /// The group a URL names, or nil for a URL that names none — and for anything that is not a
    /// URL at all.
    ///
    /// This is the strict reading, and it is the one a scanned code gets. Anything can be
    /// printed on a QR code, and a bare word off a Wi-Fi sticker is not somebody's group.
    public static func groupID(inURL text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host() != nil else { return nil }

        let components = url.pathComponents
        guard let index = components.firstIndex(of: "groups"),
              components.indices.contains(index + 1)
        else {
            return nil
        }
        let id = components[index + 1]
        return id.isEmpty ? nil : id
    }

    /// The group a pasted value names: a URL, or the bare ID people tend to paste when they copy
    /// from the address bar of a group they already have open.
    public static func groupID(inPastedText text: String) -> String? {
        if let id = groupID(inURL: text) { return id }

        // A bare ID: no slashes, no spaces.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains(" ") else { return nil }
        return trimmed
    }
}
