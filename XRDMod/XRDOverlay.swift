import UIKit
import SwiftUI
import WebKit
import Combine
import MachO

class XRDOverlay: NSObject {
    static let shared = XRDOverlay()

    let settings = GameSettings()
    let botEngine = BotEngine()
    let zoomEngine = ZoomEngine()
    let jsBridge = GameJSBridge()

    private weak var gameWindow: UIWindow?
    private var container: XRDPassthroughView?
    private var toggleBtn: ToggleButton?
    private var macroBtn: MacroButton?
    private var macroDragHandle: MacroDragHandle?
    private var menuHosting: UIHostingController<AnyView>?
    private var licenseHosting: UIHostingController<AnyView>?
    private var isMenuVisible = false
    private var feedTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func setup() {
        NetworkInterceptor.shared.install()

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
            let mainWindow = scene.windows.first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.setup()
            }
            return
        }

        gameWindow = mainWindow
        botEngine.settings = settings
        settings.load()
        installContainer()
        observeLifecycle()
        setupObservers()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.jsBridge.setup(in: mainWindow)
            self.zoomEngine.jsBridge = self.jsBridge
            self.zoomEngine.setup(window: mainWindow)

            self.jsBridge.onConnected = { [weak self] in
                guard let self = self else { return }
                if self.settings.isMacroEnabled {
                    let ms = Int(self.settings.feedInterval * 1000)
                    self.jsBridge.setFeedInterval(ms)
                }
            }

            self.readGameConfig()
        }

        if LicenseManager.shared.isValid {
            showOverlayUI()
        } else {
            showLicenseView()
        }
    }

    private func installContainer() {
        guard let window = gameWindow else { return }
        container?.removeFromSuperview()
        let c = XRDPassthroughView(frame: window.bounds)
        c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(c)
        container = c
    }

    private func ensureContainer() {
        guard let window = gameWindow else { return }
        if container == nil || container?.superview == nil {
            installContainer()
            if LicenseManager.shared.isValid {
                addToggleButton()
                if settings.isMacroEnabled { addMacroButton() }
            }
        }
        if let c = container { window.bringSubviewToFront(c) }
    }

    private func setupObservers() {
        settings.$isMacroEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.addMacroButton()
                    self?.startFeedTimer()
                } else {
                    self?.removeMacroButton()
                }
            }
            .store(in: &cancellables)

        settings.$macroPower
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.settings.isMacroEnabled else { return }
                self.startFeedTimer()
            }
            .store(in: &cancellables)

        settings.$macroButtonSize
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                self?.updateMacroSize(CGFloat(size))
            }
            .store(in: &cancellables)
    }

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appActivated),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func appActivated() {
        DispatchQueue.main.async { [weak self] in self?.ensureContainer() }
    }

    // MARK: - Feed Timer

    private func startFeedTimer() {
        feedTimer?.invalidate()
        let interval = settings.feedInterval
        if jsBridge.isConnected {
            jsBridge.setFeedInterval(Int(interval * 1000))
            return
        }
        feedTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            if let bridge = self?.jsBridge, bridge.isConnected {
                bridge.sendFeed()
            } else {
                NetworkInterceptor.shared.sendFeed()
            }
        }
    }

    private func stopFeedTimer() {
        feedTimer?.invalidate()
        feedTimer = nil
        if jsBridge.isConnected {
            jsBridge.setFeedInterval(0)
        }
    }

    // MARK: - License

    private func showLicenseView() {
        ensureContainer()
        guard let c = container else { return }
        let view = LicenseView(licenseManager: LicenseManager.shared) { [weak self] in
            self?.hideLicenseView()
            self?.showOverlayUI()
        }
        let hosting = UIHostingController(rootView: AnyView(view))
        hosting.view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        hosting.view.frame = c.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        c.addSubview(hosting.view)
        licenseHosting = hosting
    }

    private func hideLicenseView() {
        licenseHosting?.view.removeFromSuperview()
        licenseHosting = nil
    }

    // MARK: - Overlay UI

    private func showOverlayUI() {
        addToggleButton()
        if settings.isMacroEnabled {
            addMacroButton()
            startFeedTimer()
        }
    }

    private func addToggleButton() {
        ensureContainer()
        guard let c = container else { return }
        toggleBtn?.removeFromSuperview()
        let screenW = c.bounds.width
        let btn = ToggleButton(frame: CGRect(x: screenW - 52, y: 40, width: 40, height: 40))
        btn.autoresizingMask = [.flexibleLeftMargin]
        btn.onTap = { [weak self] in self?.toggleMenu() }
        c.addSubview(btn)
        toggleBtn = btn
    }

    private func addMacroButton() {
        ensureContainer()
        guard let c = container else { return }
        macroBtn?.removeFromSuperview()
        macroDragHandle?.removeFromSuperview()

        let size = CGFloat(settings.macroButtonSize)
        let btn = MacroButton(frame: CGRect(x: 50, y: c.bounds.height - size - 50, width: size, height: size))
        btn.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
        c.addSubview(btn)
        macroBtn = btn

        let handleSize: CGFloat = 36
        let handle = MacroDragHandle(frame: CGRect(
            x: btn.frame.maxX + 6,
            y: btn.frame.midY - handleSize / 2,
            width: handleSize,
            height: handleSize
        ))
        handle.onDrag = { [weak self] delta in
            guard let btn = self?.macroBtn, let h = self?.macroDragHandle else { return }
            btn.center = CGPoint(x: btn.center.x + delta.x, y: btn.center.y + delta.y)
            h.center = CGPoint(x: h.center.x + delta.x, y: h.center.y + delta.y)
        }
        c.addSubview(handle)
        macroDragHandle = handle
    }

    private func removeMacroButton() {
        stopFeedTimer()
        macroBtn?.removeFromSuperview()
        macroBtn = nil
        macroDragHandle?.removeFromSuperview()
        macroDragHandle = nil
    }

    private func updateMacroSize(_ size: CGFloat) {
        guard let btn = macroBtn else { return }
        let cx = btn.center.x
        let cy = btn.center.y
        btn.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        btn.center = CGPoint(x: cx, y: cy)
        btn.layer.cornerRadius = size / 2
        btn.setNeedsDisplay()
        macroDragHandle?.center = CGPoint(x: btn.frame.maxX + 6 + 18, y: cy)
    }

    // MARK: - Menu

    private func toggleMenu() {
        if isMenuVisible { hideMenu() } else { showMenu() }
        isMenuVisible.toggle()
    }

    private func showMenu() {
        ensureContainer()
        guard let c = container else { return }
        let menu = ModMenuView(settings: settings, botEngine: botEngine, zoomEngine: zoomEngine)
        let hosting = UIHostingController(rootView: AnyView(menu))
        hosting.view.backgroundColor = .clear
        let menuW: CGFloat = 220
        let menuH: CGFloat = 310
        let x = c.bounds.width - menuW - 8
        let y: CGFloat = 85
        let finalFrame = CGRect(x: x, y: y, width: menuW, height: menuH)
        hosting.view.frame = finalFrame.offsetBy(dx: 0, dy: -12)
        hosting.view.alpha = 0
        c.addSubview(hosting.view)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragMenu(_:)))
        hosting.view.addGestureRecognizer(pan)
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            hosting.view.alpha = 1
            hosting.view.frame = finalFrame
        }
        menuHosting = hosting
    }

    private func hideMenu() {
        guard let hosting = menuHosting else { return }
        UIView.animate(withDuration: 0.15, animations: {
            hosting.view.alpha = 0
            hosting.view.frame = hosting.view.frame.offsetBy(dx: 0, dy: -10)
        }) { _ in hosting.view.removeFromSuperview() }
        menuHosting = nil
    }

    @objc private func dragMenu(_ g: UIPanGestureRecognizer) {
        guard let v = g.view else { return }
        let t = g.translation(in: v.superview)
        v.center = CGPoint(x: v.center.x + t.x, y: v.center.y + t.y)
        g.setTranslation(.zero, in: v.superview)
    }

    private(set) var gameConfigData: [String: String] = [:]

    private func readGameConfig() {
        let bundle = Bundle.main

        if let url = bundle.url(forResource: "GameConfiguration", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dumpAllKeys(from: json, prefix: "GameConfig")
        }

        if let url = bundle.url(forResource: "GameConfiguration", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any] {
            dumpAllKeys(from: dict, prefix: "GamePlist")
        }

        if let url = bundle.url(forResource: "EnvironmentsConfiguration", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any] {
            dumpAllKeys(from: dict, prefix: "Env")
        }

        for name in ["Slice_External - Service Keys",
                     "Slice_Default Settings - Regions",
                     "Slice_Default Settings - Gameplay",
                     "Slice_Default Settings - UI",
                     "Slice_Default Settings - Network"] {
            if let url = bundle.url(forResource: name, withExtension: "plist"),
               let dict = NSDictionary(contentsOf: url) as? [String: Any] {
                let short = name.replacingOccurrences(of: "Slice_Default Settings - ", with: "")
                    .replacingOccurrences(of: "Slice_External - ", with: "")
                    .prefix(16)
                dumpAllKeys(from: dict, prefix: String(short))
            }
        }

        if let rp = bundle.resourcePath,
           let files = try? FileManager.default.contentsOfDirectory(atPath: rp) {
            for f in files where f.hasSuffix(".plist") && !f.hasPrefix("Info") {
                if let url = bundle.url(forResource: (f as NSString).deletingPathExtension, withExtension: "plist"),
                   let dict = NSDictionary(contentsOf: url) as? [String: Any] {
                    let short = String((f as NSString).deletingPathExtension.prefix(16))
                    dumpAllKeys(from: dict, prefix: short)
                }
            }
        }

        if let url = bundle.url(forResource: "agario", withExtension: "xcconfig"),
           let content = try? String(contentsOf: url) {
            gameConfigData["xcconfig"] = String(content.prefix(500))
        }
    }

    private func isServerRelated(_ key: String) -> Bool {
        let kl = key.lowercased()
        return kl.contains("region") || kl.contains("domain") || kl.contains("server") ||
               kl.contains("url") || kl.contains("host") || kl.contains("endpoint") ||
               kl.contains("api") || kl.contains("comm") || kl.contains("network") ||
               kl.contains("websocket") || kl.contains("socket") || kl.contains("service key")
    }

    private func dumpAllKeys(from dict: [String: Any], prefix: String, depth: Int = 0) {
        let maxDepth = isServerRelated(prefix) ? 6 : 3
        guard depth < maxDepth else { return }
        let skipFrameData = !isServerRelated(prefix)
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            if skipFrameData && depth >= 2 {
                let kl = k.lowercased()
                if kl.contains("frame") || kl.contains("sprite") || kl.contains("texture") ||
                   kl.contains("animation") || kl.contains("atlas") { continue }
            }
            let key = "\(prefix).\(k)"
            if let s = v as? String {
                gameConfigData[key] = String(s.prefix(200))
            } else if let n = v as? NSNumber {
                gameConfigData[key] = n.stringValue
            } else if let d = v as? [String: Any] {
                gameConfigData[key] = "{dict:\(d.count)}"
                dumpAllKeys(from: d, prefix: key, depth: depth + 1)
            } else if let a = v as? [Any] {
                let limit = isServerRelated(key) ? 20 : 5
                gameConfigData[key] = "[arr:\(a.count)]"
                for (i, item) in a.prefix(limit).enumerated() {
                    if let s = item as? String {
                        gameConfigData["\(key)[\(i)]"] = String(s.prefix(200))
                    } else if let d = item as? [String: Any] {
                        dumpAllKeys(from: d, prefix: "\(key)[\(i)]", depth: depth + 1)
                    } else if let n = item as? NSNumber {
                        gameConfigData["\(key)[\(i)]"] = n.stringValue
                    }
                }
            } else {
                gameConfigData[key] = String(describing: v).prefix(80).description
            }
        }
    }

    func debugDump() -> String {
        var L: [String] = []
        L.append("=== XRD DUMP v16 ===")

        L.append("")
        L.append("-- APP --")
        let info = Bundle.main.infoDictionary ?? [:]
        L.append("Bundle: \(info["CFBundleIdentifier"] ?? "?")")
        L.append("Name: \(info["CFBundleDisplayName"] ?? info["CFBundleName"] ?? "?")")
        L.append("Version: \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))")

        L.append("")
        L.append("-- DEVICE --")
        L.append("Screen: \(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height)) scale=\(UIScreen.main.scale)")
        L.append("iOS: \(UIDevice.current.systemVersion)")

        L.append("")
        L.append("-- XRD STATE --")
        L.append("Zoom: \(zoomEngine.activeMethod.rawValue) current=\(zoomEngine.currentZoom) native=\(zoomEngine.isNativeGame)")
        L.append("Zoom.status: \(zoomEngine.statusText)")
        L.append("Zoom.debug: \(zoomEngine.debugInfo)")
        L.append("JS: connected=\(jsBridge.isConnected) status=\(jsBridge.statusInfo)")
        L.append("JS.scanned: \(jsBridge.scannedCount) urls: \(jsBridge.connectedURLs.joined(separator: " | "))")
        let ni = NetworkInterceptor.shared
        L.append("Net.server: \(ni.bestServerURL ?? "none")")
        L.append("Net.captured: \(ni.capturedServerURL ?? "none")")
        L.append("Net.bsd: \(ni.bsdCapturedServer ?? "none")")
        L.append("Net.manual: \(ni.manualServerURL ?? "none")")
        L.append("Net.saved: \(ni.savedServerURL ?? "none")")
        L.append("Net.serverIP: \(ni.capturedServerIP ?? "none")")
        L.append("Net.serverPort: \(ni.capturedServerPort.map { String($0) } ?? "none")")
        L.append("Net.hasServer: \(ni.hasServer)")
        L.append("Net.intercepted: \(ni.interceptedCount)")
        L.append("Net.apiEndpoint: \(ni.discoveredAPIEndpoint ?? "none")")
        L.append("Net.urlLog(\(ni.capturedURLLog.count)):")
        for u in ni.capturedURLLog.suffix(15) { L.append("  \(u)") }
        L.append("Net.wsLog(\(ni.capturedWSLog.count)):")
        for w in ni.capturedWSLog { L.append("  \(w)") }

        L.append("")
        L.append("-- BSD HOOKS --")
        let bsdHookClass = NSClassFromString("XRDBSDHook")
        L.append("BSD.active: \(bsdHookClass != nil)")
        if let cls = bsdHookClass {
            let syncSel = NSSelectorFromString("syncToDefaults")
            if (cls as AnyObject).responds(to: syncSel) {
                _ = (cls as AnyObject).perform(syncSel)
            }
        }
        let bsdConns = UserDefaults.standard.stringArray(forKey: "XRD_bsdConns") ?? []
        let bsdDNS = UserDefaults.standard.stringArray(forKey: "XRD_bsdDNS") ?? []
        let bsdServer = UserDefaults.standard.string(forKey: "XRD_bsdServer")
        let bsdCandidates = UserDefaults.standard.stringArray(forKey: "XRD_bsdCandidates") ?? []
        L.append("BSD.server: \(bsdServer ?? "none")")
        L.append("BSD.candidates(\(bsdCandidates.count)):")
        for c in bsdCandidates.suffix(20) { L.append("  \(c)") }
        L.append("BSD.dns(\(bsdDNS.count)):")
        for d in bsdDNS.suffix(30) { L.append("  \(d)") }
        L.append("BSD.conns(\(bsdConns.count)):")
        for c in bsdConns.suffix(40) { L.append("  \(c)") }

        L.append("")
        L.append("-- FEATURES --")
        L.append("Bots: running=\(botEngine.isRunning) alive=\(botEngine.totalAlive) spawned=\(botEngine.totalSpawned)")
        L.append("Bots.status: \(botEngine.statusMessage)")
        L.append("Bots.lastURL: \(botEngine.lastResolvedURL ?? "none")")
        L.append("Bots.capturedIP: \(ni.capturedServerIP ?? "none"):\(ni.capturedServerPort ?? 0)")
        for (i, bot) in botEngine.bots.prefix(5).enumerated() {
            L.append("  Bot[\(i)]: \(bot.state) ip=\(bot.serverIP):\(bot.serverPort) sni=\(bot.serverHostname) err=\(bot.lastError)")
        }
        L.append("Macro: on=\(settings.isMacroEnabled) power=\(settings.macroPower)")

        L.append("")
        L.append("-- WINDOWS --")
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for (wi, window) in ws.windows.enumerated() {
                let rc = window.rootViewController.map { String(describing: type(of: $0)) } ?? "nil"
                L.append("W[\(wi)]: \(type(of: window)) \(Int(window.frame.width))x\(Int(window.frame.height)) root=\(rc)")
            }
        }

        L.append("")
        L.append("-- GAME VIEW --")
        if let gv = zoomEngine.gameViewForDump {
            L.append("Class: \(type(of: gv))")
            L.append("Frame: \(gv.frame)")
        } else {
            L.append("Not found")
        }

        L.append("")
        L.append("-- GAME CONFIG --")
        if gameConfigData.isEmpty { L.append("(none extracted)") }
        for (k, v) in gameConfigData.sorted(by: { $0.key < $1.key }) {
            L.append("  \(k) = \(v)")
        }

        L.append("")
        L.append("-- OBJC CLASSES --")
        let candidates = ["CCDirector", "CCEAGLView", "CCMetalView", "CCGLView",
                          "CCGLView_MCPlatform", "Director", "EAGLView", "MetalView",
                          "GLView", "CCDirectorCaller", "AppController",
                          "RootViewController", "MTKView", "GLKView",
                          "CCScheduler", "CCActionManager", "CCTextureCache",
                          "CCApplication", "CCScene", "CCLayer", "CCNode",
                          "CCSprite", "CCLabelTTF", "CCMenu", "CCParticleSystem",
                          "CCCamera", "CCRenderer"]
        let found = candidates.filter { NSClassFromString($0) != nil }
        L.append("Found: \(found.joined(separator: ", "))")

        L.append("")
        L.append("-- DLSYM --")
        if let h = dlopen(nil, RTLD_NOW) {
            let syms = [
                "glViewport", "glOrtho", "glFrustum", "glScalef",
                "glMatrixMode", "glLoadIdentity",
                "_ZN7cocos2d8Director11getInstanceEv",
                "_ZN7cocos2d8Director14sharedDirectorEv",
                "_ZN7cocos2d4Node8setScaleEf",
                "_ZNK7cocos2d8Director15getRunningSceneEv",
                "_ZN7cocos2d6Camera9setZoomXYEff",
                "_ZN7cocos2d6Camera6setFOVEf",
                "_ZN7cocos2d6Camera14setEyeXYZEfff",
                "_ZN7cocos2d8Director13setProjectionENS0_10ProjectionE",
                "_ZNK7cocos2d8Director10getWinSizeEv",
                "_ZN2cc8Director11getInstanceEv",
                "_ZN2cc4Node8setScaleEf",
                "_ZN2ax8Director11getInstanceEv",
                "_ZN2ax4Node8setScaleEf"
            ]
            var any = false
            for s in syms {
                if dlsym(h, s) != nil { L.append("  \(s) YES"); any = true }
            }
            if !any { L.append("  (none)") }
        }

        L.append("")
        L.append("-- FRAMEWORKS --")
        let imgCount = _dyld_image_count()
        for i in 0..<imgCount {
            guard let n = _dyld_get_image_name(i) else { continue }
            let p = String(cString: n)
            if !p.hasPrefix("/usr/") && !p.hasPrefix("/System/") && !p.hasPrefix("/Developer/") {
                L.append("  \(p)")
            }
        }

        L.append("")
        L.append("-- RESOURCES --")
        if let rp = Bundle.main.resourcePath,
           let contents = try? FileManager.default.contentsOfDirectory(atPath: rp) {
            let interesting = contents.filter { f in
                let fl = f.lowercased()
                return fl.hasSuffix(".js") || fl.hasSuffix(".html") || fl.hasSuffix(".json") ||
                       fl.hasSuffix(".plist") || fl.hasSuffix(".framework") ||
                       fl.hasSuffix(".dylib") || fl.hasSuffix(".bundle") ||
                       fl.contains("agar") || fl.contains("game") || fl.contains("cocos")
            }.sorted()
            for f in interesting { L.append("  \(f)") }
        }
        if let fwp = Bundle.main.privateFrameworksPath,
           let fws = try? FileManager.default.contentsOfDirectory(atPath: fwp) {
            L.append("PrivateFrameworks:")
            for f in fws.sorted() { L.append("  \(f)") }
        }

        L.append("")
        L.append("-- XRD INJECT --")
        let xb = Bundle(for: XRDOverlay.self)
        L.append("Bundle: \(xb.bundlePath)")
        L.append("inject.js: xrd=\(xb.url(forResource: "inject", withExtension: "js") != nil) main=\(Bundle.main.url(forResource: "inject", withExtension: "js") != nil)")
        L.append("License: \(LicenseManager.shared.isValid)")

        L.append("")
        L.append("=== END DUMP ===")
        return L.joined(separator: "\n")
    }

}

