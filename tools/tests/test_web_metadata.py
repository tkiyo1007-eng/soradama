from __future__ import annotations

import json
import pathlib
import re
import unittest
from html.parser import HTMLParser


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_URL = "https://tkiyo1007-eng.github.io/soradama/"
APP_STORE_URL = "https://apps.apple.com/app/id6788443049"
APP_ID = "6788443049"
IMAGE_URL = f"{BASE_URL}assets/icon.png"

PAGES = {
    "index.html": {
        "language": "ja",
        "canonical": BASE_URL,
        "alternate_locale": "en_US",
        "locale": "ja_JP",
        "name": "空玉（そらだま）",
        "alternate_name": "Soradama",
        "image_alt": "空玉（そらだま）のアプリアイコン",
        "currency": "JPY",
    },
    "en.html": {
        "language": "en",
        "canonical": f"{BASE_URL}en.html",
        "alternate_locale": "ja_JP",
        "locale": "en_US",
        "name": "Soradama",
        "alternate_name": "空玉（そらだま）",
        "image_alt": "Soradama app icon",
        "currency": "USD",
    },
}

EXPECTED_ALTERNATES = {
    "ja": BASE_URL,
    "en": f"{BASE_URL}en.html",
    "x-default": f"{BASE_URL}en.html",
}

PRIVACY_PAGES = {
    "privacy.html": f"{BASE_URL}privacy.html",
    "privacy-en.html": f"{BASE_URL}privacy-en.html",
}


class HeadMetadataParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta: dict[str, str] = {}
        self.links: list[dict[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]):
        attributes = {key: value or "" for key, value in attrs}
        if tag == "meta":
            key = attributes.get("property") or attributes.get("name")
            if key:
                self.meta[key] = attributes.get("content", "")
        elif tag == "link":
            self.links.append(attributes)


def load_page(filename: str) -> tuple[str, HeadMetadataParser, dict]:
    html = (REPO_ROOT / filename).read_text(encoding="utf-8")
    parser = HeadMetadataParser()
    parser.feed(html)

    json_ld_blocks = re.findall(
        r'<script\s+type="application/ld\+json">\s*(.*?)\s*</script>',
        html,
        flags=re.DOTALL,
    )
    software_apps = []
    for block in json_ld_blocks:
        value = json.loads(block)
        entries = value.get("@graph", []) if isinstance(value, dict) and "@graph" in value else [value]
        software_apps.extend(
            entry for entry in entries
            if isinstance(entry, dict) and entry.get("@type") == "SoftwareApplication"
        )
    if len(software_apps) != 1:
        raise AssertionError(
            f"{filename}: expected one SoftwareApplication JSON-LD block, "
            f"found {len(software_apps)}"
        )
    return html, parser, software_apps[0]


def links_with_rel(parser: HeadMetadataParser, rel: str) -> list[dict[str, str]]:
    return [
        link for link in parser.links
        if rel in link.get("rel", "").split()
    ]


