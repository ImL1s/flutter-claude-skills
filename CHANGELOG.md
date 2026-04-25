# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for milestone releases.

## [Unreleased]

### Fixed
- `apple-appstore-manager/scripts/app_review_watch.sh` — repaired broken `APPS` array syntax (stray `)"` mid-array caused `bash -n` to fail; script could not execute).
- `visual-verdict/SKILL.md` — removed unresolved `{{ARGUMENTS}}` template artifact that was being injected literally into agent context.
- `skills/figma-use`, `skills/figma-implement-design`, `skills/kmp` — replaced dangling symlinks (pointing to a maintainer-local `.agents/skills/` directory that does not exist in the public repo) with the actual SKILL.md content. These three skills had been listed in the README and CHANGELOG since the initial release but never shipped real content on GitHub. `figma-use` now also ships its 17-file `references/` directory (Figma plugin API docs, design-system patterns, gotchas).
- 4 ghost cross-references removed: `skills/figma-implement-design/SKILL.md` no longer points at the non-existent `figma-generate-design`, `figma-code-connect-components`, or `figma-create-design-system-rules` skills (now points at the underlying Figma MCP tools instead). `skills/figma-use/SKILL.md` no longer redirects to the non-existent `figma-generate-design`. `skills/apple-appstore-manager/SKILL.md` no longer references `audit-team-apps.sh` (replaced with App Store Connect API documentation reference).

### Changed
- README "Start here" decision tree gains a row for UI / layout / rendering bugs routing to `verify-ui` and `flutter-listview-viewport-gotchas`. The previous Debugging row only covered crash / exception / hang triage.
- README Debugging category strengthens disambiguation for the bare `debug` skill: it is now explicitly labeled as Claude Code session diagnostics and **not** for Flutter app bugs (use `systematic-debugging` for those).
- 4 OMC-coupled skills (`deep-dive`, `deep-interview`, `ai-slop-cleaner`, `visual-verdict`) carry `requires-omc: true` in their frontmatter. The new field is documented in CONTRIBUTING.md alongside the other optional fields (`level`, `triggers`, `pipeline`).
- `skills/verify-ui-auto/SKILL.md` and `skills/flutter-verify/SKILL.md` descriptions are now bilingual: English summary + explicit English trigger keyword list, with original Chinese preserved. Previously these two skills had Chinese-only descriptions which reduced activation probability in English-language sessions.

### Removed
- Legacy `superpowers:` namespace prefix stripped from 20 occurrences across 8 skills (`systematic-debugging`, `executing-plans`, `brainstorming`, `testing-skills-with-subagents`, `writing-plans`, `requesting-code-review`, `writing-skills`, `subagent-driven-development`). Bare skill names are the canonical format documented in `writing-skills/SKILL.md`. The `superpowers:` prefix was a legacy from a different skill system and did not resolve in OMC's current loader.

### Notes (history rewrite)
- Git author email rewritten from a personal hotmail address to GitHub's privacy-safe noreply form (`16792527+ImL1s@users.noreply.github.com`) across all 29 commits using `git filter-repo --email-callback`. All commit SHAs changed; if you had a fork or pinned to a specific SHA, re-pull from `main`. File content is unchanged.

### Removed
- `skills/kotlin-multiplatform/` — fabricated stub with fake frontmatter schema (`sasmp_version`, `bonded_agent`, etc. — never read by Claude Code harness) and unrelated Python filler in `references/PATTERNS.md` (categorized as "Database"). Use `skills/kmp/` (604-line canonical KMP skill). If you forked and referenced the path, update to `kmp`.

### Added
- **PLAYBOOKS.md**: 5 new cross-skill composition patterns (Playbooks #4-#8): Debug Triage, Figma-to-Code Pipeline, Release Preflight Chain, Skill Authoring Loop, Firebase + Monetization Init.
- **README.md**: "Start here" decision-tree table with 11 task rows + playbook/skill cross-references.
- **All 66 skills**: `## Related skills` sections with skill composition guidance (1-4 entries per skill, or explicit fallback for design-system/methodology skills with no natural partners).
- **Disambiguation mandate**: 5 overlap-pair disambiguations (e.g., `debug` vs `systematic-debugging`, `flutter-verify` vs `verify-ui`) to clarify when each skill applies.
- `CONTRIBUTING.md` — full contributor guide (SKILL.md format, sanitization rules, language policy).
- `CODE_OF_CONDUCT.md` — Contributor Covenant v2.1.
- `CHANGELOG.md` — this file.
- `.github/ISSUE_TEMPLATE/` — skill request, skill bug, and config templates.
- `.github/PULL_REQUEST_TEMPLATE.md` — PR checklist.
- `.github/workflows/skill-check.yml` + `.github/scripts/check_skills.py` — P0 CI on every PR: frontmatter YAML validation, frontmatter `name` matches directory, README badge skill-count sync, kebab-case directory name check. Skips `_template/`.
- `skills/_template/SKILL.md` — copy-paste starter for new skills with all required sections pre-populated. Excluded from skill-count via `_*` filter.
- README badges, table of contents, "Why this repo?" section, collapsible categories, Quick Start.
- GitHub repo topics: `flutter`, `dart`, `claude-code`, `anthropic`, `skills`, `ai`, `mobile-development`, `agentic`, `llm`, `developer-tools`.

---

## [0.1.0] — 2026-04-23

Initial public release.

### Added

**67 curated skills** organized by category:

- **Flutter core (14)** — verify, mcp-testing, unit/integration testing, mobile debugging, pub-get stuck, listview gotchas, background tasks, Windows UI, device CRUD, API reverse engineering, social login, fullstack init, fvm release.
- **Dart testing (3)** — unit, integration, API contract.
- **Firebase (4)** — Flutter setup, AI Logic (Gemini), App Check, Auth manager.
- **Native / cross-platform (2)** — Kotlin Multiplatform, KMP fundamentals.
- **Testing methodology (4)** — TDD, anti-patterns, verification-before-completion, condition-based-waiting.
- **Debugging (4)** — systematic-debugging, root-cause-tracing, debug, defense-in-depth.
- **Design / UI alignment (9)** — playwright-figma-scrape, figma-rest-api-scrape, figma-playwright-fallback, figma-use, figma-implement-design, verify-ui, visual-verdict, verify-ui-auto, webapp-testing.
- **Release / distribution (6)** — release-app, release-preflight, store-console-playbooks, mobile-store-upload-cli, store-screenshot-beautifier, macos-notarization.
- **Monetization (3)** — admob-ux-best-practices, apple-appstore-manager, revenuecat-manager.
- **Brand / style (1)** — brand-guidelines.
- **Collaboration (6)** — receiving/requesting code review, review-fix-commit, subagent-driven-development, dispatching-parallel-agents, testing-skills-with-subagents.
- **Planning / skill authoring (7)** — brainstorming, executing-plans, writing-plans, writing-skills, skill-creator, deep-interview, deep-dive.
- **Porting / refactoring (1)** — contract-based-porting.
- **Code quality (1)** — ai-slop-cleaner.
- **Git workflow (2)** — using-git-worktrees, finishing-a-development-branch.

### Notes
- All skills sanitized: no secrets, no personal paths, no company internal references.
- MIT licensed.
- Targeted at Claude Code; frontmatter triggers auto-load skills when conditions match.

[Unreleased]: https://github.com/ImL1s/flutter-claude-skills/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ImL1s/flutter-claude-skills/releases/tag/v0.1.0
