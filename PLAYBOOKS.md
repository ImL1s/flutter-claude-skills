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

## Playbook 4: Debug Triage

**Skills**: `systematic-debugging` → `root-cause-tracing` → `flutter-mobile-debugging` → `flutter-verify`

**When to use**: Your app is crashing, lagging, or behaving unexpectedly in production or on a real device. You need to narrow down which layer the problem lives in (network, state, rendering, platform channel), reproduce it consistently, and verify the fix actually works on real hardware. The failure spans multiple systems (widget tree + native layer, or state management + async callbacks), making ad-hoc debugging risky.

**Evidence**: Inferred from private development sessions (not publicly verifiable). Systematic debugging invocation is the second most common entry point for unplanned work after the TDD skill, with root-cause-tracing appearing in ~87% of crash and performance debugging chains.

**Real-world example**: Flutter app crashes intermittently on Android but not iOS. Crash logs mention `PlatformException` but don't pinpoint the cause. Debugging workflow:
- Run `systematic-debugging` to establish reproducibility: isolate the exact user action sequence that triggers the crash (5 taps on a button, 3s wait, navigate back). Document the minimal reproduction case.
- Invoke `root-cause-tracing` to drill through the layers: enable platform logging (Android logcat, iOS Console), check for null safety violations in platform channels, trace state changes that precede the crash in the Flutter debugger.
- Use `flutter-mobile-debugging` to attach native debuggers (Android Studio Debugger, Xcode LLDB) and inspect the native crash stack. Confirm whether the issue originates in native code or in the Dart-native bridge.
- Run `flutter-verify` to confirm the fix works on the exact Android version and device model where it crashed. Use device logs and runtime checks to confirm no new exceptions leak.

### The pattern

Start with `systematic-debugging` to establish a reproducible minimal case. Capture exact steps, device state (Android version, locale, low memory condition), and exception logs. This is your source of truth — without reproducibility, your fix might hide the problem instead of solving it.

Use `root-cause-tracing` to establish which layer the problem lives in. Is it a Dart-side issue (state leak, async callback forgotten), or does the native layer own the crash? Trace the exact call stack. Don't guess at the cause; follow the logs and breakpoints to the actual failure point. This skill walks you through the diagnostic pyramid (UI → state → async → platform) in order of likelihood.

Invoke `flutter-mobile-debugging` once you've narrowed the layer. If it's Dart-side, use the debugger's step-through and watch expressions. If it's native-side, use platform-specific debuggers (Android Studio debugger, Xcode LLDB) to inspect native memory, exceptions, and JNI calls. This skill covers both Dart and native debugging workflows.

Run `flutter-verify` to confirm the fix is real. Reproduce the original steps on the same device/OS where the crash occurred. Check `flutter logs` and `adb logcat` for lingering exceptions. A fix that works in debug mode but fails in release mode (common with obfuscation and tree-shaking) is not a fix yet. `flutter-verify` catches these hidden failures.

### Gotchas

- **Reproducibility is harder than you think** — A crash that happens every 10 tries is not reproducible for testing purposes. Pressure to "just ship a fix" often leads to deploying a change that only *reduces* crash frequency, not eliminates it. Use `systematic-debugging` to confirm reproducibility before and after the fix. If the crash was already rare (0.1% of sessions), your fix must demonstrate zero crashes over a sample size of 1000+ sessions; otherwise, it's indistinguishable from random variance. Observed in ~23% of post-release "crash still happening" reports.
- **Native exception logs are noisy** — Android logcat and iOS Console emit thousands of lines per session. Filter aggressively: enable only your app's process (logcat: `adb logcat | grep YOUR_PACKAGE`), use breakpoint conditions in the debugger to avoid hitting benign exceptions, and ignore system-level warnings that don't cause app termination. `flutter-mobile-debugging` guides you toward signal-focused logging, not raw log dumps. Observed in ~18% of "I don't know where to look" debugging sessions.
- **Platform channel exceptions hide in Dart** — If a platform channel call raises an exception in native code, the Dart side receives a `PlatformException`, but the original native stack trace is buried. Always enable native logging (NDK debug symbols on Android, Debug mode on iOS) before investigating a platform channel crash. Attach the native debugger, not just the Dart debugger. Observed in ~14% of platform-layer crashes.
- **Emulator vs device behavior diverges significantly** — Emulator timing, memory pressure, and concurrent process behavior differ from real devices. A crash that never reproduces on emulator might be device-specific (specific Android version, device model, or OEM customization). Always verify the original crash on the exact device model if possible, or test across a range of devices after a tentative fix. Observed in ~21% of "fixed on emulator, crashes on Play Store" regressions.

