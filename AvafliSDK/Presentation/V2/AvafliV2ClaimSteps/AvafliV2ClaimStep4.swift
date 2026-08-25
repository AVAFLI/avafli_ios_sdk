//
//  AvafliV2ClaimStep4.swift
//  AvafliSDK
//
//  "PLEASE SHARE A LITTLE" — since 2.9 this screen comes AFTER the claim is
//  submitted (the claim is already safe on the backend, so closing this
//  screen loses nothing). Multiline story text area plus the "Share on
//  Social Media:" glyph row with HONEST per-platform behavior:
//    • X — twitter.com intent URL, text prefilled with the winner line +
//      the publisher's shareUrl (when configured).
//    • Facebook — sharer.php with the shareUrl only (Facebook ignores
//      prefilled text); no shareUrl → system share sheet fallback.
//    • Instagram / Snapchat / TikTok — no text-prefill APIs exist, so these
//      open the system share sheet with the text + link. Same icons.
//

import SwiftUI

/// Full post-submit share screen: sparkle backdrop + header (close only) +
/// the share page. Shown between the review submit and the confirmation.
struct AvafliV2ClaimShareScreen: View {
    let accent: Color
    let logoUrl: String?
    /// "I just won {prize} in {appName}!" — built by the winner-flow root.
    let shareLine: String
    /// Publisher share link from sdkConfig (OPTIONAL — absent from current prod).
    let shareUrl: String?
    /// Receives the typed story on DONE / close / disappear. The receiver
    /// (view model) trims, drops blanks, dedupes, and sends it via the
    /// attachClaimStory callable — fire-and-forget, so a typed story is never
    /// lost but a failure never blocks (the claim is already submitted).
    let onStory: (String) -> Void
    let onDone: () -> Void
    let onClose: () -> Void

    /// The optional story lives here now (post-submit). The claim itself was
    /// already submitted, so closing loses nothing required.
    @State private var story = ""

    var body: some View {
        ZStack(alignment: .top) {
            AvafliV2Color.deepCharcoal.ignoresSafeArea()
            AvafliClaimSparkleBackdrop()

            VStack(spacing: 0) {
                AvafliClaimStepHeader(
                    logoUrl: logoUrl,
                    showsBack: false,
                    onBack: {},
                    onClose: {
                        onStory(story)
                        onClose()
                    }
                )
                .padding(.top, 18)

                AvafliClaimShareView(
                    accent: accent,
                    story: $story,
                    shareLine: shareLine,
                    shareUrl: shareUrl,
                    onDone: {
                        onStory(story)
                        onDone()
                    }
                )
            }
        }
        // Safety net for any other dismissal path (e.g. the host tearing the
        // experience down) — the receiver dedupes, so double-fires are safe.
        .onDisappear { onStory(story) }
    }
}

struct AvafliClaimShareView: View {
    let accent: Color
    @Binding var story: String
    /// "I just won {prize} in {app}!" — built by the flow root.
    let shareLine: String
    let shareUrl: String?
    let onDone: () -> Void

    @FocusState private var storyFocused: Bool
    @Environment(\.avafliScrollToField) private var scrollToField

    private static let storyAnchor = "avafli-claim-story"
    private static let placeholder =
        "Please share anything. What you\u{2019}re going to do with the prize, why you love our app, your favorite food, etc."

    var body: some View {
        AvafliClaimStepPage(
            accent: accent,
            title: "PLEASE SHARE A LITTLE",
            subtitle: "This helps us show real people like you win!",
            ctaTitle: "DONE",
            onCTA: onDone
        ) {
            storyEditor
                .padding(.top, 29)

            VStack(spacing: 15) {
                Text("Share on Social Media:")
                    .font(AvafliV2Font.inter(18, .medium))
                    .kerning(-0.54)
                    .foregroundColor(.white)
                HStack(spacing: 26) {
                    ForEach(AvafliSocialGlyph.Kind.allCases, id: \.self) { kind in
                        Button {
                            AvafliShareActions.share(kind: kind, text: shareLine, shareUrl: shareUrl)
                        } label: {
                            AvafliSocialGlyph(kind: kind)
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share on \(kind.displayName)")
                    }
                }
            }
            .padding(.top, 38)
            .padding(.bottom, 17)
        }
    }

    /// 199pt multiline text area in the Figma field styling, with the frame's
    /// placeholder while empty. Scrolls itself above the keyboard on focus.
    private var storyEditor: some View {
        ZStack(alignment: .topLeading) {
            editor
                .font(AvafliV2Font.inter(20))
                .foregroundColor(.white)
                .focused($storyFocused)
                .frame(height: 199)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            if story.isEmpty {
                Text(Self.placeholder)
                    .font(AvafliV2Font.inter(20))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 25)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(AvafliClaimStepTheme.fieldBackground)
        .id(Self.storyAnchor)
        .onChange(of: storyFocused) { focused in
            if focused { scrollToField(Self.storyAnchor) }
        }
    }

    @ViewBuilder private var editor: some View {
        if #available(iOS 16.0, *) {
            TextEditor(text: $story)
                .scrollContentBackground(.hidden)
        } else {
            TextEditor(text: $story)
                .onAppear { UITextView.appearance().backgroundColor = .clear }
        }
    }
}

// MARK: - Share actions (honest per-platform behavior)

enum AvafliShareActions {

