#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""英訳を String Catalog に安全に流し込む。

使い方:
    # 1. 文字列を抽出
    xcodebuild -exportLocalizations -project AuroraWeather.xcodeproj \
      -localizationPath /tmp/l10n -exportLanguage en
    # 2. 未訳を確認（訳を足す先は tools/translations_en.py）
    python3 tools/sync_translations.py --check
    # 3. 流し込み
    python3 tools/sync_translations.py

InfoPlist.xcstrings は通常の Localizable.xcstrings と異なり、XLIFF の
trans-unit id（CFBundleDisplayName など）がカタログのキーになる。
source は日本語の値であり、翻訳表を引くためにだけ使う。

書き込みは「全XLIFF・全カタログを検証 → 全出力を一時ファイルへ作成 →
os.replace」の順に行う。未訳や不正な入力が1件でもあれば元ファイルを変更しない。
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import pathlib
import re
import stat
import sys
import tempfile
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parent.parent
XLIFF_DEFAULT = pathlib.Path("/tmp/l10n/en.xcloc/Localized Contents/en.xliff")
NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


class SyncError(Exception):
    """入力が安全に同期できないことを表す。"""


def load_translations(root: pathlib.Path = ROOT) -> dict[str, str]:
    """訳の辞書を得る。無ければ既存の .xcstrings から復元する。"""
    table = root / "tools" / "translations_en.py"
    if table.exists():
        namespace: dict[str, object] = {}
        source = table.read_text(encoding="utf-8")
        exec(compile(source, str(table), "exec"), namespace)
        translations = namespace.get("T")
        if not isinstance(translations, dict):
            raise SyncError(f"翻訳表 T が辞書ではありません: {table}")
        return translations

    translations: dict[str, str] = {}
    for path in root.rglob("*.xcstrings"):
        if "build" in path.parts:
            continue
        try:
            catalog = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise SyncError(f"String Catalogを読めません: {path}: {error}") from error
        for key, entry in catalog.get("strings", {}).items():
            localizations = entry.get("localizations", {})
            english = (
                localizations.get("en", {})
                .get("stringUnit", {})
                .get("value")
            )
            if not english:
                continue
            japanese = (
                localizations.get("ja", {})
                .get("stringUnit", {})
                .get("value")
            )
            if japanese:
                translations.setdefault(japanese, english)
            translations.setdefault(key, english)
    return translations


def lookup(translations: dict[str, str], key: str) -> str | None:
    """位置指定子の有無が揺れるXLIFFでも同じ訳を引く。"""
    if key in translations:
        return translations[key]

    counter = [0]

    def add_position(match: re.Match[str]) -> str:
        counter[0] += 1
        return "%%%d$%s" % (counter[0], match.group(1))

    positional = re.sub(r"%(@|lld|d|f)", add_position, key)
    if positional in translations:
        return re.sub(r"%(\d+)\$", "%", translations[positional])
    return None


def is_info_plist_catalog(original: str) -> bool:
    return pathlib.PurePosixPath(original).name.endswith("InfoPlist.xcstrings")


def safe_target(root: pathlib.Path, original: str) -> pathlib.Path:
    root = root.resolve()
    target = (root / pathlib.PurePosixPath(original)).resolve()
    try:
        target.relative_to(root)
    except ValueError as error:
        raise SyncError(f"リポジトリ外の出力先は使えません: {original}") from error
    return target


def read_catalog(path: pathlib.Path) -> dict[str, object]:
    if not path.exists():
        return {"sourceLanguage": "ja", "strings": {}, "version": "1.0"}
    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SyncError(f"String Catalogを読めません: {path}: {error}") from error
    if not isinstance(catalog, dict):
        raise SyncError(f"String Catalogのルートが辞書ではありません: {path}")
    strings = catalog.get("strings", {})
    if not isinstance(strings, dict):
        raise SyncError(f"String Catalogの strings が辞書ではありません: {path}")
    return catalog


