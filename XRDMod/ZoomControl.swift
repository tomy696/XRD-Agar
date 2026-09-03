import SwiftUI

struct ZoomControl: View {
    @ObservedObject var settings: GameSettings

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                settings.zoomLevel = max(0.2, settings.zoomLevel - 0.1)
            }) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(xrdPurple)
            }

            VStack(spacing: 2) {
                Text(String(format: "%.1fx", settings.zoomLevel))
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                Slider(value: $settings.zoomLevel, in: 0.2...5.0, step: 0.1)
                    .accentColor(xrdPurple)
                    .frame(width: 120)
            }

            Button(action: {
                settings.zoomLevel = min(5.0, settings.zoomLevel + 0.1)
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(xrdCyan)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
