"""Checks that every Material icon the app uses is actually in the built app's icon font.

Why this exists: Flutter subsets `MaterialIcons-Regular.otf` at build time down to the icons it
believes the app uses. On this project that subset has been seen to go *stale* - an incremental
`flutter build windows` kept a subset from an earlier state of the code, so the search
magnifier, the empty-state icon and a new sidebar button were all silently absent from the
release build. A missing icon draws nothing at all: no box, no warning, no analyzer error.
It looks exactly like a widget that was never added.

The fix is `flutter clean` before the build. This script is how you know whether you need it.

Usage:  python tools/check_icons.py
        python tools/check_icons.py <project root>

The Flutter SDK is found through `FLUTTER_ROOT`, or by looking next to whatever `flutter` is on
PATH. Exit code 0 when every icon is present, 1 otherwise.
"""

import os
import re
import shutil
import struct
import sys

FLUTTER_ICONS = os.path.join(
    "packages", "flutter", "lib", "src", "material", "icons.dart")
BUILT_FONT = os.path.join(
    "build", "windows", "x64", "runner", "Release", "data", "flutter_assets",
    "fonts", "MaterialIcons-Regular.otf")

ICON_USE = re.compile(r"\bIcons\.([a-z0-9_]+)\b")
# The definitions are line-wrapped in the SDK's `icons.dart`, so the codepoint can be on the
# next line: `static const IconData arrow_back = IconData(\n  0xe5c4, ...`.
ICON_DEF = re.compile(
    r"static const IconData ([a-z0-9_]+) = IconData\(\s*0x([0-9a-fA-F]+)"
)


def flutter_root():
    """The Flutter SDK, from the environment or from whatever `flutter` is on PATH."""
    from_env = os.environ.get("FLUTTER_ROOT")
    if from_env and os.path.isdir(from_env):
        return from_env
    flutter = shutil.which("flutter")
    if flutter:
        # .../flutter/bin/flutter  ->  .../flutter
        candidate = os.path.dirname(os.path.dirname(os.path.realpath(flutter)))
        if os.path.isdir(candidate):
            return candidate
    raise SystemExit(
        "cannot find the Flutter SDK: set FLUTTER_ROOT, or put `flutter` on PATH")


def used_icons(root):
    """Every Icons.<name> written anywhere in the app's Dart sources."""
    names = set()
    for base, _dirs, files in os.walk(os.path.join(root, "lib")):
        for name in files:
            if not name.endswith(".dart"):
                continue
            with open(os.path.join(base, name), encoding="utf-8") as handle:
                names.update(ICON_USE.findall(handle.read()))
    return names


def icon_codepoints():
    source = os.path.join(flutter_root(), FLUTTER_ICONS)
    if not os.path.exists(source):
        raise SystemExit(f"no {source} - is that really the Flutter SDK?")
    with open(source, encoding="utf-8") as handle:
        return {name: int(code, 16) for name, code in ICON_DEF.findall(handle.read())}


def font_codepoints(path):
    with open(path, "rb") as handle:
        data = handle.read()

    def u16(at):
        return struct.unpack_from(">H", data, at)[0]

    def u32(at):
        return struct.unpack_from(">I", data, at)[0]

    cmap = None
    for index in range(u16(4)):
        record = 12 + index * 16
        if data[record:record + 4] == b"cmap":
            cmap = u32(record + 8)
            break
    if cmap is None:
        raise SystemExit(f"{path}: no cmap table")

    points = set()
    for index in range(u16(cmap + 2)):
        record = cmap + 4 + index * 8
        offset = cmap + u32(record + 4)
        fmt = u16(offset)

        if fmt == 4:
            seg_x2 = u16(offset + 6)
            seg = seg_x2 // 2
            ends = [u16(offset + 14 + i * 2) for i in range(seg)]
            starts = [u16(offset + 16 + seg_x2 + i * 2) for i in range(seg)]
            deltas = [u16(offset + 16 + seg_x2 * 2 + i * 2) for i in range(seg)]
            range_base = offset + 16 + seg_x2 * 3
            range_offs = [u16(range_base + i * 2) for i in range(seg)]
            for i in range(seg):
                for code in range(starts[i], min(ends[i], 0xFFFF) + 1):
                    if range_offs[i] == 0:
                        glyph = (code + deltas[i]) & 0xFFFF
                    else:
                        at = range_base + i * 2 + range_offs[i] + (code - starts[i]) * 2
                        if at + 2 > len(data):
                            continue
                        glyph = u16(at)
                        if glyph:
                            glyph = (glyph + deltas[i]) & 0xFFFF
                    if glyph:
                        points.add(code)
        elif fmt == 12:
            for group in range(u32(offset + 12)):
                at = offset + 16 + group * 12
                for code in range(u32(at), min(u32(at + 4), 0x10FFFF) + 1):
                    points.add(code)
    return points


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = sys.argv[1] if len(sys.argv) > 1 else here
    font_path = os.path.join(root, BUILT_FONT)
    if not os.path.exists(font_path):
        raise SystemExit(f"no built font at {font_path} - build for Windows first")

    names = used_icons(root)
    definitions = icon_codepoints()
    present = font_codepoints(font_path)

    unknown = sorted(n for n in names if n not in definitions)
    missing = sorted(
        n for n in names
        if n in definitions and definitions[n] not in present
    )

    print(f"{len(names)} icons used in lib/")
    print(f"built font carries {len(present)} glyphs "
          f"({os.path.getsize(font_path)} bytes)")
    if unknown:
        print(f"\nnot found in Flutter's icon table (renamed?): {', '.join(unknown)}")
    if missing:
        print(f"\nMISSING from the built font ({len(missing)}):")
        for name in missing:
            print(f"  Icons.{name}  U+{definitions[name]:04X}")
        print("\nrun `flutter clean` and build again: the icon subset has gone stale")
        return 1
    print("\nevery icon the app uses is in the font")
    return 0


if __name__ == "__main__":
    sys.exit(main())
