#!/usr/bin/env python3
"""Reconciles the string catalogues against the strings the source actually contains.

Xcode does this for you in the IDE; nothing does it from the command line, which is how the
app catalogue came to hold 21 of its 166 keys. The compiler writes a `.stringsdata` beside
every object file (see `SWIFT_EMIT_LOC_STRINGS` in project.yml), so a build knows the answer
exactly — this reads those and compares them with what is committed. Core's native
NSLocalizedString calls are extracted by Xcode's extractLocStrings tool instead.

Reports three things, and exits non-zero for any of them:

  missing       in the source, absent from the catalogue — invisible to translators, and it
                ships in English no matter what language the phone is in
  stale         in the catalogue, gone from the source — a translation of nothing
  untranslated  in the catalogue, with no value for a language the app claims to support

Usage: check-strings.py <derived-data-path>
"""
from __future__ import annotations

import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

# Every language the app ships beyond the source one. Adding to this is what makes the check
# start demanding translations for it.
LANGUAGES = ["fr"]

REPO = Path(__file__).resolve().parent.parent

# Which catalogue a string belongs in, decided by the file it was written in. SpliitCore has a
# table of its own because it is a package: `NSLocalizedString` there resolves against
# `Bundle.module`, and a translation in the app's catalogue would never be found.
CATALOGS = {
    "app": REPO / "Spliit/Resources/Localizable.xcstrings",
    "core": REPO / "Packages/SpliitKit/Sources/SpliitCore/Resources/en.lproj/Localizable.strings",
    "shortcuts": REPO / "Spliit/Resources/AppShortcuts.xcstrings",
    "categories": REPO / "Spliit/Resources/Categories.xcstrings",
}

CORE_SOURCES = REPO / "Packages/SpliitKit/Sources/SpliitCore"

# Table name in the source -> catalogue, for the tables that are not `Localizable`.
BY_TABLE = {"AppShortcuts": "shortcuts", "Categories": "categories"}


def catalog_for(source: str, table: str) -> str | None:
    if table in BY_TABLE:
        return BY_TABLE[table]
    if table != "Localizable":
        return None
    try:
        Path(source).resolve().relative_to(CORE_SOURCES)
    except ValueError:
        return "app"
    return "core"


def core_keys(sources: Path = CORE_SOURCES) -> set[str]:
    """Swift compiler string extraction does not include NSLocalizedString calls."""
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run([
            "xcrun", "extractLocStrings", "-q", "-o", directory,
            *map(str, sorted(sources.rglob("*.swift"))),
        ], check=True)
        table = Path(directory) / "Localizable.strings"
        return set(json.loads(subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(table)]
        ))) if table.exists() else set()


def extracted_keys(derived: Path) -> dict[str, set[str]]:
    """The keys the compiler found, grouped by the catalogue that should hold them."""
    found: dict[str, set[str]] = {name: set() for name in CATALOGS}
    files = list(derived.rglob("*.stringsdata"))

    # Only the simulator build — the one `make strings` just produced. `make device` leaves a
    # Debug-iphoneos tree beside it, and a union of the two reports a string as missing because
    # a stale copy from before an edit still mentions the wording that changed. Falls back to
    # everything so a derived-data layout this does not recognise still gets checked.
    simulator = [path for path in files if "iphonesimulator" in str(path)]
    files = simulator or files

    if not files:
        sys.exit(
            f"No .stringsdata under {derived} — run `make build` first, and check that\n"
            "SWIFT_EMIT_LOC_STRINGS is still YES in project.yml."
        )

    for path in files:
        raw = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(path)],
            capture_output=True,
        )
        if raw.returncode:
            continue
        data = json.loads(raw.stdout)
        source = data.get("source", "")
        for table, entries in (data.get("tables") or {}).items():
            catalog = catalog_for(source, table)
            if catalog is None:
                continue
            for entry in entries:
                # An App Shortcut records every phrase of a shortcut under the first one, so
                # the alternatives are only ever visible in `values`.
                for key in entry.get("values") or [entry.get("key")]:
                    if key:
                        found[catalog].add(key)
    found["core"] = core_keys()
    return found


def committed(path: Path) -> dict:
    if not path.exists():
        return {}
    if path.suffix == ".strings":
        tables = {}
        for language in ["en", *LANGUAGES]:
            localized = path.parent.parent / f"{language}.lproj" / path.name
            tables[language] = json.loads(subprocess.check_output(
                ["plutil", "-convert", "json", "-o", "-", str(localized)]
            )) if localized.exists() else {}
        for language in LANGUAGES:
            extra = tables[language].keys() - tables["en"].keys()
            if extra:
                raise ValueError(f"{language}: translations have no English key: {sorted(extra)}")
        return {
            key: {"localizations": {
                language: {"stringUnit": {"value": tables[language].get(key)}}
                for language in LANGUAGES
            }}
            for key in tables["en"]
        }
    return json.loads(path.read_text(encoding="utf-8")).get("strings", {})


def translated(entry: dict, language: str) -> bool:
    """Whether this entry says something in `language` — or says it needs no translation."""
    if entry.get("shouldTranslate") is False:
        return True
    localization = entry.get("localizations", {}).get(language)
    if not localization:
        return False
    if "stringUnit" in localization:
        return bool(localization["stringUnit"].get("value"))
    # A counted string is only done when every plural category the language uses is filled in,
    # and the catalogue is the only place that knows which those are.
    plural = localization.get("variations", {}).get("plural", {})
    return bool(plural) and all(
        unit.get("stringUnit", {}).get("value") for unit in plural.values()
    )


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {Path(sys.argv[0]).name} <derived-data-path>")

    found = extracted_keys(Path(sys.argv[1]))
    problems = 0

    for name, path in CATALOGS.items():
        try:
            entries = committed(path)
        except ValueError as error:
            print(f"{path.relative_to(REPO)} — {error}")
            problems += 1
            continue
        source_keys = found[name]
        relative = path.relative_to(REPO)

        missing = sorted(source_keys - entries.keys())
        stale = sorted(entries.keys() - source_keys)
        untranslated = {
            language: sorted(
                key
                for key, entry in entries.items()
                if key in source_keys and not translated(entry, language)
            )
            for language in LANGUAGES
        }

        counts = [f"{len(entries)} keys"]
        for language in LANGUAGES:
            counts.append(f"{language}: {len(untranslated[language])} untranslated")
        print(f"{relative} — {', '.join(counts)}")

        for label, keys in [("missing", missing), ("stale", stale)]:
            for key in keys:
                print(f"  {label}: {key!r}")
                problems += 1
        for language, keys in untranslated.items():
            for key in keys:
                print(f"  no {language}: {key!r}")
                problems += 1

    if problems:
        print(f"\n{problems} problem(s).")
        return 1
    print("\nEvery string is in its catalogue and translated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