def unit_text(unit: ET.Element, element_name: str) -> str | None:
    element = unit.find(f"x:{element_name}", NS)
    if element is None or element.text is None:
        return None
    return element.text


def merge_string_unit(entry: dict[str, object], locale: str, value: str) -> None:
    localizations = entry.setdefault("localizations", {})
    if not isinstance(localizations, dict):
        raise SyncError("entry.localizations が辞書ではありません")

    localization = localizations.setdefault(locale, {})
    if not isinstance(localization, dict):
        raise SyncError(f"entry.localizations.{locale} が辞書ではありません")
    if "variations" in localization and "stringUnit" not in localization:
        raise SyncError(
            f"{locale} のvariationsを単一翻訳で安全に置換できません"
        )

    string_unit = localization.setdefault("stringUnit", {})
    if not isinstance(string_unit, dict):
        raise SyncError(
            f"entry.localizations.{locale}.stringUnit が辞書ではありません"
        )
    string_unit["state"] = "translated"
    string_unit["value"] = value


def deep_merge_entries(
    canonical: dict[str, object],
    legacy: dict[str, object],
    *,
    context: str,
    path: tuple[str, ...] = (),
) -> None:
    """legacyにだけある値をcanonicalへ移し、異値の競合は拒否する。"""
    for field, legacy_value in legacy.items():
        field_path = path + (field,)
        if field not in canonical:
            canonical[field] = copy.deepcopy(legacy_value)
            continue

        canonical_value = canonical[field]
        if isinstance(canonical_value, dict) and isinstance(legacy_value, dict):
            deep_merge_entries(
                canonical_value,
                legacy_value,
                context=context,
                path=field_path,
            )
            continue
        if canonical_value != legacy_value:
            dotted_path = ".".join(field_path)
            raise SyncError(
                f"canonical/legacy entry が競合しています: "
                f"{context}: {dotted_path}"
            )


def migrated_entry(
    existing_strings: dict[str, object],
    key: str,
    source: str,
    info_plist: bool,
) -> dict[str, object]:
    canonical = existing_strings.get(key)
    legacy = (
        existing_strings.get(source)
        if info_plist and source != key
        else None
    )

    if canonical is not None and not isinstance(canonical, dict):
        raise SyncError(f"String Catalog entry が辞書ではありません: {key}")
    if legacy is not None and not isinstance(legacy, dict):
        raise SyncError(f"String Catalog entry が辞書ではありません: {source}")

    if canonical is None and legacy is None:
        return {}
    if canonical is None:
        assert isinstance(legacy, dict)
        return copy.deepcopy(legacy)
    if legacy is None:
        assert isinstance(canonical, dict)
        return copy.deepcopy(canonical)

    # canonical entryと旧value-key entryが併存する移行途中でも、片方にしかない
    # コメント・他言語・variation等を失わない。同一路径の異値は曖昧なので止める。
    assert isinstance(canonical, dict)
    assert isinstance(legacy, dict)
    merged = copy.deepcopy(canonical)
    deep_merge_entries(
        merged,
        legacy,
        context=f"{key!r} <- legacy {source!r}",
    )
    return merged


def add_entry(
    output: dict[str, object],
    key: str,
    entry: dict[str, object],
    original: str,
) -> None:
    previous = output.get(key)
    if previous is not None and previous != entry:
        raise SyncError(f"同じキーに異なる翻訳があります: {original}: {key!r}")
    output[key] = entry


