import UIKit
import SwiftUI
import WebKit
import Combine

class XRDOverlay: NSObject {
    static let shared = XRDOverlay()

    let settings = GameSettings()
    let botEngine = BotEngine()
    let bridge = GameJSBridge()

    weak var capturedWebView: WKWebView?
    private var overlayWindow: XRDWindow?
    private var toggleButton: UIButton?
    private var menuHosting: UIHostingController<AnyView>?
    private var licenseHosting: UIHostingController<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var isMenuVisible = false
    private var scanTimer: Timer?
    private var targetTimer: Timer?

    func setup() {
        bridge.settings = settings
        setupObservers()
        createWindow()

        if LicenseManager.shared.isValid {
            showOverlayUI()
        } else {
            showLicenseView()
        }

        startWebViewScan()
        setupTargetTracking()
    }

    // MARK: - Settings → JS bridge

    private func setupObservers() {
        settings.$zoomLevel
            .dropFirst()
            .sink { [weak self] zoom in
                self?.evaluateJS("if(window.XRD) XRD.setZoom(\(zoom));")
            }
            .store(in: &cancellables)

        settings.$isAutoFeeding
            .dropFirst()
            .sink { [weak self] feeding in
                self?.evaluateJS("if(window.XRD) XRD.setAutoFeed(\(feeding));")
            }
            .store(in: &cancellables)
    }

    func evaluateJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.capturedWebView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - Window

    private func createWindow() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let window = XRDWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC
        window.isHidden = false

