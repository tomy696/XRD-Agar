import SwiftUI
import WebKit

struct AgarWebView: UIViewRepresentable {
    @ObservedObject var settings: GameSettings
    let bridge: GameJSBridge

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = config.userContentController
        contentController.add(bridge, name: "xrdBridge")

        if let jsPath = Bundle.main.path(forResource: "inject", ofType: "js"),
           let jsContent = try? String(contentsOfFile: jsPath, encoding: .utf8) {
            let script = WKUserScript(
                source: jsContent,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(script)
        }

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        if let url = URL(string: "https://agar.io") {
            webView.load(URLRequest(url: url))
        }

        context.coordinator.webView = webView
        bridge.settings = settings

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let zoom = settings.zoomLevel
        webView.evaluateJavaScript("if(window.XRD) XRD.setZoom(\(zoom));")

        let autoFeed = settings.isAutoFeeding
        webView.evaluateJavaScript("if(window.XRD) XRD.setAutoFeed(\(autoFeed));")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var webView: WKWebView?

        func getPlayerPosition(uid: String, completion: @escaping ((x: Double, y: Double)?) -> Void) {
            webView?.evaluateJavaScript("XRD.getPlayerPosition('\(uid)')") { result, _ in
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let x = dict["x"] as? Double,
                      let y = dict["y"] as? Double else {
                    completion(nil)
                    return
                }
                completion((x, y))
            }
        }
    }
}
