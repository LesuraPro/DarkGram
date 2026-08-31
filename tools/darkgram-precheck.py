#!/usr/bin/env python3
"""Catch, in seconds, the mistakes that otherwise cost an hour-long build.

Every compile failure in this fork so far has been one of two kinds:

  1. A type used without importing the module that declares it.
  2. A declaration removed while something else still referenced it, or a
     settings key added without its default value or accessor.

Neither needs a Swift compiler to spot. Run before pushing:

    python3 tools/darkgram-precheck.py

Exit code is non-zero when something looks wrong, so it can gate a push.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Types this fork uses that live in a module people forget to import. Learned the
# hard way: TextAlertAction cost one full build.
TYPE_MODULES = {
    "TextAlertAction": "Display",
    "textAlertController": "PresentationDataUtils",
    "promptController": "PromptUI",
    "UTType": "UniformTypeIdentifiers",
    "SGSimpleSettings": "SGSimpleSettings",
}

SETTINGS = os.path.join(REPO, "Swiftgram", "SGSimpleSettings", "Sources", "SimpleSettings.swift")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def darkgram_files():
    """Every Swift file this fork wrote or annotated."""
    for root, dirs, names in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in (".git", "bazel-out", "build", "third-party")]
        for name in names:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(root, name)
            text = read(path)
            if "MARK: DarkGram" in text or "DarkGram" in name:
                yield path, text


def check_imports(problems):
    for path, text in darkgram_files():
        # @testable import counts too -- test files import their subject that way.
        imports = set(re.findall(r"^(?:@testable\s+)?import\s+(\w+)", text, re.M))
        body = "\n".join(
            line for line in text.splitlines() if not line.strip().startswith("//")
        )
        for symbol, module in TYPE_MODULES.items():
            # A file inside a module never imports itself.
            if os.sep + module + os.sep in path:
                continue
            # Word boundaries: 'UTType' must not match 'UTTypeReference' and friends.
            if not re.search(r"\b" + re.escape(symbol) + r"\b", body):
                continue
            if module not in imports:
                problems.append(
                    "%s uses %s but does not import %s"
                    % (os.path.relpath(path, REPO), symbol, module)
                )


def check_settings(problems):
    if not os.path.exists(SETTINGS):
        problems.append("SimpleSettings.swift not found")
        return
    text = read(SETTINGS)

    keys_block = re.search(r"public enum Keys: String, CaseIterable \{(.*?)\n    \}", text, re.S)
    if not keys_block:
        problems.append("could not locate the Keys enum")
        return
    keys = re.findall(r"^\s*case\s+(\w+)", keys_block.group(1), re.M)

    defaults = set(re.findall(r"Keys\.(\w+)\.rawValue:", text))
    accessors = set(re.findall(r"@UserDefault\(key: Keys\.(\w+)\.rawValue\)", text))
    accessors |= set(re.findall(r"userDefaultsKey: Keys\.(\w+)\.rawValue", text))
    # Keys reached directly through UserDefaults rather than through a wrapper.
    accessors |= set(re.findall(r"forKey: Keys\.(\w+)\.rawValue", text))

    for key in keys:
        if key not in accessors and key not in defaults:
            problems.append(
                "settings key '%s' has neither an accessor nor a default value -- dead key?" % key
            )

    # A value read on a hot path must be pre-warmed, or its first concurrent touch races.
    warmed = set(re.findall(r"\{ let _ = self\.(\w+) \}", text))
    for key in ("ghostMode", "stealthStoryViews", "preferLocalSearch"):
        if key in keys and key not in warmed:
            problems.append("hot setting '%s' is not in preCacheValues" % key)


def check_orphans(problems):
    """Declarations left behind after their only user was deleted."""
    for path, text in darkgram_files():
        for name in re.findall(
            r"^\s*(?:private |public )?let (\w+): PeerInfoScreenDisclosureItem\.Label", text, re.M
        ):
            if len(re.findall(r"\b%s\b" % name, text)) <= 1:
                problems.append(
                    "%s declares '%s' but never uses it" % (os.path.relpath(path, REPO), name)
                )


SETTINGS_UI = os.path.join(REPO, "Swiftgram", "SGSettingsUI", "Sources", "SGSettingsController.swift")


def enum_cases(text, header):
    """Cases of one enum, stopping at its closing brace."""
    block = re.search(re.escape(header) + r"(.*?)\n\}", text, re.S)
    if not block:
        return None
    return set(re.findall(r"^\s*case\s+(\w+)", block.group(1), re.M))


def check_settings_ui(problems):
    """Every settings row must name a case that exists in the enum its field expects.

    Getting this wrong costs a whole build to find. The compiler reports it as "type
    'Sequence' has no member ..." -- the append overload falls back to append(contentsOf:)
    once the argument fails to type-check -- which points nowhere near the mistake. It
    happened by inserting a case after the first "case diagnostics" in the file, which
    belongs to the section enum rather than the link enum.
    """
    if not os.path.exists(SETTINGS_UI):
        return
    text = read(SETTINGS_UI)

    for header, field in (
        ("private enum SGDisclosureLink: String {", "link"),
        ("private enum SGControllerSection: Int32, SGItemListSection {", "section"),
    ):
        cases = enum_cases(text, header)
        if cases is None:
            problems.append("could not locate enum: " + header)
            continue
        for used in sorted(set(re.findall(field + r": \.(\w+)", text))):
            if used not in cases:
                problems.append(
                    "settings row uses %s: .%s but that case is in another enum" % (field, used)
                )


def main():
    problems = []
    check_imports(problems)
    check_settings(problems)
    check_orphans(problems)
    check_settings_ui(problems)

    if not problems:
        print("precheck: clean")
        return 0
    print("precheck found %d issue(s):" % len(problems))
    for item in problems:
        print("  -", item)
    return 1


if __name__ == "__main__":
    sys.exit(main())