def plan_sync(
    root: pathlib.Path,
    xliff: pathlib.Path,
    translations: dict[str, str],
) -> tuple[dict[pathlib.Path, dict[str, object]], dict[str, int]]:
    """全入力を検証し、まだ書き込まずに完成形を返す。"""
    if not xliff.exists():
        raise SyncError(
            f"xliff が見つかりません: {xliff}\n"
            "先に xcodebuild -exportLocalizations を実行してください"
        )
    try:
        document = ET.parse(xliff)
    except (ET.ParseError, OSError) as error:
        raise SyncError(f"xliff を読めません: {xliff}: {error}") from error

    planned: dict[pathlib.Path, dict[str, object]] = {}
    counts: dict[str, int] = {}
    missing: list[tuple[str, str]] = []

    files = document.getroot().findall("x:file", NS)
    for file_element in files:
        original = file_element.get("original")
        if not original or not original.endswith(".xcstrings"):
            continue

        target = safe_target(root, original)
        catalog = read_catalog(target)
        existing_strings = catalog.get("strings", {})
        assert isinstance(existing_strings, dict)
        info_plist = is_info_plist_catalog(original)

        units: list[tuple[ET.Element, str, str, str | None]] = []
        for unit in file_element.findall(".//x:trans-unit", NS):
            source = unit_text(unit, "source")
            if source is None or source == "":
                continue
            unit_id = unit.get("id")
            if not unit_id:
                raise SyncError(f"trans-unit id がありません: {original}: {source!r}")
            units.append((unit, unit_id, source, unit_text(unit, "note")))

        # 旧value-key entryが残るXLIFFでは、同じsourceに対して
        # id=CFBundleDisplayName と id=そらだま が併存する。
        # id != source のcanonical unitを優先する。
        canonical_sources = {
            source
            for _, unit_id, source, _ in units
            if info_plist and unit_id != source
        }

        generated_strings: dict[str, object] = {}
        for _, unit_id, source, note in units:
            if info_plist and unit_id == source and source in canonical_sources:
                continue

            key = unit_id if info_plist else source
            english = lookup(translations, source)
            if english is None:
                missing.append((original, source))
                continue

            entry = migrated_entry(existing_strings, key, source, info_plist)
            if note and "comment" not in entry:
                entry["comment"] = note
            if info_plist:
                merge_string_unit(entry, "ja", source)
            merge_string_unit(entry, "en", english)
            add_entry(generated_strings, key, entry, original)

            if not info_plist:
                plain = re.sub(r"%(\d+)\$", "%", key)
                if plain != key:
                    plain_english = re.sub(r"%(\d+)\$", "%", english)
                    plain_entry = migrated_entry(
                        existing_strings, plain, plain, info_plist=False
                    )
                    if note and "comment" not in plain_entry:
                        plain_entry["comment"] = note
                    merge_string_unit(plain_entry, "en", plain_english)
                    add_entry(generated_strings, plain, plain_entry, original)

        # XLIFFに今回現れない手動entry、コメント、variation、他言語は残す。
        # InfoPlistだけはcanonical unitと同じsourceを持つ旧value-keyを除去する。
        output_strings = copy.deepcopy(existing_strings)
        if info_plist:
            for legacy_key in canonical_sources:
                output_strings.pop(legacy_key, None)
        output_strings.update(generated_strings)

        updated_catalog = copy.deepcopy(catalog)
        updated_catalog.setdefault("sourceLanguage", "ja")
        updated_catalog.setdefault("version", "1.0")
        updated_catalog["strings"] = output_strings
        # 書く前に、完成形がJSONとして往復できることも検証する。
        try:
            json.loads(
                json.dumps(updated_catalog, ensure_ascii=False, allow_nan=False)
            )
        except (TypeError, ValueError, json.JSONDecodeError) as error:
            raise SyncError(f"JSONへ変換できません: {original}: {error}") from error

        planned[target] = updated_catalog
        counts[original] = len(generated_strings)

    if not planned:
        raise SyncError("xliff に .xcstrings の入力がありません")
    if missing:
        lines = [f"未訳 {len(missing)} 件:"]
        lines.extend(f"  {original}: {source!r}" for original, source in missing[:20])
        if len(missing) > 20:
            lines.append(f"  ... 残り {len(missing) - 20} 件")
        raise SyncError("\n".join(lines))
    return planned, counts


def render_catalog(catalog: dict[str, object]) -> str:
    return (
        json.dumps(
            catalog,
            ensure_ascii=False,
            indent=2,
            allow_nan=False,
        )
        + "\n"
    )


