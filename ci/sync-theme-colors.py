"""Export named launch/accent assets from AppTheme; --check detects token drift."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / "MealShuffler/Theme/AppTheme.swift"
ASSETS = ROOT / "MealShuffler/Resources/Assets.xcassets"
MAPPING = {"background": "LaunchBackground", "accent": "AccentColor"}


def asset(theme, token):
    pattern = rf"static let {token} = dynamic\(light: \(([^)]+)\), dark: \(([^)]+)\)\)"
    match = re.search(pattern, theme)
    if not match:
        raise ValueError(f"Cannot read canonical theme token: {token}")
    colors = []
    for index, channels in enumerate(match.groups()):
        rgb = [float(value.strip()) for value in channels.split(",")]
        if len(rgb) != 3 or any(not 0 <= value <= 1 for value in rgb):
            raise ValueError(f"Invalid RGB channels: {token}")
        entry = {
            "color": {
                "color-space": "srgb",
                "components": dict(alpha="1.000", **{
                    channel: f"{value:.3f}"
                    for channel, value in zip(("red", "green", "blue"), rgb)
                }),
            },
            "idiom": "universal",
        }
        if index == 1:
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        colors.append(entry)
    return {"colors": colors, "info": {"author": "xcode", "version": 1}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    theme = THEME.read_text(encoding="utf-8")
    failures = []
    for token, name in MAPPING.items():
        target = ASSETS / f"{name}.colorset/Contents.json"
        expected = asset(theme, token)
        if args.check:
            if not target.exists() or json.loads(target.read_text(encoding="utf-8")) != expected:
                failures.append(name)
        else:
            target.write_text(json.dumps(expected, indent=2) + "\n", encoding="utf-8")
    if failures:
        raise SystemExit("Theme asset drift: " + ", ".join(failures) + ". Run ci/sync-theme-colors.py.")
    print("Theme color assets match AppTheme." if args.check else "Exported light/dark launch and accent colors.")


if __name__ == "__main__":
    main()
