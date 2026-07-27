#!/usr/bin/env python3
"""Fail CI when Norwegian localization drifts from English source copy."""

from __future__ import annotations

import collections
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "MealShuffler"
NORWEGIAN = APP / "Resources" / "nb.lproj" / "Localizable.strings"

SWIFT_STRING = r'"((?:[^"\\]|\\.)*)"'
LOCALIZED_CONSTRUCTORS = (
    "Text",
    "TextField",
    "Label",
    "Button",
    "Section",
    "Picker",
    "Toggle",
    "Menu",
    "Link",
    "LabeledContent",
)
LOCALIZED_MODIFIERS = (
    "navigationTitle",
    "accessibilityLabel",
    "alert",
    "confirmationDialog",
)
FORMAT_TOKEN = re.compile(r"%(?:\d+\$)?(?:ld|@|d|f)")
ENTRY = re.compile(
    rf'^\s*{SWIFT_STRING}\s*=\s*{SWIFT_STRING}\s*;\s*$',
    re.MULTILINE,
)


def source_keys() -> set[str]:
    keys: set[str] = set()
    for path in APP.rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        keys.update(
            match.group(1)
            for match in re.finditer(rf"L10n\.string\(\s*{SWIFT_STRING}", source)
        )
        for constructor in LOCALIZED_CONSTRUCTORS:
            keys.update(
                match.group(1)
                for match in re.finditer(
                    rf"\b{constructor}\(\s*{SWIFT_STRING}", source
                )
            )
        for modifier in LOCALIZED_MODIFIERS:
            keys.update(
                match.group(1)
                for match in re.finditer(
                    rf"\.{modifier}\(\s*{SWIFT_STRING}", source
                )
            )
        keys.update(
            match.group(1)
            for match in re.finditer(
                rf"\.searchable\([^)]*?\bprompt:\s*{SWIFT_STRING}",
                source,
                re.DOTALL,
            )
        )

    # Runtime-built/interpolated labels are localized explicitly with L10n.
    return {
        key
        for key in keys
        if key
        and r"\(" not in key
        and not key.startswith(("http://", "https://"))
        and any(character.isalpha() for character in key)
    }


def fail(message: str) -> None:
    print(f"Localization validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    raw = NORWEGIAN.read_text(encoding="utf-8")
    entries = ENTRY.findall(raw)
    translations = collections.defaultdict(list)
    for key, value in entries:
        translations[key].append(value)

    duplicates = sorted(key for key, values in translations.items() if len(values) > 1)
    if duplicates:
        fail(f"duplicate Norwegian keys: {duplicates}")

    missing = sorted(source_keys() - translations.keys(), key=str.casefold)
    if missing:
        fail(f"missing Norwegian keys: {missing}")

    format_mismatches = sorted(
        key
        for key, values in translations.items()
        if sorted(FORMAT_TOKEN.findall(key))
        != sorted(FORMAT_TOKEN.findall(values[0]))
    )
    if format_mismatches:
        fail(f"format placeholders differ: {format_mismatches}")

    print(
        f"Localization validation passed: "
        f"{len(source_keys())} source keys, {len(translations)} Norwegian entries"
    )


if __name__ == "__main__":
    main()
