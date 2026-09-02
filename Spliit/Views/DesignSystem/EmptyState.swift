import SwiftUI

/// The screen with nothing on it — six of these exist, and one of them is the first thing anyone
/// ever sees of the app.
///
/// `ContentUnavailableView` did this job correctly and anonymously: a grey SF Symbol, a title and
/// a line of text, identical in every app that ships one. This keeps the same shape and gives it
/// the app's own voice — the rounded display face for the title, and either the brand mark or an
/// icon held in a tinted tile.
struct EmptyState<Actions: View>: View {

    enum Art {
        /// The brand mark. Reserved for welcome and first-run — the places where naming the app
        /// is the point. An error is not an occasion for a logo.
        case logo
        /// An SF Symbol, in a tile tinted with the accent.
        case icon(String)
    }

    let art: Art
    let title: Text
    var description: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        // Centred when it fits, scrollable when it doesn't. At the largest accessibility sizes a
        // title, a description and two buttons are taller than the screen, and an empty state
        // whose only action has fallen off the bottom is worse than no empty state at all.
        GeometryReader { proxy in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            artwork

            VStack(spacing: 8) {
                title
                    .font(.system(.title3, design: .rounded, weight: .bold))

                if let description {
                    description
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        // Long enough to read, short enough to stay a paragraph rather than a line
                        // running the full width of an iPad.
                        .frame(maxWidth: 320)
                }
            }
            .multilineTextAlignment(.center)

            actions.padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    /// Fixed size, deliberately: this is the one thing on the screen that does not scale with
    /// Dynamic Type. At the largest sizes the description alone is taller than the phone, and a
    /// decoration that grew along with it would push the button further out of reach to say
    /// nothing extra.
    @ViewBuilder
    private var artwork: some View {
        switch art {
        case .logo:
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 60)
                .accessibilityHidden(true)

        case .icon(let systemName):
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(
                    Color.brandAccentSoft,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }
}

extension EmptyState where Actions == EmptyView {
    init(art: Art, title: Text, description: Text? = nil) {
        self.init(art: art, title: title, description: description) { EmptyView() }
    }
}

#Preview("Welcome") {
    EmptyState(
        art: .logo,
        title: Text("Welcome to Spliit"),
        description: Text("Create a group to start splitting expenses with friends.")
    ) {
        VStack(spacing: 12) {
            Button("Create group") {}.buttonStyle(.borderedProminent)
            HStack(spacing: 12) {
                Button("Add by link") {}
                Button("Add by QR code") {}
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview("Error") {
    EmptyState(
        art: .icon("wifi.exclamationmark"),
        title: Text("Couldn’t load this group"),
        description: Text("The server didn’t respond.")
    ) {
        Button("Try again") {}.buttonStyle(.borderedProminent)
    }
}