// MARK: - Zoom Engine

class ZoomEngine: NSObject, ObservableObject {
    enum Method: String {
        case engineHook = "Engine"
        case objcHook = "ObjC"
        case jsHook = "JS Canvas"
        case displayZoom = "Display"
    }

    @Published var currentZoom: CGFloat = 1.0
    @Published var activeMethod: Method = .displayZoom
    @Published var statusText: String = "Searching..."
    @Published var debugInfo: String = ""
    var isNativeGame: Bool = false

    private weak var gameWindow: UIWindow?
    private var gameView: UIView?
    var gameViewForDump: UIView? { gameView }
    private var originalFrame: CGRect = .zero

    var jsBridge: GameJSBridge?
    private var engineSetScale: ((Float) -> Void)?
    private var displayLink: CADisplayLink?
    private var zoomEnforceTimer: Timer?

    deinit {
        displayLink?.invalidate()
        zoomEnforceTimer?.invalidate()
    }

    func setup(window: UIWindow) {
        gameWindow = window
        gameView = findGameView(in: window)
        if gameView == nil {
            gameView = findGameViewAnywhere(in: window)
        }
        if gameView == nil {
            gameView = window.rootViewController?.view
        }
        if let gv = gameView {
            originalFrame = gv.frame
            let viewName = String(describing: type(of: gv))
            debugInfo = viewName
            let nativeHints = ["CCGL", "CCMetal", "CCEAGL", "GLView", "EAGLView",
                               "MetalView", "MTKView", "GLKView", "Cocos", "Unity"]
            isNativeGame = nativeHints.contains(where: { viewName.localizedCaseInsensitiveContains($0) })
        }

        if tryCppHooks() {
            activeMethod = .engineHook
            statusText = "C++ zoom (\(debugInfo))"
        } else if tryObjCHooks() {
            activeMethod = .objcHook
            statusText = "ObjC zoom (\(debugInfo))"
        } else {
            activeMethod = .displayZoom
            statusText = "Display zoom (\(debugInfo))"
        }
    }

