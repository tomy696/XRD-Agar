import SwiftUI

struct LicenseView: View {
    @ObservedObject var licenseManager: LicenseManager
    @State private var keyInput: String = ""
    @State private var shakeOffset: CGFloat = 0
    var onUnlocked: () -> Void

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Background glow
            Circle()
                .fill(xrdPurple.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(y: -100)

            VStack(spacing: 30) {
                Spacer()

                // Logo
                VStack(spacing: 8) {
                    Text("XRD")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(xrdGradient)
                        .shadow(color: xrdPurple.opacity(0.8), radius: 20)

                    Text("AGAR.IO MOD MENU")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .tracking(6)
                }

                // Key Input
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LICENSE KEY")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(xrdCyan)
                            .tracking(2)

                        HStack {
                            TextField("XRD-xxxxx-xxxxx", text: $keyInput)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)

                            Button(action: {
                                if let clip = UIPasteboard.general.string {
                                    keyInput = clip
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 16))
                                    .foregroundColor(xrdCyan)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }

                    Button(action: activateKey) {
                        Text("ACTIVATE")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(xrdGradient)
                            .cornerRadius(12)
                            .shadow(color: xrdPurple.opacity(0.5), radius: 10)
                    }

                    Text(licenseManager.statusMessage)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(licenseManager.isValid ? .green : .red.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .offset(x: shakeOffset)

                Spacer()
                Spacer()

                Text("v1.0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.3))
                    .padding(.bottom, 20)
            }
        }
    }

    private func activateKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if licenseManager.validate(key: trimmed) {
            onUnlocked()
        } else {
            withAnimation(.default) {
                shakeOffset = 10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.default) { shakeOffset = -10 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.default) { shakeOffset = 0 }
            }
        }
    }
}
