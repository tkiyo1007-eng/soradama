import json
import pathlib
import shutil
import sys
import tempfile
import unittest
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from tools import sync_translations as sync


FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures"
TRANSLATIONS = {
    "InternalName": "InternalName",
    "そらだま": "Soradama",
    "現在地の天気を表示するために位置情報を使用します。":
        "Your location is used to show the weather where you are.",
    "こんにちは": "Hello",
}


class SyncTranslationsTests(unittest.TestCase):
    def make_root(
        self,
        info_fixture: str = "legacy_info_catalog.xcstrings",
    ) -> tuple[pathlib.Path, pathlib.Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        app = root / "App"
        app.mkdir()
        shutil.copyfile(
            FIXTURES / info_fixture,
            app / "InfoPlist.xcstrings",
        )
        shutil.copyfile(
            FIXTURES / "regular_catalog.xcstrings",
            app / "Localizable.xcstrings",
        )
        return root, FIXTURES / "mixed_catalogs.xliff"

    def read_json(self, path: pathlib.Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))

    def test_info_plist_uses_canonical_ids_and_removes_legacy_keys(self):
        root, xliff = self.make_root()
        info_path = root / "App" / "InfoPlist.xcstrings"
        old_inode = info_path.stat().st_ino

        counts = sync.sync_catalogs(root, xliff, TRANSLATIONS)

        self.assertEqual(counts["App/InfoPlist.xcstrings"], 3)
        catalog = self.read_json(info_path)
        self.assertEqual(
            set(catalog["strings"]),
            {
                "CFBundleDisplayName",
                "CFBundleName",
                "NSLocationWhenInUseUsageDescription",
                "obsolete",
            },
        )
        self.assertNotEqual(info_path.stat().st_ino, old_inode)
        self.assertEqual(catalog["fixtureMetadata"], {"owner": "tests"})

        display_name = catalog["strings"]["CFBundleDisplayName"]
        self.assertEqual(display_name["comment"], "既存コメントを保持")
        self.assertEqual(
            display_name["localizations"]["ja"]["stringUnit"]["value"],
            "そらだま",
        )
        self.assertEqual(
            display_name["localizations"]["en"]["stringUnit"]["value"],
            "Soradama",
        )
        self.assertIn("variations", display_name["localizations"]["fr"])

        bundle_name = catalog["strings"]["CFBundleName"]["localizations"]
        self.assertEqual(bundle_name["ja"]["stringUnit"]["value"], "InternalName")
        self.assertEqual(bundle_name["en"]["stringUnit"]["value"], "InternalName")

    def test_regular_catalog_still_uses_source_and_preserves_metadata(self):
        root, xliff = self.make_root()
        sync.sync_catalogs(root, xliff, TRANSLATIONS)

        catalog = self.read_json(root / "App" / "Localizable.xcstrings")
        self.assertEqual(
            set(catalog["strings"]),
            {"こんにちは", "obsolete", "manual-only"},
        )
        entry = catalog["strings"]["こんにちは"]
        self.assertEqual(entry["comment"], "既存の通常カタログコメント")
        self.assertEqual(entry["extractionState"], "manual")
        self.assertIn("variations", entry["localizations"]["fr"])
        english = entry["localizations"]["en"]["stringUnit"]
        self.assertEqual(english["value"], "Hello")
        self.assertEqual(english["state"], "translated")
        self.assertEqual(english["reviewer"], "keep")
        manual_only = catalog["strings"]["manual-only"]
        self.assertEqual(manual_only["comment"], "XLIFFに無いentryも保持")
        self.assertIn("variations", manual_only["localizations"]["de"])

    def test_coexisting_canonical_and_legacy_entries_are_deep_merged(self):
        root, xliff = self.make_root("coexisting_info_catalog.xcstrings")

        sync.sync_catalogs(root, xliff, TRANSLATIONS)

        catalog = self.read_json(root / "App" / "InfoPlist.xcstrings")
        self.assertNotIn("そらだま", catalog["strings"])
        display_name = catalog["strings"]["CFBundleDisplayName"]
        self.assertEqual(display_name["comment"], "legacy comment")
        self.assertEqual(display_name["extractionState"], "manual")
        self.assertEqual(display_name["legacyMetadata"], {"owner": "legacy"})
        self.assertEqual(
            display_name["localizations"]["en"]["stringUnit"]["reviewer"],
            "canonical",
        )
        self.assertIn("variations", display_name["localizations"]["fr"])

    def test_coexisting_entry_conflict_stops_before_any_write(self):
        root, xliff = self.make_root("coexisting_info_catalog.xcstrings")
        info_path = root / "App" / "InfoPlist.xcstrings"
        catalog = self.read_json(info_path)
        catalog["strings"]["CFBundleDisplayName"]["comment"] = "canonical conflict"
        info_path.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        paths = [info_path, root / "App" / "Localizable.xcstrings"]
        before = {path: path.read_bytes() for path in paths}

        with self.assertRaisesRegex(
            sync.SyncError,
            r"canonical/legacy entry.*comment",
        ):
            sync.sync_catalogs(root, xliff, TRANSLATIONS)

        self.assertEqual({path: path.read_bytes() for path in paths}, before)
        self.assertEqual(list((root / "App").glob(".*.tmp")), [])
        self.assertEqual(list((root / "App").glob(".*.bak")), [])

    def test_missing_translation_leaves_every_catalog_unchanged(self):
        root, xliff = self.make_root()
        paths = [
            root / "App" / "InfoPlist.xcstrings",
            root / "App" / "Localizable.xcstrings",
        ]
        before = {path: path.read_bytes() for path in paths}
        incomplete = dict(TRANSLATIONS)
        incomplete.pop("現在地の天気を表示するために位置情報を使用します。")

        with self.assertRaises(sync.SyncError):
            sync.sync_catalogs(root, xliff, incomplete)

        self.assertEqual({path: path.read_bytes() for path in paths}, before)
        self.assertEqual(list((root / "App").glob(".*.tmp")), [])

    def test_check_only_validates_without_writing(self):
        root, xliff = self.make_root()
        paths = [
            root / "App" / "InfoPlist.xcstrings",
            root / "App" / "Localizable.xcstrings",
        ]
        before = {path: path.read_bytes() for path in paths}

        counts = sync.sync_catalogs(
            root,
            xliff,
            TRANSLATIONS,
            check_only=True,
        )

        self.assertEqual(counts["App/InfoPlist.xcstrings"], 3)
        self.assertEqual({path: path.read_bytes() for path in paths}, before)

    def test_replace_failure_rolls_back_every_catalog(self):
        root, xliff = self.make_root()
        paths = [
            root / "App" / "InfoPlist.xcstrings",
            root / "App" / "Localizable.xcstrings",
        ]
        before = {path: path.read_bytes() for path in paths}
        real_replace = sync.os.replace
        replacement_count = 0

        def fail_second_replacement(source, destination):
            nonlocal replacement_count
            if pathlib.Path(source).suffix == ".tmp":
                replacement_count += 1
                if replacement_count == 2:
                    raise OSError("simulated replacement failure")
            return real_replace(source, destination)

        with mock.patch.object(sync.os, "replace", side_effect=fail_second_replacement):
            with self.assertRaises(sync.SyncError):
                sync.sync_catalogs(root, xliff, TRANSLATIONS)

        self.assertEqual(replacement_count, 2)
        self.assertEqual({path: path.read_bytes() for path in paths}, before)
        self.assertEqual(list((root / "App").glob(".*.tmp")), [])
        self.assertEqual(list((root / "App").glob(".*.bak")), [])
    def test_rollback_failure_preserves_recovery_backup(self):
        root, xliff = self.make_root()
        info_path = root / "App" / "InfoPlist.xcstrings"
        regular_path = root / "App" / "Localizable.xcstrings"
        before = {
            info_path: info_path.read_bytes(),
            regular_path: regular_path.read_bytes(),
        }
        real_replace = sync.os.replace
        replacement_count = 0

        def fail_replacement_and_rollback(source, destination):
            nonlocal replacement_count
            source_path = pathlib.Path(source)
            if source_path.suffix == ".tmp":
                replacement_count += 1
                if replacement_count == 2:
                    raise OSError("simulated replacement failure")
            if source_path.suffix == ".bak":
                raise OSError("simulated rollback failure")
            return real_replace(source, destination)

        with mock.patch.object(
            sync.os,
            "replace",
            side_effect=fail_replacement_and_rollback,
        ):
            with self.assertRaisesRegex(
                sync.SyncError,
                r"復旧用backupを保持",
            ):
                sync.sync_catalogs(root, xliff, TRANSLATIONS)

        backups = list((root / "App").glob(".*.bak"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), before[info_path])
        self.assertNotEqual(info_path.read_bytes(), before[info_path])
        self.assertEqual(regular_path.read_bytes(), before[regular_path])
        self.assertEqual(list((root / "App").glob(".*.tmp")), [])


    def test_second_sync_is_byte_identical(self):
        root, xliff = self.make_root("coexisting_info_catalog.xcstrings")
        paths = [
            root / "App" / "InfoPlist.xcstrings",
            root / "App" / "Localizable.xcstrings",
        ]

        sync.sync_catalogs(root, xliff, TRANSLATIONS)
        after_first = {path: path.read_bytes() for path in paths}
        sync.sync_catalogs(root, xliff, TRANSLATIONS)

        self.assertEqual({path: path.read_bytes() for path in paths}, after_first)

    def test_translation_fallback_uses_explicit_japanese_value(self):
        root, _ = self.make_root()
        # canonical fixtureを作るため、一度同期してja/enを明示する。
        sync.sync_catalogs(root, FIXTURES / "mixed_catalogs.xliff", TRANSLATIONS)

        recovered = sync.load_translations(root)

        self.assertEqual(recovered["そらだま"], "Soradama")
        self.assertEqual(
            recovered["現在地の天気を表示するために位置情報を使用します。"],
            "Your location is used to show the weather where you are.",
        )


if __name__ == "__main__":
    unittest.main()
