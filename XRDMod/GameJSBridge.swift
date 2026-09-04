import UIKit
import WebKit

class GameJSBridge: NSObject, WKScriptMessageHandler {
    private var injectedWebViews = NSHashTable<WKWebView>.weakObjects()
    private var scanTimer: Timer?

    private(set) var isConnected = false
    private(set) var statusInfo: String = "Scanning..."
    private(set) var connectedURLs: [String] = []
    private(set) var scannedCount: Int = 0
    var onConnected: (() -> Void)?

    func setup(in window: UIWindow) {
        scanAndInject()
        var attempts = 0
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            attempts += 1
            self.scanAndInject()
            if attempts >= 60 && self.injectedWebViews.count == 0 {
                self.statusInfo = "No WebView found"
                timer.invalidate()
            }
        }
    }

    private func scanAndInject() {
        var found = 0
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                found += injectAllWebViews(in: window)
            }
        }
        scannedCount = found
    }

    private func injectAllWebViews(in view: UIView) -> Int {
        var count = 0
        if let wv = view as? WKWebView {
            if !injectedWebViews.contains(wv) {
                attach(to: wv)
                count += 1
            }
        }
        for sub in view.subviews {
            count += injectAllWebViews(in: sub)
        }
        return count
    }

    private func attach(to wv: WKWebView) {
        injectedWebViews.add(wv)

        wv.configuration.userContentController.add(self, name: "xrdBridge")

        let jsCode = loadJS()

        let userScript = WKUserScript(source: jsCode, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        wv.configuration.userContentController.addUserScript(userScript)

        wv.evaluateJavaScript(jsCode) { [weak self] _, error in
            if let error = error {
                let msg = error.localizedDescription.prefix(40)
                self?.statusInfo = "JS err: \(msg)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    wv.evaluateJavaScript(jsCode) { _, _ in }
                }
            }
        }

        let url = wv.url?.absoluteString ?? "about:blank"
        connectedURLs.append(String(url.prefix(80)))
        statusInfo = "Injected \(injectedWebViews.count) WKWebView(s)"
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
            statusInfo = "WS captured: \(String(data.prefix(40)))"
        case "ready":
            isConnected = true
            statusInfo = "JS active (\(injectedWebViews.count) WV)"
            onConnected?()
        case "hooks":
            statusInfo = "Hooks \(data) (\(injectedWebViews.count) WV)"
        default:
            break
        }
    }

    // MARK: - JS calls

    func setZoom(_ level: CGFloat) {
        for wv in injectedWebViews.allObjects {
            wv.evaluateJavaScript("typeof XRD !== 'undefined' && XRD.setZoom(\(level))") { _, _ in }
        }
    }

    func setFeedInterval(_ ms: Int) {
        for wv in injectedWebViews.allObjects {
            wv.evaluateJavaScript("typeof XRD !== 'undefined' && XRD.setFeedInterval(\(ms))") { _, _ in }
        }
    }

    func sendFeed() {
        for wv in injectedWebViews.allObjects {
            wv.evaluateJavaScript("typeof XRD !== 'undefined' && XRD.sendFeed()") { _, _ in }
        }
    }

    // MARK: - JS loading

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

    // MARK: - Fallback inline JS (minimal zoom only)

    private static let fallbackJS = """
    (function(){
        if(window._xrdInjected) return;
        window._xrdInjected = true;
        var z=1,aws=null;
        var oSend=WebSocket.prototype.send;
        WebSocket.prototype.send=function(d){
            if(this.url&&aws!==this){aws=this;try{window.webkit.messageHandlers.xrdBridge.postMessage({type:'serverURL',data:this.url})}catch(e){}}
            return oSend.call(this,d);
        };
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
            aws=ws;
            return ws;
        };
        window.WebSocket.prototype=oWS.prototype;
        window.XRD={
            setZoom:function(l){z=l},
            sendFeed:function(){if(aws&&aws.readyState===1){var p=new ArrayBuffer(1);new DataView(p).setUint8(0,21);aws.send(p)}},
            setFeedInterval:function(){}
        };
        try{window.webkit.messageHandlers.xrdBridge.postMessage({type:'ready',data:'fallback'})}catch(e){}
    })();
    """
}
