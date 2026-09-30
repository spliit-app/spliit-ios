#!/usr/bin/env python3
"""Run with python3 Scripts/test-check-strings.py on the macOS build host."""
import plistlib
import runpy
import tempfile
from pathlib import Path

checker = runpy.run_path(str(Path(__file__).with_name("check-strings.py")))
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    english = root / "en.lproj/Localizable.strings"
    french = root / "fr.lproj/Localizable.strings"
    english.parent.mkdir()
    french.parent.mkdir()
    english.write_bytes(plistlib.dumps({"Hello": "Hello", "Missing": "Missing"}))
    french.write_bytes(plistlib.dumps({"Hello": "Bonjour"}))

    entries = checker["committed"](english)
    assert set(entries) == {"Hello", "Missing"}
    assert checker["translated"](entries["Hello"], "fr")
    assert not checker["translated"](entries["Missing"], "fr")

    french.write_bytes(plistlib.dumps({"Hello": "Bonjour", "Stale": "Obsolète"}))
    try:
        checker["committed"](english)
    except ValueError as error:
        assert "Stale" in str(error)
    else:
        raise AssertionError("A French key without an English key must fail")

    french.unlink()
    assert not checker["translated"](checker["committed"](english)["Hello"], "fr")

    source = root / "Messages.swift"
    source.write_text('NSLocalizedString("Hello", bundle: .module, comment: "")\n')
    assert checker["core_keys"](root) == {"Hello"}
    source.write_text('let ordinary = "Not localized"\n')
    assert checker["core_keys"](root) == set()

for source, table, expected in [
    ("Spliit/Views/ExpenseRow.swift", "Localizable", "app"),
    ("Spliit/Shared/ExpenseCategoryName.swift", "Categories", "categories"),
    ("Spliit/Intents/SpliitIntents.swift", "AppShortcuts", "shortcuts"),
    ("Packages/SpliitKit/Sources/SpliitCore/ExpenseFormDraft.swift", "Localizable", "core"),
    (".build/checkouts/skip-ui/Sources/SkipUI/Text.swift", "Localizable", None),
    (".build/checkouts/skip-ui/Sources/SkipUI/Text.swift", "Categories", None),
]:
    assert checker["catalog_for"](str(checker["REPO"] / source), table) == expected
assert checker["catalog_for"]("", "Localizable") is None

print("String table checks passed.")
