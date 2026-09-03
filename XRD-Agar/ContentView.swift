import SwiftUI

struct ContentView: View {
    @StateObject private var settings = GameSettings()
    @StateObject private var botEngine = BotEngine()
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var menuOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var showMenu: Bool = false
    @State private var showZoom: Bool = true
    @State private var isUnlocked: Bool = false
    @State private var targetUpdateTimer: Timer?

    private let bridge = GameJSBridge()

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        if !isUnlocked && !licenseManager.isValid {
            LicenseView(licenseManager: licenseManager) {
                withAnimation { isUnlocked = true }
            }
        } else {
            gameView
        }
    }

    private var gameView: some View {
        ZStack {
            // Game WebView (full screen)
            AgarWebView(settings: settings, bridge: bridge)
                .ignoresSafeArea()

            // Toggle Button (top right)
            VStack {
                HStack {
                    Spacer()
                    menuToggleButton
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.trailing, 12)

            // Zoom Control (bottom center)
            if showZoom {
                VStack {
                    Spacer()
                    ZoomControl(settings: settings)
                        .padding(.bottom, 20)
                }
            }

            // Auto Feed Indicator
            if settings.isAutoFeeding {
                VStack {
                    HStack {
                        autoFeedIndicator
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.leading, 12)
            }

            // Mod Menu (draggable)
            if showMenu {
                ModMenuView(settings: settings, botEngine: botEngine)
                    .offset(
                        x: menuOffset.width + dragOffset.width,
                        y: menuOffset.height + dragOffset.height
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                menuOffset.width += value.translation.width
                                menuOffset.height += value.translation.height
                                dragOffset = .zero
                            }
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            setupTargetTracking()
        }
        .onDisappear {
            targetUpdateTimer?.invalidate()
        }
    }

    // MARK: - Menu Toggle

    private var menuToggleButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showMenu.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(xrdGradient, lineWidth: 2)
                    )
                    .shadow(color: xrdPurple.opacity(0.5), radius: 8)

                Text("XRD")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(xrdGradient)
            }
        }
    }

    // MARK: - Auto Feed Indicator

    private var autoFeedIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .scaleEffect(settings.isAutoFeeding ? 1.5 : 1.0)
                        .opacity(settings.isAutoFeeding ? 0.0 : 0.5)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: settings.isAutoFeeding)
                )

            Text("AUTO FEED")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7))
        .cornerRadius(20)
    }

    // MARK: - Target Tracking

    private func setupTargetTracking() {
        bridge.onPlayersUpdated = { players in
            if let targetUID = settings.botConfig.targetUID.nilIfEmpty,
               let target = players.first(where: { $0.uid == targetUID }) {
                settings.targetPlayer = target
                botEngine.updateTargetFromPlayer(target)
            }
        }

        targetUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            if let target = settings.targetPlayer,
               let updated = settings.currentPlayers.first(where: { $0.id == target.id }) {
                settings.targetPlayer = updated
                botEngine.updateTargetFromPlayer(updated)
            }
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview {
    ContentView()
}
