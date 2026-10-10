# アプリ内イベント「冬のはじまりの空玉」（2026年11月）

状態: 案。App Store Connect には未作成・未提出。アプリの更新はいらない（今あるアプリの内容だけを使う）。

## 中身（アプリに実際にあるもの）

- 立冬（11月7日）・小雪（11月22日）に記録した空玉は、詳細に節気の名前とひとこと（`SolarTerm.poem`）が出る。記録したときに「今日は立冬」などのお祝い表示（`OrbCelebrationView`）が出る。
- 満月の夜（11月24日。アプリの判定は21時基準）に夜の空玉を記録すると、玉の中にまるい月が映り、「満月の夜です」と出る。
- 日付は `SolarTerm.on`・`MoonPhase.on` で計算した（東京）。玉の見た目は節気の日も通常の玉と同じ（クリスタルは節目の玉だけ）なので、「見た目が変わる」とは書かない。

## 画像

- `event-card-1920x1080.png`（イベントカード 16:9）、`event-detail-1080x1920.png`（イベント詳細 9:16）。文字なし。
- 立冬の朝の玉と満月の夜の玉。どちらもアプリと同じ描画（`EventArtRenderTests.renderWinterOrbs`）。雪や雨は描いていない。

```
TEST_RUNNER_SORADAMA_RENDER_WINTER_ORBS=/path/orbs xcodebuild ... -only-testing:AuroraWeatherTests/EventArtRenderTests test
python3 scripts/compose_winter_event_art.py --orbs /path/orbs --winter-output AppStore/InAppEvents/winter-start-2026 --christmas-output AppStore/InAppEvents/christmas-2026
```

## イベントの設定（案）

- バッジ: スペシャルイベント、目的: 新規ユーザを獲得する、優先度: 通常、アプリ内購入: 必須ではない、配信: すべての国・地域
- 期間: 2026-11-07 0:00 〜 2026-11-25 23:30 JST。公開開始（予告）は 2026-10-24 0:00（開始の最大14日前）
- ディープリンク: `soradama://winter`（審査への追加に必須。アプリは通常どおり天気画面を開く）
- 2026-10-11 00:07 JST に審査へ提出（イベント ID 6821042134）。画像は `scripts/asc_event_images.py` で入れた。
- 提出の目安: 10月下旬（審査に1日前後かかる想定）

| 項目 | 上限 | 日本語 | English (U.S.) |
|---|---|---|---|
| イベント名 | 30 | 冬のはじまりの空玉（9） | Winter's First Sky Orbs (23) |
| 短い説明 | 50 | 立冬と小雪の日、満月の夜は、空玉が少し特別になります（26） | Seasonal days and a full moon, kept in orbs (43) |
| 長い説明 | 120 | 11月7日は立冬、22日は小雪。その日の空玉には、節気の名前とひとことが添えられます。24日の夜は満月で、夜の空玉にまるい月が映ります。（68） | Nov 7 and 22 are winter's seasonal days; that day's orb shows their name. Night orbs hold the Nov 24 full moon. (111) |

## プロモーション用テキスト（11月1日にハロウィンの文面から差し替える案。上限170文字、審査なし）

- 日本語: 11月7日は立冬、22日は小雪、24日の夜は満月。特別な日の空は、節気の名前やまるい月といっしょに空玉に残ります。
- English: Nov 7 and 22 are winter's seasonal days, and Nov 24 brings a full moon. On special days, your orb keeps the day's name or the moon.
