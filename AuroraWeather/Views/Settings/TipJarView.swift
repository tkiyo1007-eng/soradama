import SwiftUI
import StoreKit

/// 投げ銭の画面。
///
/// 「支援してください」と迫るのではなく、置いてあるだけの募金箱にしたい。
/// なので金額は前に出さず、まず空玉を見せて、押した人にだけ価格が見えるようにしている。
struct TipJarView: View {
    private var tipJar = TipJar.shared
    @State private var showThanks = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.11, blue: 0.26),
                             Color(red: 0.16, green: 0.22, blue: 0.42)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 26) {
                        header
                        content
                        footnote
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 28)
                }

                if showThanks {
                    ThanksOverlay(message: tipJar.thanksMessage) {
                        withAnimation(.easeOut(duration: 0.3)) { showThanks = false }
                    }
                    .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .navigationTitle("作者を応援する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task { await tipJar.load() }
        .onChange(of: tipJar.justThanked) { _, thanked in
            guard thanked else { return }
            tipJar.justThanked = false
            Haptics.success()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showThanks = true }
        }
    }

    // MARK: - 各部

    private var header: some View {
        VStack(spacing: 14) {
            OrbBadge()
                .frame(width: 96, height: 96)
                .padding(.top, 8)

            Text("空玉は、ひとりで作っています")
                .font(.headline)

            Text("広告も、有料機能もありません。\nもし気に入ってもらえたら、\n開発を続けるための応援をいただけると嬉しいです。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tipJar.state {
        case .idle, .loading:
            ProgressView()
                .tint(.white)
                .padding(.vertical, 40)

        case .unavailable(let reason):
            VStack(spacing: 10) {
                Image(systemName: "cloud.fog")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                Button("もう一度読み込む") {
                    Task { await tipJar.load() }
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 2)
            }
            .padding(.vertical, 30)

        case .ready:
            VStack(spacing: 12) {
                ForEach(tipJar.products, id: \.id) { product in
                    if let tier = TipJar.Tier(rawValue: product.id) {
                        TipRow(
                            tier: tier,
                            price: product.displayPrice,
                            isPurchasing: tipJar.purchasingID == product.id
                        ) {
                            Task { await tipJar.purchase(product) }
                        }
                    }
                }
            }
        }
    }

    private var footnote: some View {
        VStack(spacing: 8) {
            if tipJar.tipCount > 0 {
                Label("これまで \(tipJar.tipCount) 回の応援をいただきました", systemImage: "heart.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.78))
            }
            Text("応援は何度でもできます。機能が増えたり、広告が消えたりすることはありません。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}

// MARK: - 一行ぶんのボタン

private struct TipRow: View {
    let tier: TipJar.Tier
    let price: String
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: tier.symbol)
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(Color(red: 0.78, green: 0.90, blue: 1.0))

                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.title)
                        .font(.callout.weight(.semibold))
                    Text(tier.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(price)
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            .padding(16)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .accessibilityLabel("\(tier.title)、\(price)")
        .accessibilityHint(tier.detail)
    }
}

// MARK: - お礼の演出

/// 買った直後に一度だけ出る。派手すぎず、でも記憶に残る程度に。
private struct ThanksOverlay: View {
    let message: String
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 20) {
                OrbBadge()
                    .frame(width: 120, height: 120)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .shadow(color: Color(red: 0.6, green: 0.85, blue: 1).opacity(0.7), radius: 30)

                Text(message)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .opacity(appeared ? 1 : 0)

                Button("閉じる", action: onDismiss)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.18), in: Capsule())
                    .opacity(appeared ? 1 : 0)
            }
            .padding(32)
            .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

// MARK: - 応援画面に置く空玉

/// アイコンではなく、その場で描いた玉を置く。
/// 設定画面のどこよりも「アプリらしさ」が要る場所なので、静止画にはしたくない。
private struct OrbBadge: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.55, green: 0.82, blue: 1.0).opacity(0.45), .clear],
                        center: .center, startRadius: 4, endRadius: 90
                    )
                )
                .scaleEffect(pulse ? 1.12 : 0.95)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.35, green: 0.62, blue: 0.95),
                                 Color(red: 0.72, green: 0.88, blue: 0.99)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.55), lineWidth: 1.5)
                        .mask(
                            LinearGradient(colors: [.white, .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .blur(radius: 6)
                        .offset(x: 22, y: 18)
                }
                .padding(14)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    TipJarView()
}
