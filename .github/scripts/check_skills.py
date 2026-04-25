#!/usr/bin/env python3
"""
P0 checks for the flutter-claude-skills repo.

Run from the repo root or via GitHub Actions. Exits non-zero on any failure.

Checks:
1. Each skills/<dir>/SKILL.md has parseable YAML frontmatter.
2. Frontmatter has required `name` and `description`.
3. Frontmatter `name` matches the directory name.
4. README skill-count badge matches the actual skill count.
5. Directory name is kebab-case (lowercase + hyphens only).
6. SKILL.md body has at least 3 H2 sections (proxy for the
   required-sections spec in CONTRIBUTING.md: What this skill does +
   When to trigger + Workflow, with Examples / Gotchas recommended).

Directories beginning with `_` (e.g. `_template`) are skipped.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
SKILLS_DIR = REPO / "skills"
README = REPO / "README.md"

KEBAB_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
BADGE_RE = re.compile(r"badge/skills-(\d+)-")
H2_RE = re.compile(r"^##\s+\S", re.MULTILINE)
MIN_H2_SECTIONS = 3


def parse_frontmatter(text: str):
    if not text.startswith("---"):
        return None, "no frontmatter delimiter"
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None, "frontmatter not closed"
    try:
        return yaml.safe_load(parts[1]), None
    except yaml.YAMLError as exc:
        return None, f"YAML parse error: {exc}"


def collect_skill_dirs() -> list[Path]:
    out = []
    for entry in sorted(SKILLS_DIR.iterdir()):
        if entry.name.startswith("_") or entry.name.startswith("."):
            continue
        if not (entry.is_dir() or entry.is_symlink()):
            continue
        out.append(entry)
    return out


def main() -> int:
    errors: list[str] = []
    skill_dirs = collect_skill_dirs()
    print(f"Discovered {len(skill_dirs)} skill directories")

    for d in skill_dirs:
        if not KEBAB_RE.match(d.name):
            errors.append(f"{d.name}: directory name is not kebab-case")

        skill_md = d / "SKILL.md"
        if not skill_md.exists():
            errors.append(f"{d.name}: SKILL.md missing")
            continue

        fm, err = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
        if err:
            errors.append(f"{d.name}: {err}")
            continue
        if not isinstance(fm, dict):
            errors.append(f"{d.name}: frontmatter is not a mapping")
            continue

        if "name" not in fm:
            errors.append(f"{d.name}: frontmatter missing required `name`")
        elif fm["name"] != d.name:
            errors.append(
                f"{d.name}: frontmatter name `{fm['name']}` does not match directory"
            )
        if not fm.get("description"):
            errors.append(f"{d.name}: frontmatter missing required `description`")

        body = skill_md.read_text(encoding="utf-8").split("---", 2)[-1]
        h2_count = len(H2_RE.findall(body))
        if h2_count < MIN_H2_SECTIONS:
            errors.append(
                f"{d.name}: only {h2_count} H2 section(s); expected ≥ {MIN_H2_SECTIONS} per CONTRIBUTING.md"
            )

    readme_text = README.read_text(encoding="utf-8")
    badge_match = BADGE_RE.search(readme_text)
    if not badge_match:
        errors.append("README.md: skills count badge not found")
    else:
        badge_count = int(badge_match.group(1))
        if badge_count != len(skill_dirs):
            errors.append(
                f"README.md: badge says {badge_count}, actual = {len(skill_dirs)}"
            )

    if errors:
        print(f"\nFAILURES ({len(errors)}):")
        for e in errors:
            print(f"  - {e}")
        return 1

    print(f"\nAll {len(skill_dirs)} skills valid; README badge in sync.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
