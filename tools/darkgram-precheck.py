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
        imports = set(re.findall(r"^import\s+(\w+)", text, re.M))
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


def main():
    problems = []
    check_imports(problems)
    check_settings(problems)
    check_orphans(problems)

    if not problems:
        print("precheck: clean")
        return 0
    print("precheck found %d issue(s):" % len(problems))
    for item in problems:
        print("  -", item)
    return 1


if __name__ == "__main__":
    sys.exit(main())
