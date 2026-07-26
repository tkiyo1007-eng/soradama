import SwiftUI

/// そらだま独自の天気アイコン(SF Symbols の天気グリフは使わない)。
/// 幾何形状(円・カプセル・自前のクラウドシェイプ)の組み合わせで表現する、
/// フラットなオリジナルデザイン。
struct WeatherIconView: View {
    let kind: WeatherKind
    let isDay: Bool
    var tint: Color = .white

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                content(size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func content(size: CGFloat) -> some View {
        switch kind {
        case .clear:
            if isDay {
                sunMark(size: size)
            } else {
                moonMark(size: size)
            }
        case .partlyCloudy:
            ZStack {
                if isDay {
                    sunMark(size: size * 0.58)
                        .offset(x: size * 0.17, y: -size * 0.18)
                } else {
                    moonMark(size: size * 0.5)
                        .offset(x: size * 0.17, y: -size * 0.18)
                }
                cloudMark(size: size)
                    .offset(y: size * 0.14)
            }
        case .cloudy:
            cloudMark(size: size)
        case .fog:
            ZStack {
                cloudMark(size: size * 0.88, opacity: 0.6)
                    .offset(y: -size * 0.06)
                fogLines(size: size)
                    .offset(y: size * 0.22)
            }
        case .drizzle:
            ZStack {
                cloudMark(size: size * 0.92)
                    .offset(y: -size * 0.08)
                dropMarks(size: size, count: 3)
                    .offset(y: size * 0.20)
            }
        case .rain:
            ZStack {
                cloudMark(size: size * 0.92)
                    .offset(y: -size * 0.08)
                dropMarks(size: size, count: 4)
                    .offset(y: size * 0.22)
            }
        case .snow:
            ZStack {
                cloudMark(size: size * 0.92)
                    .offset(y: -size * 0.08)
                snowMarks(size: size)
                    .offset(y: size * 0.20)
            }
        case .thunderstorm:
            ZStack {
                cloudMark(size: size * 0.92, opacity: 0.85)
                    .offset(y: -size * 0.1)
                boltMark(size: size)
                    .offset(y: size * 0.14)
            }
        }
    }

    // MARK: - パーツ

    private func sunMark(size: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(Color(red: 1.0, green: 0.78, blue: 0.35))
                    .frame(width: size * 0.07, height: size * 0.20)
                    .offset(y: -size * 0.44)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.86, blue: 0.5), Color(red: 1.0, green: 0.72, blue: 0.25)],
                        center: .center, startRadius: 0, endRadius: size * 0.3
                    )
                )
                .frame(width: size * 0.56, height: size * 0.56)
        }
        .frame(width: size, height: size)
    }

    private func moonMark(size: CGFloat) -> some View {
        MoonShape()
            .fill(Color(red: 0.85, green: 0.88, blue: 0.98), style: FillStyle(eoFill: true))
            .frame(width: size * 0.56, height: size * 0.56)
    }

    private func cloudMark(size: CGFloat, opacity: Double = 1.0) -> some View {
        CloudShape()
            .fill(tint.opacity(opacity))
            .frame(width: size * 0.92, height: size * 0.6)
    }

    private func dropMarks(size: CGFloat, count: Int) -> some View {
        HStack(spacing: size * 0.08) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color(red: 0.5, green: 0.78, blue: 1.0))
                    .frame(width: size * 0.05, height: size * (i % 2 == 0 ? 0.16 : 0.11))
            }
        }
    }

    private func snowMarks(size: CGFloat) -> some View {
        HStack(spacing: size * 0.10) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.08, height: size * 0.08)
            }
        }
    }

    private func fogLines(size: CGFloat) -> some View {
        VStack(spacing: size * 0.07) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: size * (0.7 - Double(i) * 0.12), height: size * 0.045)
            }
        }
    }

    private func boltMark(size: CGFloat) -> some View {
        BoltShape()
            .fill(Color(red: 1.0, green: 0.85, blue: 0.35))
            .frame(width: size * 0.28, height: size * 0.4)
    }
}

/// 独自クラウドシェイプ(円弧3つ+ベース台形の組み合わせ)
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.addRoundedRect(
            in: CGRect(x: w * 0.04, y: h * 0.45, width: w * 0.92, height: h * 0.45),
            cornerSize: CGSize(width: h * 0.22, height: h * 0.22)
        )
        path.addEllipse(in: CGRect(x: 0, y: h * 0.28, width: w * 0.46, height: h * 0.5))
        path.addEllipse(in: CGRect(x: w * 0.30, y: 0, width: w * 0.55, height: h * 0.62))
        path.addEllipse(in: CGRect(x: w * 0.56, y: h * 0.24, width: w * 0.44, height: h * 0.5))
        return path
    }
}

/// 独自ムーンシェイプ(三日月)
struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        // 切り欠き用の円。元の円に対して小さめ・控えめなオフセットにすることで、
        // 三日月の光る部分に十分な太さを残す(細すぎると夜空の暗い背景に沈んで見えなくなる)。
        let offsetRect = CGRect(
            x: rect.minX + rect.width * 0.30,
            y: rect.minY - rect.height * 0.16,
            width: rect.width * 0.84,
            height: rect.height * 0.84
        )
        path.addEllipse(in: offsetRect)
        return path
    }
}

/// 独自の稲妻シェイプ(SF Symbols の bolt とは異なる非対称ジグザグ)
struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.62, y: 0))
        path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.30, y: h))
        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.38))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.38))
        path.closeSubpath()
        return path
    }
}