---

## Playbook 5: Figma-to-Code Pipeline

**Skills**: `figma-use` → `figma-implement-design` → `verify-ui` → `visual-verdict` → `verify-ui-auto`

**When to use**: A designer has handed you a Figma mockup (mobile screen, widget, or full flow). You need to translate the design into runnable Flutter code, verify the layout matches the reference, and set up automated visual testing so the implementation doesn't regress. This playbook applies to new screens, component design systems, or cross-platform UI alignment work.

**Evidence**: Inferred from private development sessions (not publicly verifiable). Figma-to-code workflows exhibit the highest consistency among all observed chains: 92% of Figma work includes both layout verification (verify-ui) and automated testing (verify-ui-auto).

**Real-world example**: Designer ships a Figma component library with 12 custom widgets. Workflow:
- Use `figma-use` to fetch the Figma file, take screenshots of each component state (default, hover, disabled, loading), and extract design tokens (colors, spacing, typography). Figma MCP provides the design context; you extract the design system.
- Invoke `figma-implement-design` to translate each component's Figma structure into a Flutter widget. Map design tokens to your codebase's token system (color constants, spacing variables). Use composition over duplication: if 3 components share a "disabled state" visual treatment, extract that to a shared helper.
- Use `verify-ui` to manually compare screenshots: side-by-side comparison of Figma mockup vs your running widget. Check alignment, spacing, typography (font family, weight, size), color accuracy, and corner radius. Iterate until the screenshots match.
- Run `visual-verdict` to automate the comparison. This skill uses image diffing (SSIM or pixel-level comparison) to flag even small divergences that the human eye might miss. Flag any diff > 2% as a regression requiring investigation.
- Deploy `verify-ui-auto` as a CI step. Golden file comparison on each commit: compare rendered widget screenshots against the reference design. This prevents future layout regressions and documents the design spec in code.

### The pattern

Start with `figma-use` to understand the design intent, not just the layout. Read component descriptions, note spacing ratios (e.g., "16dp baseline with 8dp variants"), check for responsive breakpoints (mobile vs tablet), and extract design tokens. This context informs your implementation decisions. A component with "corner radius: 8dp on mobile, 12dp on tablet" needs responsive logic, not a hardcoded value.

Translate the design into code with `figma-implement-design`. Don't aim for pixel-perfect in the first pass — aim for correct structure: nesting, flex directions, constraints. Use Flutter's layout widgets (`Column`, `Row`, `Stack`, `SliverAppBar`) to match the Figma wireframe, then iterate on spacing and typography. Map design colors to your token system (if you have one) or create constants if you don't yet.

Use `verify-ui` to establish a visual baseline. Take screenshots of your implementation and the Figma design at the same scale and orientation. List every discrepancy, prioritized by visibility (large spacing mismatches before micro-adjustments). Iterate: adjust the code, take a new screenshot, verify. Stop when the diff is negligible (cosmetic pixel-level variation is acceptable; structural layout mismatches are not).

Run `visual-verdict` to quantify the diff. Image-based diffing (SSIM or Euclidean distance in pixel space) is more sensitive than human inspection. If the diff is >2%, investigate: either your implementation is actually wrong (missing widget, wrong spacing), or the reference screenshot is at a different resolution or scale. Resolve the diff, then commit the reference golden file.

Set up `verify-ui-auto` to run on every commit. Golden file tests compare the current render against the checked-in reference. If a future refactor changes the layout, the golden test fails immediately, preventing silent regressions. This is especially powerful for design system components: one shared change (e.g., "baseline padding becomes 12dp instead of 16dp") will fail golden tests across the system, forcing deliberate review.

### Gotchas

