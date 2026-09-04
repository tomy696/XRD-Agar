import UIKit
import WebKit

class GameJSBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private var injected = false
    private var scanTimer: Timer?

    private(set) var isConnected = false
    private(set) var statusInfo: String = "Scanning..."
    var onConnected: (() -> Void)?

    func setup(in window: UIWindow) {
        if let wv = findWebViewAnywhere() ?? findWebView(in: window) {
            waitAndAttach(to: wv)
            return
        }
        var attempts = 0
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            attempts += 1
            if let wv = self.findWebViewAnywhere() {
                self.waitAndAttach(to: wv)
                timer.invalidate()
            } else if attempts >= 30 {
                self.statusInfo = "No WebView found"
                timer.invalidate()
            }
        }
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let wv = view as? WKWebView { return wv }
        let className = String(describing: type(of: view))
        if className.contains("WKWebView") || className.contains("WebView") {
            if let wv = view as? WKWebView { return wv }
        }
        for sub in view.subviews {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }

    private func findWebViewAnywhere() -> WKWebView? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                if let wv = findWebView(in: window) { return wv }
            }
        }
        return nil
    }

    private func waitAndAttach(to wv: WKWebView) {
        if wv.isLoading {
            statusInfo = "WebView loading..."
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.waitAndAttach(to: wv)
            }
            return
        }
        attach(to: wv)
    }

    private func attach(to wv: WKWebView) {
        guard !injected else { return }
        webView = wv
        injected = true
        statusInfo = "Injecting JS..."

        wv.configuration.userContentController.add(self, name: "xrdBridge")

        let jsCode = loadJS()

        let userScript = WKUserScript(source: jsCode, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        wv.configuration.userContentController.addUserScript(userScript)

        wv.evaluateJavaScript(jsCode) { [weak self] _, error in
            if let error = error {
                self?.statusInfo = "JS error: \(error.localizedDescription.prefix(40))"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.retryEval(on: wv, js: jsCode)
                }
            }
        }
    }

    private func retryEval(on wv: WKWebView, js: String) {
        wv.evaluateJavaScript(js) { [weak self] _, error in
            if error != nil {
                self?.statusInfo = "JS retry failed"
            }
        }
    }

    private func loadJS() -> String {
        let bundle = Bundle(for: GameJSBridge.self)
        if let jsURL = bundle.url(forResource: "inject", withExtension: "js"),
           let jsCode = try? String(contentsOf: jsURL) {
            return jsCode
        }
        if let jsURL = Bundle.main.url(forResource: "inject", withExtension: "js"),
           let jsCode = try? String(contentsOf: jsURL) {
            return jsCode
        }
        return GameJSBridge.fallbackJS
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        let data = body["data"] as? String ?? ""

        switch type {
        case "serverURL":
            NetworkInterceptor.shared.setManualServer(data)
        case "ready":
            isConnected = true
            statusInfo = "JS active"
            onConnected?()
        case "hooks":
            statusInfo = "Hooks \(data)"
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

    // MARK: - Fallback inline JS (minimal zoom only)

    private static let fallbackJS = """
    (function(){
        var z=1;
        var oS=CanvasRenderingContext2D.prototype.scale;
        CanvasRenderingContext2D.prototype.scale=function(x,y){
            if(z!==1&&this.canvas&&this.canvas.width>100)return oS.call(this,x*z,y*z);
            return oS.call(this,x,y);
        };
        var oST=CanvasRenderingContext2D.prototype.setTransform;
        CanvasRenderingContext2D.prototype.setTransform=function(a,b,c,d,e,f){
            if(typeof a==='number'&&z!==1&&this.canvas&&this.canvas.width>100&&a===d&&b===0&&c===0&&Math.abs(a)!==1)
                return oST.call(this,a*z,b,c,d*z,e,f);
            return oST.call(this,a,b,c,d,e,f);
        };
        var oWS=window.WebSocket;
        window.WebSocket=function(u,p){
            try{window.webkit.messageHandlers.xrdBridge.postMessage({type:'serverURL',data:u})}catch(e){}
            var ws=p?new oWS(u,p):new oWS(u);
            window._xrdWS=ws;
            return ws;
        };
        window.WebSocket.prototype=oWS.prototype;
        window.XRD={
            setZoom:function(l){z=l},
            sendFeed:function(){var ws=window._xrdWS;if(ws&&ws.readyState===1){var p=new ArrayBuffer(1);new DataView(p).setUint8(0,21);ws.send(p)}},
            setFeedInterval:function(){}
        };
        try{window.webkit.messageHandlers.xrdBridge.postMessage({type:'ready',data:'fallback'})}catch(e){}
    })();
    """
}