class WebMetadataTests(unittest.TestCase):
    def test_canonical_alternates_and_smart_app_banner(self):
        for filename, expected in PAGES.items():
            with self.subTest(page=filename):
                _, parser, _ = load_page(filename)
                canonical_links = links_with_rel(parser, "canonical")
                self.assertEqual(len(canonical_links), 1)
                self.assertEqual(canonical_links[0].get("href"), expected["canonical"])
                self.assertEqual(
                    parser.meta.get("apple-itunes-app"),
                    f"app-id={APP_ID}",
                )

                alternates = {
                    link.get("hreflang"): link.get("href")
                    for link in links_with_rel(parser, "alternate")
                }
                self.assertEqual(alternates, EXPECTED_ALTERNATES)

    def test_open_graph_and_twitter_metadata_are_complete_and_localized(self):
        for filename, expected in PAGES.items():
            with self.subTest(page=filename):
                _, parser, _ = load_page(filename)
                meta = parser.meta
                self.assertEqual(meta.get("og:type"), "website")
                self.assertEqual(meta.get("og:url"), expected["canonical"])
                self.assertEqual(meta.get("og:locale"), expected["locale"])
                self.assertEqual(meta.get("og:locale:alternate"), expected["alternate_locale"])
                self.assertEqual(meta.get("og:site_name"), expected["name"])
                self.assertEqual(meta.get("og:title"), expected["name"])
                self.assertTrue(meta.get("og:description"))
                self.assertEqual(meta.get("og:image"), IMAGE_URL)
                self.assertEqual(meta.get("og:image:type"), "image/png")
                self.assertEqual(meta.get("og:image:width"), "512")
                self.assertEqual(meta.get("og:image:height"), "512")
                self.assertEqual(meta.get("og:image:alt"), expected["image_alt"])

                # The current acquisition asset is a square app icon, so use the
                # square-card format instead of asking social clients to crop it wide.
                self.assertEqual(meta.get("twitter:card"), "summary")
                self.assertEqual(meta.get("twitter:title"), meta.get("og:title"))
                self.assertEqual(meta.get("twitter:description"), meta.get("og:description"))
                self.assertEqual(meta.get("twitter:image"), meta.get("og:image"))
                self.assertEqual(meta.get("twitter:image:alt"), meta.get("og:image:alt"))

    def test_software_application_json_ld_is_localized_and_consistent(self):
        for filename, expected in PAGES.items():
            with self.subTest(page=filename):
                _, parser, app = load_page(filename)
                self.assertEqual(app.get("@context"), "https://schema.org")
                self.assertEqual(app.get("name"), expected["name"])
                self.assertEqual(app.get("alternateName"), expected["alternate_name"])
                self.assertEqual(app.get("inLanguage"), expected["language"])
                self.assertEqual(app.get("url"), expected["canonical"])
                self.assertEqual(app.get("downloadUrl"), APP_STORE_URL)
                self.assertEqual(app.get("image"), IMAGE_URL)
                self.assertEqual(app.get("applicationCategory"), "WeatherApplication")
                self.assertEqual(app.get("operatingSystem"), "iOS, watchOS")
                self.assertIs(app.get("isAccessibleForFree"), True)
                self.assertEqual(app.get("description"), parser.meta.get("description"))
                self.assertEqual(
                    app.get("offers"),
                    {
                        "@type": "Offer",
                        "price": "0",
                        "priceCurrency": expected["currency"],
                    },
                )

    def test_every_app_store_url_uses_the_public_app_id(self):
        url_pattern = re.compile(r"https://apps\.apple\.com/[A-Za-z0-9_?&=./%-]+")
        for filename in PAGES:
            with self.subTest(page=filename):
                html, _, _ = load_page(filename)
                urls = url_pattern.findall(html)
                self.assertGreaterEqual(len(urls), 4)
                self.assertEqual(set(urls), {APP_STORE_URL})

    def test_english_page_uses_english_screenshot_assets(self):
        html, _, _ = load_page("en.html")
        sources = re.findall(r'<figure class="shot reveal"><img src="([^"]+)"', html)
        self.assertEqual(sources, [f"assets/en/shot{index}.jpg" for index in range(1, 5)])
        for source in sources:
            self.assertTrue((REPO_ROOT / source).is_file(), source)

    def test_english_copy_names_solar_terms_accurately(self):
        html, _, _ = load_page("en.html")
        self.assertIn("24 traditional Japanese solar terms", html)
        self.assertNotIn("24 traditional Japanese seasons", html)

    def test_privacy_pages_are_canonical_and_do_not_contradict_weather_requests(self):
        expected_alternates = {
            "ja": f"{BASE_URL}privacy.html",
            "en": f"{BASE_URL}privacy-en.html",
            "x-default": f"{BASE_URL}privacy-en.html",
        }
        forbidden_claims = {
            "privacy.html": "個人情報を収集・保存・送信しません",
            "privacy-en.html": "not collect, store, or transmit any personal information",
        }

        for filename, canonical in PRIVACY_PAGES.items():
            with self.subTest(page=filename):
                html = (REPO_ROOT / filename).read_text(encoding="utf-8")
                parser = HeadMetadataParser()
                parser.feed(html)
                canonical_links = links_with_rel(parser, "canonical")
                self.assertEqual(len(canonical_links), 1)
                self.assertEqual(canonical_links[0].get("href"), canonical)
                alternates = {
                    link.get("hreflang"): link.get("href")
                    for link in links_with_rel(parser, "alternate")
                }
                self.assertEqual(alternates, expected_alternates)
                self.assertNotIn(forbidden_claims[filename], html)
                self.assertIn("Open-Meteo", html)
                if filename.endswith("-en.html"):
                    self.assertIn("latitude", html)
                    self.assertIn("WatchConnectivity", html)
                else:
                    self.assertIn("緯度", html)
                    self.assertIn("WatchConnectivity", html)


if __name__ == "__main__":
    unittest.main()
