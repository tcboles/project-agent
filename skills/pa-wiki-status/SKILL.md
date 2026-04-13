---
name: pa-wiki-status
description: >-
  Dashboard view of the project-agent wiki vault — page counts by category,
  recent log activity, pending promotions, coverage gaps, and vault health.
  Use when the user says "wiki status", "what's in the wiki", "wiki dashboard",
  or wants a quick health overview.
allowed-tools: [Bash, Read, Grep, Glob]
---

# PA Wiki Status

Show a terse dashboard of the project-agent wiki vault's current state.

## When to Use

- User says "wiki status", "what's in the wiki", `/pa-wiki-status`
- Quick orientation at the start of a session
- After ingests to see what changed
- To spot coverage gaps before dispatching agents

## Arguments

- `--project {name}` — optional; drill into one project's stats in addition to the
  workspace-level summary

## Configuration

1. Read global config from `~/.claude/project-agent/config.json` (if it exists).
2. Read workspace config from `{cwd}/.project-agent/config.json` (if it exists).
3. Merge (workspace overrides global).
4. Use `wiki.vault_path` (default: `~/projects/obsidian/project-agent`) as the vault root.
   Expand `~` to the actual home directory.

If `wiki.enabled` is `false`, print `Wiki memory is disabled in config.` and stop.

## Instructions

### Step 1: Resolve Vault Path and Arguments

1. Parse `--project` from user input (if provided).
2. Resolve the vault root path from config (expand `~`).
3. If vault root does not exist, print:
   ```
   Vault not found at {vault_path}. Has the wiki been scaffolded? See PA-002.
   ```
   and stop.

### Step 2: Count Pages by Category

Count `.md` files in each category directory. Directories that don't exist yet
should show `0`.

**Global (under `{vault}/wiki/`):**
| Category | Directory |
|---|---|
| concepts | `wiki/concepts/` |
| patterns | `wiki/patterns/` |
| tools | `wiki/tools/` |
| decisions | `wiki/decisions/` |
| gotchas | `wiki/gotchas/` |

**Per-project (under `{vault}/projects/`):**
For each subdirectory of `{vault}/projects/`:
| Category | Directory |
|---|---|
| architecture | `projects/{name}/architecture/` |
| domain | `projects/{name}/domain/` |
| decisions | `projects/{name}/decisions/` |
| gotchas | `projects/{name}/gotchas/` |

Also count `{vault}/sources/global/` and `{vault}/sources/projects/{name}/`
to show source page counts.

Also count stubs: grep for `^status: stub` across `wiki/` and `projects/`.

### Step 3: Recent Activity

Read `{vault}/log.md`. Extract the first 10 lines. Present them as-is (they are
already formatted, and log.md is reverse-chronological so the first lines are
the most recent). If `log.md` does not exist, show `No activity yet.`

### Step 4: Pending Promotions

Count `learnings.json` entries that have NOT yet been ingested (no `ingested_at`
field) across all tiers:

1. **Global tier:** `~/.claude/project-agent/learnings.json`
2. **Workspace tier:** `{cwd}/.project-agent/learnings.json`
3. **Per-project tiers:** `{cwd}/.project-agent/projects/*/learnings.json`
   (iterate over all projects in registry)

For each file:
- If the file does not exist: count = 0, no error
- If it exists: parse JSON array, count entries where `ingested_at` is absent or null

Total = sum across all tiers. Also show a per-tier breakdown.

### Step 5: Coverage Gaps

Read `{cwd}/.project-agent/registry.json`. For each project in `projects[]`:
- Check if `{vault}/projects/{name}/` exists and contains any `.md` files
- If it does NOT: flag as a coverage gap (project has no wiki pages at all)

### Step 6: Vault Health Summary

Check if `{vault}/log.md` exists and contains a recent lint entry:
- Look for a log block containing `**Operation:** lint` in the first 20 lines of the file
  (i.e., a lint was run recently enough to appear at the top of the reverse-chronological log)
- If found: extract the "Issues found" line and display it as a one-line health summary
- If not found or log.md is absent: display:
  `No recent lint data — run /pa-wiki-lint for a full health report`

"Recent" means the log.md lint entry appears within the first 20 lines (since log.md
is reverse-chronological, the first 20 lines reflect the most recent operations).

### Step 7: Print Dashboard

Output a terse markdown dashboard. Keep it scannable — one section per concern,
no verbose prose.

```
## Wiki Status — Project-Agent Vault
Vault: {vault_path}
Date: {ISO date}

### Page Counts

**Global** ({total_global} pages, {stub_global} stubs)
| Category | Pages |
|---|---|
| concepts | {N} |
| patterns | {N} |
| tools | {N} |
| decisions | {N} |
| gotchas | {N} |

**Sources**
| Scope | Count |
|---|---|
| global | {N} |
| {project-name} | {N} |
...

**Per-Project**
| Project | architecture | domain | decisions | gotchas | total |
|---|---|---|---|---|---|
| {name} | {N} | {N} | {N} | {N} | {N} |
...
```

If `--project {name}` was passed, add an expanded section after Per-Project:

```
**Project Detail: {name}**
| Category | Pages | Stubs |
|---|---|---|
| architecture | {N} | {N} |
| domain | {N} | {N} |
| decisions | {N} | {N} |
| gotchas | {N} | {N} |
```

Then continue with the rest of the dashboard:

```
### Pending Promotions ({total} uningested entries)
| Tier | File | Pending |
|---|---|---|
| global | ~/.claude/project-agent/learnings.json | {N} |
| workspace | .project-agent/learnings.json | {N} |
| {project-name} | .project-agent/projects/{name}/learnings.json | {N} |

{If total > 0}: Run /pa-wiki-ingest to promote pending entries into the vault.
{If total == 0}: All learnings are up to date.

### Coverage Gaps
{If none}: All registered projects have wiki coverage.
{If gaps exist}:
- {project-name} — no wiki pages yet (run /pa-wiki-ingest to populate)
...

### Recent Activity (first 10 log lines — newest first)
{last 10 lines of log.md, verbatim}

### Vault Health
{One-line summary from lint data, or prompt to run /pa-wiki-lint}
```

## Important

- **Read-only.** This skill never writes any files, including log.md.
- Status is a query, not an operation. No side effects.
- If any data source is missing (log.md, a learnings.json), show `0` or `No data`
  rather than erroring.
- Keep output compact. The user wants a dashboard, not a report.
- Parse JSON files with standard JSON parsing. Do not eval or exec.
- For pending promotions, treat a missing `ingested_at` key the same as
  `ingested_at: null` — both mean "not yet ingested."
