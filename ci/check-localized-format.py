#!/usr/bin/env python3
"""Every L10n.string(...) call must pass exactly as many arguments as its key expects.

`String(format:)` reads its arguments positionally off a list it cannot check. Passing one
too few does not fail to compile and does not throw -- it reads whatever is next in memory,
which is a crash on a good day and nonsense on the screen on a bad one. The localization
validator already pins the English and Norwegian sides of a key to the same placeholders;
this pins the call sites to them as well.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = [
    ROOT / "MealShuffler",
    ROOT / "MealShufflerWidget",
    ROOT / "MealShufflerShare",
]

# %@ %ld %d %f, with an optional positional index and width.
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?[-+ 0#]?[\d.]*(?:ld|lu|@|d|u|f|s)")
CALL = re.compile(r"L10n\.string\(")


def read_string_literal(text: str, index: int) -> tuple[str, int] | None:
    """Reads a Swift string literal starting at `index` (which must be the opening quote)."""
    if index >= len(text) or text[index] != '"':
        return None
    out: list[str] = []
    i = index + 1
    while i < len(text):
        character = text[i]
        if character == "\\":
            out.append(text[i:i + 2])
            i += 2
            continue
        if character == '"':
            return "".join(out), i + 1
        if character == "\n":
            return None
        out.append(character)
        i += 1
    return None


def split_arguments(text: str, open_index: int) -> list[str] | None:
    """Top-level comma-separated arguments between the parens starting at `open_index`."""
    depth = 0
    i = open_index
    start = open_index + 1
    args: list[str] = []
    in_string = False
    while i < len(text):
        character = text[i]
        if in_string:
            if character == "\\":
                i += 2
                continue
            if character == '"':
                in_string = False
            i += 1
            continue
        if character == '"':
            in_string = True
            i += 1
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                args.append(text[start:i])
                return [a for a in (arg.strip() for arg in args) if a]
        elif character == "," and depth == 1:
            args.append(text[start:i])
            start = i + 1
        i += 1
    return None


def expected_arguments(key: str) -> int:
    """How many values the key consumes. Positional specifiers pick a slot rather than
    advancing, so the count is the highest slot referenced."""
    matches = list(PLACEHOLDER.finditer(key))
    if not matches:
        return 0
    if any(match.group(1) for match in matches):
        return max(int(match.group(1)) for match in matches if match.group(1))
    return len(matches)


def main() -> None:
    problems: list[str] = []
    checked = 0

    for base in SOURCES:
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for call in CALL.finditer(text):
                open_index = call.end() - 1
                args = split_arguments(text, open_index)
                if args is None:
                    continue
                literal = read_string_literal(text, call.end())
                if literal is None:
                    # A key built at runtime; the validator cannot see it either.
                    continue
                checked += 1
                key = literal[0]
                wanted = expected_arguments(key)
                supplied = len(args) - 1
                if wanted != supplied:
                    line = text[: call.start()].count("\n") + 1
                    problems.append(
                        f"{path.relative_to(ROOT)}:{line} "
                        f'"{key[:60]}" wants {wanted} argument(s), got {supplied}'
                    )

    print(f"checked {checked} L10n.string call(s) with literal keys")
    if problems:
        print()
        print(f"{len(problems)} problem(s):")
        for problem in problems:
            print("  " + problem)
        raise SystemExit(1)
    print("every call matches its key")


if __name__ == "__main__":
    main()
