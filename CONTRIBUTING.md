# Contributing to flutter-claude-skills

Thanks for your interest in contributing! This repo collects production-tested [Claude Code](https://claude.com/claude-code) skills for Flutter / Dart developers. We welcome new skills, bug fixes, clarifications, and better examples.

## Table of Contents

- [Ways to contribute](#ways-to-contribute)
- [Repository structure](#repository-structure)
- [Adding a new skill](#adding-a-new-skill)
- [SKILL.md format](#skillmd-format)
- [Sanitization rules](#sanitization-rules)
- [Language policy](#language-policy)
- [Commit & PR guidelines](#commit--pr-guidelines)
- [Code of Conduct](#code-of-conduct)

---

## Ways to contribute

- **New skill** — package a reusable workflow you've been using with Claude Code.
- **Improve an existing skill** — sharper triggers, better examples, more accurate commands.
- **Bug fix** — broken command, stale syntax, wrong expected output.
- **Documentation** — clearer README, better examples, cleaner structure.

Open an issue first for larger changes (new skill categories, restructuring, breaking rename). Small fixes can go straight to a PR.

---

## Repository structure

```
.
├── skills/                     # One directory per skill
│   └── <skill-name>/
│       ├── SKILL.md            # Required — frontmatter + content
│       └── ...                 # Optional helper scripts / templates
├── README.md                   # Category index
├── CONTRIBUTING.md             # This file
├── CHANGELOG.md                # Version log
├── CODE_OF_CONDUCT.md          # Contributor Covenant
└── LICENSE                     # MIT
```

---

## Adding a new skill

1. **Pick a directory name** — lowercase, hyphen-separated, concise. Examples: `flutter-verify`, `firebase-auth-manager`.
2. **Create `skills/<your-skill>/SKILL.md`** with the [format below](#skillmd-format).
3. **Test the triggers** — verify Claude Code picks up the skill when the trigger conditions match.
4. **Sanitize** — strip any secrets, personal paths, or company-specific references (see [Sanitization rules](#sanitization-rules)).
5. **Update `README.md`** — add the skill to the matching category, update the skill count badge if needed.
6. **Open a PR** — one skill per PR unless they're tightly related.

---

## SKILL.md format

```yaml
---
name: skill-name
description: |
  One-line summary. When the agent should invoke this skill.
  Triggers: comma-separated keywords / file-path patterns / user intents.
  Skip: conditions under which the skill should NOT activate.
---

## What this skill does

Short paragraph explaining the purpose.

## When to trigger

- Bullet list of explicit triggers
- File path patterns, keywords, or user intents

## Workflow

Step-by-step instructions. Include concrete commands / code snippets.

## Examples

Concrete before/after, input/output, or full session transcripts.

## Gotchas

Known limitations, edge cases, or environment requirements.
```

**Required sections:**
- Frontmatter (`name`, `description`)
- What this skill does
- When to trigger
- Workflow

**Strongly recommended:**
- Concrete examples with expected output
- Gotchas / known limitations

---

## Sanitization rules

Before submitting, remove or replace:

| Category | Example | Replace with |
|----------|---------|--------------|
| API keys / tokens | `sk-ant-...`, `ghp_...` | `YOUR_API_KEY` |
| Personal file paths | `/Users/alice/Documents/my-app/` | `/path/to/your/flutter/project` |
| Company internal hosts | `git.company.internal` | `<your-git-host>` |
| Personal email | `alice@company.com` | `<your-email>` |
| Team member names | `@bob` | `<team-member>` |
| Firebase project IDs | `my-company-prod` | `<your-firebase-project>` |
| Real app bundle IDs | `com.mycompany.app` | `com.example.app` |

If a placeholder is necessary for the skill to work, document it in the skill's README or in the root `README.md` under "Sanitized placeholders".

---

## Language policy

- **Chinese or English** is fine — pick whichever makes the skill clearest.
- Code snippets / command examples should work as-is (English terminal output).
- Skill `description` frontmatter should include at least English keywords so cross-language teams can trigger it.

---

## Commit & PR guidelines

- **One skill per PR** unless tightly coupled.
- **Commit messages** — short imperative, in the language you prefer. Examples:
  - `feat(flutter-verify): add widget tree inspection step`
  - `docs(readme): fix broken link to figma-use`
  - `新增 foo-bar skill`
- **PR description** — explain what problem the skill solves, how you tested the triggers, and any limitations.
- **CI** — none yet; manual review only.

---

## Code of Conduct

This project follows the [Contributor Covenant v2.1](./CODE_OF_CONDUCT.md). Be kind, be specific, assume good faith.
