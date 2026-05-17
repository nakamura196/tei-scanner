#!/usr/bin/env python3
"""Set App Store Connect metadata for TEI Scanner.

What it does:
- Ensures ja and en appStoreVersionLocalizations exist for the latest
  editable version, populates description / keywords / promotional text /
  whatsNew / supportUrl / marketingUrl.
- Sets primary + secondary categories on the app info.
- Sets copyright on the version, content rights declaration on the app.
- Sets ja and en privacyPolicyUrl on appInfoLocalizations.
- Sets the age rating declaration to all-NONE / all-False.

Idempotent: running twice is safe; existing values are overwritten with
the values defined here.
"""
import sys

from _asc import APP_NAME, BUNDLE_ID, request


COPYRIGHT = "2026 Satoru Nakamura"
PRIMARY_CATEGORY = "PRODUCTIVITY"
SECONDARY_CATEGORY = "REFERENCE"
SUPPORT_URL = "https://github.com/nakamura196/tei-scanner"
MARKETING_URL = "https://github.com/nakamura196/tei-scanner"
PRIVACY_URL = "https://github.com/nakamura196/tei-scanner/blob/main/PRIVACY.md"
CONTENT_RIGHTS = "DOES_NOT_USE_THIRD_PARTY_CONTENT"

LOCALIZED = {
    "ja": {
        "description": (
            "スキャンしたページ画像のフォルダを Apple Vision の OCR にかけ、"
            "認識した行の位置情報を含む 1 つの TEI/XML ファイルを生成するデスクトップアプリです。\n\n"
            "・フォルダ単位で複数画像を一括処理\n"
            "・各行の認識テキストとバウンディングボックスを TEI の facsimile / surface / zone / pb / lb 要素として出力\n"
            "・画像プレビュー上に bbox を重ね、認識結果と原本を一目で比較\n"
            "・言語: 自動判別 / 英語 / 日本語 / 中国語 (簡体・繁体) / 韓国語 / 仏 / 独 / 西\n"
            "・拡大縮小・パン・行リストとの双方向ハイライト\n\n"
            "デジタル人文学・図書館情報学・歴史資料デジタル化の現場で、"
            "スキャン PNG が並ぶフォルダから TEI 翻刻の素地を作るのに使えます。\n\n"
            "本アプリは端末上ですべての処理が完結し、ネットワーク接続を必要としません。"
        ),
        "keywords": "TEI,OCR,XML,翻刻,デジタル人文学,Vision,テキスト,スキャン,facsimile",
        "promotionalText": (
            "フォルダの画像を一括 OCR、各行のバウンディングボックスを TEI/XML として保存。"
            "デジタル人文学の翻刻作業を始める前のひと手間を肩代わりします。"
        ),
        "whatsNew": (
            "・OCR 結果を「バンドル」(tei.xml + images フォルダ + index.html) として"
            "書き出す機能を追加しました。IIIF サーバを介さず TEI/IIIF エディタに"
            "直接読み込めます。\n"
            "・バンドル内の index.html は、ブラウザで tei.xml を表示して OCR テキストと"
            "ページ画像を照合できる確認用ビューです。"
        ),
        "supportUrl": SUPPORT_URL,
        "marketingUrl": MARKETING_URL,
    },
    "en-US": {
        "description": (
            "TEI Scanner runs Apple's Vision OCR over a folder of scanned page images "
            "and produces a single TEI/XML file with per-line bounding-box zones.\n\n"
            "- Batch OCR a folder of pages in one click\n"
            "- Outputs TEI/XML with facsimile / surface / zone / pb / lb elements for each recognised line\n"
            "- Side-by-side preview with bbox overlay for instant comparison\n"
            "- Languages: auto / English / Japanese / Chinese (Simplified & Traditional) / Korean / French / German / Spanish\n"
            "- Zoom, pan, and synced highlighting between the image and the line list\n\n"
            "A practical starting point for digital humanities and library / archive workflows "
            "that begin with a folder of scanned PNGs and end with TEI-encoded text.\n\n"
            "All processing runs on-device. The app does not require an internet connection."
        ),
        "keywords": "TEI,XML,OCR,Vision,digital humanities,transcription,scanning,facsimile,bounding box",
        "promotionalText": (
            "Batch OCR a folder of page images. Each line gets a bounding box, "
            "exported as TEI/XML — ready for downstream digital humanities work."
        ),
        "whatsNew": (
            "- Added Export Bundle: save the OCR result as a self-contained "
            "folder (tei.xml + an images folder + index.html) that opens "
            "directly in a TEI/IIIF editor — no IIIF server needed.\n"
            "- The bundle's index.html is a verification view that renders "
            "tei.xml in the browser, so you can check the OCR text against "
            "the page images."
        ),
        "supportUrl": SUPPORT_URL,
        "marketingUrl": MARKETING_URL,
    },
}


AGE_RATING_NONE = {
    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
    "contests": "NONE",
    "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "NONE",
    "horrorOrFearThemes": "NONE",
    "matureOrSuggestiveThemes": "NONE",
    "medicalOrTreatmentInformation": "NONE",
    "profanityOrCrudeHumor": "NONE",
    "sexualContentGraphicAndNudity": "NONE",
    "sexualContentOrNudity": "NONE",
    "violenceCartoonOrFantasy": "NONE",
    "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "gambling": False,
    "lootBox": False,
    "unrestrictedWebAccess": False,
    "messagingAndChat": False,
    "ageAssurance": False,
    "advertising": False,
    "parentalControls": False,
    "userGeneratedContent": False,
    "healthOrWellnessTopics": False,
}


