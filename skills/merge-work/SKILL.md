---
name: merge-work
description: >-
  Merge completed agent worktrees back into the main branch. Detects conflicts,
  auto-resolves where safe, and flags conflicts for manual intervention. Use when
  the user asks to "merge work", "merge branches", "integrate changes", or
  "land worktrees".
---

# Merge Work

Integrate completed agent worktrees into the main branch.

## Project Resolution

1. If the user specified a project name (e.g., `/merge-work mobile-app`), use it.
2. If not, read `.project-agent/registry.json` from the cwd.
   - If only one project exists, use it.
   - If multiple exist, ask the user which one.
   - If none exist, tell the user to run `/plan-project` first.

Project data:
- Board: `{cwd}/.project-agent/projects/{name}/board.json`

## Workflow

### Step 1: Identify Completed Worktrees

Read the board.json for the resolved project. Find all tickets with `status === "done"` that have worktree branches to merge.

List all git branches that match the agent worktree naming pattern. Use:

```bash
git branch --list 'claude-worktree-*'
```

Cross-reference with done tickets to identify which branches correspond to which tickets.

### Step 2: Determine Merge Order

Sort branches by ticket dependency order. Tickets with no dependencies merge first. This minimizes conflicts because foundational changes land before dependent ones.

If ticket PA-001 is a dependency of PA-003, merge PA-001's branch first.

### Step 3: Pre-Merge Checks

For each branch, before merging:

1. **Check for conflicts** — run `git merge --no-commit --no-ff {branch}` then `git merge --abort` to preview without committing. If there are conflicts, flag them.
2. **Run tests** — checkout the branch, run the project's test suite. If tests fail, flag the branch as needing rework.
3. **Check diff size** — `git diff main...{branch} --stat` to show what changed.

### Step 4: Merge Strategy

**Clean merges (no conflicts):**
1. `git merge --no-ff {branch} -m "Merge PA-NNN: {ticket title}"`
2. Run tests after merge to catch integration issues.
3. If tests pass, continue to next branch.
4. If tests fail after merge, `git revert -m 1 HEAD` and flag for manual resolution.

**Conflicting merges:**
1. Show the user the conflict details: which files conflict, the diff hunks.
2. Offer options:
   - **Auto-resolve** — if conflicts are trivial (e.g., both sides added to the end of different files), attempt automatic resolution.
   - **Manual resolution** — present the conflicting sections and ask the user to choose or provide the resolution.
   - **Defer** — skip this branch and merge others first. The conflict may resolve itself after other merges land.
3. After resolution, run tests to verify.

### Step 5: Cleanup

After successful merges:

1. Delete merged branches: `git branch -d {branch}`
2. Update board.json: add `merged_at` timestamp to merged tickets (in the notes section).
3. Remove cleaned-up worktrees.

### Step 6: Report Results

```
## Merge Results — {project-name}

### Successfully Merged
| Ticket | Branch | Files Changed | Insertions | Deletions |
|--------|--------|---------------|------------|-----------|
| PA-001 | claude-worktree-... | 5 | +120 | -30 |

### Conflicts Requiring Resolution
| Ticket | Branch | Conflicting Files | Status |
|--------|--------|--------------------|--------|
| PA-003 | claude-worktree-... | src/router.ts | Deferred |

### Post-Merge Test Results
All tests passing: YES / NO (details)
```

## Important

- **Always merge in dependency order.** Foundational changes first, dependent changes second.
- **Never force-push or rewrite history.** Use `--no-ff` merges to preserve the branch history.
- **Run tests after EVERY merge**, not just at the end. Catch integration issues early.
- **If more than 2 branches conflict with each other**, stop and ask the user. This likely indicates a planning issue where tickets weren't properly scoped for isolation.
- **Back up before starting.** Create a restore point: `git tag pre-merge-{timestamp}` so the user can roll back if needed.
