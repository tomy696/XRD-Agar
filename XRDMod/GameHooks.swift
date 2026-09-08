import UIKit
import ObjectiveC

class GameHooks: NSObject, ObservableObject {
    static let shared = GameHooks()

    static var unlockFPS = false
    static var autoRespawn = false
    static var unlockSkins = false
    static var unlockEmojis = false
    static var feedMacroActive = false
    static var splitMacroActive = false
    static var showMass = false
    static var hideGrid = false
    static var hideBorder = false
    static var noSkins = false
    static var disableAnimations = false

    @Published var hookStatus: String = "Not installed"
    @Published var hookedMethods: [String] = []
    @Published var fpsValue: Int = 60

    private static var origSetPreferredFPS: IMP?
    private static var origOnDeath: IMP?
    private static var origAttemptSetSkin: IMP?
    private static var origFramerateControl: IMP?
    private static var origGoToAppState: IMP?
    private static var origInitCellState: IMP?
    private static var origDrawGrid: IMP?
    private static var origDrawBorder: IMP?
    private static var origSetSkinTexture: IMP?
    private static var origRunAction: IMP?
    private static var origSetMassLabel: IMP?

    private var splitButton: UIControl?
    private var feedButton: UIControl?
    private var macroTimer: Timer?
    private weak var gameWindow: UIWindow?

    func install(window: UIWindow) {
        gameWindow = window
        var hooked: [String] = []

        if hookFPS() { hooked.append("FPS") }
        if hookAutoRespawn() { hooked.append("AutoRespawn") }
        if hookSkins() { hooked.append("Skins") }
        if hookEmojis() { hooked.append("Emojis") }
        if hookGrid() { hooked.append("Grid") }
        if hookBorder() { hooked.append("Border") }
        if hookNoSkins() { hooked.append("NoSkins") }
        if hookAnimations() { hooked.append("Animations") }
        if hookMassDisplay() { hooked.append("Mass") }

        findGameButtons(in: window)

        hookedMethods = hooked
        hookStatus = hooked.isEmpty ? "No hooks found" : "\(hooked.count) hooks"
    }

    // MARK: - FPS Unlock

    private func hookFPS() -> Bool {
        guard let cls = NSClassFromString("MTKView") else { return false }
        let sel = NSSelectorFromString("setPreferredFramesPerSecond:")
        guard let method = class_getInstanceMethod(cls, sel) else { return false }

        let origIMP = method_getImplementation(method)
        GameHooks.origSetPreferredFPS = origIMP

        typealias OrigFn = @convention(c) (AnyObject, Selector, Int) -> Void
        let block: @convention(block) (AnyObject, Int) -> Void = { obj, fps in
            let target = GameHooks.unlockFPS ? 120 : fps
            let orig = unsafeBitCast(origIMP, to: OrigFn.self)
            orig(obj, sel, target)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))