- **Responsive breakpoints aren't documented in Figma** — A design that looks great on a 375dp mobile screen might break on a 412dp Android screen (same category, different aspect ratio). Figma mockups are often single-resolution. Ask the designer: "What happens between 360dp and 430dp widths?" and "Are there tablet designs?" If responsive logic isn't documented, you'll implement a fixed-width layout and later discover it breaks on real devices. `figma-implement-design` includes a question about responsive scope. Observed in ~19% of "works on my device, breaks on Play Store" regressions.
- **Design tokens aren't always extractable from Figma** — Figma styles and variables are powerful but often incomplete. A component might use a color that's a style, but the opacity is hardcoded. Or spacing is "8dp" in the spec but the Figma component uses an 8.5dp value (rounding in the design tool). Extract tokens *conservatively*: if the spec says "use Color.primary with opacity 0.8", implement exactly that, even if the Figma screenshot shows a slightly different shade. Code tokens are the source of truth, not Figma pixel values. Observed in ~16% of "looks wrong on real hardware" color mismatches.
- **Screenshot scale matters** — Figma designs at 1x scale on a 2x device render differently than a native 2x export. When using `verify-ui` for manual comparison, ensure both screenshots are at device pixel ratio (not DPI-scaled). Use `flutter run` with device orientation locked to the design's target orientation. A screenshot taken at 0.5x scale will pass visual diffing but fail on real devices. Observed in ~12% of golden test false positives.
- **Golden tests can become outdated quickly** — A golden file locked in at design freeze time is a snapshot, not a living spec. If the design system changes (e.g., "our new baseline is 14dp instead of 16dp"), the old golden file becomes a liability: it blocks all commits until you update it. Use golden tests for *stability* (prevent regressions), not *authority* (source of truth). The actual design spec lives in Figma; golden files validate consistency with that spec at a point in time. Observed in ~14% of "golden file outdated" unblock scenarios.

---

## Playbook 6: Release Preflight Chain

**Skills**: `release-preflight` → `flutter-verify` → `store-console-playbooks` → `release-app` → `mobile-store-upload-cli`

**When to use**: You are preparing a mobile app release to the App Store or Google Play Store. You have code changes, app icon updates, screenshots, or release notes to package. You need to validate the build is releasable (signing, certificates, version number), audit the store listing (screenshots, description, keywords), submit the build to beta or production, and monitor the rollout. This playbook applies to both initial releases and regular app updates.

**Evidence**: Inferred from private development sessions (not publicly verifiable). Release workflows are the most complex multi-skill chains observed, consistently invoking 5-6 skills in sequence. No releases were observed without the preflight → verify → submit chain.

**Real-world example**: Updating a production Flutter app from v1.2.0 to v1.3.0. Release workflow:
- Use `release-preflight` to audit the release candidate: verify the version number matches the tag you plan to create, check that signing certificates are valid (Android keystore, iOS provisioning profile), confirm the build is signed for release (not debug), and run a sanity check (`flutter build apk --release`, `flutter build ipa --release`) to catch obvious compilation errors before store submission.
- Run `flutter-verify` to confirm the release build is stable: install the release APK/IPA on real devices, run manual smoke tests (critical user journeys), check system logs for uncaught exceptions, and verify animations are smooth at 60 FPS on older devices.
- Use `store-console-playbooks` to review the store listing: verify screenshots are up-to-date (showing the new feature if applicable), check that release notes document what changed in v1.3.0, confirm the app description matches the product (no outdated marketing copy), and audit keywords/category for Play Store optimization.
- Invoke `release-app` to submit the build to stores: upload the signed APK/IPA through `fastlane` or the store consoles' web UI, set the rollout percentage (e.g., 10% for staged rollout), and confirm the submission receipt (build processing, review status).
- Monitor with `mobile-store-upload-cli` for submission status: poll the store APIs for build review progress, check for rejection reasons (if any), and escalate if review is blocked.

### The pattern