    static func share(kind: AvafliSocialGlyph.Kind, text: String, shareUrl: String?) {
        // UTM-tag the publisher link with the tapped network so publishers can
        // attribute installs per network (system-share-sheet paths included).
        let shareUrl = taggedShareUrl(shareUrl, network: utmSource(for: kind))
        switch kind {
        case .x:
            // X supports prefilled text via the tweet intent URL.
            var tweet = text
            if let shareUrl, !shareUrl.isEmpty { tweet += " \(shareUrl)" }
            if let url = tweetIntentURL(text: tweet) {
                UIApplication.shared.open(url)
            }
        case .facebook:
            // Facebook's sharer accepts a URL only (prefilled text is ignored
            // by design). Without a configured shareUrl, fall back to the
            // system share sheet so the button still does something honest.
            if let sharer = facebookSharerURL(shareUrl: shareUrl) {
                UIApplication.shared.open(sharer)
            } else {
                presentSystemShare(text: text, shareUrl: shareUrl)
            }
        case .instagram, .snapchat, .tiktok:
            // No text-prefill share APIs exist for these platforms — the
            // system share sheet with the text + link is the honest path.
            presentSystemShare(text: text, shareUrl: shareUrl)
        }
    }

    /// utm_source value for the tapped network.
    static func utmSource(for kind: AvafliSocialGlyph.Kind) -> String {
        switch kind {
        case .x: return "x"
        case .facebook: return "facebook"
        case .instagram: return "instagram"
        case .snapchat: return "snapchat"
        case .tiktok: return "tiktok"
        }
    }

    /// Appends `utm_source={network}&utm_medium=avafli_share` to the publisher's
    /// shareUrl via URLComponents (correct whether or not the URL already has
    /// a query string). A URL that already carries `utm_source` is returned
    /// untouched — the publisher's own tagging wins. Unparseable URLs pass
    /// through unchanged.
    static func taggedShareUrl(_ shareUrl: String?, network: String) -> String? {
        guard let shareUrl, !shareUrl.isEmpty,
              var components = URLComponents(string: shareUrl) else { return shareUrl }
        var items = components.queryItems ?? []
        guard !items.contains(where: { $0.name == "utm_source" }) else { return shareUrl }
        items.append(URLQueryItem(name: "utm_source", value: network))
        items.append(URLQueryItem(name: "utm_medium", value: "avafli_share"))
        components.queryItems = items
        return components.url?.absoluteString ?? shareUrl
    }

    /// https://twitter.com/intent/tweet?text={encoded} — URLComponents does
    /// the percent-encoding.
    static func tweetIntentURL(text: String) -> URL? {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }

    /// https://www.facebook.com/sharer/sharer.php?u={shareUrl}; nil without a
    /// configured shareUrl.
    static func facebookSharerURL(shareUrl: String?) -> URL? {
        guard let shareUrl, !shareUrl.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.facebook.com/sharer/sharer.php")
        components?.queryItems = [URLQueryItem(name: "u", value: shareUrl)]
        return components?.url
    }

    private static func presentSystemShare(text: String, shareUrl: String?) {
        var line = text
        if let shareUrl, !shareUrl.isEmpty { line += " \(shareUrl)" }
        AvafliShareSheet.present(text: line)
    }
}

// MARK: - Share sheet

/// Presents the system share sheet from the top-most view controller.
enum AvafliShareSheet {
    static func present(text: String) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let root = window?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        // iPad popover anchor (defensive — the SDK sheet is iPhone-first).
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1
        )
        top.present(sheet, animated: true)
    }
}
