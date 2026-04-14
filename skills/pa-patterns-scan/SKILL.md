---
name: pa-patterns-scan
description: >-
  Scan a directory or file for recurring patterns and propose them as templates
  one at a time. For each candidate, Claude drafts a template page, shows it
  inline for approval, and writes accepted templates to the vault via the same
  write path as /pa-patterns-capture. Use when the user says "scan this
  directory for patterns", "find patterns in", "extract templates from", or
  "what patterns are in this codebase".
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob]
---

# PA Patterns Scan

Scan a directory or file for recurring patterns and propose 3-7 template
candidates to the user one at a time. Each candidate goes through the same
inline approval flow as `/pa-patterns-capture` — the user accepts, edits, or
rejects each draft before anything is written to the vault. Scan is read-only
on the target; source code is never modified.

## When to Use

- User says "scan this directory for patterns", "find patterns in X"
- User wants to extract reusable templates from an existing codebase or module
- User says "what patterns does this directory use?"

## Arguments

```
/pa-patterns-scan <path>
```

- **`<path>`** (required) — absolute or relative path to a directory or file.
  - **Directory** — survey all readable source files for recurring patterns
  - **File** — extract patterns from that single file (e.g. multiple similar functions, repeated idioms)

## Configuration

Load config via the standard two-level merge (identical to `/pa-patterns-capture` Phase 0):

1. Read `~/.claude/project-agent/config.json` (global, if it exists)
2. Read `{cwd}/.project-agent/config.json` (workspace, if it exists)
3. Merge — workspace values override global

Honor these config fields:

- `wiki.enabled` — if `false`, print the disabled message and stop (see Phase 0).
- `wiki.patterns.enabled` — if `false`, print the patterns-disabled message and stop (see Phase 0). Missing key defaults to `true`.
- `wiki.vault_path` — path to the vault (supports `~` expansion). Default: `~/projects/obsidian/project-agent`.

## Instructions

---

### Phase 0: Pre-flight — Load Config

This phase is identical to `pa-patterns-capture` Phase 0. Copy the behavior exactly — do not diverge.

1. Read `~/.claude/project-agent/config.json`. If the file does not exist, start from empty config.
2. Read `{cwd}/.project-agent/config.json`. If it does not exist, skip.
3. Merge — workspace values override global. When a key exists in both, workspace wins.
4. Extract `wiki.enabled` (default: `true`) and `wiki.vault_path` (default: `~/projects/obsidian/project-agent`).
5. If `wiki.enabled` is `false`:
   ```
   Wiki memory is disabled (wiki.enabled = false in config).
   Run `/pa-config set wiki.enabled true` to enable it.
   ```
   Stop — do not proceed.
6. Extract `wiki.patterns.enabled` (default: `true`). If `wiki.patterns.enabled` is `false`:
   ```
   Pattern library is disabled (wiki.patterns.enabled=false). Enable it with `/pa-config set wiki.patterns.enabled true`.
   ```
   Stop — do not proceed.
7. Expand `~` in `wiki.vault_path` to the actual home directory path.
8. Verify the vault root exists on disk. If not:
   ```
   Vault not found at {vault_path}.
   Run /pa-wiki-ingest once to scaffold the vault, or set a different path with:
     /pa-config set wiki.vault_path <path>
   ```
   Stop.
9. Read `{vault}/CLAUDE.md` to load vault conventions (if it exists). This is informational — do not fail if absent.

---

### Phase 1: Validate Target

1. If no argument is provided, print:
   ```
   Please provide a path to scan. Example:
     /pa-patterns-scan src/hooks/
     /pa-patterns-scan src/utils/apiClient.ts
   ```
   Stop.
2. Expand `~` in the path if present.
3. Check whether the path exists using Bash `test -e {path}`.
   - If the path does **not** exist, print:
     ```
     Path not found: {path}
     Please provide a path that exists on disk.
     ```
     Stop.
4. Determine the scan mode:
   - `test -f {path}` → **File mode** — scan a single file
   - `test -d {path}` → **Directory mode** — survey the directory
5. Record: `scan_mode` (`file` or `directory`), `scan_target` (the resolved absolute path).

---

### Phase 2: Survey and Detect Candidates

The goal is to produce a ranked list of **3–7 candidate patterns** drawn from the target. A candidate is a recurring or particularly distinctive code shape, idiom, or structure that a developer would want to document as a reusable template. Quality over quantity — prefer specific and actionable candidates.

Scan is **read-only**. Never write to, modify, or delete any file in the target path.

#### 2A — File Mode

When the target is a single file:

1. Read the file. If unreadable, stop with:
   ```
   Could not read {path}. Check that the file is accessible and not binary.
   ```
