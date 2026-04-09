import SwiftUI
import WebKit

/// Hosts the React dashboard in a WKWebView with the custom app:// scheme handler.
struct DashboardWindow: NSViewRepresentable {

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Register custom URL scheme handler for API calls
        config.setURLSchemeHandler(APISchemeHandler(), forURLScheme: "app")

        // Inject desktop mode flag so React uses app:// for API calls
        let script = WKUserScript(
            source: "window.__MEETINGSCRIBE_DESKTOP__ = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)

        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        // Load: bundled static files first, fallback to dev server
        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web-dashboard") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        } else {
            // Dev mode: load from Next.js dev server
            webView.load(URLRequest(url: URL(string: "http://localhost:3000")!))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No updates needed
    }
}
