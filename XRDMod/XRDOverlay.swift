import UIKit
import SwiftUI
import WebKit
import Combine

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
            self.zoomEngine.debugInfo = self.jsBridge.statusInfo

            self.jsBridge.onConnected = { [weak self] in
                guard let self = self else { return }
                if self.settings.isMacroEnabled {
                    let ms = Int(self.settings.feedInterval * 1000)
                    self.jsBridge.setFeedInterval(ms)
                }
            }
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

    func debugDump() -> String {
        var L: [String] = []
        L.append("=== XRD FULL DUMP v4 ===")

        // ---- APP ----
        L.append("")
        L.append("-- APP --")
        let info = Bundle.main.infoDictionary ?? [:]
        L.append("Bundle: \(info["CFBundleIdentifier"] ?? "?")")
        L.append("Name: \(info["CFBundleDisplayName"] ?? info["CFBundleName"] ?? "?")")
        L.append("Version: \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))")
        L.append("Exec: \(info["CFBundleExecutable"] ?? "?")")

        // ---- DEVICE ----
        L.append("")
        L.append("-- DEVICE --")
        let screen = UIScreen.main
        L.append("Screen: \(Int(screen.bounds.width))x\(Int(screen.bounds.height)) scale=\(screen.scale)")
        L.append("NativeScale: \(screen.nativeScale)")
        L.append("NativeBounds: \(Int(screen.nativeBounds.width))x\(Int(screen.nativeBounds.height))")
        let orient = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first
        L.append("Orientation: \(orient.map { "\($0.rawValue)" } ?? "?")")
        L.append("iOS: \(UIDevice.current.systemVersion)")
        L.append("Model: \(UIDevice.current.model)")

        // ---- XRD STATE ----
        L.append("")
        L.append("-- XRD STATE --")
        L.append("Zoom.method: \(zoomEngine.activeMethod.rawValue)")
        L.append("Zoom.status: \(zoomEngine.statusText)")
        L.append("Zoom.debug: \(zoomEngine.debugInfo)")
        L.append("Zoom.current: \(zoomEngine.currentZoom)")
        L.append("Zoom.native: \(zoomEngine.isNativeGame)")
        L.append("JS.connected: \(jsBridge.isConnected)")
        L.append("JS.status: \(jsBridge.statusInfo)")
        let ni = NetworkInterceptor.shared
        L.append("Net.server: \(ni.bestServerURL ?? "none")")
        L.append("Net.captured: \(ni.capturedServerURL ?? "none")")
        L.append("Net.manual: \(ni.manualServerURL ?? "none")")
        L.append("Net.saved: \(ni.savedServerURL ?? "none")")
        L.append("Net.hasServer: \(ni.hasServer)")
        L.append("Net.gameWS: \(ni.gameWebSocket != nil ? "obj" : "nil") state=\(ni.gameWebSocket.map { "\($0.state.rawValue)" } ?? "nil")")
        L.append("Net.intercepted: \(ni.interceptedCount)")
        L.append("Net.apiEndpoint: \(ni.discoveredAPIEndpoint ?? "none")")
        L.append("Net.headers: \(ni.discoveredHeaders?.description ?? "none")")
        L.append("Bots.running: \(botEngine.isRunning)")
        L.append("Bots.alive: \(botEngine.totalAlive)")
        L.append("Bots.status: \(botEngine.statusMessage)")
        L.append("Macro.on: \(settings.isMacroEnabled)")
        L.append("Macro.power: \(settings.macroPower)")
        L.append("Macro.interval: \(settings.feedInterval)")
        L.append("Players: \(settings.currentPlayers.count)")
        L.append("OwnCells: \(settings.ownCellIDs)")

        // ---- WINDOWS + VIEWS ----
        L.append("")
        L.append("-- WINDOWS --")
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            L.append("Scene: \(type(of: ws)) state=\(ws.activationState.rawValue)")
            for (wi, window) in ws.windows.enumerated() {
                let wType = String(describing: type(of: window))
                let rc = window.rootViewController.map { String(describing: type(of: $0)) } ?? "nil"
                L.append("Win[\(wi)]: \(wType) \(Int(window.frame.width))x\(Int(window.frame.height)) key=\(window.isKeyWindow) root=\(rc)")
                dumpViewTree(window, indent: 1, lines: &L, depth: 0, maxDepth: 8)
            }
        }

        // ---- WKWEBVIEWS ----
        L.append("")
        L.append("-- WKWEBVIEWS --")
        var wkCount = 0
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                findAllWKWebViews(in: window) { wv, path in
                    wkCount += 1
                    let url = wv.url?.absoluteString ?? "nil"
                    let title = wv.title ?? ""
                    L.append("WK[\(wkCount)]: \(Int(wv.frame.width))x\(Int(wv.frame.height)) hidden=\(wv.isHidden) loading=\(wv.isLoading)")
                    L.append("  url: \(url)")
                    if !title.isEmpty { L.append("  title: \(title)") }
                    L.append("  path: \(path)")
                    L.append("  canGoBack: \(wv.canGoBack) canGoForward: \(wv.canGoForward)")
                    let cfg = wv.configuration
                    L.append("  userScripts: \(cfg.userContentController.userScripts.count)")
                    for (si, script) in cfg.userContentController.userScripts.enumerated() {
                        let src = script.source
                        let preview = String(src.prefix(80)).replacingOccurrences(of: "\n", with: "\\n")
                        L.append("  script[\(si)]: time=\(script.injectionTime.rawValue) mainOnly=\(script.isForMainFrameOnly) len=\(src.count) preview=\(preview)")
                    }
                }
            }
        }
        if wkCount == 0 { L.append("None found") }

        // ---- GAME VIEW ----
        L.append("")
        L.append("-- GAME VIEW --")
        if let gv = zoomEngine.gameViewForDump {
            let name = String(describing: type(of: gv))
            L.append("Class: \(name)")
            L.append("Frame: \(gv.frame)")
            L.append("Bounds: \(gv.bounds)")
            L.append("Transform: \(gv.transform)")
            L.append("ContentScale: \(gv.contentScaleFactor)")
            L.append("Layer: \(type(of: gv.layer))")
            if let eagl = gv.layer as? CAEAGLLayer {
                L.append("EAGLLayer.opaque: \(eagl.isOpaque)")
                L.append("EAGLLayer.drawableProperties: \(eagl.drawableProperties ?? [:])")
            }
            let gestures = gv.gestureRecognizers ?? []
            L.append("Gestures(\(gestures.count)):")
            for g in gestures {
                L.append("  \(type(of: g)) enabled=\(g.isEnabled) state=\(g.state.rawValue)")
            }
        } else {
            L.append("Not found")
        }

        // ---- OBJ-C CLASSES ----
        L.append("")
        L.append("-- OBJC CLASSES --")
        let knownCandidates = ["CCDirector", "CCEAGLView", "CCMetalView", "CCGLView",
                               "CCGLView_MCPlatform", "Director", "EAGLView", "MetalView",
                               "GLView", "CCDirectorCaller", "AppController",
                               "RootViewController", "MTKView", "GLKView",
                               "WKWebView", "UIWebView", "WKContentView",
                               "CCScheduler", "CCActionManager", "CCTextureCache",
                               "CCApplication", "CCScene", "CCLayer", "CCNode",
                               "CCSprite", "CCLabelTTF", "CCLabelBMFont",
                               "CCMenu", "CCMenuItem", "CCParticleSystem"]
        let foundClasses = knownCandidates.filter { NSClassFromString($0) != nil }
        L.append("Known: \(foundClasses.joined(separator: ", "))")

        // ---- ALL GAME CLASSES ----
        L.append("")
        L.append("-- GAME CLASSES --")
        var allClassCount: UInt32 = 0
        var gameClasses: [String] = []
        if let classList = objc_copyClassList(&allClassCount) {
            let systemPrefixes = ["UI", "NS", "CA", "CG", "CF", "CK", "WK", "MK", "AV",
                                  "SK", "SC", "CL", "CT", "CM", "CN", "CS", "AB", "AL",
                                  "AU", "AS", "AT", "BA", "BS", "CB", "CI", "CR", "DC",
                                  "EA", "EK", "GC", "GK", "GL", "HK", "HM", "IN", "IO",
                                  "LA", "MC", "MD", "MF", "ML", "MP", "MT", "NC", "NE",
                                  "NW", "OS", "PH", "PK", "QL", "RM", "SA", "SF", "SL",
                                  "SR", "SS", "ST", "TN", "TT", "UM", "UN", "VS", "VN",
                                  "WC", "XC", "_", "Web", "DOM", "NSCF", "NSUI", "__NS",
                                  "__CF", "Swift.", "swift.", "Swif", "objc", "dispatch",
                                  "Block", "Mach", "Protocol", "Object", "JSExport"]
            for i in 0..<Int(allClassCount) {
                let name = String(cString: class_getName(classList[i]))
                if name.count < 2 { continue }
                let isSystem = systemPrefixes.contains(where: { name.hasPrefix($0) })
                if !isSystem && !name.contains(".") {
                    gameClasses.append(name)
                }
            }
            free(UnsafeMutableRawPointer(classList))
        }
        gameClasses.sort()
        L.append("Total ObjC: \(allClassCount), Game-like: \(gameClasses.count)")
        for gc in gameClasses {
            L.append("  \(gc)")
        }

        // ---- COCOS2D DEEP INTROSPECTION ----
        L.append("")
        L.append("-- COCOS2D DEEP --")
        dumpCocos2DFull(&L)

        // ---- LOADED FRAMEWORKS ----
        L.append("")
        L.append("-- FRAMEWORKS --")
        let imageCount = _dyld_image_count()
        var gameFrameworks: [String] = []
        for i in 0..<imageCount {
            guard let name = _dyld_get_image_name(i) else { continue }
            let path = String(cString: name)
            let isSystem = path.hasPrefix("/usr/") || path.hasPrefix("/System/") ||
                           path.hasPrefix("/Developer/")
            if !isSystem {
                gameFrameworks.append(path)
            }
        }
        L.append("Non-system(\(gameFrameworks.count)):")
        for fw in gameFrameworks { L.append("  \(fw)") }

        // ---- DLSYM PROBES ----
        L.append("")
        L.append("-- DLSYM --")
        if let handle = dlopen(nil, RTLD_NOW) {
            let symbols = [
                "_ZN7cocos2d8Director11getInstanceEv",
                "_ZN7cocos2d8Director14sharedDirectorEv",
                "_ZN7cocos2d4Node8setScaleEf",
                "_ZN7cocos2d5Scene8setScaleEf",
                "_ZN7cocos2d6Camera9setZoomXYEff",
                "_ZN7cocos2d6Camera6setFOVEf",
                "_ZN7cocos2d6Camera11setPositionEf",
                "_ZN7cocos2d6Camera14setEyeXYZEfff",
                "_ZNK7cocos2d8Director15getRunningSceneEv",
                "_ZN7cocos2d8Director13setProjectionENS0_10ProjectionE",
                "_ZNK7cocos2d8Director10getWinSizeEv",
                "_ZN7cocos2d8Director20setDesignResolutionEffi",
                "_ZN2cc8Director11getInstanceEv",
                "_ZN2cc4Node8setScaleEf",
                "_ZN2ax8Director11getInstanceEv",
                "_ZN2ax4Node8setScaleEf",
                "glViewport", "glOrtho", "glFrustum", "glScalef",
                "glMatrixMode", "glLoadIdentity", "glPushMatrix", "glPopMatrix"
            ]
            var anyFound = false
            for s in symbols {
                if dlsym(handle, s) != nil {
                    L.append("  \(s) ✓")
                    anyFound = true
                }
            }
            if !anyFound { L.append("  (none found)") }

            let namespaces = ["7cocos2d", "2cc", "2ax", "5cocos"]
            for ns in namespaces {
                let probes = [
                    "_ZN\(ns)8Director11getInstanceEv",
                    "_ZN\(ns)8Director14sharedDirectorEv",
                    "_ZN\(ns)4Node8setScaleEf",
                    "_ZNK\(ns)8Director15getRunningSceneEv",
                    "_ZN\(ns)6Camera9setZoomXYEff",
                    "_ZN\(ns)6Camera6setFOVEf",
                    "_ZN\(ns)6Camera6createEv",
                    "_ZN\(ns)4Node12getChildrenEv",
                    "_ZN\(ns)4Node12setPositionEff",
                    "_ZN\(ns)4Node11getPositionEv",
                    "_ZN\(ns)4Node14setAnchorPointERKNS_4Vec2E",
                    "_ZN\(ns)4Node14setContentSizeERKNS_4SizeE"
                ]
                let foundInNs = probes.filter { dlsym(handle, $0) != nil }
                if !foundInNs.isEmpty {
                    L.append("  ns=\(ns):")
                    for f in foundInNs { L.append("    \(f) ✓") }
                }
            }
        }

        // ---- USERDEFAULTS (XRD) ----
        L.append("")
        L.append("-- USERDEFAULTS --")
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("XRD_") || $0.lowercased().contains("agar") || $0.lowercased().contains("server") }
            .sorted()
        for k in allKeys {
            let val = UserDefaults.standard.object(forKey: k)
            L.append("  \(k) = \(val ?? "nil")")
        }
        if allKeys.isEmpty { L.append("  (none)") }

        // ---- BUNDLE RESOURCES ----
        L.append("")
        L.append("-- RESOURCES --")
        if let resourcePath = Bundle.main.resourcePath {
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: resourcePath) {
                let interesting = contents.filter { f in
                    let fl = f.lowercased()
                    return fl.hasSuffix(".js") || fl.hasSuffix(".html") || fl.hasSuffix(".json") ||
                           fl.hasSuffix(".plist") || fl.hasSuffix(".framework") ||
                           fl.hasSuffix(".dylib") || fl.hasSuffix(".bundle") ||
                           fl.hasSuffix(".wasm") || fl.hasSuffix(".dat") ||
                           fl.contains("agar") || fl.contains("game") || fl.contains("config") ||
                           fl.contains("server") || fl.contains("socket") || fl.contains("cocos")
                }.sorted()
                L.append("Interesting(\(interesting.count)):")
                for f in interesting { L.append("  \(f)") }
            }
            if let frameworks = Bundle.main.privateFrameworksPath,
               let fwList = try? fm.contentsOfDirectory(atPath: frameworks) {
                L.append("PrivateFrameworks:")
                for f in fwList.sorted() { L.append("  \(f)") }
            }
        }

        // ---- XRD INJECTION STATE ----
        L.append("")
        L.append("-- XRD INJECT --")
        let xrdBundle = Bundle(for: XRDOverlay.self)
        L.append("XRD bundle: \(xrdBundle.bundlePath)")
        L.append("XRD id: \(xrdBundle.bundleIdentifier ?? "nil")")
        let hasInjectJS = xrdBundle.url(forResource: "inject", withExtension: "js") != nil
        let mainHasJS = Bundle.main.url(forResource: "inject", withExtension: "js") != nil
        L.append("inject.js in XRD: \(hasInjectJS)")
        L.append("inject.js in main: \(mainHasJS)")
        L.append("Container: \(container != nil ? "yes" : "nil")")
        L.append("ToggleBtn: \(toggleBtn != nil ? "yes" : "nil")")
        L.append("MacroBtn: \(macroBtn != nil ? "yes" : "nil")")
        L.append("MenuVisible: \(isMenuVisible)")
        L.append("License: \(LicenseManager.shared.isValid)")

        L.append("")
        L.append("=== END FULL DUMP ===")
        return L.joined(separator: "\n")
    }

    private func dumpViewTree(_ view: UIView, indent: Int, lines: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }
        for sub in view.subviews {
            let pad = String(repeating: "  ", count: indent)
            let name = String(describing: type(of: sub))
            var extras: [String] = []
            if sub.isHidden { extras.append("hidden") }
            if sub.alpha < 1 { extras.append("a=\(String(format: "%.1f", sub.alpha))") }
            if sub.isUserInteractionEnabled == false { extras.append("noTouch") }
            let extraStr = extras.isEmpty ? "" : " [\(extras.joined(separator: ","))]"
            let size = "\(Int(sub.frame.width))x\(Int(sub.frame.height))"
            lines.append("\(pad)\(name) \(size)\(extraStr)")
            dumpViewTree(sub, indent: indent + 1, lines: &lines, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private func findAllWKWebViews(in view: UIView, path: String = "", handler: (WKWebView, String) -> Void) {
        let name = String(describing: type(of: view))
        let currentPath = path.isEmpty ? name : "\(path)>\(name)"
        if let wv = view as? WKWebView {
            handler(wv, currentPath)
        }
        for sub in view.subviews {
            findAllWKWebViews(in: sub, path: currentPath, handler: handler)
        }
    }

    private func objcMethodNames(_ cls: AnyClass, instance: Bool = true) -> [String] {
        let target: AnyClass = instance ? cls : object_getClass(cls)!
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(target, &count) else { return [] }
        defer { free(methods) }
        var names: [String] = []
        for i in 0..<Int(count) {
            names.append(NSStringFromSelector(method_getName(methods[i])))
        }
        return names.sorted()
    }

    private func objcIvarNames(_ cls: AnyClass) -> [String] {
        var count: UInt32 = 0
        guard let ivars = class_copyIvarList(cls, &count) else { return [] }
        defer { free(ivars) }
        var names: [String] = []
        for i in 0..<Int(count) {
            if let n = ivar_getName(ivars[i]) { names.append(String(cString: n)) }
        }
        return names.sorted()
    }

    private func objcPropertyNames(_ cls: AnyClass) -> [String] {
        var count: UInt32 = 0
        guard let props = class_copyPropertyList(cls, &count) else { return [] }
        defer { free(props) }
        var names: [String] = []
        for i in 0..<Int(count) {
            names.append(String(cString: property_getName(props[i])))
        }
        return names.sorted()
    }

    private func dumpCocos2DFull(_ L: inout [String]) {
        let dirClasses = ["CCDirector", "Director"]

        for dcName in dirClasses {
            guard let cls = NSClassFromString(dcName) else { continue }

            let cm = objcMethodNames(cls, instance: false)
            L.append("\(dcName) +class(\(cm.count)): \(cm.joined(separator: ", "))")

            let im = objcMethodNames(cls)
            L.append("\(dcName) -inst(\(im.count)):")
            for m in im { L.append("  -\(m)") }

            let props = objcPropertyNames(cls)
            if !props.isEmpty { L.append("\(dcName) props: \(props.joined(separator: ", "))") }

            let ivars = objcIvarNames(cls)
            if !ivars.isEmpty { L.append("\(dcName) ivars: \(ivars.joined(separator: ", "))") }
        }

        let singletons = ["sharedDirector", "getInstance", "shared", "sharedInstance"]
        outer: for dcName in dirClasses {
            guard let cls = NSClassFromString(dcName) else { continue }
            for selName in singletons {
                let sel = NSSelectorFromString(selName)
                guard cls.responds(to: sel),
                      let result = (cls as AnyObject).perform(sel) else { continue }
                let director = result.takeUnretainedValue()
                L.append("")
                L.append("Director via \(dcName).\(selName)")
                L.append("Director runtime class: \(NSStringFromClass(type(of: director)))")

                let allProbes = [
                    "getWinSize", "winSize", "getWinSizeInPixels", "winSizeInPixels",
                    "getVisibleSize", "visibleSize", "getVisibleOrigin",
                    "getDesignResolutionSize", "designResolutionSize",
                    "getFrameSize", "frameSize",
                    "contentScaleFactor", "getContentScaleFactor",
                    "zoomFactor", "getZoomFactor", "setZoomFactor:",
                    "projection", "getProjection", "setProjection:",
                    "getDefaultCamera", "defaultCamera", "camera",
                    "getOpenGLView", "openGLView", "getGLView", "glView",
                    "getRunningScene", "runningScene",
                    "getScheduler", "scheduler",
                    "getActionManager", "actionManager",
                    "getTextureCache", "textureCache",
                    "isPaused", "paused", "animationInterval",
                    "getNotificationNode", "notificationNode",
                    "totalFrames", "secondsPerFrame",
                    "setDesignResolutionSize:height:resolutionPolicy:",
                    "setContentScaleFactor:", "setZoomFactor:",
                    "setFrameSize:", "setViewport",
                    "setAlphaBlending:", "setDepthTest:",
                    "setProjection:", "setGLDefaultValues",
                    "reshapeProjection:", "createStatsLabel",
                    "getCocos2dVersion", "cocos2dVersion"
                ]
                for p in allProbes {
                    if director.responds(to: NSSelectorFromString(p)) {
                        L.append("  responds: \(p) ✓")
                    }
                }

                let sizeGetters = ["getWinSize", "winSize", "getWinSizeInPixels",
                                   "getVisibleSize", "getDesignResolutionSize",
                                   "getFrameSize", "frameSize"]
                for sg in sizeGetters {
                    guard director.responds(to: NSSelectorFromString(sg)) else { continue }
                    if let imp = class_getMethodImplementation(type(of: director), NSSelectorFromString(sg)) {
                        typealias SizeFn = @convention(c) (AnyObject, Selector) -> CGSize
                        let fn = unsafeBitCast(imp, to: SizeFn.self)
                        let s = fn(director, NSSelectorFromString(sg))
                        L.append("  \(sg) = \(s.width)x\(s.height)")
                    }
                }

                let floatGetters = ["contentScaleFactor", "getContentScaleFactor",
                                    "zoomFactor", "getZoomFactor",
                                    "animationInterval", "secondsPerFrame"]
                for fg in floatGetters {
                    guard director.responds(to: NSSelectorFromString(fg)) else { continue }
                    if let imp = class_getMethodImplementation(type(of: director), NSSelectorFromString(fg)) {
                        typealias FloatFn = @convention(c) (AnyObject, Selector) -> CGFloat
                        let fn = unsafeBitCast(imp, to: FloatFn.self)
                        let v = fn(director, NSSelectorFromString(fg))
                        L.append("  \(fg) = \(v)")
                    }
                }

                let intGetters = ["projection", "getProjection", "totalFrames"]
                for ig in intGetters {
                    guard director.responds(to: NSSelectorFromString(ig)) else { continue }
                    if let imp = class_getMethodImplementation(type(of: director), NSSelectorFromString(ig)) {
                        typealias IntFn = @convention(c) (AnyObject, Selector) -> Int
                        let fn = unsafeBitCast(imp, to: IntFn.self)
                        let v = fn(director, NSSelectorFromString(ig))
                        L.append("  \(ig) = \(v)")
                    }
                }

                if director.responds(to: NSSelectorFromString("getCocos2dVersion")),
                   let vr = director.perform(NSSelectorFromString("getCocos2dVersion")),
                   let vs = vr.takeUnretainedValue() as? String {
                    L.append("  cocos2dVersion = \(vs)")
                }

                if director.responds(to: NSSelectorFromString("getOpenGLView")),
                   let glr = director.perform(NSSelectorFromString("getOpenGLView")) {
                    let glView = glr.takeUnretainedValue()
                    let glClass = NSStringFromClass(type(of: glView))
                    L.append("  openGLView class: \(glClass)")
                    let glMethods = objcMethodNames(type(of: glView))
                    L.append("  \(glClass) -inst(\(glMethods.count)):")
                    for m in glMethods { L.append("    -\(m)") }
                    let glProps = objcPropertyNames(type(of: glView))
                    if !glProps.isEmpty { L.append("  \(glClass) props: \(glProps.joined(separator: ", "))") }

                    let glSizeGetters = ["getDesignResolutionSize", "designResolutionSize",
                                         "getFrameSize", "frameSize", "surfaceSize"]
                    for gs in glSizeGetters {
                        guard (glView as AnyObject).responds(to: NSSelectorFromString(gs)) else { continue }
                        if let imp = class_getMethodImplementation(type(of: glView), NSSelectorFromString(gs)) {
                            typealias SizeFn = @convention(c) (AnyObject, Selector) -> CGSize
                            let fn = unsafeBitCast(imp, to: SizeFn.self)
                            let s = fn(glView as AnyObject, NSSelectorFromString(gs))
                            L.append("  glView.\(gs) = \(s.width)x\(s.height)")
                        }
                    }
                }

                let sceneSelectors = ["runningScene", "getRunningScene", "scene", "_runningScene"]
                for scSel in sceneSelectors {
                    let sel = NSSelectorFromString(scSel)
                    guard director.responds(to: sel),
                          let sr = director.perform(sel) else { continue }
                    let scene = sr.takeUnretainedValue()
                    let sceneClass = NSStringFromClass(type(of: scene))
                    L.append("")
                    L.append("Scene: \(sceneClass) (via \(scSel))")

                    let sceneMethods = objcMethodNames(type(of: scene))
                    L.append("\(sceneClass) -inst(\(sceneMethods.count)):")
                    for m in sceneMethods { L.append("  -\(m)") }
                    let sceneProps = objcPropertyNames(type(of: scene))
                    if !sceneProps.isEmpty { L.append("\(sceneClass) props: \(sceneProps.joined(separator: ", "))") }
                    let sceneIvars = objcIvarNames(type(of: scene))
                    if !sceneIvars.isEmpty { L.append("\(sceneClass) ivars: \(sceneIvars.joined(separator: ", "))") }

                    let sceneValueProbes = ["scale", "scaleX", "scaleY",
                                            "anchorPoint", "position", "contentSize",
                                            "zOrder", "tag", "name", "visible", "running"]
                    for sp in sceneValueProbes {
                        guard (scene as AnyObject).responds(to: NSSelectorFromString(sp)) else { continue }
                        if let imp = class_getMethodImplementation(type(of: scene), NSSelectorFromString(sp)) {
                            if sp == "anchorPoint" || sp == "position" {
                                typealias PtFn = @convention(c) (AnyObject, Selector) -> CGPoint
                                let fn = unsafeBitCast(imp, to: PtFn.self)
                                let v = fn(scene as AnyObject, NSSelectorFromString(sp))
                                L.append("  scene.\(sp) = \(v)")
                            } else if sp == "contentSize" {
                                typealias SzFn = @convention(c) (AnyObject, Selector) -> CGSize
                                let fn = unsafeBitCast(imp, to: SzFn.self)
                                let v = fn(scene as AnyObject, NSSelectorFromString(sp))
                                L.append("  scene.\(sp) = \(v)")
                            } else if sp == "scale" || sp == "scaleX" || sp == "scaleY" {
                                typealias FlFn = @convention(c) (AnyObject, Selector) -> CGFloat
                                let fn = unsafeBitCast(imp, to: FlFn.self)
                                let v = fn(scene as AnyObject, NSSelectorFromString(sp))
                                L.append("  scene.\(sp) = \(v)")
                            } else if sp == "zOrder" || sp == "tag" {
                                typealias IntFn = @convention(c) (AnyObject, Selector) -> Int
                                let fn = unsafeBitCast(imp, to: IntFn.self)
                                let v = fn(scene as AnyObject, NSSelectorFromString(sp))
                                L.append("  scene.\(sp) = \(v)")
                            }
                        }
                    }

                    let cameraProbes = ["camera", "getCamera", "defaultCamera",
                                        "_camera", "getDefaultCamera"]
                    for cp in cameraProbes {
                        guard (scene as AnyObject).responds(to: NSSelectorFromString(cp)) else { continue }
                        L.append("  scene.\(cp) ✓")
                        if let cr = (scene as AnyObject).perform(NSSelectorFromString(cp)) {
                            let cam = cr.takeUnretainedValue()
                            let camClass = NSStringFromClass(type(of: cam))
                            L.append("  Camera: \(camClass)")
                            let camMethods = objcMethodNames(type(of: cam))
                            L.append("  \(camClass) -inst(\(camMethods.count)):")
                            for m in camMethods { L.append("    -\(m)") }
                            let camProps = objcPropertyNames(type(of: cam))
                            if !camProps.isEmpty { L.append("  \(camClass) props: \(camProps.joined(separator: ", "))") }
                            let camIvars = objcIvarNames(type(of: cam))
                            if !camIvars.isEmpty { L.append("  \(camClass) ivars: \(camIvars.joined(separator: ", "))") }
                        }
                    }

                    let childSel = NSSelectorFromString("children")
                    if (scene as AnyObject).responds(to: childSel),
                       let cr = (scene as AnyObject).perform(childSel),
                       let children = cr.takeUnretainedValue() as? NSArray {
                        L.append("  children(\(children.count)):")
                        for (i, child) in children.enumerated() where i < 20 {
                            guard let childType = type(of: child) as? AnyClass else { continue }
                            let childClass = NSStringFromClass(childType)
                            var childInfo = "[\(i)] \(childClass)"
                            if (child as AnyObject).responds(to: NSSelectorFromString("tag")) {
                                if let imp = class_getMethodImplementation(childType, NSSelectorFromString("tag")) {
                                    typealias IntFn = @convention(c) (AnyObject, Selector) -> Int
                                    let fn = unsafeBitCast(imp, to: IntFn.self)
                                    childInfo += " tag=\(fn(child as AnyObject, NSSelectorFromString("tag")))"
                                }
                            }
                            L.append("    \(childInfo)")

                            let childMethods = objcMethodNames(childType)
                            L.append("    \(childClass) -inst(\(childMethods.count)):")
                            for m in childMethods { L.append("      -\(m)") }

                            let subChildSel = NSSelectorFromString("children")
                            if (child as AnyObject).responds(to: subChildSel),
                               let scr = (child as AnyObject).perform(subChildSel),
                               let subChildren = scr.takeUnretainedValue() as? NSArray, subChildren.count > 0 {
                                L.append("      subchildren(\(subChildren.count)):")
                                for (j, sc) in subChildren.enumerated() where j < 10 {
                                    guard let scType = type(of: sc) as? AnyClass else { continue }
                                    L.append("        [\(j)] \(NSStringFromClass(scType))")
                                }
                            }
                        }
                    }
                    break
                }
                break outer
            }
        }

        var classCount: UInt32 = 0
        if let classList = objc_copyClassList(&classCount) {
            var cameraClasses: [String] = []
            for i in 0..<Int(classCount) {
                let name = String(cString: class_getName(classList[i]))
                let nl = name.lowercased()
                if nl.contains("camera") || nl.contains("ccscene") ||
                   nl.contains("cclayer") || nl.contains("ccnode") ||
                   nl.contains("ccsprite") || nl.contains("ccaction") ||
                   nl.contains("cctexture") || nl.contains("ccrenderer") ||
                   nl.contains("ccglprogram") || nl.contains("ccshader") {
                    cameraClasses.append(name)
                }
            }
            free(UnsafeMutableRawPointer(classList))
            if !cameraClasses.isEmpty {
                L.append("")
                L.append("Cocos classes found: \(cameraClasses.sorted().joined(separator: ", "))")
                for cn in cameraClasses.sorted() {
                    guard let cls = NSClassFromString(cn) else { continue }
                    let methods = objcMethodNames(cls)
                    L.append("\(cn) -inst(\(methods.count)): \(methods.joined(separator: ", "))")
                }
            }
        }
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

    deinit {
        displayLink?.invalidate()
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

        _ = tryCppHooks()
        _ = tryObjCHooks()

        activeMethod = .displayZoom
        statusText = "Display zoom (\(debugInfo))"
    }

    func setZoom(_ factor: CGFloat) {
        currentZoom = factor
        engineSetScale?(Float(factor))
        applyDisplayZoom(factor)
    }

    func reset() { setZoom(1.0) }

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
