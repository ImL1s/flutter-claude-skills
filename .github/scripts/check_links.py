#!/usr/bin/env python3
"""
Internal link checker for the flutter-claude-skills repo.

Scans top-level documentation files (README.md, PLAYBOOKS.md, CONTRIBUTING.md,
CHANGELOG.md, CODE_OF_CONDUCT.md) for relative-path Markdown links and verifies
each target resolves to a real file.

Caught regressions in the past:
- figma-generate-design (ghost referenced from figma-implement-design)
- audit-team-apps.sh (orphan reference in apple-appstore-manager)

Exits non-zero on any unresolved internal link.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# Files to scan for internal links.
DOC_FILES = [
    "README.md",
    "PLAYBOOKS.md",
    "CONTRIBUTING.md",
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
]

# Markdown link pattern: [text](target)
LINK_RE = re.compile(r"\[(?:[^\]]*)\]\((?P<target>[^)]+)\)")


def is_internal(target: str) -> bool:
    """True if target is a relative path (not URL, not bare anchor, not mailto)."""
    if target.startswith(("http://", "https://", "mailto:", "#")):
        return False
    return True


def split_path_anchor(target: str) -> tuple[str, str | None]:
    if "#" in target:
        path, anchor = target.split("#", 1)
        return path, anchor
    return target, None


def resolve(source_file: Path, target_path: str) -> Path:
    if target_path.startswith("/"):
        return REPO / target_path.lstrip("/")
    return (source_file.parent / target_path).resolve()


def main() -> int:
    errors: list[str] = []
    checked = 0

    for doc_name in DOC_FILES:
        doc = REPO / doc_name
        if not doc.exists():
            continue
        text = doc.read_text(encoding="utf-8")
        for m in LINK_RE.finditer(text):
            target = m.group("target").strip()
            if not is_internal(target):
                continue
            path_str, _anchor = split_path_anchor(target)
            if not path_str:
                continue
            resolved = resolve(doc, path_str)
            checked += 1
            if not resolved.exists():
                errors.append(
                    f"{doc_name}: broken link → `{target}` (resolved to {resolved})"
                )

    print(f"Checked {checked} internal links across {len(DOC_FILES)} doc files.")

    if errors:
        print(f"\nFAILURES ({len(errors)}):")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("All internal links resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
