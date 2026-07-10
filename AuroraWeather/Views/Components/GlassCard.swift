import SwiftUI

/// 「そらだま」ブランドのカード。
/// Apple 純正「天気」アプリの均一な白フチ磨りガラスとは異なり、
/// 空色〜藍色のグラデーション縁取りと差し色のシャドウで独自のトーンを出す。
struct GlassCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    private let accentTop = Color(red: 0.55, green: 0.80, blue: 1.0)
    private let accentBottom = Color(red: 0.42, green: 0.36, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.footnote.weight(.semibold))
                    }
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .kerning(1.5)
                }
                .foregroundStyle(accentTop.opacity(0.85))
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentTop.opacity(0.22), accentBottom.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accentTop.opacity(0.55), accentBottom.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: accentBottom.opacity(0.28), radius: 18, y: 10)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        GlassCard(title: "時間ごとの予報", systemImage: "clock") {
            Text("コンテンツ")
                .foregroundStyle(.white)
        }
        .padding()
    }
}
