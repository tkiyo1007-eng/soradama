# アプリ内イベント「ハロウィンの空玉」（2026年10月）

App Store のアプリ内イベントは、App Store の検索結果・アプリのページ・Today タブなどに表示され、新しい利用者に見つけてもらうきっかけになる。アプリ内の2026年ハロウィン表示（1.8.3〜1.8.4、2026-10-01〜10-31）に合わせて作る。

## 画像

- `event-card-1920x1080.png`（イベントカード 16:9）
- `event-detail-1080x1920.png`（イベント詳細 9:16）
- 文字は入れていない（App Store 側がイベント名などを重ねて表示するため）。
- 作り方: `EventArtRenderTests` でアプリと同じ描画の空玉（`orb-render.png`、背景透明）を書き出し、`scripts/compose_halloween_event_art.py` で空・月・こうもりと合成する。

```
TEST_RUNNER_SORADAMA_RENDER_EVENT_ORB=/path/orb-render.png xcodebuild ... -only-testing:AuroraWeatherTests/EventArtRenderTests test
python3 scripts/compose_halloween_event_art.py --orb AppStore/InAppEvents/halloween-2026/orb-render.png --output AppStore/InAppEvents/halloween-2026
```

## イベントの設定（案）

- 種類（バッジ）: 特別なイベント（Special Event）
- 目的: 新しいユーザーの獲得（すべてのユーザーに適したイベント）
- 期間: 承認後すぐ開始 〜 2026-10-31 23:59 JST
- 地域: すべて（アプリの配信地域と同じ）
- ディープリンク: なし（アプリを開くとハロウィン表示が出るため）

| 項目 | 文字数の上限 | 日本語 | English (U.S.) |
|---|---|---|---|
| イベント名 | 30 | ハロウィンの空玉 | Halloween Sky Orbs |
| 短い説明 | 50 | 10月だけ、空玉がハロウィン仕様に。月とこうもりの空も | Your daily sky orb dresses up for Halloween |
| 長い説明 | 120 | 10月31日まで、天気画面に月とこうもりが現れ、今日の空玉にジャックオランタンが付きます。毎日の空を集めて、ハロウィンの空玉を残しましょう。 | Until Oct 31, a moon and bats fill the sky and today's orb gets a jack-o'-lantern. Collect one every day. |

## プロモーション用テキスト（審査なしで変更できる。上限170文字）

- 日本語: 10月31日まで、ハロウィン仕様の空玉を集めよう。月とこうもりが浮かぶ空で、今日の空玉にジャックオランタンが付きます。
- English: Through October 31, collect Halloween sky orbs: a moon and bats fill your sky, and today's orb gets a jack-o'-lantern.
- 11月1日以降は、元の文面に戻すか、季節に合わせた文面に差し替える。
