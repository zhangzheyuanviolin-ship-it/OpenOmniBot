@preconcurrency import Flutter
import Foundation
import WebKit

@MainActor
final class AgentBrowserPlatformViewFactory: NSObject, @preconcurrency FlutterPlatformViewFactory {
    static let viewType = "cn.com.omnimind.bot/agent_browser_view"

    static func register(with engine: FlutterEngine) {
        let registrar = engine.registrar(forPlugin: "OmnibotAgentBrowserPlatformView")
        let factory = AgentBrowserPlatformViewFactory()
        registrar?.register(factory, withId: viewType)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let parameters = args as? [String: Any]
        return AgentBrowserPlatformView(
            frame: frame,
            viewId: viewId,
            parameters: parameters
        )
    }
}

@MainActor
private final class AgentBrowserPlatformView: NSObject, @preconcurrency FlutterPlatformView, WKNavigationDelegate {
    private let containerView = UIView()
    private let webView: WKWebView
    private let workspaceId: String
    private let activeTabId: Int64
    private let initialTitle: String
    private let userAgentProfile: String?

    init(
        frame: CGRect,
        viewId: Int64,
        parameters: [String: Any]?
    ) {
        workspaceId = (parameters?["workspaceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        initialTitle = (parameters?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        userAgentProfile = (parameters?["userAgentProfile"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTabId = viewId

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: frame, configuration: configuration)

        super.init()

        containerView.backgroundColor = .secondarySystemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isInspectable = true
        if let userAgentProfile, userAgentProfile.isEmpty == false {
            webView.customUserAgent = userAgentProfile
        }

        containerView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        let initialURL = resolvedInitialURL(from: parameters)
        BrowserSessionStore.shared.update(
            available: true,
            workspaceId: workspaceId,
            activeTabId: activeTabId,
            currentUrl: initialURL.absoluteString,
            title: resolvedTitle(for: initialURL),
            userAgentProfile: userAgentProfile
        )
        webView.load(URLRequest(url: initialURL))
    }

    func view() -> UIView {
        containerView
    }

    func dispose() {
        BrowserSessionStore.shared.markDetached(
            workspaceId: workspaceId,
            activeTabId: activeTabId
        )
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshSnapshot(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshSnapshot(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        refreshSnapshot(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        refreshSnapshot(from: webView)
    }

    private func resolvedInitialURL(from parameters: [String: Any]?) -> URL {
        if let rawURL = (parameters?["currentUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let candidate = makeBrowsableURL(from: rawURL) {
            return candidate
        }
        if let persisted = BrowserSessionStore.shared.snapshot(for: workspaceId),
           let candidate = makeBrowsableURL(from: persisted.currentUrl) {
            return candidate
        }
        return URL(string: "about:blank")!
    }

    private func makeBrowsableURL(from rawURL: String) -> URL? {
        guard rawURL.isEmpty == false else { return nil }
        if let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(), ["http", "https", "about", "file"].contains(scheme) {
            return url
        }
        if rawURL.contains("://") == false {
            return URL(string: "https://\(rawURL)")
        }
        return nil
    }

    private func resolvedTitle(for url: URL) -> String {
        if initialTitle.isEmpty == false {
            return initialTitle
        }
        if let host = url.host, host.isEmpty == false {
            return host
        }
        return "Omnibot Browser"
    }

    private func refreshSnapshot(from webView: WKWebView) {
        BrowserSessionStore.shared.update(
            available: true,
            workspaceId: workspaceId,
            activeTabId: activeTabId,
            currentUrl: webView.url?.absoluteString ?? "",
            title: webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? resolvedTitle(for: webView.url ?? URL(string: "about:blank")!),
            userAgentProfile: userAgentProfile
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