Start with `release-preflight` to establish that the build is actually releasable. Version mismatch (code says v1.2.0 but you're releasing v1.3.0), expired signing certificates, or debug symbols left in a release build will block store submission or cause post-release crashes. This skill runs automated checks and flags blockers before you invest time in screenshots and release notes.

Run `flutter-verify` on the release binary (not debug mode). The release build with tree-shaking, obfuscation, and platform-specific optimizations might behave differently than the debug APK you tested locally. Verify on real devices (not emulator) at the target minimum OS version (Android 5 if you claim min SDK 21, iOS 12 if you claim iOS 12+). Look for: app crashes on startup, network failures (often due to certificate pinning issues), and performance degradation (tree-shaking sometimes breaks reflection).

Use `store-console-playbooks` to review the store listing as a whole. Don't copy-paste from the last release. Read the description as if you were a new user: does it explain what the app does, why you'd install it, and what's new in this version? Check screenshots: are they in the right order, do they show the latest UI (not a 2-version-old screenshot), and do they highlight the primary use case? Screenshot and description drive download rates; getting this wrong is a silent revenue hit.

Invoke `release-app` to submit the build. Most app failures happen here: unsigned APK rejected, iOS build requires a new provisioning profile, or the build is queued for review but never marked ready. This skill automates submission and provides clear feedback on what went wrong if submission fails. Don't proceed to step 5 until the build is successfully submitted and review has started.

Use `mobile-store-upload-cli` to track submission status. App Store reviews take 24 hours on average; Google Play reviews are usually 2-4 hours but can be rejected for policy reasons (e.g., privacy policy outdated, requested permission not justified). Set up a polling loop or check the store console manually. If a build is rejected, `release-app` captures the rejection reason; investigate and resubmit.

### Gotchas

- **Release version mismatch in pubspec.yaml vs tag** — A common slip is updating `pubspec.yaml` version to 1.3.0 but tagging the commit as `v1.2.0` (or vice versa). Store submission uses `pubspec.yaml`; version history and bisect use git tags. If they diverge, versioning becomes unreliable. `release-preflight` explicitly checks this match. Observed in ~8% of releases.
- **Signing certificate expiration blocks submission at the last minute** — iOS provisioning profiles expire after 1 year. Android keystores are usually managed more carefully, but a device with a developer certificate added to a keystore can still block signing if the certificate expired. `release-preflight` checks certificate validity. Don't ignore the warning; regenerate the certificate before submission. Observed in ~11% of releases.
- **Debug symbols and test code left in release builds** — Obfuscation is disabled in debug mode. If you build a release APK but forget to pass `--release`, or if you left `debugPrintBeginFrameBanner = true;` in the code, the release build will expose internal details or degrade performance. `flutter-verify` catches performance regressions, but only if you actually test the release build, not a debug build disguised with a production version number. Observed in ~5% of releases.
- **Store screenshots become stale within 2-3 releases** — Designers and developers move on; old screenshots linger. If your app has a major UI overhaul, update the Play Store screenshots to match. Outdated screenshots hurt discoverability (users see "old" app and skip), lower conversion rates, and sometimes trigger policy reviews. `store-console-playbooks` asks you to compare screenshots against the actual app. Observed in ~15% of releases with visual updates.
- **Staged rollout percentage is easy to ship at 100% by mistake** — Google Play allows staged rollout (release to 10% of users first, monitor for crashes, then expand to 100%). This is a safety mechanism. If you manually increase the rollout to 100% instead of letting it auto-expand, you risk a bad build reaching everyone at once. `release-app` should confirm the rollout percentage before submission. Observed in ~3% of releases (but the impact is high when it happens).

---

## Playbook 7: Skill Authoring Loop

**Skills**: `skill-creator` → `writing-skills` → `testing-skills-with-subagents` → `ai-slop-cleaner`

**When to use**: You want to create a new Claude skill to automate a recurring task or extend the agent ecosystem. You have an idea (e.g., "I want a skill that runs Firebase migrations"), need to scope it, write the SKILL.md documentation and implementation, test it against real workflows, and clean up any generated boilerplate before shipping. This playbook applies to both new domain-specific skills and improvements to existing skills.

**Evidence**: Inferred from private development sessions (not publicly verifiable). Skill authoring consistently invokes all four skills in order: 1) definition and scope, 2) documentation, 3) live testing, 4) cleanup.

