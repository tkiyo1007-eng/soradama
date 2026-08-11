import Foundation
import StoreKit
import Observation

/// 投げ銭(Tip Jar)。
///
/// 見返りのある課金ではなく「作者を応援する」ためのもの。
/// 消耗型(Consumable)にしているのは、機能を売っているわけではないから。
/// 何度でも贈れて、贈っても何かがアンロックされることはない。
///
/// 買った回数だけはローカルに残し、お礼の言い方を少し変えている。
/// サーバーは持たないので、機種変更で消えるが、それで困る性質のものではない。
@Observable
@MainActor
final class TipJar {
    /// 投げ銭の導線を画面に出すかどうか。
    ///
    /// Open-Meteo の無料プランは規約で商用利用が不可となっている一方、
    /// 「無料アプリで任意の寄付を受け取ること」が商用にあたるかは明記されていない。
    /// 問い合わせの回答が得られるまでは導線を隠しておく。
    /// 実装そのものは動く状態で残してあるので、true に戻せばそのまま出る。
    static let isEnabled = false

    /// 商品ID。App Store Connect 側にも同じIDで登録する必要がある。
    enum Tier: String, CaseIterable, Identifiable {
        case small  = "com.tkiyo1007.soradama.tip.small"
        case medium = "com.tkiyo1007.soradama.tip.medium"
        case large  = "com.tkiyo1007.soradama.tip.large"

        var id: String { rawValue }

        /// 金額そのものではなく「気持ちの大きさ」で並べる。
        /// 実際の価格は App Store Connect 側の設定が正で、画面には Product.displayPrice を出す。
        var title: String {
            switch self {
            case .small:  return String(localized: "ちいさな空玉")
            case .medium: return String(localized: "はれた日の空玉")
            case .large:  return String(localized: "満月の空玉")
            }
        }

        var detail: String {
            switch self {
            case .small:  return String(localized: "缶コーヒー1本ぶんの応援")
            case .medium: return String(localized: "開発を続ける力になります")
            case .large:  return String(localized: "とても大きな支えになります")
            }
        }

        var symbol: String {
            switch self {
            case .small:  return "drop"
            case .medium: return "sun.max"
            case .large:  return "moon.stars"
            }
        }
    }

    enum State: Equatable {
        case idle
        case loading
        /// 商品を取得できなかった(未登録・審査前・圏外など)
        case unavailable(String)
        case ready
    }

    private(set) var state: State = .idle
    private(set) var products: [Product] = []
    /// 購入処理中の商品ID(ボタンをスピナーに差し替えるため)
    private(set) var purchasingID: String?
    /// 直近の購入が成功した瞬間に立つ。お礼の演出を出したら呼び出し側が下ろす。
    var justThanked = false

    private static let countKey = "aurora.tipCount"

    /// これまでに応援してくれた回数
    private(set) var tipCount: Int = UserDefaults.standard.integer(forKey: TipJar.countKey)

    /// アプリに1つだけ。
    /// Transaction.updates の監視は起動中ずっと動き続けるものなので、
    /// 画面を開くたびにインスタンスを作ると監視が積み上がってしまう。
    static let shared = TipJar()

    private init() {
        // App Store 側から遅れて届く取引(承認待ち・返金など)を拾い続ける
        Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    // MARK: - 読み込み

    func load() async {
        guard products.isEmpty else { return }
        state = .loading
        do {
            let fetched = try await Product.products(for: Tier.allCases.map(\.rawValue))
            // Tier の並び順(気持ちの小さい順)を保つ。API の返却順は保証されない。
            products = Tier.allCases.compactMap { tier in
                fetched.first { $0.id == tier.rawValue }
            }
            state = products.isEmpty
                ? .unavailable(String(localized: "いまは応援を受け取れません"))
                : .ready
        } catch {
            state = .unavailable(String(localized: "通信できませんでした"))
        }
    }

    // MARK: - 購入

    func purchase(_ product: Product) async {
        guard purchasingID == nil else { return }
        purchasingID = product.id
        defer { purchasingID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // 購入の失敗は StoreKit 側がダイアログを出すので、ここでは黙って戻る
        }
    }

    /// 検証を通った取引だけを数え、消耗型なので必ず finish する。
    /// finish を忘れると同じ取引が Transaction.updates に流れ続け、
    /// アプリを開くたびにお礼の演出が出てしまう。
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        defer { Task { await transaction.finish() } }

        guard transaction.revocationDate == nil,
              Tier(rawValue: transaction.productID) != nil else { return }

        tipCount += 1
        UserDefaults.standard.set(tipCount, forKey: Self.countKey)
        justThanked = true
    }

    // MARK: - お礼の言葉

    /// 回数に応じて少しだけ言い方を変える。
    var thanksMessage: String {
        switch tipCount {
        case 0, 1: return String(localized: "ありがとうございます。\nこの空は、あなたのおかげで続きます。")
        case 2, 3: return String(localized: "また来てくださって、ありがとうございます。\n空玉はこれからも増えていきます。")
        default:   return String(localized: "いつも支えてくださって、本当にありがとうございます。")
        }
    }
}
