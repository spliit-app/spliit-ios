import Foundation

/// A link that arrived from outside the app: a shared group URL, or the custom scheme the
/// React Native app registered and this one inherited.
///
/// Three shapes reach here, and all three mean the same thing:
///
/// ```
/// https://spliit.app/groups/<id>                 a shared link, once the site vouches for us
/// https://my-instance.example.com/groups/<id>    the same, self-hosted
/// app.spliit.spliitmobile://groups/<id>          the scheme carried over from the old app
/// ```
///
/// The custom scheme has been declared in `Info.plist` since the first commit and nothing has
/// ever consumed it, so a link written for the old app opened this one and then sat there.
public enum IncomingLink: Equatable, Sendable {

    /// - Parameter instanceURL: the server the link names, which is the one that can answer for
    ///   the group. Nil for the custom scheme, which carries no address at all — there the app's
    ///   default is the only thing left to try.
    case group(id: String, instanceURL: URL?)

    /// - Parameter knownOrigins: the instances this device is entitled to open links for. A link
    ///   to anywhere else is somebody else's website and is left to Safari.
    public static func parse(_ url: URL, knownOrigins: Set<String>) -> IncomingLink? {
        if url.scheme == officialScheme {
            // No origin to check: only this app can be sent this scheme in the first place.
            guard let id = groupID(in: url.pathComponents, host: url.host()) else { return nil }
            return .group(id: id, instanceURL: nil)
        }

        guard let origin = origin(of: url), knownOrigins.contains(origin) else { return nil }
        // Past the origin check it is the same reading as a link somebody pasted, so it is the
        // same code: what a group URL says is one thing, and ``GroupLink`` is where it is said.
        guard let link = GroupLink(url: url.absoluteString) else { return nil }
        return .group(id: link.groupID, instanceURL: link.instanceURL)
    }

    public static let officialScheme = "app.spliit.spliitmobile"

    /// What a link is allowed to name, given the instances this device already talks to.
    ///
    /// Scheme *and* host, not host alone. A self-hosted instance on a home network is reachable
    /// over plain http — the app allows exactly that, and so does the end-to-end harness — so
    /// http cannot simply be refused. But matching each instance's own scheme means an
    /// `http://spliit.app/…` link is still refused while the groups from there are on https,
    /// which is what a downgrade would look like.
    public static func knownOrigins(instances: some Collection<URL>) -> Set<String> {
        Set(instances.compactMap { origin(of: $0) } + ["https://spliit.app"])
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else {
            return nil
        }
        guard scheme == "https" || scheme == "http" else { return nil }
        if let port = url.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    /// `app.spliit.spliitmobile://groups/<id>` parses with "groups" as the *host* rather than a
    /// path component, so both readings have to be tried.
    private static func groupID(in components: [String], host: String?) -> String? {
        if host == "groups", let id = components.first(where: { $0 != "/" }), !id.isEmpty {
            return id
        }
        guard let index = components.firstIndex(of: "groups"),
              components.indices.contains(index + 1)
        else {
            return nil
        }
        let id = components[index + 1]
        return id.isEmpty ? nil : id
    }

}