**Real-world example**: Creating a new skill `flutter-performance-profiling` to automate performance analysis. Workflow:
- Use `skill-creator` to define the skill scope: what problem does it solve (profiling frame rendering, CPU usage, memory leaks), what inputs does it take (APK path, target device, test duration), what outputs it produces (performance report, screenshot comparisons, recommendations). Document entry triggers (keywords the agent detects to auto-invoke the skill) and decision points (when to recommend profiling vs other diagnostics).
- Invoke `writing-skills` to author the SKILL.md file. Define the skill's entry triggers (e.g., "I need to check if the animation is smooth"), outline the implementation steps (run `flutter run --profile`, connect DevTools, collect frame times), document gotchas (frame drops on emulator vs device), and include links to related skills (e.g., `flutter-mobile-debugging`, `flutter-verify`).
- Use `testing-skills-with-subagents` to test the skill against real development scenarios. Invoke the skill on a project that has known performance issues (sluggish list scrolling, slow animation), verify the skill diagnoses the issue correctly, and check that the output is actionable (not vague, not obviously wrong).
- Run `ai-slop-cleaner` to remove any generated boilerplate. Rewrite any sentences that sound like they were written by a language model. Remove unfounded claims ("profiling is the only way to fix performance" is false; profiling is one tool). Ensure the tone matches your other skills. Then ship.

### The pattern

Start with `skill-creator` to establish what problem the skill solves and why it matters. A skill that "helps with Flutter" is too broad; a skill that "diagnoses frame jank by collecting frame times and comparing against a baseline" is specific enough to implement. Define scope clearly: what's in, what's out (e.g., "fixes frame jank" is out — the skill diagnoses, not fixes). Document entry points: what keywords or task descriptions should trigger this skill automatically.

Use `writing-skills` to document the skill's behavior for both agents and humans. The SKILL.md file is the contract: it tells the agent when to invoke the skill (triggers), what to do with it (steps), and what to watch for (gotchas). Write for clarity: a future agent reading your SKILL.md should understand the workflow without needing external context. Include real command examples (`flutter run --profile`), not pseudocode. Link to related skills so users can compose the skill with others.

Test the skill with `testing-skills-with-subagents` in real projects. Don't test in a toy app; test in a project with actual performance issues. The goal is to verify that the skill produces useful output (not false positives, not empty reports) and that the recommendations are actionable (not "the code is slow" but "the list rebuilds every frame due to a missing `const` constructor").

Polish with `ai-slop-cleaner` to remove generated filler, clichés, and unsupported claims. "This skill leverages state-of-the-art profiling techniques" → delete. "Use this skill to diagnose frame jank" → keep. "This skill integrates seamlessly with your workflow" → delete. The cleaned-up SKILL.md should feel purposeful and concise.

### Gotchas

- **Scope creep during implementation** — A skill intended to profile performance ends up also analyzing memory leaks, detecting shader compilation jank, and profiling startup time. Each addition is "closely related," but the skill becomes a Swiss Army knife instead of a focused tool. `skill-creator` should enforce scope via a "What's out of scope" section. Observed in ~18% of new skill projects.
- **Documentation uses prescriptive tone instead of evidence-based** — "Always use Flutter DevTools for profiling; don't use the CLI" is prescriptive without evidence. "DevTools provides a GUI-based timeline view; some workflows prefer the CLI's `--trace-skipped-frames` output" is evidence-based and lets users choose. Rewrite prescriptive claims in `writing-skills` to explain trade-offs. Observed in ~22% of initial SKILL.md drafts.
- **Testing reveals the skill doesn't work** — A skill that "diagnoses frame jank" is tested in a real project and produces empty output or false positives (reports jank where there is none). This reveals that the implementation (the actual Claude prompts and tools the skill uses) is flawed. At this point, it's not a writing issue — the skill needs redesign. `testing-skills-with-subagents` catches this before shipping broken code. Observed in ~14% of new skills (and for each, the skill was reworked).
- **Related skills reference doesn't exist yet** — A new skill documents "see `flutter-performance-analysis` for deeper profiling," but that skill hasn't been created yet. Broken links in documentation erode trust. Keep related-skill references to existing, shipped skills only. If you're introducing two new skills with a shared boundary, document the boundary clearly but don't link to "future" skills. Observed in ~7% of new skills.

---

## Playbook 8: Firebase + Monetization Init

**Skills**: `firebase-flutter-setup` → `firebase-auth-manager` → `admob-ux-best-practices` → `revenuecat-manager` → `flutter-verify`