        overlayWindow = window
    }

    // MARK: - License

    private func showLicenseView() {
        guard let rootVC = overlayWindow?.rootViewController else { return }

        let licenseView = LicenseView(licenseManager: LicenseManager.shared) { [weak self] in
            self?.hideLicenseView()
            self?.showOverlayUI()
        }

        let hosting = UIHostingController(rootView: AnyView(licenseView))
        hosting.view.frame = rootVC.view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rootVC.addChild(hosting)
        rootVC.view.addSubview(hosting.view)
        hosting.didMove(toParent: rootVC)

        licenseHosting = hosting
        overlayWindow?.makeKeyAndVisible()
    }

    private func hideLicenseView() {
        licenseHosting?.willMove(toParent: nil)
        licenseHosting?.view.removeFromSuperview()
        licenseHosting?.removeFromParent()
        licenseHosting = nil
        overlayWindow?.resignKey()
    }

    // MARK: - Overlay UI

    private func showOverlayUI() {
        addToggleButton()
    }

    private func addToggleButton() {
        guard let rootView = overlayWindow?.rootViewController?.view else { return }

        let btn = UIButton(type: .custom)
        let screenW = UIScreen.main.bounds.width
        btn.frame = CGRect(x: screenW - 62, y: 50, width: 50, height: 50)
        btn.layer.cornerRadius = 25
        btn.clipsToBounds = true
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        btn.layer.borderWidth = 2
        btn.layer.borderColor = UIColor(red: 0.459, green: 0.318, blue: 0.957, alpha: 1).cgColor
        btn.setTitle("XRD", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .black)
        btn.setTitleColor(.white, for: .normal)
        btn.addTarget(self, action: #selector(toggleMenu), for: .touchUpInside)

        rootView.addSubview(btn)
        toggleButton = btn
    }

    @objc private func toggleMenu() {
        if isMenuVisible {
            hideMenu()
        } else {
            showMenu()
        }
        isMenuVisible.toggle()
    }

    private func showMenu() {
        guard let rootVC = overlayWindow?.rootViewController else { return }
        let rootView = rootVC.view!

        let menuView = ModMenuView(settings: settings, botEngine: botEngine)
        let hosting = UIHostingController(rootView: AnyView(menuView))
        hosting.view.backgroundColor = .clear

        let menuWidth: CGFloat = 340
        let menuHeight: CGFloat = 520
        let x = rootView.bounds.width - menuWidth - 8
        let y = (rootView.bounds.height - menuHeight) / 2
        hosting.view.frame = CGRect(x: x, y: y, width: menuWidth, height: menuHeight)

        rootVC.addChild(hosting)
        rootView.addSubview(hosting.view)
        hosting.didMove(toParent: rootVC)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMenuDrag(_:)))
        hosting.view.addGestureRecognizer(pan)

        hosting.view.alpha = 0
        hosting.view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            hosting.view.alpha = 1
            hosting.view.transform = .identity
        }

        menuHosting = hosting
    }

    private func hideMenu() {
        guard let hosting = menuHosting else { return }
        UIView.animate(withDuration: 0.2, animations: {
            hosting.view.alpha = 0
            hosting.view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) { _ in
            hosting.willMove(toParent: nil)
            hosting.view.removeFromSuperview()
            hosting.removeFromParent()
        }
        menuHosting = nil
    }

    @objc private func handleMenuDrag(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let translation = gesture.translation(in: view.superview)
        view.center = CGPoint(x: view.center.x + translation.x, y: view.center.y + translation.y)
        gesture.setTranslation(.zero, in: view.superview)
    }

    // MARK: - Target tracking

    private func setupTargetTracking() {
        bridge.onPlayersUpdated = { [weak self] players in
            guard let self = self else { return }
            let uid = self.settings.botConfig.targetUID
            if !uid.isEmpty, let target = players.first(where: { $0.uid == uid }) {
                self.settings.targetPlayer = target
                self.botEngine.updateTargetFromPlayer(target)
            }
        }

        targetTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self,
                  let target = self.settings.targetPlayer,
                  let updated = self.settings.currentPlayers.first(where: { $0.id == target.id }) else { return }
            self.settings.targetPlayer = updated
            self.botEngine.updateTargetFromPlayer(updated)
        }
    }

    // MARK: - WebView scanning

    private func startWebViewScan() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if let webView = self.findWebView() {
                self.hookWebView(webView)
                timer.invalidate()
                self.scanTimer = nil
            }
        }
    }

    private func findWebView() -> WKWebView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        for window in windows {
            if window === overlayWindow { continue }
            if let wk = findWebViewIn(view: window) {
                return wk
            }
        }
        return nil
    }

    private func findWebViewIn(view: UIView) -> WKWebView? {
        if let wk = view as? WKWebView { return wk }
        for subview in view.subviews {
            if let wk = findWebViewIn(view: subview) { return wk }
        }
        return nil
    }

    private func hookWebView(_ webView: WKWebView) {
        capturedWebView = webView

        let js: String
        if let jsPath = Bundle(for: XRDLoader.self).path(forResource: "inject", ofType: "js"),
           let content = try? String(contentsOfFile: jsPath, encoding: .utf8) {
            js = content
        } else {
            js = injectedJSFallback

        }

        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "xrdBridge")
        webView.configuration.userContentController.add(bridge, name: "xrdBridge")

        webView.evaluateJavaScript(js, completionHandler: nil)
        settings.isConnected = true
    }

    // Inline JS fallback in case bundle resource loading fails
    private var injectedJSFallback: String {
        """
        (function(){
        'use strict';
        if(window.XRD) return;
        const XRD={zoomLevel:1,autoFeed:false,players:{},ownIDs:[],serverURL:'',activeWS:null,
        init:function(){this.hookCanvas();this.hookWebSocket();this.startPlayerScan();this.setupFeedLoop()},
        hookCanvas:function(){const o=HTMLCanvasElement.prototype.getContext;const s=this;
        HTMLCanvasElement.prototype.getContext=function(t,a){const c=o.call(this,t,a);
        if(t==='2d'&&this.width>100){const os=c.scale;c.scale=function(x,y){return os.call(this,x*s.zoomLevel,y*s.zoomLevel)}}return c}},
        hookWebSocket:function(){const O=window.WebSocket;const s=this;
        window.WebSocket=function(u,p){s.serverURL=u;s.notifyNative('serverURL',u);
        const w=p?new O(u,p):new O(u);w.addEventListener('message',function(e){
        if(e.data instanceof ArrayBuffer)s.parseServerMessage(new DataView(e.data))});s.activeWS=w;return w};
        window.WebSocket.prototype=O.prototype;window.WebSocket.CONNECTING=O.CONNECTING;
        window.WebSocket.OPEN=O.OPEN;window.WebSocket.CLOSING=O.CLOSING;window.WebSocket.CLOSED=O.CLOSED},
        parseServerMessage:function(v){if(v.byteLength<1)return;const op=v.getUint8(0);
        if(op===16)this.parseWorldUpdate(v);else if(op===50)this.parseOwnIDs(v)},
        parseWorldUpdate:function(v){let o=1;if(o+2>v.byteLength)return;const ec=v.getUint16(o,true);o+=2;o+=ec*8;
        while(o+4<=v.byteLength){const id=v.getUint32(o,true);o+=4;if(id===0)break;if(o+6>v.byteLength)break;
        const x=v.getInt16(o,true);o+=2;const y=v.getInt16(o,true);o+=2;const sz=v.getInt16(o,true);o+=2;
        if(o>=v.byteLength)break;const f=v.getUint8(o);o+=1;const iv=(f&1)!==0;const hc=(f&2)!==0;
        const hs=(f&4)!==0;const hn=(f&8)!==0;const he=(f&0x80)!==0;if(he&&o<v.byteLength)o+=1;
        if(hc&&o+3<=v.byteLength)o+=3;let sk='';if(hs){while(o<v.byteLength&&v.getUint8(o)!==0){
        sk+=String.fromCharCode(v.getUint8(o));o++}if(o<v.byteLength)o++}let nm='';
        if(hn){while(o<v.byteLength&&v.getUint8(o)!==0){nm+=String.fromCharCode(v.getUint8(o));o++}
        if(o<v.byteLength)o++}if(!iv&&sz>10){this.players[id]={id:id,name:nm||('Cell_'+id),
        x:x,y:y,mass:Math.floor(sz*sz/100),size:sz,uid:id.toString(16).toUpperCase().padStart(8,'0')}}}},
        parseOwnIDs:function(v){this.ownIDs=[];for(let i=1;i+3<v.byteLength;i+=4)
        this.ownIDs.push(v.getUint32(i,true));this.notifyNative('ownIDs',JSON.stringify(this.ownIDs))},
        startPlayerScan:function(){setInterval(()=>{const pl=Object.values(this.players)
        .filter(p=>!this.ownIDs.includes(p.id)).sort((a,b)=>b.mass-a.mass).slice(0,50);
        this.notifyNative('players',JSON.stringify(pl))},500)},
        setupFeedLoop:function(){setInterval(()=>{if(this.autoFeed&&this.activeWS&&this.activeWS.readyState===1){
        const p=new ArrayBuffer(1);new DataView(p).setUint8(0,21);this.activeWS.send(p)}},80)},
        setZoom:function(l){this.zoomLevel=l},
        setAutoFeed:function(e){this.autoFeed=e},
        getPlayerPosition:function(u){const p=Object.values(this.players).find(p=>p.uid===u);
        return p?JSON.stringify({x:p.x,y:p.y,mass:p.mass}):null},
        notifyNative:function(t,d){try{window.webkit.messageHandlers.xrdBridge.postMessage({type:t,data:d})}catch(e){}}};
        if(document.readyState==='complete')XRD.init();else window.addEventListener('load',()=>XRD.init());
        window.XRD=XRD})();
        """
    }
}

// MARK: - Passthrough Window

class XRDWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self || result === rootViewController?.view {
            return nil
        }
        return result
    }
}
