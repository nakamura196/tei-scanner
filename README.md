# TEI Scanner

macOS の Vision フレームワークで OCR をかけて、フォルダ内の複数画像から 1 つの TEI/XML を生成するデスクトップアプリ。
A macOS desktop app that runs Apple Vision OCR over a folder of page images and emits a single TEI/XML file with `<facsimile>` zones.

## ダウンロード / Download

[Releases](../../releases) から最新の `.dmg` を取得してください。 ダブルクリックでマウント → `TEIScanner.app` を Applications にドラッグ。
Get the latest `.dmg` from [Releases](../../releases). Double-click to mount and drag `TEIScanner.app` to Applications.

> Apple による Notarization 済みなので、初回起動時に「開発元未確認」警告は出ません。
> Notarized by Apple — no "unidentified developer" warning on first launch.

## 機能 / Features

- フォルダ単位で複数画像を一括 OCR / Batch OCR over a folder of images
- bbox オーバーレイと行リストの並列ビュー / Side-by-side image preview with bbox overlay and recognized-line list
- 拡大縮小・パン / Zoom & pan in the image preview
- TEI/XML 出力：1 ページ = 1 `<surface>`、1 行 = 1 `<zone>` + `<ab facs="#…">` / TEI/XML output with one `<surface>` per page and one `<zone>` + `<ab>` per line
- 言語切り替え：自動検出 / 英語 / 日本語 / 中文 / 한국어 / 仏 / 独 / 西 / Language picker: auto / English / Japanese / Chinese / Korean / French / German / Spanish

## ビルド / Build

```bash
brew install xcodegen
git clone https://github.com/nakamura196/tei-scanner.git
cd tei-scanner
xcodegen generate
open TEIScanner.xcodeproj
```

開発用に `swift run` でも起動できます。
For development, `swift run` works too.

## 配布 / Release pipeline

```bash
# Developer ID + notarized .dmg
scripts/archive.sh --devid

# Mac App Store .pkg
scripts/archive.sh --appstore
```

`.env` に App Store Connect API キー、Bundle ID、Team ID 等を記載（`.env.example` 参照）。
See `.env.example` for required environment variables.

## ライセンス / License

MIT License. See [LICENSE](LICENSE).
