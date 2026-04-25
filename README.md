# Flutter Claude Skills

[![Skills](https://img.shields.io/badge/skills-67-blue)](./skills)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Maintained](https://img.shields.io/badge/maintained-yes-brightgreen)](https://github.com/ImL1s/flutter-claude-skills/commits/main)
[![Claude Code](https://img.shields.io/badge/claude--code-compatible-8A63D2)](https://claude.com/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](./CONTRIBUTING.md)

A curated collection of [Claude Code](https://claude.com/claude-code) skills for **Flutter / Dart development, testing, mobile app release workflows, and AI-assisted design-to-code pipelines**.

Extracted and sanitized from real-world mobile app development experience.

---

## Table of Contents

- [Why this repo?](#why-this-repo)
- [Quick Start](#quick-start)
- [Start here](#start-here) — decision tree for your task
- [Playbooks](#playbooks) — cross-skill composition patterns
- [What's inside](#whats-inside)
- [Installation](#installation)
- [Skill anatomy](#skill-anatomy)
- [Sanitized placeholders](#sanitized-placeholders)
- [Contributing](#contributing)
- [License](#license)
- [Related](#related)

---

## Why this repo?

Claude Code skills are reusable, triggerable knowledge packs that the agent loads when your task matches the trigger conditions. Building a solid skill library takes time — you have to discover the patterns, test them in real workflows, and iterate until the agent reliably picks the right one.

This repo gives you a **production-tested starting point** for Flutter-centric teams:

- **Real-world origin** — every skill was extracted from active mobile app development, not invented in isolation.
- **Multi-layer coverage** — testing, debugging, design-to-code, release, monetization, and collaboration workflows.
- **Sanitized & portable** — secrets, personal paths, and company-specific references are stripped out (see [Sanitized placeholders](#sanitized-placeholders)).
- **MIT licensed** — drop it into your project, fork it, remix it.

If you're onboarding a team to Claude Code or want to skip months of trial-and-error discovering which skills actually matter for Flutter work, this is a reasonable baseline.

---

## Quick Start

```bash
git clone https://github.com/ImL1s/flutter-claude-skills.git
cp -R flutter-claude-skills/skills/flutter-verify ~/.claude/skills/
# Open Claude Code in any Flutter project — flutter-verify auto-loads on trigger
```

That's it. Repeat `cp -R` for any other skills you want, or symlink the whole `skills/` directory (see [Installation](#installation)).

---

## Start here

Pick a row by your task, then follow the "Start with" skill and the linked playbook.

| I want to... | Start with | Playbook | Category |
|---|---|---|---|
| ship a Flutter package / app to pub.dev or App Store | `writing-plans` → `flutter-verify` | [#1 Pub package release cycle](./PLAYBOOKS.md#playbook-1-pub-package-release-cycle) | Flutter core / Release |
| write a test-first feature or fix | `test-driven-development` | [#2 TDD per task](./PLAYBOOKS.md#playbook-2-tdd-per-task) | Testing methodology |
| open / review a PR with rigor | `requesting-code-review` ↔ `receiving-code-review` | [#3 Bidirectional code review](./PLAYBOOKS.md#playbook-3-bidirectional-code-review) | Code quality |
| debug an unfamiliar Flutter bug (crash, exception, hang) | `systematic-debugging` | [#4 Debug Triage](./PLAYBOOKS.md#playbook-4-debug-triage) | Debugging |
| fix a UI layout / rendering / overflow bug (visual mismatch, golden fail) | `verify-ui` → `flutter-listview-viewport-gotchas` | — | Design / UI alignment |
| implement a design from Figma | `figma-use` | [#5 Figma-to-Code Pipeline](./PLAYBOOKS.md#playbook-5-figma-to-code-pipeline) | Design / UI alignment |
| cut a store release (TestFlight / Play) | `release-preflight` | [#6 Release Preflight Chain](./PLAYBOOKS.md#playbook-6-release-preflight-chain) | Release / distribution |
| author a new Claude Code skill | `skill-creator` | [#7 Skill Authoring Loop](./PLAYBOOKS.md#playbook-7-skill-authoring-loop) | Meta / skill authoring |
| initialize Firebase + monetization in a new app | `flutter-fullstack-init` or `firebase-flutter-setup` | [#8 Firebase + Monetization Init](./PLAYBOOKS.md#playbook-8-firebase--monetization-init) | Firebase / Monetization |
| port native Android/iOS code to Flutter | `contract-based-porting` | — | Porting / refactoring |
| clean up AI-generated slop from a branch | `ai-slop-cleaner` | — | Code quality |
| drive Codex CLI from a script (success-check / diff-feed / worktree) | `codex-cli-rules` | — | Code quality |
| Figma MCP ran out of View seat quota | `figma-playwright-fallback` | — | Design / UI alignment |
| accidentally pushed a private email / API key to a public repo | [`finishing-a-development-branch`](./skills/finishing-a-development-branch/SKILL.md#rescue-leaked-secret) | — | Git workflow |
| something else | Browse [What's inside](#whats-inside) | — | — |

---

## Playbooks

Skills are most useful when **composed**. See [`PLAYBOOKS.md`](./PLAYBOOKS.md) for eight cross-skill composition patterns distilled from real usage:

1. **Pub package release cycle** — `writing-plans` → `flutter-verify`
2. **TDD per task** — `test-driven-development` → `testing-anti-patterns`
3. **Bidirectional code review** — `requesting-code-review` ↔ `receiving-code-review`
4. **Debug Triage** — `systematic-debugging` → `root-cause-tracing`
5. **Figma-to-Code Pipeline** — `figma-use` → `figma-implement-design` → `verify-ui`
6. **Release Preflight Chain** — `release-preflight` → `release-app`
7. **Skill Authoring Loop** — `skill-creator` → `writing-skills`
8. **Firebase + Monetization Init** — `flutter-fullstack-init` or `firebase-flutter-setup` → `admob-ux-best-practices`

Each playbook names the skill chain, when it applies, and anchors to worked examples in [`PLAYBOOKS.md`](./PLAYBOOKS.md).

---

## What's inside

**66 skills** organized by category. Each skill is a `SKILL.md` file that Claude Code auto-loads when its trigger conditions match.

<details>
<summary><b>Flutter core (14)</b></summary>

- `flutter-verify` — post-code-change multi-layer verification (analyze + test + widget tree + runtime errors)
- `flutter-mcp-testing` — orchestrate Marionette / Dart MCP / Mobile MCP / Codex for device testing
- `flutter-unit-testing` — write effective Dart unit tests (Riverpod providers, freezed, etc.)
- `flutter-integration-testing` — cross-module widget tests with real interactions
- `flutter-mobile-debugging` — debug on real Android devices and iOS simulators
- `flutter-pub-get-stuck` — diagnose hanging `flutter pub get` / build
- `flutter-listview-viewport-gotchas` — recycling / viewport pitfalls in CustomScrollView
- `flutter-background-tasks` — iOS BGTaskScheduler + Android WorkManager config
- `flutter-windows-ui-testing` — automate Win32 testing for Flutter desktop
- `flutter-device-crud-testing` — CRUD testing on real devices/simulators
- `flutter-api-reverse-engineering` — Frida + BoringSSL traffic interception
- `flutter-social-login` — Google / Apple Sign-In with Firebase Auth
- `flutter-fullstack-init` — end-to-end project init with Firebase / AdMob / RevenueCat
- `fvm-flutter-release` — fvm-based Flutter release workflow

</details>

<details>
<summary><b>Dart testing (3)</b></summary>

- `unit-testing-dart` — write tests that actually catch bugs, not just satisfy coverage
- `integration-testing-dart` — cross-module flow verification
- `api-contract-testing` — Flutter/Dart API contract tests + reverse engineering

</details>

<details>
<summary><b>Firebase (4)</b></summary>

- `firebase-flutter-setup` — Auth + AdMob + RevenueCat end-to-end
- `firebase-ai-logic` — Gemini integration via Firebase AI Logic (formerly Vertex AI)
- `firebase-appcheck-manager` — App Check attestation configuration
- `firebase-auth-manager` — sign-in providers / authorized domains

</details>

<details>
<summary><b>Native / cross-platform (1)</b></summary>

- `kmp` — Kotlin Multiplatform fundamentals (shared code, expect/actual, iOS integration, project setup)

</details>

<details>
<summary><b>Testing methodology (4)</b></summary>

- `test-driven-development` — red/green/refactor loop enforcement
- `testing-anti-patterns` — detect and avoid fake tests / mock overuse
- `verification-before-completion` — require fresh evidence before claiming done
- `condition-based-waiting` — replace flaky timing dependencies

</details>

<details>
<summary><b>Debugging (4)</b></summary>

- `systematic-debugging` — four-phase diagnosis workflow
- `root-cause-tracing` — trace errors back to original trigger
- `debug` — Claude Code session / repo state diagnostics (**not** for Flutter app bugs — use `systematic-debugging` for those)
- `defense-in-depth` — multi-layer input validation strategy

</details>

<details>
<summary><b>Design / UI alignment (9)</b></summary>

- `playwright-figma-scrape` — systematic Figma scraping (screenshot / token / inventory) via Playwright MCP
- `figma-rest-api-scrape` — faster/cleaner alternative via Figma REST API + PAT
- `figma-playwright-fallback` — quick fallback when Figma MCP quota exhausts
- `figma-use` — official Figma MCP prerequisite
- `figma-implement-design` — translate Figma to production code
- `verify-ui` — real-device UI comparison vs Figma
- `visual-verdict` — structured screenshot comparison verdict
- `verify-ui-auto` — ImageMagick SSIM / Golden Test automation
- `webapp-testing` — Playwright-based local webapp testing

</details>

<details>
<summary><b>Release / distribution (6)</b></summary>

- `release-app` — global TestFlight / Google Play release
- `release-preflight` — pre-release checklist (build number / signing / metadata)
- `store-console-playbooks` — App Store Connect + Google Play Console browser automation
- `mobile-store-upload-cli` — iOS/Android CLI upload
- `store-screenshot-beautifier` — store listing screenshot beautification
- `macos-notarization` — macOS app notarization

</details>

<details>
<summary><b>Monetization (3)</b></summary>

- `admob-ux-best-practices` — AdMob placement best practices
- `apple-appstore-manager` — App Store Connect API management
- `revenuecat-manager` — RevenueCat IAP configuration

</details>

<details>
<summary><b>Brand / style (1)</b></summary>

- `brand-guidelines` — Anthropic brand colors / typography application

</details>

<details>
<summary><b>Collaboration (6)</b></summary>

- `receiving-code-review` — how to process review feedback
- `requesting-code-review` — how to request reviews
- `review-fix-commit` — review → fix → commit cycle
- `subagent-driven-development` — dispatch fresh-context subagents
- `dispatching-parallel-agents` — parallelize independent failure investigation
- `testing-skills-with-subagents` — validate skills against subagent pressure

</details>

<details>
<summary><b>Planning / skill authoring (7)</b></summary>

- `brainstorming` — idea refinement before implementation
- `executing-plans` — batch execution with review checkpoints
- `writing-plans` — detailed plan authoring
- `writing-skills` — skill authoring guidelines
- `skill-creator` — create / modify / measure skills
- `deep-interview` — Socratic requirements interview
- `deep-dive` — trace + interview pipeline

</details>

<details>
<summary><b>Porting / refactoring (1)</b></summary>

- `contract-based-porting` — zero-regression port via contract TDD

</details>

<details>
<summary><b>Code quality (2)</b></summary>

- `ai-slop-cleaner` — regression-safe AI slop cleanup
- `codex-cli-rules` — operational rules for driving Codex CLI from scripts (success-check / diff-feed / worktree / stdin)

</details>

<details>
<summary><b>Git workflow (2)</b></summary>

- `using-git-worktrees` — feature isolation with worktrees
- `finishing-a-development-branch` — branch integration decisions

</details>

---

## Installation

Drop any skill directory into your Claude Code skills path:

```bash
# User-global skills (available in all sessions)
cp -R skills/<skill-name> ~/.claude/skills/

# Project-local skills (only for one project)
cp -R skills/<skill-name> <your-project>/.claude/skills/
```

Or clone and symlink:

```bash
git clone https://github.com/ImL1s/flutter-claude-skills.git
ln -s "$(pwd)/flutter-claude-skills/skills/flutter-verify" ~/.claude/skills/flutter-verify
```

Claude Code auto-discovers skills on session start. Trigger conditions are declared in each `SKILL.md` frontmatter.

---

## Skill anatomy

Each skill is a directory containing at minimum a `SKILL.md` with YAML frontmatter:

```yaml
---
name: skill-name
description: |
  One-line summary + when to trigger.
  Triggers: keywords / conditions that activate this skill.
---

## Skill content
...
```

Some skills include helper scripts / templates / reference snippets in the same directory.

---

## Sanitized placeholders

A few skills contain placeholder values you should replace for your project:

| Skill | Placeholder | Replace with |
|-------|-------------|--------------|
| `flutter-verify` | `/path/to/your/flutter/project` | Your actual Flutter project path |
| `figma-rest-api-scrape` | `YOUR_FIGMA_FILE_KEY` | Your Figma file key (from URL) |
| `figma-playwright-fallback` | `<your-figma-email>` | Your Figma account email |

---

## Contributing

PRs welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for detailed guidelines, or the short version:

1. Follow the `SKILL.md` frontmatter format
2. Include clear **trigger conditions** and **when to skip**
3. Add concrete examples with expected output
4. No hardcoded secrets / personal info / company-specific paths
5. Prefer Chinese or English (or both) — whichever serves clarity better

Also see:
- [Code of Conduct](./CODE_OF_CONDUCT.md)
- [Changelog](./CHANGELOG.md)

---

## License

MIT — see [LICENSE](LICENSE).

Originally authored by skill authors including Anthropic, oh-my-claudecode contributors, and this repo's maintainer. Each skill retains its original attribution in-file where applicable.

---

## Related

- [Claude Code](https://claude.com/claude-code) — Anthropic's official CLI
- [oh-my-claudecode](https://github.com/oh-my-claudecode/oh-my-claudecode) — multi-agent orchestration layer
- [Claude Code skills documentation](https://docs.claude.com/en/docs/claude-code/skills)