def stage_file(target: pathlib.Path, content: str) -> pathlib.Path:
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=target.parent,
        prefix=f".{target.name}.",
        suffix=".tmp",
    )
    temporary = pathlib.Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        if target.exists():
            os.chmod(temporary, stat.S_IMODE(target.stat().st_mode))
        return temporary
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def stage_backup(target: pathlib.Path) -> pathlib.Path:
    """置換失敗時に元へ戻せるよう、同じディレクトリへ完全な複製を置く。"""
    descriptor, temporary_name = tempfile.mkstemp(
        dir=target.parent,
        prefix=f".{target.name}.",
        suffix=".bak",
    )
    temporary = pathlib.Path(temporary_name)
    try:
        content = target.read_bytes()
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, stat.S_IMODE(target.stat().st_mode))
        return temporary
    except Exception:
        try:
            os.close(descriptor)
        except OSError:
            pass
        temporary.unlink(missing_ok=True)
        raise


def atomic_write_many(planned: dict[pathlib.Path, dict[str, object]]) -> None:
    """全出力をstageし、途中失敗時は置換済みファイルも元へ戻す。"""
    rendered = {target: render_catalog(catalog) for target, catalog in planned.items()}
    staged: dict[pathlib.Path, pathlib.Path] = {}
    backups: dict[pathlib.Path, pathlib.Path] = {}
    originally_missing: set[pathlib.Path] = set()
    replaced: list[pathlib.Path] = []
    preserved_backups: set[pathlib.Path] = set()
    try:
        for target, content in sorted(rendered.items(), key=lambda item: str(item[0])):
            staged[target] = stage_file(target, content)
        for target in sorted(staged, key=str):
            if target.exists():
                backups[target] = stage_backup(target)
            else:
                originally_missing.add(target)
        for target, temporary in sorted(staged.items(), key=lambda item: str(item[0])):
            os.replace(temporary, target)
            replaced.append(target)
    except OSError as error:
        rollback_errors: list[str] = []
        for target in reversed(replaced):
            try:
                if target in originally_missing:
                    target.unlink(missing_ok=True)
                else:
                    os.replace(backups[target], target)
            except OSError as rollback_error:
                backup = backups.get(target)
                recovery_hint = ""
                if backup is not None and backup.exists():
                    preserved_backups.add(backup)
                    recovery_hint = f"（復旧用backupを保持: {backup}）"
                rollback_errors.append(
                    f"{target}: {rollback_error}{recovery_hint}"
                )
        if rollback_errors:
            details = "; ".join(rollback_errors)
            raise SyncError(
                f"String Catalogを書き込めず、元への復元にも失敗しました: "
                f"{error}; {details}"
            ) from error
        raise SyncError(f"String Catalogを書き込めません: {error}") from error
    finally:
        for temporary in staged.values():
            temporary.unlink(missing_ok=True)
        for temporary in backups.values():
            if temporary not in preserved_backups:
                temporary.unlink(missing_ok=True)


def sync_catalogs(
    root: pathlib.Path,
    xliff: pathlib.Path,
    translations: dict[str, str],
    *,
    check_only: bool = False,
) -> dict[str, int]:
    planned, counts = plan_sync(root, xliff, translations)
    if not check_only:
        atomic_write_many(planned)
    return counts


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="検証のみ行い、String Catalogを書き換えない",
    )
    parser.add_argument(
        "xliff",
        nargs="?",
        type=pathlib.Path,
        default=XLIFF_DEFAULT,
        help=f"入力XLIFF（既定: {XLIFF_DEFAULT}）",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    try:
        translations = load_translations(ROOT)
        counts = sync_catalogs(
            ROOT,
            arguments.xliff,
            translations,
            check_only=arguments.check,
        )
    except SyncError as error:
        print(error, file=sys.stderr)
        return 1

    for name, count in sorted(counts.items()):
        print(f"{count:>4} 件  {name}")
    suffix = "（確認のみ・書き込みなし）" if arguments.check else ""
    print(f"\n未訳なし{suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
