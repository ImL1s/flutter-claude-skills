---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup
---

# Finishing a Development Branch

## Overview

Guide completion of development work by presenting clear options and handling chosen workflow.

**Core principle:** Verify tests → Present options → Execute choice → Clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## The Process

### Step 1: Verify Tests

**Before presenting options, verify tests pass:**

```bash
# Run project's test suite
npm test / cargo test / pytest / go test ./...
```

**If tests fail:**
```
Tests failing (<N> failures). Must fix before completing:

[Show failures]

Cannot proceed with merge/PR until tests pass.
```

Stop. Don't proceed to Step 2.

**If tests pass:** Continue to Step 2.

### Step 2: Determine Base Branch

```bash
# Try common base branches
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

Or ask: "This branch split from main - is that correct?"

### Step 3: Present Options

Present exactly these 4 options:

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
4. Discard this work

Which option?
```

**Don't add explanation** - keep options concise.

### Step 4: Execute Choice

#### Option 1: Merge Locally

```bash
# Switch to base branch
git checkout <base-branch>

# Pull latest
git pull

# Merge feature branch
git merge <feature-branch>

# Verify tests on merged result
<test command>

# If tests pass
git branch -d <feature-branch>
```

Then: Cleanup worktree (Step 5)

#### Option 2: Push and Create PR

```bash
# Push branch
git push -u origin <feature-branch>

# Create PR
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<2-3 bullets of what changed>

## Test Plan
- [ ] <verification steps>
EOF
)"
```

Then: Cleanup worktree (Step 5)

#### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

**Don't cleanup worktree.**

#### Option 4: Discard

**Confirm first:**
```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for exact confirmation.

If confirmed:
```bash
git checkout <base-branch>
git branch -D <feature-branch>
```

Then: Cleanup worktree (Step 5)

### Step 5: Cleanup Worktree

**For Options 1, 2, 4:**

Check if in worktree:
```bash
git worktree list | grep $(git branch --show-current)
```

If yes:
```bash
git worktree remove <worktree-path>
```

**For Option 3:** Keep worktree.

## Rescue: leaked secret

Use this section **after** the branch is already merged + pushed to a public remote and you notice the diff included a secret (personal email in commit author metadata, API key in a config example, internal hostname in a doc). The destructive nature means treat it as a separate flow, not Step 4 above.

**Scope:** rewriting **public history** is irreversible from your end and disruptive for downstream clones / forks. Confirm the leak is worth the cost before running.

### Recipe (placeholders, substitute your own values)

```bash
# 1. Backup tag — recovery anchor before destruction
git tag backup-pre-rewrite

# 2. Install git-filter-repo if not present (it is NOT bundled with git)
brew install git-filter-repo            # macOS
# pip install git-filter-repo            # alternative

# 3. Run the rewrite. Example — replace all commits' author email
#    Use a complete callback; the body is a real Python expression
git filter-repo --email-callback '
return b"<numeric-id>+<username>@users.noreply.github.com" if email == b"<your-old-email>" else email
'

# 4. filter-repo strips the origin remote on purpose. Re-add it.
git remote add origin <your-repo-url>

# 5. Force-push with --force-with-lease (NOT --force)
#    --force-with-lease aborts if remote moved since last fetch — safer
git push --force-with-lease origin main

# 6. Notify forks/clones that history was rewritten — they must re-pull
#    (`git pull --rebase` won't do it; they need `git fetch && git reset --hard origin/main`)
```

### What `<numeric-id>` is

GitHub's privacy noreply email format is `<numeric-id>+<username>@users.noreply.github.com`. Find your numeric id with:

```bash
gh api users/<your-username> --jq .id
```

Both forms (`<numeric-id>+<username>@users.noreply.github.com` and bare `<username>@users.noreply.github.com` for newer accounts) route to your inbox if email privacy is enabled in GitHub settings.

### Gotchas

- **filter-repo removes origin on purpose**, expecting you to push the rewritten history to a fresh repo. If you're rewriting in-place, re-add origin (step 4 above).
- **Paths-filtered CI workflows don't trigger** on a metadata-only force-push (no file content changed → `paths:` filter sees no match). Add `workflow_dispatch:` to your workflow so you can manually re-run validation post-rewrite.
- **All commit SHAs change**. Anyone who pinned to a SHA, anyone who has the repo cloned, anyone who has a fork — they all need to invalidate their state. Plan a heads-up message.
- **Public-cache residue**: GitHub's web UI clears immediately, but external mirrors (Sourcegraph, Software Heritage, GitHub search index) may retain the leaked content for hours-to-weeks. The rewrite stops the leak from propagating; it does not fully erase it. If the secret was a credential, **rotate the credential too** — don't trust the rewrite to fix it.

## Quick Reference

| Option | Merge | Push | Keep Worktree | Cleanup Branch |
|--------|-------|------|---------------|----------------|
| 1. Merge locally | ✓ | - | - | ✓ |
| 2. Create PR | - | ✓ | ✓ | - |
| 3. Keep as-is | - | - | ✓ | - |
| 4. Discard | - | - | - | ✓ (force) |

## Common Mistakes

**Skipping test verification**
- **Problem:** Merge broken code, create failing PR
- **Fix:** Always verify tests before offering options

**Open-ended questions**
- **Problem:** "What should I do next?" → ambiguous
- **Fix:** Present exactly 4 structured options

**Automatic worktree cleanup**
- **Problem:** Remove worktree when might need it (Option 2, 3)
- **Fix:** Only cleanup for Options 1 and 4

**No confirmation for discard**
- **Problem:** Accidentally delete work
- **Fix:** Require typed "discard" confirmation

## Red Flags

**Never:**
- Proceed with failing tests
- Merge without verifying tests on result
- Delete work without confirmation
- Force-push without explicit request

**Always:**
- Verify tests before offering options
- Present exactly 4 options
- Get typed confirmation for Option 4
- Clean up worktree for Options 1 & 4 only

## Integration

**Called by:**
- **subagent-driven-development** (Step 7) - After all tasks complete
- **executing-plans** (Step 5) - After all batches complete

**Pairs with:**
- **using-git-worktrees** - Cleans up worktree created by that skill

## Related skills

- **`writing-plans`** — generates the plan document that you reference in the merge commit message. Use this skill after writing-plans is complete.
- **`verification-before-completion`** — verify tests pass before presenting merge options. This skill's Step 1 depends on verification evidence.
- **`requesting-code-review`** → `receiving-code-review` — handle code review feedback using these skills before finishing the branch.
