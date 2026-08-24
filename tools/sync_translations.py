#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""英訳を String Catalog に流し込む。

使い方:
    # 1. 文字列を抽出
    xcodebuild -exportLocalizations -project AuroraWeather.xcodeproj \
      -localizationPath /tmp/l10n -exportLanguage en
    # 2. 未訳を確認（訳を足す先は tools/translations_en.py）
    python3 tools/sync_translations.py --check
    # 3. 流し込み
    python3 tools/sync_translations.py

**なぜこれが要るか**
Xcode の IDE を使えば .xcstrings は自動更新されるが、CLI では
ビルド時の抽出結果が derivedData にしか出ず、元ファイルには書き戻されない。
このプロジェクトは CLI で完結させているため、この橋渡しが必要になる。
"""
import xml.etree.ElementTree as ET
import re, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
XLIFF_DEFAULT = pathlib.Path('/tmp/l10n/en.xcloc/Localized Contents/en.xliff')
NS = {'x': 'urn:oasis:names:tc:xliff:document:1.2'}


def load_translations():
    """訳の辞書を得る。無ければ既存の .xcstrings から復元する。"""
    table = ROOT / 'tools' / 'translations_en.py'
    if table.exists():
        ns = {}
        exec(table.read_text(encoding='utf-8'), ns)
        return ns['T']
    T = {}
    for p in ROOT.rglob('*.xcstrings'):
        if 'build' in str(p):
            continue
        for k, v in json.loads(p.read_text(encoding='utf-8')).get('strings', {}).items():
            en = v.get('localizations', {}).get('en', {}).get('stringUnit', {}).get('value')
            if en:
                T.setdefault(k, en)
    return T


def lookup(T, key):
    """xliff は同じ文字列を %1$@ とも %@ とも書き出す（抽出のたびに揺れる）。
    片方しか表に無いと未訳になるため、位置指定子を振り直して引き直す。"""
    if key in T:
        return T[key]
    counter = [0]
    def repl(m):
        counter[0] += 1
        return '%%%d$%s' % (counter[0], m.group(1))
    positional = re.sub(r'%(@|lld|d|f)', repl, key)
    if positional in T:
        return re.sub(r'%(\d+)\$', '%', T[positional])
    return None


def main():
    check_only = '--check' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    xliff = pathlib.Path(args[0]) if args else XLIFF_DEFAULT
    if not xliff.exists():
        sys.exit(f'xliff が見つからない: {xliff}\n先に xcodebuild -exportLocalizations を実行してください')

    T = load_translations()
    missing, written = [], {}

    for f in ET.parse(xliff).getroot().findall('x:file', NS):
        original = f.get('original')
        if not original.endswith('.xcstrings'):
            continue
        strings = {}
        for unit in f.findall('.//x:trans-unit', NS):
            src = unit.find('x:source', NS)
            if src is None or src.text is None:
                continue
            key = src.text
            en = lookup(T, key)
            if en is None:
                missing.append((original, key))
                continue
            entry = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": en}}}}
            strings[key] = entry
            # 位置指定子なしの形でも引けるようにする（実行時のキーはこちらのことがある）
            plain = re.sub(r'%(\d+)\$', '%', key)
            if plain != key:
                strings[plain] = {"localizations": {"en": {"stringUnit":
                    {"state": "translated", "value": re.sub(r'%(\d+)\$', '%', en)}}}}
        if not check_only:
            target = ROOT / original
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps({"sourceLanguage": "ja", "strings": strings, "version": "1.0"},
                                         ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        written[original] = len(strings)

    for name, count in sorted(written.items()):
        print(f'{count:>4} 件  {name}')
    if missing:
        print(f'\n未訳 {len(missing)} 件:')
        for _, k in missing[:20]:
            print(f'  {k!r}')
        sys.exit(1)
    print('\n未訳なし' + ('（確認のみ・書き込みなし）' if check_only else ''))


if __name__ == '__main__':
    main()
