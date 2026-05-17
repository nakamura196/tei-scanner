# TEI Scanner

スキャンした版面画像のフォルダを Apple Vision OCR にかけ、各行のバウンディングボックスを `<facsimile>` / `<zone>` として保持した 1 つの TEI/XML を生成する macOS デスクトップアプリです。

A macOS desktop app that runs Apple Vision OCR over a folder of page images and emits a single TEI/XML document with per-line `<facsimile>` / `<zone>` zones.

## スクリーンショット / Screenshots

| 起動直後 / Empty state | フォルダ読込後 / Folder loaded |
|---|---|
| ![Empty state](docs/screenshots/01-empty.png) | ![Folder loaded](docs/screenshots/02-loaded.png) |

| OCR 完了 / OCR done | TEI/XML 表示 / TEI/XML view |
|---|---|
| ![OCR done](docs/screenshots/03-ocr-done.png) | ![TEI/XML](docs/screenshots/04-xml.png) |

スクリーンショットは `scripts/capture_screenshots.sh` で自動生成しています。
Screenshots are generated automatically by `scripts/capture_screenshots.sh`.

## ダウンロード / Download

[Releases](../../releases) から最新の `.dmg` を取得し、ダブルクリックでマウント → `TEIScanner.app` を `/Applications` にドラッグしてください。

Get the latest `.dmg` from [Releases](../../releases). Double-click to mount, then drag `TEIScanner.app` into `/Applications`.

> Apple による Notarization 済みのため、初回起動で「開発元未確認」警告は出ません。  
> Notarized by Apple — no "unidentified developer" prompt on first launch.

## 機能 / Features

- フォルダ単位で複数画像を一括 OCR / Batch OCR over a folder of images
- 認識した行を bbox オーバーレイと連動するテキスト一覧として並列表示 / Side-by-side image preview with bbox overlay and a synced line list
- 拡大縮小・パン / Zoom and pan in the image preview
- 1 ページ = 1 `<surface>`、1 行 = 1 `<zone>` + `<lb corresp="#…">` の TEI/XML 出力 / TEI/XML output: one `<surface>` per page, one `<zone>` + `<lb>` per line
- 言語切り替え：自動判別 / English / 日本語 / 中文 / 한국어 / Français / Deutsch / Español / Language picker covering the same set
- UI ローカライズ：日本語（既定）/ 英語 / Bilingual UI (Japanese default / English)

## ビルド / Build

```bash
brew install xcodegen
git clone https://github.com/nakamura196/tei-scanner.git
cd tei-scanner
xcodegen generate
open TEIScanner.xcodeproj
```

開発時は `swift run` でも軽量に立ち上がります（ローカライズは Xcode ビルド時のみ反映されます）。

For lightweight iteration, `swift run` works as well. Note that localized strings are only bundled when building via Xcode.

## 配布 / Release pipeline

リリースは `project.yml` の `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を上げてコミットしてから、以下のスクリプトで実行します。GitHub と Mac App Store でバージョン番号は共通です。

Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` and commit, then run the scripts below. The GitHub and Mac App Store releases share one version number.

```bash
# GitHub リリース / GitHub release
#   アーカイブ → 公証済み .dmg → タグ v<version> → リリース公開
#   archive → notarized .dmg → tag v<version> → publish the release
scripts/release.sh

# Mac App Store
#   アーカイブ → .pkg アップロード → 処理待ち → メタデータ → ビルド添付 → 審査
#   archive → upload .pkg → wait for processing → metadata → attach build → review
scripts/release-appstore.sh              # 審査提出の手前まで / stage only, do not submit
scripts/release-appstore.sh --submit     # 審査提出まで / also submit for review
scripts/release-appstore.sh --skip-build # ビルドが既にアップロード済みのとき再開 / resume after upload
```

署名・公証には配布証明書（`Developer ID Application` / `Apple Distribution`）が必要です。App Store Connect API キー・Bundle ID・Team ID 等は `.env` に記載します（`.env.example` 参照）。低レベルの構成要素として `scripts/archive.sh --devid` / `--appstore` も利用できます。App Privacy（プライバシー申告）は API 非対応のため、App Store Connect の Web UI で一度だけ設定します。

Signing and notarization need distribution certificates (`Developer ID Application` / `Apple Distribution`). The App Store Connect API key, Bundle ID, Team ID, etc. go in `.env` (see `.env.example`). The lower-level building blocks `scripts/archive.sh --devid` / `--appstore` are still available. App Privacy declarations are not covered by the API — set them once in the App Store Connect web UI.

## ライセンス / License

MIT License. See [LICENSE](LICENSE).
