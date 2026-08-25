//
//  AvafliV2LegalWebView.swift
//  AvafliSDK
//
//  In-experience legal pages (2.9.4): Official Rules and Privacy Policy render
//  in an in-app WKWebView sheet instead of kicking the user out to Safari.
//  The privacy policy loads with `?app=1`, which makes winrmedia.com/sdk/privacy
//  render its delete-my-data section; tapping delete there navigates to
//  `winr://delete`, which the SDK intercepts in the navigation delegate — no
//  custom URL-scheme registration is required of the host app — and hands to
//  the EXISTING destructive opt-out confirmation flow.
//

import SwiftUI
import WebKit

// MARK: - Routing (pure, testable)

/// One presentable legal document: the sheet's header title plus the URL the
/// webview loads.
struct AvafliV2LegalSheet: Identifiable, Equatable {
    let title: String
    let url: URL
    var id: String { title + "|" + url.absoluteString }
}

enum AvafliV2LegalRouting {

    static let rulesTitle = "Official Rules"
    static let privacyTitle = "Privacy Policy"

    /// The privacy policy URL AS LOADED IN-APP: the base policy with `app=1`
    /// appended (the page renders its delete-my-data section only then).
    /// Appends correctly whether or not the base already carries a query, and
    /// never doubles an existing `app` param.
    static func privacyPolicyURL(base: String = AvafliConstants.privacyURL) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "app" }) {
            items.append(URLQueryItem(name: "app", value: "1"))
        }
        components.queryItems = items
        return components.url
    }

    /// Maps a tapped in-experience link onto the sheet that should present it,
    /// or nil for URLs that are not the experience's legal documents (those
    /// keep the system open behavior). Matching is by string equality against
    /// the two known destinations: the rules URL (giveaway falling back to
    /// sdkConfig) and the hardcoded privacy URL.
    static func sheet(for url: URL, rulesUrl: String?) -> AvafliV2LegalSheet? {
        let tapped = url.absoluteString
        if let rulesUrl, tapped == rulesUrl {
            return AvafliV2LegalSheet(title: rulesTitle, url: url)
        }
        if tapped == AvafliConstants.privacyURL, let privacy = privacyPolicyURL() {
            return AvafliV2LegalSheet(title: privacyTitle, url: privacy)
        }
        return nil
    }
}

// MARK: - Native bridge (pure decision)

/// What the webview does with an attempted navigation. The delete deep link is
/// the ONLY native bridge: the privacy page (loaded with `?app=1`) navigates
/// there when its delete section is used, and the SDK cancels the navigation
/// and raises the existing opt-out confirmation. The live privacy page still
/// emits `winr://delete`; `avafli://delete` is accepted too so the page can
/// migrate schemes without an SDK release. Any other `winr://` / `avafli://`
/// navigation is cancelled quietly (nothing could load it anyway); everything
/// else — including external links inside the legal pages — loads in the
/// webview.
enum AvafliV2LegalBridge {
    /// Both bridge schemes are intercepted: the legacy `winr://` (what the
    /// live winrmedia.com privacy page emits today) and `avafli://` (the
    /// post-rebrand scheme).
    private static let bridgeSchemes: Set<String> = ["winr", "avafli"]

    enum Decision: Equatable {
        /// `winr://delete` or `avafli://delete` — cancel the navigation and
        /// raise the delete flow.
        case invokeDelete
        /// Unknown `winr://` / `avafli://` navigation — cancel, no side effect.
        case cancel
        /// Everything else — let the webview load it.
        case allow
    }

    static func decision(for url: URL?) -> Decision {
        guard let url, let scheme = url.scheme?.lowercased(),
              bridgeSchemes.contains(scheme) else { return .allow }
        // `winr://delete` / `avafli://delete` parse with host "delete";
        // tolerate a `winr:///delete`-style path form too.
        let target = (url.host ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return target == "delete" ? .invokeDelete : .cancel
    }
}

// MARK: - Sheet view

/// The in-experience legal sheet: slim gunmetal header (title + X), the
/// webview, a loading spinner until the first paint, and a simple retryable
/// error state when the load fails.
struct AvafliV2LegalWebView: View {
    let sheet: AvafliV2LegalSheet
    let accent: Color
    let onClose: () -> Void
    /// The privacy page's delete section navigated to `winr://delete`.
    let onDeleteRequested: () -> Void

    @State private var isLoading = true
    @State private var failed = false
    /// Bumped by RETRY — the representable reloads when it changes.
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(sheet.title)
                    .font(AvafliV2Font.inter(18, .black))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image("avafli-close", bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AvafliV2Color.deepCharcoal))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ZStack {
                AvafliV2LegalWebContainer(
                    url: sheet.url,
                    attempt: attempt,
                    onLoadingChanged: { loading in
                        isLoading = loading
                        if loading { failed = false }
                    },
                    onFailed: {
                        isLoading = false
                        failed = true
                    },
                    onDeleteRequested: onDeleteRequested
                )
                .opacity(failed ? 0 : 1)

                if isLoading && !failed {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                }

                if failed {
                    VStack(spacing: 14) {
                        Text("Couldn't load this page")
                            .font(AvafliV2Font.inter(18, .bold))
                            .foregroundColor(.white)
                        Text("Check your connection and try again.")
                            .font(AvafliV2Font.inter(14))
                            .foregroundColor(AvafliV2Color.textSecondary)
                            .multilineTextAlignment(.center)
                        AvafliV2PillButton(accent: accent, title: "RETRY") {
                            failed = false
                            isLoading = true
                            attempt += 1
                        }
                        .frame(maxWidth: 220)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AvafliV2Color.gunmetal.ignoresSafeArea())
    }
}

// MARK: - WKWebView wrapper

private struct AvafliV2LegalWebContainer: UIViewRepresentable {
    let url: URL
    let attempt: Int
    let onLoadingChanged: (Bool) -> Void
    let onFailed: () -> Void
    let onDeleteRequested: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(AvafliV2Color.gunmetal)
        webView.scrollView.backgroundColor = UIColor(AvafliV2Color.gunmetal)
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.loadedAttempt = attempt
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedAttempt != attempt {
            context.coordinator.loadedAttempt = attempt
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AvafliV2LegalWebContainer
        var loadedAttempt = 0

        init(_ parent: AvafliV2LegalWebContainer) { self.parent = parent }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            switch AvafliV2LegalBridge.decision(for: navigationAction.request.url) {
            case .invokeDelete:
                decisionHandler(.cancel)
                parent.onDeleteRequested()
            case .cancel:
                decisionHandler(.cancel)
            case .allow:
                // target="_blank" links have no frame to load into — route
                // them into this same webview instead of dropping the tap.
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            // A cancelled navigation (the winr:// bridge, or a rapid
            // re-navigation) is not a failure the user needs to see.
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            parent.onFailed()
        }
    }
}
