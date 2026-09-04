import UIKit
import WebKit

class GameJSBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private var injected = false
    private var scanTimer: Timer?

    private(set) var isConnected = false
    var onConnected: (() -> Void)?

    func setup(in window: UIWindow) {
        if let wv = findWebView(in: window) {
            attach(to: wv)
            return
        }
        var attempts = 0
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak window] timer in
            guard let self = self, let window = window else { timer.invalidate(); return }
            attempts += 1
            if let wv = self.findWebView(in: window) {
                self.attach(to: wv)
                timer.invalidate()
            } else if attempts > 20 {
                timer.invalidate()
            }
        }
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let wv = view as? WKWebView { return wv }
        for sub in view.subviews {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }

    private func attach(to wv: WKWebView) {
        guard !injected else { return }
        webView = wv

        wv.configuration.userContentController.add(self, name: "xrdBridge")

        let bundle = Bundle(for: GameJSBridge.self)
        guard let jsURL = bundle.url(forResource: "inject", withExtension: "js"),
              let jsCode = try? String(contentsOf: jsURL) else { return }

        let userScript = WKUserScript(source: jsCode, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        wv.configuration.userContentController.addUserScript(userScript)

        wv.evaluateJavaScript(jsCode) { _, _ in }

        injected = true
        isConnected = true
        onConnected?()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let data = body["data"] as? String else { return }

        switch type {
        case "serverURL":
            NetworkInterceptor.shared.setManualServer(data)
        case "ready":
            isConnected = true
        default:
            break
        }
    }

    // MARK: - JS calls

    func setZoom(_ level: CGFloat) {
        webView?.evaluateJavaScript("XRD.setZoom(\(level))") { _, _ in }
    }

    func setFeedInterval(_ ms: Int) {
        webView?.evaluateJavaScript("XRD.setFeedInterval(\(ms))") { _, _ in }
    }

    func sendFeed() {
        webView?.evaluateJavaScript("XRD.sendFeed()") { _, _ in }
    }
}