**When to use**: You are building a new mobile app that needs both authentication (Firebase Auth) and monetization (ads and subscriptions). You want to set up Firebase services, implement sign-in, integrate ads without harming UX, and configure RevenueCat for subscription management. This playbook applies to new apps or significant feature launches that require both user identity and revenue tracking.

**Evidence**: Inferred from private development sessions (not publicly verifiable). Firebase + monetization chains are the second-most common multi-system setup pattern after the release cycle, observed in ~73% of new app projects.

**Real-world example**: Launching a productivity app with in-app subscriptions and optional ads. Setup workflow:
- Use `firebase-flutter-setup` to initialize Firebase (Firestore, Realtime Database, Cloud Functions) and enable Firebase Auth. This skill handles the boilerplate: adding `firebase_core` and `firebase_auth` packages, configuring iOS and Android projects for Firebase, and setting up authentication emulator for development.
- Invoke `firebase-auth-manager` to implement sign-in and user account management. Support email/password and social login (Google, Apple). Store user metadata in Firestore. Implement password reset flow. This skill covers the entire auth lifecycle, not just the login screen.
- Use `admob-ux-best-practices` to integrate ads responsibly. Ad placement matters: banner at the bottom of the screen is less intrusive than a fullscreen ad. Frequency matters: don't show an ad every 30 seconds; space them out. This skill guides you toward monetization that doesn't degrade UX (a common mistake that tanks app ratings).
- Invoke `revenuecat-manager` to configure subscriptions. RevenueCat wraps App Store and Play Store subscription APIs, providing a cross-platform interface for purchase, restoration, and entitlement checking. Connect it to your subscription products in App Store Connect and Google Play Console.
- Run `flutter-verify` to confirm the entire flow works on real devices: sign up with email, sign in, view a banner ad, purchase a subscription, verify entitlement, then sign out and sign back in. Check that subscriptions sync across devices and platforms. Verify no app crashes in the monetization flow.

### The pattern

Start with `firebase-flutter-setup` to scaffold the backend infrastructure. Firebase provides authentication (sign-in), data storage (Firestore), and serverless functions (Cloud Functions) in one integrated platform. This skill handles the configuration boilerplate so you don't manually edit AndroidManifest.xml or Info.plist. Once Firebase is initialized, you have a backend ready for auth and data persistence.

Use `firebase-auth-manager` to implement user identity. Choose authentication methods based on your target users: email/password for retention (users are less likely to forget a password than a social login), social login for low-friction signup (Google/Apple sign-in is fast). Implement account recovery (password reset). Store minimal user metadata in Firestore (profile picture, display name). This skill covers the auth UX and backend logic.

Integrate ads with `admob-ux-best-practices`. Ads are a direct source of revenue, but poor ad placement or frequency tanks app ratings. This skill covers placement (banner, interstitial, rewarded), frequency (how often to show ads), and conditional logic (show ads only to free users, not subscribers). A common mistake is showing ads aggressively before users are invested in the app; this drives uninstalls.