def get_app_id():
    _, data = request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    items = data.get("data", [])
    if not items:
        raise SystemExit(f"App record for {BUNDLE_ID} not found in App Store Connect.")
    return items[0]["id"]


def get_editable_version_id(app_id):
    _, data = request("GET", f"apps/{app_id}/appStoreVersions?filter[platform]=MAC_OS")
    versions = data.get("data", [])
    editable = [v for v in versions
                if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                 "REJECTED", "METADATA_REJECTED")]
    if editable:
        v = editable[0]
        print(f"  editable version: {v['attributes']['versionString']} ({v['attributes']['appStoreState']})")
        return v["id"]
    if versions:
        v = versions[0]
        print(f"  using newest version: {v['attributes']['versionString']} ({v['attributes']['appStoreState']})")
        return v["id"]
    raise SystemExit("No version exists yet — wait for the uploaded build to finish processing, then create a version in App Store Connect.")


def get_app_info_id(app_id):
    _, data = request("GET", f"apps/{app_id}/appInfos")
    return data["data"][0]["id"]


def upsert_version_localizations(version_id, locales):
    _, data = request("GET", f"appStoreVersions/{version_id}/appStoreVersionLocalizations")
    existing = {loc["attributes"]["locale"]: loc["id"] for loc in data.get("data", [])}
    for locale, fields in locales.items():
        if locale in existing:
            loc_id = existing[locale]
            request("PATCH", f"appStoreVersionLocalizations/{loc_id}", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc_id,
                    "attributes": fields,
                }
            })
            print(f"  patched version localization: {locale}")
        else:
            try:
                _, data = request("POST", "appStoreVersionLocalizations", {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "attributes": {"locale": locale, **fields},
                        "relationships": {
                            "appStoreVersion": {
                                "data": {"type": "appStoreVersions", "id": version_id}
                            }
                        },
                    }
                })
                print(f"  created version localization: {locale} ({data['data']['id']})")
            except Exception:
                print(f"  [skip] could not create {locale} (likely app-name uniqueness; add manually via Web UI with a distinct name)")


def upsert_info_localizations(app_info_id):
    _, data = request("GET", f"appInfos/{app_info_id}/appInfoLocalizations")
    existing = {loc["attributes"]["locale"]: loc["id"] for loc in data.get("data", [])}
    for locale in ("ja", "en-US"):
        if locale not in existing:
            print(f"  (skipping {locale} info localization — not present; create via Web UI if needed)")
            continue
        loc_id = existing[locale]
        request("PATCH", f"appInfoLocalizations/{loc_id}", {
            "data": {
                "type": "appInfoLocalizations",
                "id": loc_id,
                "attributes": {"privacyPolicyUrl": PRIVACY_URL},
            }
        })
        print(f"  patched info localization: {locale} privacyPolicyUrl")


def set_categories(app_info_id):
    request("PATCH", f"appInfos/{app_info_id}", {
        "data": {
            "type": "appInfos",
            "id": app_info_id,
            "relationships": {
                "primaryCategory": {
                    "data": {"type": "appCategories", "id": PRIMARY_CATEGORY}
                },
                "secondaryCategory": {
                    "data": {"type": "appCategories", "id": SECONDARY_CATEGORY}
                },
            },
        }
    })
    print(f"  categories: {PRIMARY_CATEGORY} / {SECONDARY_CATEGORY}")


def set_copyright(version_id):
    request("PATCH", f"appStoreVersions/{version_id}", {
        "data": {
            "type": "appStoreVersions",
            "id": version_id,
            "attributes": {"copyright": COPYRIGHT},
        }
    })
    print(f"  copyright: {COPYRIGHT}")


def set_content_rights(app_id):
    request("PATCH", f"apps/{app_id}", {
        "data": {
            "type": "apps",
            "id": app_id,
            "attributes": {"contentRightsDeclaration": CONTENT_RIGHTS},
        }
    })
    print(f"  contentRightsDeclaration: {CONTENT_RIGHTS}")


def set_age_rating(app_info_id):
    # ageRatingDeclarations resource id matches the appInfo id.
    request("PATCH", f"ageRatingDeclarations/{app_info_id}", {
        "data": {
            "type": "ageRatingDeclarations",
            "id": app_info_id,
            "attributes": AGE_RATING_NONE,
        }
    })
    print("  age rating: 4+ (all NONE / all False)")


def main() -> int:
    print(f"App: {APP_NAME} ({BUNDLE_ID})")
    app_id = get_app_id()
    print(f"  app_id={app_id}")
    app_info_id = get_app_info_id(app_id)
    print(f"  app_info_id={app_info_id}")
    version_id = get_editable_version_id(app_id)
    print(f"  version_id={version_id}")
    print()

    print("[1/6] version localizations")
    upsert_version_localizations(version_id, LOCALIZED)
    print()

    print("[2/6] copyright")
    set_copyright(version_id)
    print()

    print("[3/6] categories")
    set_categories(app_info_id)
    print()

    print("[4/6] content rights")
    set_content_rights(app_id)
    print()

    print("[5/6] privacy URL on info localizations")
    upsert_info_localizations(app_info_id)
    print()

    print("[6/6] age rating")
    set_age_rating(app_info_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
