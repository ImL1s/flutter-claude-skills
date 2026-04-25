---
name: _template
description: |
  One-line summary of WHEN this skill should activate. Be specific.
  Triggers: comma-separated keywords / file-path patterns / user intents (e.g. `flutter test`, `*.golden.png`, `golden test fails`).
  Skip: conditions under which the skill should NOT activate (e.g. "not for unit tests", "not for non-Flutter projects").
---

<!--
This is the COPY-PASTE STARTER for new skills. To use:

1. cp -r skills/_template skills/your-skill-name
2. Replace `_template` in frontmatter `name:` with the new directory name (must match exactly).
3. Rewrite each section. Delete this comment block.
4. Run `python .github/scripts/check_skills.py` locally to verify it passes the same checks CI runs.

Required sections (CI enforces presence of frontmatter; sections below are project convention):
  - What this skill does
  - When to trigger
  - Workflow

Recommended:
  - Examples
  - Gotchas
  - Related skills
-->

## What this skill does

Short paragraph (2-4 sentences) explaining the purpose. Lead with the outcome the skill produces, not the steps. Example:

> Diagnoses why `flutter pub get` hangs on Windows + FVM setups by checking the four most common root causes (lockfile corruption, FVM SDK path drift, network proxy, dependency resolution loop) in priority order, with one-liner remediation commands for each.

## When to trigger

- Bullet list of explicit triggers
- File path patterns (e.g. `pubspec.lock`, `**/*.dart`)
- Keywords or user intents (e.g. "pub get hangs", "flutter command stuck")
- Task contexts (e.g. "during release preflight after `flutter clean`")

## Workflow

Step-by-step instructions. Include concrete commands, code snippets, and expected outputs. Each step should be runnable.

1. **First action** — what to check first.
   ```bash
   # Concrete command, copy-pasteable
   ```
2. **Second action** — what to do based on the first action's output.
3. **Escalation** — if the first two steps don't resolve it, what to try next.

## Examples

Concrete before/after, input/output, or full session transcripts. Show what success looks like AND a representative failure case if relevant.

**Input:** The user reports `flutter pub get` has been hanging for 5 minutes.

**Output:** Skill checks lockfile, finds it stale; runs `dart pub upgrade --major-versions` and the operation completes in 12 seconds.

## Gotchas

Known limitations, edge cases, or environment requirements.

- **Environment:** macOS / Windows / Linux differences if any.
- **Tool version pins:** if behavior depends on specific Flutter / Dart / FVM versions, document the version range.
- **False positives:** when this skill might match but shouldn't act (link to the skip condition above).

## Related skills

- **`other-skill-name`** — short note on how it composes (before / after / alternative).
- **`another-skill`** — when to prefer the other one over this.
