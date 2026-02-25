#!/usr/bin/env python3
"""
Translate all Localizable.strings keys from en.lproj into non-English locale files.

Uses Google Translate public endpoint for convenience in local automation.
Preserves printf-style placeholders like %@, %d, %1$@, and %%.
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

LINE_RE = re.compile(r'^"((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)";\s*$')
PLACEHOLDER_RE = re.compile(r"%%|%(?:\d+\$)?[@dDuUxXfFeEgGcCs]")

# Map locale folder names to translation target language codes.
LOCALE_TO_LANG = {
    "ar-SA": "ar",
    "ar": "ar",
    "bg-BG": "bg",
    "ca": "ca",
    "cs": "cs",
    "da": "da",
    "de-DE": "de",
    "de": "de",
    "el": "el",
    "es-ES": "es",
    "es-MX": "es",
    "es": "es",
    "fi": "fi",
    "fr-CA": "fr",
    "fr-FR": "fr",
    "fr": "fr",
    "he": "he",
    "hi": "hi",
    "hr": "hr",
    "hu": "hu",
    "id": "id",
    "it": "it",
    "ja": "ja",
    "ko": "ko",
    "ms": "ms",
    "nb": "no",
    "no": "no",
    "nl-NL": "nl",
    "nl": "nl",
    "pl": "pl",
    "pt-BR": "pt",
    "pt-PT": "pt",
    "ro": "ro",
    "ru": "ru",
    "sk": "sk",
    "sv": "sv",
    "th": "th",
    "tr": "tr",
    "uk": "uk",
    "vi": "vi",
    "zh-Hans": "zh-CN",
    "zh-Hant-HK": "zh-TW",
    "zh-Hant": "zh-TW",
}


def unescape_strings_value(raw: str) -> str:
    return raw.replace('\\"', '"').replace("\\\\", "\\")


def escape_strings_value(raw: str) -> str:
    return raw.replace("\\", "\\\\").replace('"', '\\"')


def parse_strings_rows(path: Path) -> List[Tuple[str, str, str]]:
    rows: List[Tuple[str, str, str]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        match = LINE_RE.match(raw_line.strip())
        if match:
            key = unescape_strings_value(match.group(1))
            value = unescape_strings_value(match.group(2))
            rows.append(("kv", key, value))
        else:
            rows.append(("raw", raw_line, ""))
    return rows


def write_strings_rows(path: Path, rows: Sequence[Tuple[str, str, str]]) -> None:
    out: List[str] = []
    for row_type, key, value in rows:
        if row_type == "kv":
            out.append(f'"{escape_strings_value(key)}" = "{escape_strings_value(value)}";')
        else:
            out.append(key)
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def protect_placeholders(text: str) -> Tuple[str, Dict[str, str]]:
    mapping: Dict[str, str] = {}
    idx = 0

    def repl(match: re.Match[str]) -> str:
        nonlocal idx
        token = f"__PH_{idx}__"
        mapping[token] = match.group(0)
        idx += 1
        return token

    protected = PLACEHOLDER_RE.sub(repl, text)
    return protected, mapping


def restore_placeholders(text: str, mapping: Dict[str, str]) -> str:
    restored = text
    for token, original in mapping.items():
        restored = restored.replace(token, original)
    return restored


def translate_text(text: str, target_lang: str, retries: int = 3) -> str:
    url = (
        "https://translate.googleapis.com/translate_a/single?client=gtx"
        f"&sl=en&tl={urllib.parse.quote(target_lang)}&dt=t&q={urllib.parse.quote(text)}"
    )
    backoff = 0.7
    last_error: Exception | None = None

    for _ in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=40) as response:
                data = json.loads(response.read().decode("utf-8"))
            return "".join(part[0] for part in data[0])
        except Exception as error:  # noqa: PERF203
            last_error = error
            time.sleep(backoff)
            backoff *= 1.8

    assert last_error is not None
    raise last_error


def build_translations_for_language(
    keys: Sequence[str],
    target_lang: str,
    max_chunk_chars: int = 2800,
) -> Dict[str, str]:
    prepared: Dict[str, str] = {}
    restore_maps: Dict[str, Dict[str, str]] = {}
    for key in keys:
        protected, mapping = protect_placeholders(key)
        prepared[key] = protected
        restore_maps[key] = mapping

    translated: Dict[str, str] = {}
    separator = "\n__KSEP__\n"

    chunk: List[str] = []
    chunk_len = 0

    def flush(items: Sequence[str]) -> None:
        if not items:
            return
        joined = separator.join(prepared[k] for k in items)
        parts: List[str]
        try:
            translated_joined = translate_text(joined, target_lang)
            parts = translated_joined.split(separator)
            if len(parts) != len(items):
                raise ValueError("translation split mismatch")
        except Exception:
            # Fallback to item-by-item to avoid losing progress when chunk parsing fails.
            parts = [translate_text(prepared[k], target_lang) for k in items]

        for key, value in zip(items, parts):
            translated[key] = restore_placeholders(value.strip(), restore_maps[key])

    for key in keys:
        to_add = prepared[key]
        add_len = len(to_add) + (len(separator) if chunk else 0)
        if chunk and chunk_len + add_len > max_chunk_chars:
            flush(chunk)
            chunk = []
            chunk_len = 0
        chunk.append(key)
        chunk_len += add_len

    flush(chunk)
    return translated


def audit_translations(base_dir: Path) -> Tuple[Dict[str, int], Dict[str, int]]:
    en_file = base_dir / "en.lproj" / "Localizable.strings"
    en_rows = parse_strings_rows(en_file)
    en_map = {key: value for row_type, key, value in en_rows if row_type == "kv"}
    en_keys = set(en_map.keys())

    missing_counts: Dict[str, int] = {}
    same_counts: Dict[str, int] = {}

    for file in sorted(base_dir.glob("*.lproj/Localizable.strings")):
        locale = file.parent.name.replace(".lproj", "")
        if locale.startswith("en") or locale == "en":
            continue
        rows = parse_strings_rows(file)
        locale_map = {key: value for row_type, key, value in rows if row_type == "kv"}
        missing_counts[locale] = len([k for k in en_keys if k not in locale_map])
        same_counts[locale] = len([k for k, v in locale_map.items() if k in en_keys and k == v])

    return missing_counts, same_counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base-dir",
        default="/Users/test/XCodeProjects/CompressTarget/CompressVideoToTargetSize",
        help="Directory containing *.lproj localization folders",
    )
    args = parser.parse_args()

    base_dir = Path(args.base_dir)
    en_file = base_dir / "en.lproj" / "Localizable.strings"
    if not en_file.exists():
        raise FileNotFoundError(f"Missing {en_file}")

    en_rows = parse_strings_rows(en_file)
    en_keys = [key for row_type, key, _ in en_rows if row_type == "kv"]

    target_locales: List[str] = []
    for file in sorted(base_dir.glob("*.lproj/Localizable.strings")):
        locale = file.parent.name.replace(".lproj", "")
        if locale.startswith("en") or locale == "en":
            continue
        if locale in LOCALE_TO_LANG:
            target_locales.append(locale)

    for locale in target_locales:
        lang = LOCALE_TO_LANG[locale]
        print(f"[translate] {locale} ({lang}) ...", flush=True)
        try:
            locale_translations = build_translations_for_language(en_keys, lang)
        except Exception as error:
            print(f"[error] failed translating locale {locale}: {error}", flush=True)
            continue

        strings_file = base_dir / f"{locale}.lproj" / "Localizable.strings"
        locale_rows = parse_strings_rows(strings_file)
        locale_map = {key: value for row_type, key, value in locale_rows if row_type == "kv"}

        # Rebuild KV rows in EN key order to guarantee complete coverage.
        new_rows: List[Tuple[str, str, str]] = []
        for key in en_keys:
            translated_value = locale_translations.get(key, locale_map.get(key, key))
            new_rows.append(("kv", key, translated_value))

        # Preserve raw non-KV rows from original (rarely used comments/spacing).
        for row_type, key, value in locale_rows:
            if row_type == "raw" and key.strip():
                new_rows.append((row_type, key, value))

        write_strings_rows(strings_file, new_rows)
        print(f"[write] {locale}", flush=True)

    missing_counts, same_counts = audit_translations(base_dir)
    missing_total = sum(missing_counts.values())
    same_total = sum(same_counts.values())
    print(f"[audit] total missing keys: {missing_total}", flush=True)
    print(f"[audit] total key==value in non-EN locales: {same_total}", flush=True)
    for locale in sorted(missing_counts):
        print(
            f"[audit] {locale}: missing={missing_counts[locale]} sameAsKey={same_counts[locale]}",
            flush=True,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