        applyFPSToExisting()
        return true
    }

    func applyFPSToExisting() {
        guard let window = gameWindow else { return }
        let target = GameHooks.unlockFPS ? 120 : 60
        findMTKViews(in: window) { view in
            if view.responds(to: NSSelectorFromString("setPreferredFramesPerSecond:")) {
                view.perform(NSSelectorFromString("setPreferredFramesPerSecond:"), with: target)
            }
        }
    }

    private func findMTKViews(in view: UIView, handler: (UIView) -> Void) {
        let name = String(describing: type(of: view))
        if name.contains("MTKView") || name.contains("MetalView") {
            handler(view)
        }
        for sub in view.subviews { findMTKViews(in: sub, handler: handler) }
    }

    // MARK: - Auto Respawn

    private func hookAutoRespawn() -> Bool {
        let classNames = [
            "OnlineClassicArenaState", "ClassicArenaState",
            "BaseArenaState", "OnlineArenaState"
        ]
        for className in classNames {
            guard let cls = NSClassFromString(className) else { continue }
            let sel = NSSelectorFromString("onDeath")
            guard let method = class_getInstanceMethod(cls, sel) else { continue }

            let origIMP = method_getImplementation(method)
            GameHooks.origOnDeath = origIMP

            typealias OrigFn = @convention(c) (AnyObject, Selector) -> Void
            let block: @convention(block) (AnyObject) -> Void = { obj in
                let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                orig(obj, sel)
                if GameHooks.autoRespawn {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let playSel = NSSelectorFromString("playButtonCallback")
                        if obj.responds(to: playSel) {
                            _ = obj.perform(playSel)
                        }
                        let goSel = NSSelectorFromString("goToApplicationState:")
                        if obj.responds(to: goSel) {
                            _ = obj.perform(goSel, with: 1)
                        }
                    }
                }
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
            return true
        }
        return false
    }

    // MARK: - Unlock Skins

    private func hookSkins() -> Bool {
        let classNames = [
            "BaseArenaView", "ClassicArenaView",
            "BaseArenaState", "OnlineClassicArenaState",
            "AgarIoPromoManager"
        ]
        for className in classNames {
            guard let cls = NSClassFromString(className) else { continue }
            let sel = NSSelectorFromString("attemptSetMysterySkinWithName:hasTemporarySkin:")
            guard let method = class_getInstanceMethod(cls, sel) else { continue }

            let origIMP = method_getImplementation(method)
            GameHooks.origAttemptSetSkin = origIMP

            typealias OrigFn = @convention(c) (AnyObject, Selector, AnyObject, ObjCBool) -> Void
            let block: @convention(block) (AnyObject, AnyObject, ObjCBool) -> Void = { obj, name, hasTmp in
                let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                if GameHooks.unlockSkins {
                    orig(obj, sel, name, ObjCBool(true))
                } else {
                    orig(obj, sel, name, hasTmp)
                }
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
            return true
        }

        for className in classNames {
            guard let cls = NSClassFromString(className) else { continue }
            let allMethods = ["isSkinUnlocked:", "isSkinAvailable:", "hasSkin:",
                              "isEmoticonUnlocked:", "isCoinSkinUnlocked:"]
            for mName in allMethods {
                let sel = NSSelectorFromString(mName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let block: @convention(block) (AnyObject, AnyObject) -> ObjCBool = { _, _ in
                    return GameHooks.unlockSkins ? ObjCBool(true) : ObjCBool(false)
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
            }
        }
        return false
    }

    // MARK: - Unlock Emojis

    private func hookEmojis() -> Bool {
        let classNames = [
            "BaseArenaView", "ClassicArenaView", "BaseArenaState"
        ]
        let selNames = ["isEmoticonUnlocked:", "isEmojiUnlocked:", "isEmojiAvailable:"]

        for className in classNames {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in selNames {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let block: @convention(block) (AnyObject, AnyObject) -> ObjCBool = { _, _ in
                    return GameHooks.unlockEmojis ? ObjCBool(true) : ObjCBool(false)
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                return true
            }
        }
        return false
    }

    // MARK: - Hide Grid

    private func hookGrid() -> Bool {
        let arenaClasses = [
            "BaseArenaView", "ClassicArenaView", "BaseArenaState",
            "OnlineClassicArenaState", "OnlineArenaState"
        ]
        let gridSelectors = ["drawGrid", "renderGrid", "drawGridLines", "drawGridWithContext:"]
        var found = false
        for className in arenaClasses {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in gridSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let origIMP = method_getImplementation(method)
                GameHooks.origDrawGrid = origIMP
                typealias OrigFn = @convention(c) (AnyObject, Selector) -> Void
                let block: @convention(block) (AnyObject) -> Void = { obj in
                    if !GameHooks.hideGrid {
                        let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                        orig(obj, sel)
                    }
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                found = true
            }

            let boolSelectors = ["isGridVisible", "gridEnabled", "showGrid"]
            for selName in boolSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let block: @convention(block) (AnyObject) -> ObjCBool = { _ in
                    return GameHooks.hideGrid ? ObjCBool(false) : ObjCBool(true)
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                found = true
            }
        }
        return found
    }

    // MARK: - Hide Border

    private func hookBorder() -> Bool {
        let arenaClasses = [
            "BaseArenaView", "ClassicArenaView", "BaseArenaState",
            "OnlineClassicArenaState", "OnlineArenaState"
        ]
        let borderSelectors = ["drawBorder", "renderBorder", "drawBorderLines", "drawWorldBorder"]
        var found = false
        for className in arenaClasses {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in borderSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let origIMP = method_getImplementation(method)
                GameHooks.origDrawBorder = origIMP
                typealias OrigFn = @convention(c) (AnyObject, Selector) -> Void
                let block: @convention(block) (AnyObject) -> Void = { obj in
                    if !GameHooks.hideBorder {
                        let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                        orig(obj, sel)
                    }
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                found = true
            }

            let boolSelectors = ["isBorderVisible", "borderEnabled", "showBorder"]
            for selName in boolSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let block: @convention(block) (AnyObject) -> ObjCBool = { _ in
                    return GameHooks.hideBorder ? ObjCBool(false) : ObjCBool(true)
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                found = true
            }
        }
        return found
    }

    // MARK: - No Skins (raw cells)

    private func hookNoSkins() -> Bool {
        let cellClasses = [
            "AgarCell", "PlayerAvatar", "CellSprite", "CellNode",
            "BaseArenaView", "ClassicArenaView"
        ]
        let skinSelectors = [
            "setSkinTexture:", "applySkin:", "loadSkinTexture:",
            "setSkinImage:", "setSkin:", "updateSkinTexture"
        ]
        var found = false
        for className in cellClasses {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in skinSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let origIMP = method_getImplementation(method)
                GameHooks.origSetSkinTexture = origIMP
                typealias OrigFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
                let block: @convention(block) (AnyObject, AnyObject?) -> Void = { obj, texture in
                    if GameHooks.noSkins {
                        let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                        orig(obj, sel, nil)
                    } else {
                        let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                        orig(obj, sel, texture)
                    }
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                found = true
            }
        }
        return found
    }

    // MARK: - Disable Animations

    private func hookAnimations() -> Bool {
        let nodeClasses = [
            "AgarCell", "PlayerAvatar", "CellSprite", "CellNode",
            "BaseArenaView", "ClassicArenaView"
        ]
        let animSelectors = [
            "runAction:", "runAnimation:", "startAnimation:",
            "playAnimation:", "animateWithDuration:animations:"
        ]
        var found = false
        for className in nodeClasses {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in animSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let origIMP = method_getImplementation(method)
                GameHooks.origRunAction = origIMP
                typealias OrigFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
                let block: @convention(block) (AnyObject, AnyObject?) -> Void = { obj, action in
                    if !GameHooks.disableAnimations {
                        let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                        orig(obj, sel, action)
                    }
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                found = true
            }
        }
        return found
    }

    // MARK: - Show Mass Display

    private func hookMassDisplay() -> Bool {
        let cellClasses = [
            "AgarCell", "PlayerAvatar", "CellSprite", "CellNode"
        ]
        let massLabelSelectors = [
            "setDisplayedText:", "updateLabel:", "setLabelText:",
            "setNameLabel:", "updateNameLabel:"
        ]
        var found = false
        for className in cellClasses {
            guard let cls = NSClassFromString(className) else { continue }

            let sizeSelectors = ["setSize:", "setCellSize:", "setRadius:"]
            for selName in sizeSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let origIMP = method_getImplementation(method)
                let encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? ""
                let isFloat = encoding.contains("f") && !encoding.contains("d")

                if isFloat {
                    typealias OrigFn = @convention(c) (AnyObject, Selector, Float) -> Void
                    let block: @convention(block) (AnyObject, Float) -> Void = { obj, size in
                        let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                        orig(obj, sel, size)
                        if GameHooks.showMass {
                            let mass = Int(size * size / 100.0)
                            let massStr = mass > 999 ? "\(mass / 1000)k" : "\(mass)"
                            let labelSel = NSSelectorFromString("setMassText:")
                            if obj.responds(to: labelSel) {
                                _ = obj.perform(labelSel, with: massStr)
                            }
                        }
                    }
                    method_setImplementation(method, imp_implementationWithBlock(block))
                } else {
                    typealias OrigFn = @convention(c) (AnyObject, Selector, Double) -> Void
                    let block: @convention(block) (AnyObject, Double) -> Void = { obj, size in
                        let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                        orig(obj, sel, size)
                        if GameHooks.showMass {
                            let mass = Int(size * size / 100.0)
                            let massStr = mass > 999 ? "\(mass / 1000)k" : "\(mass)"
                            let labelSel = NSSelectorFromString("setMassText:")
                            if obj.responds(to: labelSel) {
                                _ = obj.perform(labelSel, with: massStr)
                            }
                        }
                    }
                    method_setImplementation(method, imp_implementationWithBlock(block))
                }
                found = true
            }

            for selName in massLabelSelectors {
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(cls, sel) else { continue }
                let origIMP = method_getImplementation(method)
                GameHooks.origSetMassLabel = origIMP
                typealias OrigFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
                let block: @convention(block) (AnyObject, AnyObject?) -> Void = { obj, text in
                    let orig = unsafeBitCast(origIMP, to: OrigFn.self)
                    if GameHooks.showMass {
                        let sizeSel = NSSelectorFromString("size")
                        var massStr = ""
                        if obj.responds(to: sizeSel), let sizeVal = obj.perform(sizeSel) {
                            let size = Double(Int(bitPattern: sizeVal.toOpaque()))
                            let mass = Int(size * size / 100.0)
                            massStr = mass > 999 ? " [\(mass / 1000)k]" : " [\(mass)]"
                        }
                        let combined = "\(text ?? "" as AnyObject)\(massStr)" as NSString
                        orig(obj, sel, combined)
                    } else {
                        orig(obj, sel, text)
                    }
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
                found = true
            }
        }
        return found
    }

    // MARK: - Feed / Split Macros

    func findGameButtons(in window: UIWindow) {
        findButtonByTag(in: window, tag: "split") { [weak self] btn in
            self?.splitButton = btn
        }
        findButtonByTag(in: window, tag: "eject") { [weak self] btn in
            self?.feedButton = btn
        }
        if splitButton == nil || feedButton == nil {
            findButtonsByPosition(in: window)
        }
    }

    private func findButtonByTag(in view: UIView, tag: String, handler: (UIControl) -> Void) {
        if let btn = view as? UIControl {
            let desc = String(describing: type(of: btn)).lowercased()
            if desc.contains(tag) { handler(btn); return }
            if let label = btn.accessibilityLabel?.lowercased(), label.contains(tag) {
                handler(btn); return
            }
        }
        for sub in view.subviews { findButtonByTag(in: sub, tag: tag, handler: handler) }
    }

    private func findButtonsByPosition(in window: UIWindow) {
        let screenW = window.bounds.width
        let screenH = window.bounds.height
        var candidates: [(UIControl, CGRect)] = []
        collectControls(in: window, into: &candidates)

        for (btn, frame) in candidates {
            let centerX = frame.midX
            let centerY = frame.midY
            if centerY > screenH * 0.7 {
                if centerX > screenW * 0.7 && splitButton == nil {
                    splitButton = btn
                } else if centerX < screenW * 0.3 && feedButton == nil {
                    feedButton = btn
                }
            }
        }
    }

    private func collectControls(in view: UIView, into list: inout [(UIControl, CGRect)]) {
        if let btn = view as? UIControl, btn.bounds.width > 30 && btn.bounds.height > 30 {
            let frame = btn.convert(btn.bounds, to: nil)
            list.append((btn, frame))
        }
        for sub in view.subviews { collectControls(in: sub, into: &list) }
    }

    func startFeedMacro(rate: Double = 50, size: Int = 1, invisible: Bool = false) {
        guard GameHooks.feedMacroActive else { return }
        macroTimer?.invalidate()
        let interval = max(0.02, 1.0 / rate)
        macroTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard GameHooks.feedMacroActive else {
                self?.macroTimer?.invalidate()
                self?.macroTimer = nil
                return
            }
            for _ in 0..<max(1, size) {
                if invisible {
                    NetworkInterceptor.shared.sendFeed()
                } else {
                    self?.tapButton(self?.feedButton)
                }
            }
        }
    }

    func startSplitMacro(count: Int = 16, rate: Double = 40, invisible: Bool = false) {
        let interval = max(0.02, 1.0 / rate)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                if invisible {
                    NetworkInterceptor.shared.sendSplit()
                } else {
                    self?.tapButton(self?.splitButton)
                }
            }
        }
    }

    private func tapButton(_ btn: UIControl?) {
        guard let btn = btn else { return }
        btn.sendActions(for: .touchUpInside)
    }

    func stopMacros() {
        macroTimer?.invalidate()
        macroTimer = nil
        GameHooks.feedMacroActive = false
        GameHooks.splitMacroActive = false
    }

    // MARK: - UserDefaults Persistence

    func saveToggles() {
        let d = UserDefaults.standard
        d.set(GameHooks.unlockFPS, forKey: "XRD_unlockFPS")
        d.set(GameHooks.autoRespawn, forKey: "XRD_autoRespawn")
        d.set(GameHooks.unlockSkins, forKey: "XRD_unlockSkins")
        d.set(GameHooks.unlockEmojis, forKey: "XRD_unlockEmojis")
        d.set(GameHooks.showMass, forKey: "XRD_showMass")
        d.set(GameHooks.hideGrid, forKey: "XRD_hideGrid")
        d.set(GameHooks.hideBorder, forKey: "XRD_hideBorder")
        d.set(GameHooks.noSkins, forKey: "XRD_noSkins")
        d.set(GameHooks.disableAnimations, forKey: "XRD_disableAnimations")
        d.synchronize()
    }

    func loadToggles() {
        let d = UserDefaults.standard
        GameHooks.unlockFPS = d.bool(forKey: "XRD_unlockFPS")
        GameHooks.autoRespawn = d.bool(forKey: "XRD_autoRespawn")
        GameHooks.unlockSkins = d.bool(forKey: "XRD_unlockSkins")
        GameHooks.unlockEmojis = d.bool(forKey: "XRD_unlockEmojis")
        GameHooks.showMass = d.bool(forKey: "XRD_showMass")
        GameHooks.hideGrid = d.bool(forKey: "XRD_hideGrid")
        GameHooks.hideBorder = d.bool(forKey: "XRD_hideBorder")
        GameHooks.noSkins = d.bool(forKey: "XRD_noSkins")
        GameHooks.disableAnimations = d.bool(forKey: "XRD_disableAnimations")
    }
}
