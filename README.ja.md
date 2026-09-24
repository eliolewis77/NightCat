# NightCat

[English](README.md) | [中文](README.zh-CN.md) | **日本語**

macOS メニューバーのスリープ防止ツール。4段階のモードを搭載 — 汎用の電源管理ツールではありません。

| モード | 動作 |
|---|---|
| **オフ** | すべて通常どおり |
| **画面常時点灯** | 画面がスリープしない — プレゼン、相場のチェック |
| **アイドルスリープ防止** | システムはスリープせず、画面はスリープ可 — ダウンロード、バッチ処理、長時間タスク |
| **クラムシェル稼働** | 蓋を閉じても稼働し続ける — 無人運用、リモートアクセス |

安全装置：タイマー自動オフ、モードロック + 確認ダイアログ、電源接続時のみ有効化、低バッテリーしきい値、バッテリー警告、外部からの制御検出、終了時に状態を復元、ハング防止の Helper ウォッチドッグ。過熱時ポリシーは3つから選択：**自動一時停止 / 通知のみ / 無視**。オプションの「起動時にクラムシェルモードを復元」— 再起動後もリモートから到達可能なままに。

オプションの「ネットワークキープアライブ」：タイマーでゲートウェイに ping を送り、アイドルによるリンク切断を防止。切断・IP 変更イベントは `~/Library/Logs/NightCat/network.log` に自動記録され、リモート接続の障害を後から追跡できます。

中国語・英語のバイリンガル対応（システム設定に追従、切替可能）、システム通知、モードごとに色が変わる猫のメニューバーアイコン、Sparkle による自動アップデート。

<p align="center">
  <img src="panel.png" width="420" alt="NightCat menu bar panel">
</p>

## ダウンロード

💛 開発を支援：NightCat が役に立ったら、Gumroad で有料サポート（$4.99 買い切り、永久アップデート）— あなたの支援はそのまま新機能の開発に充てられます。GitHub 版は永遠に無料・オープンソースです。

[Releases](https://github.com/eliolewis77/NightCat/releases/latest) から DMG をダウンロード
（公証 + EdDSA 署名済み）。インストール済みのユーザーは「設定 → 情報 → アップデートを確認」で自動アップグレードされます。

## ビルド

```bash
brew install xcodegen        # Xcode 15+
xcodegen generate
xcodebuild build -scheme NightCat -destination 'platform=macOS' -configuration Debug
```

テスト：`xcodebuild test -scheme NightCat-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

> 実行には開発者署名が必要です — 特権 Helper が App のコード署名を検証します。詳細は [`AGENTS.md`](AGENTS.md)。

## アーキテクチャ

```
NightCat.app（SwiftUI MenuBarExtra、LSUIElement、非サンドボックス）
   │ XPC（Mach service = <bundle id>.helper）
   ▼
NightCatHelper（root LaunchDaemon、SMAppService で登録）
   │ pmset -a disablesleep · 90秒ハートビートウォッチドッグ
   ▼
IOPMrootDomain SleepDisabled
```

- **App**：すべてのステートマシンと UI。`Sources/NightCat`
- **Helper**：意図的に薄く、フラグ設定とハートビートの送受信のみ。`Sources/Helper`
- **Shared**：純粋なロジック（安全性評価、状態照合、タイマー）、約1300行をユニットテストでカバー。`Sources/Shared`

## 出典とライセンス

[nghialuong/Lidless](https://github.com/nghialuong/Lidless) v0.1.3（MIT）からフォーク。
アップストリームの著作権は [`LICENSE`](LICENSE) を参照。改変部分はこのリポジトリの所有者に帰属します。
自動アップデートフィード：https://eliolewis77.github.io/NightCat/appcast.xml