    func setZoom(_ factor: CGFloat) {
        currentZoom = factor
        zoomEnforceTimer?.invalidate()
        zoomEnforceTimer = nil

        if let hook = engineSetScale {
            hook(Float(factor))
            if abs(factor - 1.0) > 0.01 {
                zoomEnforceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self, let hook = self.engineSetScale else { return }
                    hook(Float(self.currentZoom))
                }
            }
        } else {
            applyDisplayZoom(factor)
        }
    }

    func reset() {
        zoomEnforceTimer?.invalidate()
        zoomEnforceTimer = nil
        setZoom(1.0)
    }

    // MARK: - C++ dlsym

    private func tryCppHooks() -> Bool {
        guard let handle = dlopen(nil, RTLD_NOW) else { return false }

        let namespaces = ["7cocos2d", "2cc", "2ax", "5cocos", "6cocos2"]
        for ns in namespaces {
            let dirGetters = [
                "_ZN\(ns)8Director11getInstanceEv",
                "_ZN\(ns)8Director14sharedDirectorEv"
            ]
            var dSym: UnsafeMutableRawPointer?
            for n in dirGetters { dSym = dlsym(handle, n); if dSym != nil { break } }
            guard let dirSym = dSym else { continue }

            let sceneGetters = [
                "_ZNK\(ns)8Director15getRunningSceneEv",
                "_ZN\(ns)8Director15getRunningSceneEv",
                "_ZNK\(ns)8Director8getSceneEv"
            ]
            var sSym: UnsafeMutableRawPointer?
            for n in sceneGetters { sSym = dlsym(handle, n); if sSym != nil { break } }
            guard let sceneSym = sSym else { continue }

            let scaleSetters = [
                "_ZN\(ns)4Node8setScaleEf",
                "_ZN\(ns)5Scene8setScaleEf",
                "_ZN\(ns)4Node8setScaleEff"
            ]
            var scSym: UnsafeMutableRawPointer?
            for n in scaleSetters { scSym = dlsym(handle, n); if scSym != nil { break } }
            guard let scaleSym = scSym else { continue }

            typealias GetDir = @convention(c) () -> UnsafeMutableRawPointer
            typealias GetScene = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
            typealias SetScale = @convention(c) (UnsafeMutableRawPointer, Float) -> Void

            let getDir = unsafeBitCast(dirSym, to: GetDir.self)
            let getScene = unsafeBitCast(sceneSym, to: GetScene.self)
            let setScale = unsafeBitCast(scaleSym, to: SetScale.self)

            let dir = getDir()
            guard getScene(dir) != nil else { continue }

            engineSetScale = { scale in
                let d = getDir()
                if let scene = getScene(d) { setScale(scene, scale) }
            }
            debugInfo = "C++ \(ns)"
            return true
        }
        return false
    }

    // MARK: - ObjC runtime

    private func tryObjCHooks() -> Bool {
        let classNames = ["CCDirector", "Director", "CCDirectorCaller",
                          "cocos2d.Director", "AppController"]
        let singletons = ["sharedDirector", "getInstance", "shared",
                          "sharedInstance", "director", "currentDirector"]
        let sceneSelectors = ["runningScene", "getRunningScene", "scene",
                              "currentScene", "_runningScene"]

        for className in classNames {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in singletons {
                let sel = NSSelectorFromString(selName)
                guard cls.responds(to: sel),
                      let result = (cls as AnyObject).perform(sel) else { continue }
                let director = result.takeUnretainedValue()

                for sceneSelName in sceneSelectors {
                    let sceneSel = NSSelectorFromString(sceneSelName)
                    guard director.responds(to: sceneSel),
                          let sceneResult = director.perform(sceneSel) else { continue }
                    let scene = sceneResult.takeUnretainedValue()

                    let scaleSel = NSSelectorFromString("setScale:")
                    guard scene.responds(to: scaleSel),
                          let imp = class_getMethodImplementation(type(of: scene), scaleSel) else { continue }

                    let dirRef = director
                    let scSelCopy = sceneSel

                    engineSetScale = { scale in
                        guard let sr = dirRef.perform(scSelCopy) else { return }
                        let sc = sr.takeUnretainedValue()
                        typealias Fn = @convention(c) (AnyObject, Selector, CGFloat) -> Void
                        let fn = unsafeBitCast(imp, to: Fn.self)
                        fn(sc, NSSelectorFromString("setScale:"), CGFloat(scale))
                    }
                    debugInfo = "ObjC \(className).\(sceneSelName)"
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Display zoom (fallback)

    private func applyDisplayZoom(_ factor: CGFloat) {
        guard let view = gameView else { return }

        displayLink?.invalidate()
        displayLink = nil

        if abs(factor - 1.0) < 0.01 {
            view.transform = .identity
            return
        }

        view.transform = CGAffineTransform(scaleX: factor, y: factor)

        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkFired() {
        guard let view = gameView else { return }
        if abs(currentZoom - 1.0) < 0.01 {
            view.transform = .identity
            displayLink?.invalidate()
            displayLink = nil
        } else {
            view.transform = CGAffineTransform(scaleX: currentZoom, y: currentZoom)
        }
    }

    // MARK: - Class scan (debug)

    private func scanEngineClasses() -> [String] {
        let candidates = [
            "CCDirector", "CCEAGLView", "CCMetalView", "CCGLView",
            "Director", "EAGLView", "MetalView", "GLView",
            "CCDirectorCaller", "AppController", "RootViewController"
        ]
        return candidates.filter { NSClassFromString($0) != nil }
    }

    // MARK: - Game view detection

    private func findGameView(in window: UIWindow) -> UIView? {
        let hints = ["CCGLView", "CCGL", "CCEAGL", "CCMetal", "CCRender",
                     "MTKView", "GLKView", "EAGLView", "MetalView",
                     "OpenGL", "Cocos", "cocos"]
        if let root = window.rootViewController?.view,
           let found = findByClass(root, hints: hints) { return found }
        if let found = findByClass(window, hints: hints) { return found }
        if let root = window.rootViewController?.view { return findBiggestOpaque(root) }
        return findBiggestOpaque(window)
    }

    private func findGameViewAnywhere(in window: UIWindow) -> UIView? {
        let hints = ["CCGLView", "CCGL", "CCEAGL", "CCMetal"]
        return findByClass(window, hints: hints)
    }

    private func findByClass(_ view: UIView, hints: [String]) -> UIView? {
        let name = String(describing: type(of: view))
        if hints.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return view }
        for sub in view.subviews {
            if let found = findByClass(sub, hints: hints) { return found }
        }
        return nil
    }

    private func findBiggestOpaque(_ root: UIView) -> UIView? {
        let screenArea = UIScreen.main.bounds.width * UIScreen.main.bounds.height
        var best: UIView?
        var bestArea: CGFloat = 0
        func scan(_ v: UIView) {
            let a = v.bounds.width * v.bounds.height
            if a > screenArea * 0.5 && a > bestArea && v !== root && v.isOpaque {
                best = v; bestArea = a
            }
            v.subviews.forEach { scan($0) }
        }
        scan(root)
        return best
    }
}

// MARK: - Passthrough View

class XRDPassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for sub in subviews where !sub.isHidden && sub.alpha > 0.01 && sub.isUserInteractionEnabled {
            let p = convert(point, to: sub)
            if sub.point(inside: p, with: event) { return true }
        }
        return false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self { return nil }
        return result
    }
}

// MARK: - Toggle Button

class ToggleButton: UIView {
    var onTap: (() -> Void)?
    private var startCenter: CGPoint = .zero
    private var moved = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        layer.cornerRadius = frame.width / 2
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(red: 0.459, green: 0.318, blue: 0.957, alpha: 1).cgColor
        clipsToBounds = true
        let lbl = UILabel(frame: bounds)
        lbl.text = "XRD"
        lbl.font = .systemFont(ofSize: 10, weight: .black)
        lbl.textColor = .white
        lbl.textAlignment = .center
        lbl.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(lbl)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        startCenter = center; moved = false
        UIView.animate(withDuration: 0.1) { self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: superview)
        let prev = t.previousLocation(in: superview)
        center = CGPoint(x: center.x + loc.x - prev.x, y: center.y + loc.y - prev.y)
        if hypot(center.x - startCenter.x, center.y - startCenter.y) > 6 { moved = true }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.transform = .identity }
        if !moved { onTap?() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.transform = .identity }
    }
}

// MARK: - Macro Button (FEED indicator, not draggable)

class MacroButton: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.cornerRadius = frame.width / 2
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 0.6).cgColor)
        ctx.fillEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        let green = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.8)
        ctx.setStrokeColor(green.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .black),
            .foregroundColor: UIColor.white
        ]
        let text = "FEED"
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
            withAttributes: attrs
        )
    }
}

// MARK: - Macro Drag Handle (moves the FEED button)

class MacroDragHandle: UIView {
    var onDrag: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = frame.width / 2
        layer.borderWidth = 2
        layer.borderColor = UIColor(red: 0.2, green: 0.8, blue: 0.9, alpha: 0.9).cgColor

        let icon = UILabel(frame: bounds)
        icon.text = "✥"
        icon.font = .systemFont(ofSize: 18, weight: .bold)
        icon.textColor = UIColor(red: 0.2, green: 0.8, blue: 0.9, alpha: 1.0)
        icon.textAlignment = .center
        icon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: superview)
        let prev = t.previousLocation(in: superview)
        let delta = CGPoint(x: loc.x - prev.x, y: loc.y - prev.y)
        onDrag?(delta)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 0.5 }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 1 }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 1 }
    }
}
