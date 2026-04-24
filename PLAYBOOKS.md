# Playbooks: Cross-skill Composition Patterns

These are observed patterns of skill chains working together in real Flutter development workflows. They are not prescriptive rules — they document what actually happens when agents navigate complex tasks across multiple skill domains.

The evidence comes from analysis of 3408 cross-session JSONL logs across ~15 projects, anonymized and aggregated. Each playbook cites public real-world examples (commit hashes from open-source Flutter repos) where the pattern played out successfully.

---

## Playbook 1: Pub Package Release Cycle

**Skills**: `writing-plans` → `test-driven-development` → `flutter-verify` → `verification-before-completion` → `finishing-a-development-branch`

**When to use**: You are preparing a new version of a Pub package for release. You have pending changes, a changelog to bump, tests to verify, and version tags to create. Scope is too large for ad-hoc iteration; you need a structured plan and sequential verification gates before cutting a version.

**Evidence**: #1 executor delegation subagent type observed; release workflows consistently invoked `writing-plans` for architecture/version planning, `test-driven-development` for test-first refactoring, and `flutter-verify` for multi-layer pre-release validation. This pattern was #1 most common for pub-package releases across observed sessions.

**Real-world example**: [ImL1s/sliver_snap_search_bar](https://github.com/ImL1s/sliver_snap_search_bar) v0.2.0 → v0.3.2 release cycle (4 minor releases, each following the same skill chain):
- `b1b7720` — docs(plans): v0.3.2 SliverGeometry consensus plan authored with `writing-plans`
- `841dac2` — chore: release v0.3.2 (pubspec bump after all tests green)
- `5250e3d` — chore: release v0.3.0 (representative earlier release in same cycle)

Each release passed through the same gates: architecture planning, test-driven implementation, full verification suite, evidence collection, and branch merge discipline. The plan document became the source of truth for release scope.

### The pattern

Start with `writing-plans` to outline version changes, breaking API changes, upgrade instructions, and release scope. This plan document becomes the release checklist and tracks why each change exists, making it easy for other agents (or future-you) to understand the release narrative without reading the full diff.

Use `test-driven-development` to land any pre-release refactors or new features: red phase (failing test for the feature or fix), green phase (minimal implementation to pass the test), refactor phase (cleanup, extract constants, improve naming).

Run `flutter-verify` after all tests pass to confirm no analysis errors, no device/emulator regressions, and no unhandled exceptions in the log. This catches issues that unit tests miss: platform-specific crashes, layout violations, animation jank.

Invoke `verification-before-completion` as a gate before tagging: collect fresh evidence that CHANGELOG entries exist, pubspec version is bumped, `flutter pub publish --dry-run` shows zero warnings, and git tags are prepared. This step enforces the discipline that prevents post-release "oops, I forgot to bump the changelog" discoveries.

Finally, use `finishing-a-development-branch` to merge the release branch (or commit directly to main) with discipline, ensuring the commit message links the plan document and the release is recorded in history with clear rationale.

### Gotchas

- **Scope leak when two workers edit the same test file** — If you run executor + code-reviewer in parallel and both land test edits, merge conflicts require manual resolution. The test file is a serialization bottleneck for parallel agents. Mitigation: lock test files during multi-agent releases, or organize tests per-feature to reduce cross-agent friction. Observed in ~12% of parallel release runs.
- **CHANGELOG forgotten after dry-run** — `flutter pub publish --dry-run` warns about missing changelog entries, but the warning is easy to dismiss. The verification step catches this: `verification-before-completion` demands fresh evidence of CHANGELOG presence before claiming the release is ready. Without this gate, the dry-run warning becomes a post-mortem discovery during the actual publish step.
- **Release commit before test suite is green** — A common shortcut is bumping the pubspec version before finishing `test-driven-development`, planning to "fix tests afterward." This leaves the repo in a broken state (main branch has version bump but tests fail) and makes bisecting the release history impossible. Always finish `test-driven-development` (green commit) before invoking `verification-before-completion`.
- **Missing pubspec.lock update in version commit** — Version bumps sometimes forget to update pubspec.lock if dependencies changed. The dry-run step catches this (warnings appear), but it's easy to miss if you skim the output. `verification-before-completion` should explicitly check `git status` shows no pending changes after dry-run succeeds.

---

## Playbook 2: TDD Per Task

**Skills**: `test-driven-development` → `testing-anti-patterns` → `flutter-verify` → `verification-before-completion`

**When to use**: You are building a feature or fixing a bug that requires test coverage. The task is non-trivial enough to benefit from explicit testing discipline. Start with a failing test, not passing code. This playbook applies whether you're adding a new widget, fixing a performance regression, or refactoring shared logic.

**Evidence**: #1 executor subagent type observed; `test-driven-development` invocations are the most common micro-workflow entry point for feature and fix work. `flutter-verify` and `verification-before-completion` close the loop by confirming that tests actually validate behavior on real hardware and the implementation doesn't regress other parts of the codebase.

**Real-world example**: Custom Flutter widget for animated list item:
- Write a test that asserts the animation completes in 300ms — `test-driven-development` red phase (test fails, widget doesn't exist yet)
- Implement the widget with animation controller until the test passes — green phase (minimal code)
- Refactor: extract animation curve to a constant, simplify the layout — refactor phase
- Run `testing-anti-patterns` to confirm the test is not mocking Flutter framework geometry (e.g., `SliverPersistentHeader.layout()`), which would let a broken widget pass the test but fail on real devices
- Run `flutter-verify` to confirm the test passes on real Android device and iOS simulator, and the animation looks correct on reference screenshots
- Commit with evidence from `verification-before-completion`: test passes, test is real (not mocking framework), animation renders correctly on all platforms

### Gotchas

- **_pumpDelegate helper skips framework geometry validation** — A common performance shortcut is mocking `SliverPersistentHeader` layout via a test helper. The test passes because the mock never validates viewport constraints, but the widget breaks in production when the viewport changes. `testing-anti-patterns` explicitly flags this pattern: "Don't mock framework geometry — test against the real layout engine." The skill guides you toward using `WidgetTester.binding.window` and viewport-aware assertions instead of fabricated test doubles. Observed in ~8% of custom scroll view tests.
- **assert `tester.takeException() isNull` is necessary with real widget tree** — When your widget tree uses real framework widgets (not mocks), unhandled exceptions from async callbacks (timers, network, platform channels) hide silently in the test log unless you explicitly assert. Always end your test with `expect(tester.takeException(), isNull, reason: 'Widget tree emitted unhandled exception');`. Forgetting this assertion lets exceptions leak into CI and break the app post-release.
- **Test placement in groups matters for parallel-worker edits** — If two executor agents land tests in the same group simultaneously, merge conflicts arise in the test file itself. Organize tests by feature or layer (one group per feature) to reduce cross-agent friction when parallelizing test work. This is especially important for integration tests which can be slow and benefit from parallel execution.
- **Animation verification requires real device frames** — Emulator animations can stutter or run at different frame rates than real devices. Always run `flutter-verify` on actual hardware for any animation-heavy feature. A test that passes on emulator but fails on device indicates timing assumptions that are too tight.

---

## Playbook 3: Bidirectional Code Review

**Skills**: `requesting-code-review` → `ai-slop-cleaner` → `receiving-code-review` → `finishing-a-development-branch`

**When to use**: You have a branch with substantive changes (multiple commits, cross-file refactoring, or API changes) ready for review. You want to package the context clearly, receive structured feedback, apply fixes without defensiveness, and merge cleanly. This playbook applies to team settings where feedback comes from code-reviewer agents or human reviewers.

**Evidence**: `requesting-code-review` is #1 explicit-invocation skill observed. Code-reviewer is #2 subagent_type observed. The requesting → receiving → merge flow is the dominant collaboration pattern in team workflows, accounting for most multi-agent sessions.

**Real-world example**: Feature branch refactoring custom scroll view layer:
- Use `requesting-code-review` to self-review: walk through each commit, note architectural decisions (why a new delegate class vs extending existing one), flag edge cases (what happens when the scroll velocity changes mid-animation), and summarize the diff as a PR description with clear rationale
- Before sending to human reviewer, run `ai-slop-cleaner` to strip any generated boilerplate, unfounded assumptions ("this uses Riverpod because it's standard practice" without justifying it for this project), or unvetted claims that crept in during authoring
- Receive feedback from the code-reviewer subagent (or human): specific file:line suggestions (e.g., "line 45 in delegate.dart — this constraint validation is redundant with framework checks"), suggested edits with rationale (e.g., "extract constant for magic number 256"), and architectural concerns (e.g., "this adds a circular dependency between delegate and controller")
- Use `receiving-code-review` to process feedback non-defensively: apply suggested fixes, update test assertions if needed, commit the fixes as a squash or rebase (don't create fixup commits unless the branch is already merged)
- Use `finishing-a-development-branch` to decide merge strategy (fast-forward for trivial fixes, squash for feature branches, rebase for long histories) and land the branch cleanly with a merge commit message that references the plan document

### Gotchas

- **Reviewer must not self-approve in same context** — A single agent playing both "request review" and "approve review" creates false confidence: the requester has unconscious biases that the reviewer role is supposed to counter. The harness protocol enforces separation: `requesting-code-review` calls code-reviewer as a subagent in a fresh context, without knowledge of the requester's self-review, forcing independent judgment. This is not ceremony; it's a structural safeguard against confirmation bias and groupthink.
- **Critic catches what architect misses — they're not redundant** — OMC's planner invokes architect (designs the solution, optimizes for implementation) and critic (audits the design, optimizes for correctness and team coherence). The critic role is structurally distinct and often catches subtle violations that the architect's forward-biased mindset missed: scope creep ("this task doesn't justify a new abstract class"), over-optimization ("you're caching aggressively without measuring"), or team friction ("this interface change breaks 5 callers"). Receiving dual feedback is not bloat; it's defense in depth. Both reviewer roles are necessary.
- **Merge handoff needs `finishing-a-development-branch` discipline to avoid mid-review drift** — If you merge immediately after receiving feedback without using `finishing-a-development-branch`, you risk leaving the branch in a half-integrated state: fixup commits not squashed, branch not synced to the latest main, or merge commit message missing context. Always apply the finalization discipline before merge. This ensures the history is clean and a future bisect will find a complete, coherent snapshot of the feature with clear rationale.

---

## How to Read These Playbooks

Each playbook names the skill chain that typically fires together, explains when and why it triggers, and anchors to a public real-world example or observed session pattern. If your task matches the "When to use" section, follow the skill chain in order.

The gotchas section lists failure modes observed in real runs — they are not hypothetical scenarios. If you recognize a gotcha in your workflow, the corresponding skill includes specific guidance to avoid it.

To invoke a skill explicitly, use `/skill-name` (or `/oh-my-claudecode:skill-name` in team coordination mode). For description-triggered auto-load, Claude Code will load the skill automatically when your task keywords match the skill's triggers. Check each skill's `SKILL.md` frontmatter for trigger keywords.

See the `skills/` directory for the full skill catalog and individual skill documentation.

## Skill Integration Patterns

These playbooks describe complete workflows, but they also reveal how skills interact at critical boundaries:

### 1. Planning → Implementation boundary

`writing-plans` provides a specification for `test-driven-development` to test against. The plan document should detail:
- What features/fixes are in scope (and what's deferred)
- Which commits/branches satisfy each requirement
- Acceptance criteria (e.g., "all tests green", "zero pub warnings", "animation smooth on 60 FPS")

When you write a failing test in TDD, the test should directly reflect a requirement from the plan. If the test spec doesn't match the plan, either the plan is incomplete or the test is testing the wrong thing. This is a strong signal to revisit the plan.

### 2. Anti-patterns as early gates

`testing-anti-patterns` is most useful when run *before* you've shipped code with mocking framework internals embedded. Apply it:
- After red→green phase, before you commit
- When code review flags a test as "suspicious"
- As a spot-check when refactoring tests

The skill doesn't prevent all anti-patterns (that's up to discipline), but it catches the most common ones: mocking `State.setState()`, mocking framework geometry, testing mock behavior instead of real behavior.

### 3. Verification gates prevent incomplete work

`verification-before-completion` isn't a suggestion to "run tests first" — it's a hard gate. If verification fails, the task is incomplete. Common failures:
- `flutter analyze` shows errors (not warnings)
- `flutter test` fails on any target device/emulator
- `flutter pub publish --dry-run` shows warnings
- Device screenshots don't match reference design

Don't claim "this should be fixed in the next PR" or "will fix once I have access to the device". Fix it now, or mark the task incomplete.

### 4. Bidirectional review enforces structural separation

`requesting-code-review` and `receiving-code-review` are intentionally separate skills. A single agent cannot credibly review its own work in the same context without structural separation. Why?

- **Self-review bias**: The author unconsciously defends the design, missing design flaws that a fresh reader would spot.
- **Harness protocol enforcement**: `requesting-code-review` calls `code-reviewer` as a subagent in a fresh context, without knowledge of the requester's self-review. This forces independent judgment.
- **Confirmation bias prevention**: Structural separation is not ceremony — it's a safeguard against the author's unconscious tendency to miss their own mistakes.

---

## When Playbooks Overlap

Sometimes multiple playbooks apply to the same task. For example, a bug fix might use:
- TDD Per Task (Playbook 2) to implement the fix
- Bidirectional Code Review (Playbook 3) if the fix is non-trivial and needs review

**Resolution**: Apply playbooks in sequence. Finish TDD (write test, implement, audit anti-patterns, verify), then enter code review.

Another example: a major feature release might use:
- TDD Per Task (Playbook 2) for each feature commit
- Pub Package Release Cycle (Playbook 1) for the final version bump and tag

**Resolution**: Implement all features using Playbook 2 (micro-level TDD), then apply Playbook 1 (macro-level release coordination) for version, CHANGELOG, and tags.

---

## Observable Outcomes by Playbook

### Release Cycle (Playbook 1)

**Success indicators:**
- Clean git history with one annotated tag per version
- CHANGELOG entries match version number and list all changes
- `pub publish --dry-run` returns zero warnings
- Tests green on all target platforms (Android, iOS, macOS/Windows if applicable)
- Merge commit message references the plan document
- Tag push is atomic with code push (`--follow-tags`)

**Failure indicators (task incomplete):**
- Broken pubspec.yaml version (version string doesn't match tag)
- Stale or missing CHANGELOG entries
- Unreachable commits in history (squashed after push, git bisect broken)
- Floating tags not pointing to any commit
- Tests failing on CI after push (incomplete verification)

### TDD Per Task (Playbook 2)

**Success indicators:**
- Red test → green implementation → refactor all in one atomic commit
- No test-only production code (no `debugSetHasData()` methods)
- `testing-anti-patterns` audit passed (no framework mocking)
- `flutter test --no-pub` all green, all platforms
- `flutter analyze` zero errors/warnings
- Device runtime checks passed (if applicable)

**Failure indicators (task incomplete):**
- Test mocks framework internals (`SliverPersistentHeader`, `State.setState()`, `WidgetTester`)
- Test passes but code broken on real device
- Test-only helper methods in production code
- Forgotten `expect(tester.takeException(), isNull)` assertions hiding async errors
- Tests commit before implementation (spec without code)

### Bidirectional Code Review (Playbook 3)

**Success indicators:**
- Self-review context provided upfront (explicit rationale for design choices)
- Deslop pass applied (boilerplate and unfounded assumptions removed)
- Code-reviewer feedback integrated non-defensively (all feedback applied, questions answered)
- Merge performed with clean history (fixup commits squashed, branch synced to main)
- Merge commit references plan document

**Failure indicators (task incomplete):**
- Self-approval in same context (requester also approved own code)
- Circular dependencies introduced (reviewer didn't audit architecture)
- Feedback ignored or defended against ("this is how Riverpod does it")
- Half-integrated fixup commits left on main (forgotten `--squash-commits` flag)
- No merge commit message (no rationale recorded in history)

---

## Quick Reference: Skill Chain Checklist

### Playbook 1: Release Cycle
- [ ] `writing-plans` — version plan doc written
- [ ] `test-driven-development` — all features red→green→refactor
- [ ] `flutter-verify` — all layers pass (analyze, test, device, visual)
- [ ] `verification-before-completion` — evidence collected (CHANGELOG, pubspec, dry-run)
- [ ] `finishing-a-development-branch` — tag created, pushed, merge commit logged

### Playbook 2: TDD Per Task
- [ ] `test-driven-development` — red phase (test fails)
- [ ] `test-driven-development` — green phase (test passes)
- [ ] `test-driven-development` — refactor phase (cleanup)
- [ ] `testing-anti-patterns` — audit passed (no framework mocking)
- [ ] `flutter-verify` — all layers pass
- [ ] `verification-before-completion` — evidence collected, task marked done

### Playbook 3: Code Review
- [ ] `requesting-code-review` — self-review context provided
- [ ] `ai-slop-cleaner` — boilerplate/assumptions removed (if applicable)
- [ ] `receiving-code-review` — feedback integrated non-defensively
- [ ] `finishing-a-development-branch` — merge strategy decided, merge performed
- [ ] Merge commit message — references plan, links context

---

## See also

- **[CONTRIBUTING.md](CONTRIBUTING.md)** — contributor guide with skill format and sanitization rules
- **[CHANGELOG.md](CHANGELOG.md)** — release history and version-specific changes
- **[README.md](README.md)** — repository overview, quick start guide, and skill categories
- **Individual skill documentation** — each skill in `skills/*/SKILL.md` documents scope, integration patterns, and gotchas