2. Detect the file's language from its extension (use the same extension→language table from `pa-patterns-capture` Phase 2).
3. Analyze the file content for recurring internal patterns. Look for:
   - **Repeated function signatures** — multiple functions with similar parameter shapes, return types, or JSDoc conventions
   - **Repeated error handling blocks** — try/catch shapes, Promise chains, or error boundary patterns used more than once
   - **Repeated type/interface structures** — interfaces or type aliases with consistent shapes
   - **Initialization patterns** — class constructors or factory functions with a consistent shape
4. Each distinct pattern found in the file is one candidate. Cap at 7 candidates.
5. Build a `candidates` list. Each candidate has:
   - `label` — a short human-readable label (e.g. "Async error handler pattern")
   - `source_file` — the absolute path to the file
   - `excerpt` — the representative 10–30 line code excerpt illustrating the pattern (a single representative occurrence)
   - `language` — the detected language
   - `rationale` — one sentence explaining why this is a good template candidate

#### 2B — Directory Mode

When the target is a directory:

1. Use Glob to list all files recursively (up to depth 3). Ignore `node_modules`, `.git`, `__pycache__`, `dist`, `build`, `.next`, `coverage`, `.turbo`, `out`.
2. Filter to source code and config extensions: `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.sql`, `.sh`, `.yaml`, `.yml`, `.go`, `.rs`, `.rb`, `.java`, `.cs`, `.toml`, `.json`.
3. If more than 30 files remain, select the 30 most recently modified (use Bash `ls -t` on the directory).

**Detect candidates across four heuristic categories:**

##### Category 1 — Code Utility / Helper Functions

Use Grep to find repeated function-like patterns:
- TypeScript/JavaScript: grep for `^export (function|const|async function)` or `^export default function`
- Python: grep for `^def ` or `^async def `
- Go: grep for `^func `

Group results by shape similarity:
- Functions with very similar parameter list structures (e.g., multiple `(id: string, options?: {...})` shapes)
- Functions in files named `*util*`, `*helper*`, `*service*`, `use*.ts`, `*middleware*`

Each distinct utility/helper shape that appears in 2+ files OR in a clearly utility-oriented file is a candidate.

##### Category 2 — Component / Class Shapes

- Grep for `class .* extends` (base class inheritance patterns)
- Grep for `@Component`, `@Injectable`, `@Module`, `@Controller` (decorator patterns)
- Grep for `React.FC`, `React.Component`, `const .* = (): JSX.Element` (component shapes)

A component or class shape that appears 3+ times or in a shared base-class file is a candidate.

##### Category 3 — Test Idioms

Find files matching `*.test.*`, `*.spec.*`, `*_test.*`, `test_*.py`:
- Grep within those files for `describe(` / `it(` / `test(` / `beforeEach(` / `def test_`
- Look for repeated `beforeEach` / `setUp` blocks that share a similar shape
- Look for repeated assertion patterns (e.g., always asserting `.toMatchObject({...})` with a consistent shape)

A shared test setup or assertion pattern that appears in 3+ test files is a candidate.

##### Category 4 — Config / Schema Shapes

Find config files: `*.json`, `*.yaml`, `*.yml`, `*.toml`, `.env.example`
- For JSON: grep for repeated top-level keys (e.g., every config file has `"env"`, `"database"`, `"redis"`)
- For YAML: grep for repeated top-level keys
- A stable config shape that appears in 2+ config files is a candidate (document the shared schema, not environment-specific values)

##### Ranking

After gathering candidates across all four categories:

1. Assign a distinctiveness score to each candidate:
   - +2 if the pattern appears in 3 or more files
   - +1 if the pattern is in a file whose name signals it is shared (`*util*`, `*helper*`, `*base*`, `*common*`, `*shared*`)
   - +1 if the pattern has clear placeholder points (parameters, options objects, generic types)
   - +1 if the pattern is in a test file (test idioms are high-value templates)
   - -1 if the excerpt is less than 5 lines (too small to be a useful template)

2. Sort descending by score. Keep the top 3–7 candidates.

3. If fewer than 3 candidates are found after filtering: keep all found candidates and note in the report that the directory had limited pattern density.

Record the final `candidates` list (ranked).

---

### Phase 3: Iterate Through Candidates

Iterate through `candidates` in ranked order. For each candidate:

#### 3A — Draft the Template Page

Draft a complete template page for the candidate. Follow `pa-patterns-capture` Phase 4 exactly:

- **Title inference:** use the candidate's `label` converted to Title Case. Prefer specific, descriptive titles (e.g. "Async Repository Method Pattern" rather than "Function Pattern").
- **Slug generation:** same rule as `pa-patterns-capture` Phase 4 — lowercase, hyphens, max 50 chars.
- **Frontmatter:** compose the full frontmatter per PA-001 Section 1. Set `status: proposed`.
- **Body:** compose all five body sections (Purpose, Template, Usage Notes, Examples, Related Pages) using the candidate's `excerpt` as the primary Template section content. Fill in Usage Notes with the placeholder variables identified in the excerpt. Provide one filled-in example in the Examples section using realistic but anonymized data.

Record `draft_content` (frontmatter + body) for this candidate.

#### 3B — Determine Scope

Before showing the draft, determine scope/project — this is a lightweight version of `pa-patterns-capture` Phase 3:

1. Check if `.project-agent/registry.json` exists in the current working directory.
2. If it does not exist: scope stays `global`, project stays `null`. Skip to 3C.
3. If it exists: parse the JSON. Count only active projects.
   - Zero active projects → `scope=global, project=null`.
   - One active project → ask user: "Should this template be global or scoped to `{project-name}`?" (options: Global / Project: {name}).
   - Two or more active projects → show numbered list: "Which scope? 1. Global, 2. Project: {name1}, 3. Project: {name2}, ..."

Record `scope` and `project` for this candidate.

#### 3C — Inline Approval

Invoke the **Template Draft Approval Helper** from `pa-patterns-shared` with:

```
draft_content  = <the full draft_content composed in Phase 3A>
options        = "scan"
context_header = "Candidate {N} of {total}: \"{label}\"\nSource: {source_file}"
```

The helper renders the draft with the `scan` option set (Accept / Edit / Reject /
Skip Remaining), manages the edit loop (up to 3 iterations per candidate), and
returns one of four verdicts. Handle each verdict as follows:

**`verdict: "accepted"`:**
- Use the `content` field returned by the helper (already has `status: approved`).
- Set `draft_content = result.content`.
- Increment `accepted_count`.
- Proceed to Phase 3D (write the page).
- After writing, continue to the next candidate.

**`verdict: "rejected"`:**
- Increment `rejected_count`.
- Print: "Draft discarded. Moving to next candidate."
- **Early stop rule:** if `rejected_count` reaches 3 in a row (no accepts between
  them), print:
  ```
  Three consecutive rejections. Stopping early.
  Run /pa-patterns-scan again with a more specific path if you'd like different candidates.
  ```
  Jump to Phase 4 (final report).
- Otherwise, continue to the next candidate.

**`verdict: "skip_remaining"`:**
- Print: "Stopping scan at your request."
- Jump to Phase 4 (final report).

**Rate cap:** regardless of user choices, stop after 7 candidates have been
proposed (across all outcomes — accepted, edited, rejected). Jump to Phase 4.

#### 3D — Write the Accepted Page

This step is identical to `pa-patterns-capture` Phases 6–7. Execute those phases for the accepted candidate:

**Phase 6 equivalent — Write the Page:**

1. Resolve target directory:
   - `scope=global` → `{vault}/wiki/templates/`
   - `scope=project` → `{vault}/projects/{project}/templates/`
2. Create the directory if it does not exist (`mkdir -p`).
3. Resolve filename: preferred name is `{slug}.md`. Check for collisions — if `{slug}.md` exists, try `{slug}-2.md`, `{slug}-3.md`, etc. Record final `target_path`.
4. Write `draft_content` (with `status: approved`) to `target_path` using the Write tool.
5. On failure: print "Failed to write {target_path}: {error}." Do not update index.md or log.md. Continue to the next candidate (do not stop the scan).

**Phase 7 equivalent — Update Index and Log:**

After the page write succeeds, update index.md and log.md using the same logic as `pa-patterns-capture` Phases 7A and 7B:

*Phase 7A — Update index.md:*

1. Read `{vault}/index.md`. If it does not exist, skip (print a note).
2. Locate the correct subsection:
   - `scope=global` → `### Templates` under `## Global`
   - `scope=project` → `#### Templates` under `## Projects` → `### {project-name}`. If the project block does not exist, insert a new project block (use the full scaffold format from `pa-patterns-capture` Phase 7A).
3. Add a new alphabetically-sorted entry:
   - Global: `- [[wiki/templates/{slug}|{title}]] — {one-line description from Purpose}`
   - Project: `- [[projects/{project}/templates/{slug}|{title}]] — {one-line description from Purpose}`
4. Update the `> Last updated:` timestamp at the top of `index.md`.
5. Write the updated `index.md`.

*Phase 7B — Prepend to log.md:*

Prepend a new block at the top of `{vault}/log.md`:

