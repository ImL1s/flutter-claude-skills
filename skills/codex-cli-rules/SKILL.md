---
name: codex-cli-rules
description: |
  Operational rules for driving Codex CLI from scripts: success-signal contract, diff-feeding semantics, worktree -C flag, and stdin vs argv. Triggers when invoking `codex exec` programmatically (not interactively) — script wrappers, ralph loops, cron pipelines, multi-CLI fan-out. Surfaces silent failure modes that exit 0 but produce no useful output.
  Triggers (English): codex exec, codex cli, codex review, codex rescue, codex fallthrough, agent script invocation, programmatic codex.
---

## When to Use

Use this skill when you are **driving Codex CLI from a script or ralph loop** and need to verify it actually ran (not just exited 0). Read it BEFORE writing any wrapper that pipes Codex output into a downstream step.

Tested with **Codex CLI v0.118.0+**, model `gpt-5.4`, `model_reasoning_effort: xhigh`. Older CLIs (`<0.118`) reject `xhigh` as `unknown variant` for `model_reasoning_effort` — pin a fallback.

Skip if you are using Codex interactively (the TUI), or just running it once by hand.

## stdin vs argv

Highest-frequency footgun. Putting a long prompt into `"$(cat prompt.md)"` hits `ARG_MAX` (~1MB on modern macOS, ~256KB on POSIX-only systems) and either truncates or fails with `argument list too long`.

```bash
# ❌ Bad — diff over ~500 lines silently truncates or errors
codex exec -s read-only --ephemeral -o /tmp/out.md "$(cat /tmp/prompt.md)"

# ✅ Good — pipe via stdin, trailing `-` reads from stdin
cat /tmp/prompt.md | codex exec -s read-only --ephemeral -o /tmp/out.md -
```

Bounded only by the model's context window, not the shell's `ARG_MAX`. Use this form unconditionally for any prompt that includes a `git diff` or file body.

## Three-element contract

`codex exec` exits 0 even when Codex never produced a response. **Exit code alone is not a success signal.** Verify three elements:

| Check | What it confirms |
|---|---|
| `out > 500B` | The `-o out.md` file actually has a final assistant message |
| log contains `tokens used` | The model session reached completion (the "tokens used: N" footer prints only on success) |
| `.exit == 0` (nohup path only) | Process didn't crash mid-run |

```bash
cat prompt.md | codex exec -s read-only -c 'mcp_servers={}' --ephemeral \
  -o /tmp/codex.out -                                                \
  > /tmp/codex.log 2>&1 &

wait $!
[ -s /tmp/codex.out ] && [ "$(wc -c < /tmp/codex.out)" -gt 500 ] || echo "FAIL: out empty/short"
grep -q 'tokens used' /tmp/codex.log || echo "FAIL: no completion signature"
```

**Two failure modes you'll see**:

- `out 5KB but log has no "tokens used"` → process killed mid-run (often by `| tail -N` truncating final message). Re-run.
- `out empty but log has "tokens used"` → MCP stall or auth issue. Set `-c 'mcp_servers={}'` to disable MCP for the reviewer.

## Three-dot diff

When feeding a PR diff to Codex for review, the diff syntax matters. Two-dot `BASE..HEAD` includes commits reachable from `HEAD` but not `BASE` — which on a long-running fork means **BASE's own new commits get pulled in as "your changes"**. Three-dot `BASE...HEAD` walks the merge-base instead.

```bash
# ❌ Bad — if BASE moved forward since your branch diverged, you ship BASE's commits
git diff BASE..HEAD > /tmp/diff.txt

# ✅ Good — three dots walks merge-base
git diff BASE...HEAD > /tmp/diff.txt
```

Then embed the diff into the prompt and feed via stdin (see § stdin vs argv). Don't ask Codex to run `git diff` itself — its working directory under `codex exec` may not be what you think (see § Running from a worktree).

## Running from a worktree

If you're in a git worktree (e.g., `repo/.worktrees/feature-x/`), `codex exec` defaults its cwd to the **main repo's HEAD**, not the worktree's HEAD. You'll get reviews of the wrong branch.

Fix: pass `-C <worktree-path>` explicitly.

```bash
# Wrong — Codex reads main repo's checked-out branch
codex exec -s read-only --ephemeral -o /tmp/out.md - < prompt.md

# Right — pin Codex to the worktree
codex exec -C "$(git rev-parse --show-toplevel)" -s read-only --ephemeral -o /tmp/out.md - < prompt.md
```

Sanity check: have Codex echo `git rev-parse HEAD` in its first response. If the SHA doesn't match `git -C <worktree-path> rev-parse HEAD`, you're reviewing the wrong tree.

## Gotchas

- **`-m xhigh` is a 400 error** — `xhigh` is the value of `model_reasoning_effort`, not a model name. Use `-m gpt-5.4` (or your model) and put effort in `~/.codex/config.toml` or pass `-c 'model_reasoning_effort="xhigh"'` for a single-call override.
- **Usage limit** — ChatGPT-account Codex returns `ERROR: You've hit your usage limit. ... try again at HH:MM AM` when out of credits. Exit code is non-zero. Wall-clock reset time, not delta. Parse to schedule retry.
- **`| tail -N` eats the final message** — Codex's "final assistant message" prints last in the log. Truncating output kills the `tokens used` signature. Capture full log: `> /tmp/log 2>&1`, never `| tail`.

## Examples

A complete invocation that satisfies all four rules:

```bash
WORKTREE=$(git rev-parse --show-toplevel)
git diff main...HEAD > /tmp/diff.txt
cat <<'EOF' > /tmp/prompt.md
Review this diff for correctness. Focus on null safety + race conditions.
---
EOF
cat /tmp/diff.txt >> /tmp/prompt.md

cat /tmp/prompt.md | codex exec \
  -C "$WORKTREE" \
  -s read-only \
  -c 'mcp_servers={}' \
  --ephemeral \
  -o /tmp/codex.out - \
  > /tmp/codex.log 2>&1

# Three-element verification
[ -s /tmp/codex.out ] || { echo "FAIL: out empty"; exit 1; }
[ "$(wc -c < /tmp/codex.out)" -gt 500 ] || { echo "FAIL: out < 500B"; exit 1; }
grep -q 'tokens used' /tmp/codex.log || { echo "FAIL: no completion"; exit 1; }
echo "OK"
cat /tmp/codex.out
```

## Related skills

- **`requesting-code-review`** — for dispatching Claude's `code-reviewer` subagent. Codex driven via this skill is a complementary parallel reviewer (different model, different blind spots).
- **`finishing-a-development-branch`** — when the codex review is the last gate before push.
