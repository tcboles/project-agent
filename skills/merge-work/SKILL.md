---
name: merge-work
description: >-
  Land completed work into the main branch. In worktree mode, merges agent
  branches back with conflict detection. In working-tree mode, commits the
  shared working tree directly. Use when the user asks to "merge work",
  "merge branches", "integrate changes", or "land worktrees".
---

# Merge Work

Integrate completed work into the main branch. Supports two modes:
- **Worktree mode** — merges `claude-worktree-*` branches created by agents running with `isolation: "worktree"`.
- **Working-tree mode** — commits the shared main working tree after a wave of agents that wrote directly to it.

The mode is resolved automatically from session state or config.

## Project Resolution

1. If the user specified a project name (e.g., `/merge-work mobile-app`), use it.
2. If not, read `.project-agent/registry.json` from the cwd.
   - If only one project exists, use it.
   - If multiple exist, ask the user which one.
   - If none exist, tell the user to run `/plan-project` first.

Project data:
- Board: `{cwd}/.project-agent/projects/{name}/board.json`

## Workflow

### Step 0: Load Configuration

Read config from global (`~/.claude/project-agent/config.json`) and workspace (`{cwd}/.project-agent/config.json`), merging workspace over global. Defaults: `autonomous: false`, `dispatch.isolation_mode: "auto"`.

**Determine execution mode.** If `/merge-work` was invoked from `/plan-project` Phase 7, the caller passes an `execution_mode`. Otherwise, read `autonomous` from config:
- If `autonomous === true` → `execution_mode = "autonomous"`
- Otherwise → `execution_mode = "manual"`

### Step 0b: Resolve Isolation Mode

The merge flow depends on which mode the agents dispatched under:

1. If `session.isolation_mode` was set by a prior `/assign-work` invocation in this session, use it.
2. Otherwise, read `dispatch.isolation_mode` from config:
   - `"worktree"` → use worktree mode
   - `"working-tree"` → use working-tree mode
   - `"auto"` → detect empirically: run `git branch --list 'claude-worktree-*'`. If branches exist, mode is `worktree`. If not, check `git status --short` for uncommitted changes — if present, mode is `working-tree`. If neither branches nor changes exist, there is nothing to merge; report and exit cleanly.
3. Cache the result and print: `Merge mode: {resolved_mode}`.

**Fork:**
- If `worktree` → proceed to **Flow A: Worktree Merge**.
- If `working-tree` → skip to **Flow B: Working-Tree Merge** (below).

---

## Flow A: Worktree Merge

Run these steps when `session.isolation_mode === "worktree"`.

### Step A1: Identify Completed Worktrees

Read the board.json for the resolved project. Find all tickets with `status === "done"` that have worktree branches to merge.

List all git branches that match the agent worktree naming pattern:

```bash
git branch --list 'claude-worktree-*'
```

Cross-reference with done tickets to identify which branches correspond to which tickets.

If no branches exist but done tickets exist, that is a mode mismatch — the tickets were not produced under worktree isolation. Fall back to **Flow B** and note the inconsistency to the user.

### Step A2: Determine Merge Order

Sort branches by ticket dependency order. Tickets with no dependencies merge first. This minimizes conflicts because foundational changes land before dependent ones.

If ticket PA-001 is a dependency of PA-003, merge PA-001's branch first.

### Step A3: Pre-Merge Checks

For each branch, before merging:

1. **Check for conflicts** — run `git merge --no-commit --no-ff {branch}` then `git merge --abort` to preview without committing. If there are conflicts, flag them.
2. **Run tests** — checkout the branch, run the project's test suite. If tests fail, flag the branch as needing rework.
3. **Check diff size** — `git diff main...{branch} --stat` to show what changed.

### Step A4: Present Merge Plan and Get Approval

**Always print the merge plan first**, regardless of execution mode:

```
## Ready to Merge — {project-name} (worktree mode)

| Ticket | Branch | Files Changed | Conflicts? |
|--------|--------|---------------|------------|
| PA-001 | claude-worktree-... | 5 files | No |
| PA-003 | claude-worktree-... | 3 files | Yes (src/router.ts) |

Merge order: PA-001 → PA-003 (dependency order)
A restore tag will be created before merging.
```

Count how many branches have conflicts (from Step 3).

**If `execution_mode === "autonomous"` AND conflict count === 0**, skip the approval prompt. Log `"Autonomous mode — merging {N} branches."` and proceed to Step 5.

**If `execution_mode === "autonomous"` AND conflict count > 0**, pause and prompt anyway. Log `"Autonomous mode — but {N} branches have conflicts; pausing for input."` Conflict resolution needs human judgment.

**Otherwise (manual mode)**, ask: **"Ready to merge these branches?"** using `AskUserQuestion`. If there are conflicts, highlight them and ask how to handle each one before proceeding.

### Step A5: Merge Strategy

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

### Step A6: Cleanup

After successful merges:

1. Delete merged branches: `git branch -d {branch}`
2. Update board.json: add `merged_at` timestamp to merged tickets (in the notes section).
3. Remove cleaned-up worktrees.

### Step A7: Report Results

```
## Merge Results — {project-name} (worktree mode)

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

---

## Flow B: Working-Tree Merge

Run these steps when `session.isolation_mode === "working-tree"`. Agents wrote directly to the shared main checkout; there are no branches to merge. The orchestrator commits the accumulated changes here.

### Step B1: Inspect Working Tree State

Run `git status --short` and `git diff --stat HEAD`. Capture:
- List of modified files (`M`)
- List of new/untracked files (`??`)
- List of deleted files (`D`)
- Total insertions and deletions

If the working tree is clean (no staged or unstaged changes, no untracked files), report "Nothing to merge — working tree is already clean" and exit.

### Step B2: Map Files to Tickets

Read the board.json and find all tickets with `status === "done"`. For each done ticket:

1. Parse its `## Files Involved` section to collect declared file paths.
2. Parse its `## Handoff Notes` section for `Files Modified`, `Files Created`, or similar lists of concrete paths.
3. Build a mapping `{file_path → [ticket_id, ...]}`.

Then cross-reference against the `git status` file list:
- **Mapped files:** files that appear in at least one ticket's declared/actual list. Group them by ticket.
- **Unmapped files:** files changed but not declared by any ticket. List them under "Miscellaneous / undeclared changes".

This is best-effort. If handoff notes are ambiguous, put the file under multiple tickets rather than dropping it.

### Step B3: Generate Commit Message

Build a commit message from the board's project metadata:

- **Title line** (≤ 72 chars): `{verb} {project.name}: {one-line summary}` where verb matches the project nature (e.g., `Add`, `Refactor`, `Fix`).
- **Body:** one paragraph describing what landed, referencing the project by name and listing key tickets. Do NOT enumerate every ticket — summarize.
- **No AI attribution.** Do not mention Claude, AI, or any assistant in the message.

Example output:
```
Add pattern-library: curated templates with inline approval

Introduces /pa-patterns-capture and /pa-patterns-scan plus a shared approval
helper so users can pin coding best practices and reference designs into the
wiki vault. Extends the vault schema with a 'template' category, new optional
frontmatter fields, and binary asset storage. Fixes a pa-wiki-query filter
bug that would have excluded the new template pages.
```

### Step B4: Present Merge Plan and Get Approval

Print the full plan regardless of execution mode:

```
## Ready to Merge — {project-name} (working-tree mode)

Tickets done: {N}  ({PA-001, PA-002, ...})
Files changed: {total}  ({modified} modified, {new} new, {deleted} deleted)
Insertions: +{N}   Deletions: -{N}

### Files by ticket
PA-001 → file-a.md, file-b.md
PA-002 → file-c.md
...
Misc → file-z.md

### Commit message preview
{title}

{body}

### Post-commit plan
1. git add {explicit file list}
2. git commit -m "{title}" (HEREDOC body)
3. Run tests (if a test script exists)
4. Stamp board.json merged_at for each done ticket
5. Push to origin only if user explicitly asks — this skill does NOT auto-push
```