```markdown
### {YYYY-MM-DD HH:MM} — scan-capture

- **Operation:** scan-capture
- **Trigger:** manual
- **Input:** scan — {scan_target}
- **Pages created:** [[{vault-relative-path}|{title}]]
- **Pages updated:** none
- **Contradictions flagged:** none
- **Notes:** {scope} template; {slug}.md written from pattern scan of {scan_target}
```

If `log.md` does not exist, create it with the standard header (matching `pa-patterns-capture` Phase 7B). If it contains a `No entries yet.` placeholder, replace it.

On log write failure: print a warning and continue — the page is already written.

---

### Phase 4: Final Report

Print a summary of the scan session:

```
## Patterns Scan Complete

**Target:** {scan_target}
**Candidates proposed:** {total_proposed}
**Accepted:** {accepted_count}
**Rejected / skipped:** {rejected_skipped_count}

### Accepted Templates
{for each accepted template:}
- **{title}** → {target_path}
{if none: - (none accepted)}

### Next Steps
- View all templates: /pa-wiki-status
- Search the wiki: /pa-wiki-query --query "template"
- Capture more patterns manually: /pa-patterns-capture <path>
```

---

## Algorithm Summary (Quick Reference)

```
Phase 0: Pre-flight — config load (identical to pa-patterns-capture Phase 0)
         → wiki.enabled check → wiki.patterns.enabled check → vault existence check
Phase 1: Validate target — path must exist; detect file vs. directory mode
Phase 2: Survey and detect candidates
         → File mode: analyze single file for repeated function/error/type shapes
         → Directory mode: run 4-category heuristics (utilities, components,
           tests, configs); score and rank; keep top 3-7
Phase 3: Iterate through candidates (one at a time, user controls the loop)
         For each candidate:
           3A — Draft template page (pa-patterns-capture Phase 4 logic)
           3B — Determine scope (pa-patterns-capture Phase 3 lite)
           3C — Inline approval: invoke Template Draft Approval Helper (pa-patterns-shared)
                options = "scan"; context_header includes candidate N-of-total + source
                → verdict: accepted      → write (3D); continue loop
                → verdict: rejected      → reject×3 in a row → early stop
                → verdict: skip_remaining → jump to Phase 4
                → 7 candidates proposed  → stop (rate cap)
           3D — Write accepted page (pa-patterns-capture Phases 6-7 logic)
Phase 4: Final report — candidates proposed, accepted, written paths
```

---

## Error Handling

| Situation | Behavior |
|-----------|----------|
| `wiki.enabled = false` | Print disabled message, stop. No files touched. |
| `wiki.patterns.enabled = false` | Print patterns-disabled message, stop. No files touched. |
| Vault path does not exist | Print vault-not-found message with setup instructions, stop. |
| No argument provided | Prompt user for path, stop. |
| Path not found on disk | Print not-found message, stop. |
| File is unreadable (binary, permissions) | Stop with a clear error message. |
| Directory has no readable source files | Report 0 candidates found; skip to Phase 4. |
| Fewer than 3 candidates detected | Report all found (even if 1-2); note limited pattern density. |
| User rejects 3 candidates in a row | Early stop, jump to Phase 4. |
| User selects "Skip remaining" | Immediate jump to Phase 4. |
| 7 candidates proposed | Rate cap reached; jump to Phase 4. |
| Write fails for an individual candidate | Print error, do NOT update index/log for that candidate, continue to next. |
| index.md does not exist | Skip 7A with a note. 7B still runs. |
| log.md write fails | Print warning, continue. |

---

## Important Invariants

- **Read-only on target.** The scan skill never writes to, modifies, or deletes any file under `{scan_target}`. All writes go to the vault only.
- **User approval is required per candidate.** Never write a template to the vault without explicit acceptance in Phase 3C.
- **No bulk accept.** The user must approve each candidate individually. There is no "accept all" option.
- **Shared approval UX.** Phase 3C invokes the Template Draft Approval Helper from `pa-patterns-shared` (options=`"scan"`). This is the same helper used by `/pa-patterns-capture` Phase 5 (options=`"capture"`). Changes to the approval flow belong in `pa-patterns-shared/SKILL.md`.
- **Reuses pa-patterns-capture write path.** Phases 3D (write) and 7A/7B (index/log) replicate the exact logic from `pa-patterns-capture` Phases 6–7.
- **status: approved only on accept.** Drafts start as `proposed`. Written files are always `approved`.
- **Slug collision is sequential.** Use `-2`, `-3`, etc. — not hashes.
- **Log is informational.** Log write failures must never prevent page writes or stop the iteration loop.
- **No hallucinated wikilinks.** Related Pages section starts with a comment placeholder only.
- **scan-capture operation tag.** Log entries use `operation: scan-capture` and `trigger: manual` to distinguish scan-origin templates from manually captured ones.