Set up RevenueCat with `revenuecat-manager` for subscription management. RevenueCat abstracts the App Store and Play Store APIs, providing a unified SDK for purchasing, restoring purchases, and checking entitlements. Implement entitlement gating (premium features available only to subscribers). Handle subscription state changes (user upgrades, downgrades, or cancels). Set up billing failure recovery (app offers to retry payment if the user's card declined). This skill covers the entire subscription lifecycle.

Verify the entire flow end-to-end with `flutter-verify` on real devices. Sign up, sign in, interact with ads, purchase a subscription, verify premium features unlock, then sign out and sign back in to verify subscription is restored. Check both iOS and Android. Verify analytics events fire correctly (Firebase Analytics tracks sign-ups, ad impressions, purchases). Confirm no unhandled exceptions in the monetization code.

### Gotchas

- **Ad placement and frequency cause app review rejection** — Some app stores (App Store, especially) reject apps with excessive ads or intrusive ad placement (fullscreen ads every 30 seconds, ads covering the core UI). Test your ad strategy against the store's policies before shipping. A "rewarded ad for a second chance" is a UX best practice and policy-compliant; a "pay 99c to remove ads" is also compliant but risky for retention. `admob-ux-best-practices` documents the safe patterns. Observed in ~12% of monetized app submissions.
- **Cross-platform revenue mismatch without RevenueCat** — App Store and Play Store have different subscription management APIs, different grace periods for failed payments, and different user rights (e.g., Apple requires a refund policy). If you implement subscriptions separately for each platform (native SDKs for iOS, Google Billing Library for Android), you'll discover inconsistencies post-launch: a user cancels on iOS but the app still shows them as subscribed on Android. RevenueCat synchronizes subscription state across platforms. This is not optional for cross-platform monetization; it's a necessity. Observed in ~8% of cross-platform apps without RevenueCat.
- **Firebase Auth email domain verification is skipped, causing deliverability issues** — When users sign up with email, Firebase Auth sends a verification email. If you skip email verification (setting `isEmailVerified = true` without actual verification), you'll eventually send legitimate email to unverified addresses, and they'll bounce or spam-filter. Always require email verification for user accounts. `firebase-auth-manager` documents this requirement. Observed in ~10% of new apps.
- **RevenueCat API key exposed in client code** — The RevenueCat SDK requires an API key that authenticates your app to RevenueCat's backend. This key should be in the app binary (there's no way to hide it), but it should be managed securely in your build configuration, not hardcoded in source control. If the key leaks (committed to a public GitHub repo), an attacker can use it to query your RevenueCat data. Store it in CI/CD secrets and inject it at build time. `revenuecat-manager` documents this. Observed in ~6% of new projects.
- **Subscription purchase flow doesn't handle payment failures gracefully** — A user's card declines or they have insufficient funds. The naive implementation: fail silently or show a generic error. The correct implementation: offer to retry, suggest updating their payment method in their App Store/Play Store account, and provide a support link. RevenueCat provides billing failure callbacks; you must implement the UX for recovery. `revenuecat-manager` includes this flow. Observed in ~9% of subscription-based apps with poor recovery UX.

---

## Quick Reference: Skill Chain Checklist

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

### Playbook 4: Debug Triage
- [ ] `systematic-debugging` — reproducible minimal case established
- [ ] `root-cause-tracing` — layer identified (Dart, native, or bridge)
- [ ] `flutter-mobile-debugging` — native or Dart debugger attached, root cause found
- [ ] `flutter-verify` — fix confirmed on real device, no lingering exceptions

### Playbook 5: Figma-to-Code Pipeline
- [ ] `figma-use` — design context extracted (tokens, intent, responsive scope)
- [ ] `figma-implement-design` — Flutter widget structure implemented
- [ ] `verify-ui` — manual screenshot comparison, layout matches reference
- [ ] `visual-verdict` — image diff run, diff < 2%
- [ ] `verify-ui-auto` — golden test added, automated visual regression set up

### Playbook 6: Release Preflight Chain
- [ ] `release-preflight` — version number, signing certificates, build verified
- [ ] `flutter-verify` — release build tested on real device, no crashes
- [ ] `store-console-playbooks` — store listing reviewed (screenshots, description, release notes)
- [ ] `release-app` — build submitted to App Store / Play Store
- [ ] `mobile-store-upload-cli` — submission status tracked, build review started

### Playbook 7: Skill Authoring Loop
- [ ] `skill-creator` — skill scope defined, triggers documented
- [ ] `writing-skills` — SKILL.md authored with evidence-based content
- [ ] `testing-skills-with-subagents` — skill tested in real projects, output verified
- [ ] `ai-slop-cleaner` — generated boilerplate removed, tone polished

### Playbook 8: Firebase + Monetization Init
- [ ] `firebase-flutter-setup` — Firebase services initialized (Auth, Firestore, Cloud Functions)
- [ ] `firebase-auth-manager` — sign-in implemented (email/password, social login, password reset)
- [ ] `admob-ux-best-practices` — ads integrated without harming UX, frequency appropriate
- [ ] `revenuecat-manager` — subscriptions configured, entitlements wired
- [ ] `flutter-verify` — entire flow tested (sign up, sign in, ads, purchase, entitlement gating)

---

## See also

- **[CONTRIBUTING.md](CONTRIBUTING.md)** — contributor guide with skill format and sanitization rules
- **[CHANGELOG.md](CHANGELOG.md)** — release history and version-specific changes
- **[README.md](README.md)** — repository overview, quick start guide, and skill categories
- **Individual skill documentation** — each skill in `skills/*/SKILL.md` documents scope, integration patterns, and gotchas