**If `execution_mode === "autonomous"`**: skip approval. Log `"Autonomous mode — committing working-tree changes for {N} done tickets."` Proceed to Step B5.

**Otherwise (manual mode)**: ask via `AskUserQuestion`: "Ready to commit these working-tree changes?" Options:
1. **Commit as planned** (recommended)
2. **Edit the commit message** first
3. **Split into per-ticket commits** — one commit per done ticket, using each ticket's handoff notes as the per-commit body
4. **Abort** — leave the working tree as-is

### Step B5: Commit

1. **Stage explicit files, not `-A`.** Use the concrete list of file paths from Step B1. This avoids accidentally staging unrelated files (`.env`, editor scratch, etc.).
2. **Never commit files that likely contain secrets** (`.env`, `credentials*`, `*secret*`, `*.pem`, `*.key`). If any such file appears in the list, stop and warn the user before proceeding.
3. **Create the commit** using a HEREDOC for the message body:
   ```bash
   git commit -m "$(cat <<'EOF'
   {title}

   {body}
   EOF
   )"
   ```
4. **Do NOT use `--amend` or `--no-verify`.** Let hooks run. If a pre-commit hook fails, fix the underlying issue and create a new commit — do not bypass.

### Step B6: Run Tests (if available)

Detect a test runner from the project:
- `package.json` with a `test` script → `npm test`
- `pyproject.toml` or `pytest.ini` → `pytest`
- `Cargo.toml` → `cargo test`
- etc.

If no test runner is detected, skip this step and note it in the report.

If tests fail after commit:
- Do NOT revert automatically.
- Report the failure clearly with the test output summary.
- The commit stays; it's the user's decision whether to revert, fix-forward, or ignore.

### Step B7: Stamp Tickets and Report

1. For each done ticket that was included in the commit, add/update a `merged_at` timestamp in board.json.
2. Print the result:

```
## Merge Results — {project-name} (working-tree mode)

### Committed
Commit: {short-sha}  {title}
Files: {count}  (+{insertions} -{deletions})
Tickets stamped merged_at: PA-001, PA-002, ...

### Test Results
{test summary or "No test runner detected"}

### Next Steps
- Push when ready: git push origin {branch}
- Undo the merge: git reset --hard HEAD~1 (discards the commit and keeps working tree clean)
```

**Do NOT push automatically.** Working-tree mode commits directly to whatever branch the user is on (typically `main`). Pushing is a separate, explicit user decision.

---

## Important

- **Mode is resolved in Step 0b** — do not assume worktree mode without checking. If `session.isolation_mode` or the empirical detection says `working-tree`, run Flow B.
- **Worktree mode (Flow A): always merge in dependency order.** Foundational changes first, dependent changes second.
- **Worktree mode: never force-push or rewrite history.** Use `--no-ff` merges to preserve the branch history.
- **Worktree mode: run tests after EVERY merge**, not just at the end. Catch integration issues early.
- **Worktree mode: if more than 2 branches conflict with each other**, stop and ask the user. This likely indicates a planning issue where tickets weren't properly scoped for isolation.
- **Worktree mode: back up before starting.** Create a restore point: `git tag pre-merge-{timestamp}` so the user can roll back if needed.
- **Working-tree mode (Flow B): stage explicit files, never `-A`.** The working tree may contain unrelated user edits that should not land with the project commit.
- **Working-tree mode: never push automatically.** This mode commits directly to whatever branch the user is on (usually `main`), so pushing is a separate user decision.
- **Working-tree mode: do not auto-revert on test failure.** Report the failure and let the user decide.
- **Neither mode should ever use `--no-verify` or `--amend`.** If a hook fails, fix the underlying issue.
