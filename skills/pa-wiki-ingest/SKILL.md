---
name: pa-wiki-ingest
description: >-
  Promote new project-agent learnings.json entries into the wiki vault. Reads
  unprocessed entries (those without an ingested_at timestamp), distills them
  into structured wiki pages, and stamps each entry so it is never re-processed.
  Use when the user says "ingest learnings", "update wiki", "promote learnings",
  or after agents complete work.
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob]
---

# PA Wiki Ingest

Promote raw project-agent learning entries into the Obsidian wiki vault as structured, cross-referenced wiki pages.

## When to Use

- User says "ingest learnings", "run wiki ingest", "promote learnings to wiki"
- After one or more agents complete and new entries appear in learnings.json files
- Invoked automatically by the orchestrator when `wiki.auto_ingest: true`

## Arguments

- `--ticket PA-NNN` — ingest only entries whose `source_ticket` matches this ID (overrides `--scope`)
- `--project {name}` — ingest only from this project's learnings file (skips global and other projects)
- `--scope global|project|all` — default `all`; `global` reads only `~/.claude/project-agent/learnings.json`; `project` reads only per-project files

Arguments are optional. With no arguments, process all unprocessed entries from all learnings files.

## Configuration

Load config following the standard two-level merge:

1. Read `~/.claude/project-agent/config.json` (global, if it exists)
2. Read `{cwd}/.project-agent/config.json` (workspace, if it exists)
3. Merge — workspace values override global

Honor these config fields:

- `wiki.enabled` — if `false`, print "Wiki memory is disabled (wiki.enabled=false). Enable it with `/config set wiki.enabled true`." and stop.
- `wiki.vault_path` — path to the vault (supports `~` expansion). Default: `~/projects/obsidian/project-agent`.

If `wiki.vault_path` does not exist on disk: print "Vault not found at {path}. Run PA-002 to scaffold the vault, or set a different path with `/config set wiki.vault_path <path>`." and stop.

## Instructions

---

### Phase 0: Pre-flight Checks

1. Load config (see Configuration above). Stop early if `wiki.enabled=false` or vault is missing.
2. Expand `wiki.vault_path`: replace leading `~` with the user's home directory.
3. Read `{vault}/CLAUDE.md` to load all vault conventions. This is the operational contract for every vault operation.

---

### Phase 1: Discovery — Enumerate Learnings Files

Build the list of learnings files to process, subject to `--scope` and `--project` flags:

**Global file** (include unless `--scope project`):
- `~/.claude/project-agent/learnings.json`
- Also treat `.project-agent/learnings.json` (workspace-level, if it exists) as global scope

**Per-project files** (include unless `--scope global`):
- Read `{cwd}/.project-agent/registry.json` to get all registered projects
- For each project (or just the `--project` project if specified): `.project-agent/projects/{name}/learnings.json`
- Skip any file that doesn't exist on disk (not an error — project may have no learnings yet)

Result: a list of `{file_path, scope, project_name}` tuples where `scope` is `global` or `project` and `project_name` is `null` for global files.

---

### Phase 2: Filter — Collect Unprocessed Entries

For each file in the discovery list:

1. Read the JSON file. If the file is missing or empty, skip (not an error).
2. Parse the JSON array. Each entry has: `id`, `text`, `source_ticket`, `agent`, `created_at`, and optionally `ingested_at`.
3. **Filter rule:** keep entries where `ingested_at` is absent or null.
4. If `--ticket PA-NNN` is set: further restrict to entries where `source_ticket === "PA-NNN"`. Both conditions must hold — the entry must match the ticket AND have no `ingested_at` field. These filters are always ANDed; `--ticket` never bypasses the idempotency guard.

If no entries pass the filter anywhere: print a no-op summary and stop:
```
Wiki ingest: no new entries to process.
Last run already stamped all entries. Nothing to do.
```
Append a no-op entry to `{vault}/log.md` (see Phase 8) and stop.

---

### Phase 3: Snapshot — Write Source Pages

For each unprocessed entry, create an immutable source page in the vault. The source page preserves the raw entry verbatim and is never modified after creation.

**Source directory:**
- Global entry → `{vault}/sources/global/`
- Project entry → `{vault}/sources/projects/{name}/`

Create the directory if it does not exist.

**Source filename** (3-part format, per Section 14 of vault-schema.md):
```
{YYYY-MM-DD}-{learning-id}-{slug}.md
```
- `YYYY-MM-DD` is the date portion of `created_at` (the entry's creation date, not today)
- `learning-id` is the `id` field from the entry, lowercased (e.g., `l-001`)
- `slug` is derived from the first sentence of `text`: lowercase, replace spaces and punctuation with hyphens, max 50 characters, no leading/trailing hyphens

Example: `2026-01-15-l-001-worktree-branches-from-main.md`

**Source page content:**
```markdown
---
type: source
scope: {global|project}
project: {null|"project-name"}
learning_id: "{id}"
source_ticket: "{source_ticket}"
agent: "{agent}"
ingested_at: "{ISO8601-now}"
created_at: "{created_at}"
---

{verbatim text field from the entry}
```

Do not add wikilinks, interpretation, or any modifications to the body. Source pages are immutable.

**Idempotency:** before writing, check if the file already exists (it shouldn't if `ingested_at` filtering works, but be defensive). If it exists, skip creation and log a warning.

Collect the source wikilink for each entry (used in Phase 5):
- Global: `[[sources/global/{filename-without-extension}]]`
- Project: `[[sources/projects/{name}/{filename-without-extension}]]`

---

### Phase 4: Classify — Infer Category, Title, Keywords

For each entry, derive the metadata needed for wiki page routing.

#### Category Inference

Infer from the `text` field using these signal-based rules (applied in order; first match wins):

1. Text contains any of: `don't`, `avoid`, `never`, `broke`, `failed`, `error`, `bug`, `issue`, `pitfall`, `gotcha`, `problem`, `mistake` → `gotcha`
2. Text contains any of: `always`, `pattern`, `approach`, `convention`, `prefer`, `best practice`, `should`, `recommend` → `pattern`
3. Text contains any of: `decided`, `chose`, `ADR`, `trade-off`, `decision`, `rationale` → `decision`
4. Text has a tool name as primary subject (git, claude, obsidian, npm, pnpm, bash, ripgrep, rg, jq, python, node, brew, etc.) → `tool` (global scope) or `gotcha`/`architecture` if project scope and context warrants
5. Default → `concept` (global scope) or `architecture` (project scope)

**Per-project scope** only uses: `architecture`, `domain`, `gotcha`, `decision`. Map as:
- `concept` → `architecture` (project default)
- `pattern` → `architecture`
- `tool` → `gotcha` (project scope has no tool category)
- `gotcha` → `gotcha`
- `decision` → `decision`
- If text contains business/domain-specific terms (entities, processes, rules, invariants, terminology unique to the project) → `domain`

#### Title Generation

Generate a short, canonical, human-readable title from the entry text:

1. First, search the target wiki category directory for existing page titles. Read all `.md` file frontmatter `title:` fields. **Prefer reusing an existing title** if the entry is semantically about the same thing — this is what makes knowledge compound.
2. If reusing: use the existing page's exact title (enables the merge path in Phase 5).
3. If creating new: extract a noun phrase from the first sentence. Aim for 3–6 words. Title case. No trailing punctuation.

#### Keyword Extraction

Extract 3–5 keywords from the entry text. Prefer:
- Proper nouns (tool names, project names, ticket IDs)
- Technical terms specific to the entry
- Action verbs that describe the core behavior
- Avoid generic words ("the", "a", "in", "to", "be")

---

### Phase 5: Merge — Update or Create Wiki Pages

For each classified entry, determine whether to update an existing wiki page or create a new one. Use the algorithm from vault-schema.md Section 7, exactly as specified.

**Target directory:**
- Global entry, category `concept` → `{vault}/wiki/concepts/`
- Global entry, category `pattern` → `{vault}/wiki/patterns/`
- Global entry, category `tool` → `{vault}/wiki/tools/`
- Global entry, category `decision` → `{vault}/wiki/decisions/`
- Global entry, category `gotcha` → `{vault}/wiki/gotchas/`
- Project entry, category `architecture` → `{vault}/projects/{name}/architecture/`
- Project entry, category `domain` → `{vault}/projects/{name}/domain/`
- Project entry, category `decision` → `{vault}/projects/{name}/decisions/`
- Project entry, category `gotcha` → `{vault}/projects/{name}/gotchas/`

Create the directory if it does not exist.

#### Step 1 — Title Fuzzy Match

Compare the candidate title (from Phase 4) against all existing wiki page `title:` fields in the target directory:

- Read all `.md` files in the target directory; extract their `title:` frontmatter field
- **Match criteria (binary — no scoring):**
  - Levenshtein distance between candidate title and existing title is ≤ 2, OR
  - One title is a case-insensitive substring of the other
- If either criterion is satisfied → match found → proceed to Update (Step 4)
- If neither is satisfied for any page → proceed to Step 2

To compute Levenshtein distance without external libraries: implement inline using the standard dynamic programming approach (it is short enough to write inline in a skill). If the titles differ by more than `max(len(a), len(b))` characters in raw length, they cannot match on Levenshtein — skip the DP computation as an optimization.

#### Step 2 — Keyword + Category Match

- Take the 3–5 keywords from Phase 4
- Use Grep to search the target wiki directory for those keywords (grep each keyword separately across all `.md` files in the directory)
- For each candidate page found by grep: read its `category:` frontmatter field
- A candidate page matches if: **≥ 3 keywords were found in it AND its `category` matches the inferred category**
- If a match is found → proceed to Update (Step 4)
- If no match → proceed to Create (Step 5)

#### Step 3 — Category Inference (used by Step 2 and Step 5)

Already performed in Phase 4. No additional work needed here.

#### Step 4 — Update Existing Page

1. Read the existing wiki page in full.
2. **Contradiction check (Phase 6 — run first, before writing anything).**
3. If no contradiction: append new information under the appropriate section heading (see Section 13 of vault-schema.md for required sections by category). Do not replace existing content — add to it.
4. Update frontmatter:
   - Add source wikilink to `sources:` array (append, do not duplicate)
   - Add `source_ticket` to `tickets:` array (if not already present)
   - Add `agent` to `agents:` array (if not already present)
   - Set `updated:` to today's date in `YYYY-MM-DD` format
5. If contradiction was detected: insert warning callout (see Phase 6) and downgrade `status:` to `draft`.
6. Write the updated file.

Record: `{page_path, action: "updated", title}` for the log.

#### Step 5 — Create New Page

No match found in Steps 1–2.

1. Determine the category (from Phase 4).
2. Generate a slug from the title: lowercase, replace spaces and punctuation with hyphens, collapse consecutive hyphens, strip leading/trailing hyphens, max 50 chars.
3. For `decision` category: slug must be prefixed `adr-NNN-` where NNN is the next available zero-padded three-digit number. Count existing `adr-NNN-*` files in the target directory to determine NNN.
4. **Target filename:** `{slug}.md` (or `adr-NNN-{slug}.md` for decisions).
5. Read the appropriate template from `{vault}/templates/{category}.md`. Use the template file that PA-002 placed there — do not hardcode the template content inline.
6. Perform string substitution on the template:
   - `{{title}}` → the generated title
   - `{{date}}` → today's date in `YYYY-MM-DD`
   - `{{project}}` → the project name (only present in `architecture.md` and `domain.md` templates)
7. After substitution, set the correct frontmatter:
   - `scope:` → `global` or `project`
   - `project:` → `null` (global) or `"{name}"` (project)
   - `sources:` → `["[[sources/.../{source-filename}]]"]`
   - `tickets:` → `["{source_ticket}"]`
   - `agents:` → `["{agent}"]`
   - `status:` → `stub` if entry text is fewer than 50 words AND contains no concrete example or command; otherwise `draft`
8. For non-stub pages: after filling in frontmatter, synthesize the body content from the learning text. Fill in the section headings (per Section 13) with content derived from the learning entry. Write substantive content, not just the comment placeholders.
9. Write the file.

Record: `{page_path, action: "created", title}` for the log.

---

### Phase 6: Contradiction Detection

Run this check **during Step 4 (Update)** before writing any changes.

**Detection signals** — the new entry text contradicts existing page content when:
- The new text negates a claim on the page ("don't" vs "always", "avoid" vs "prefer", "never" vs "use")
- The new text prescribes a different tool or approach for the same problem and presents it as the right answer
- The new text contains a date-bounded correction ("as of version X", "no longer applies", "deprecated")

**Procedure:**
1. Read the existing wiki page body.
2. Compare the new entry text against the existing body. Look for the signals above.
3. If no contradiction detected: proceed normally with the update.
4. If contradiction detected:
   - Do NOT overwrite the conflicting content
   - Identify the specific paragraph or claim on the page that conflicts
   - Insert immediately below that paragraph:
     ```markdown
     > [!warning] Contradicts [[{path/to/this-page}|{this page's title}]]
     > New evidence from [[sources/{scope}/{source-filename}]] (ticket {source_ticket}, agent {agent}) suggests the opposite. Needs human review.
     ```
   - Note: the wikilink in the callout header is a self-link to the wiki page being updated — the page whose existing content is contradicted. The PA-001 Section 8 phrase "other page" refers to this same existing wiki page from the incoming source entry's perspective: the "other" page is other-than-the-source, i.e., the page being written to. The source wikilink in the body identifies the contradicting entry.
   - Downgrade the page's `status:` frontmatter to `draft` (even if it was `reviewed`)
   - Append the new entry's information to the page under its relevant section (still add the knowledge — just flag the conflict)
   - Record this contradiction for the log

---

### Phase 7: Cross-Link Phase

After writing or updating a wiki page, find related pages and establish bidirectional wikilinks.

**Scope of search:** grep only the target scope directories to avoid false positives:
- Global entries: search `{vault}/wiki/` only
- Project entries: search `{vault}/projects/{name}/` only

**Procedure:**
1. Take the page's title and top 3 keywords.
2. Use Grep to search the scoped directories for these terms across `.md` files (exclude source pages).
3. For each candidate page returned (that is NOT the page just written):
   - Read it briefly to verify the relationship is semantically meaningful (not just incidental keyword co-occurrence)
   - If meaningful: add a wikilink to the related page in the "Related Pages" section of the page just written
   - Check if the related page already links back. If not, and the relationship is meaningful, add a back-link wikilink to the related page's "Related Pages" section and update its `updated:` date
4. Do not add wikilinks to source pages. Do not add wikilinks for generic terms.
5. Use the full wikilink format with display name: `[[wiki/concepts/slug|Display Name]]` or `[[projects/{name}/gotchas/slug|Display Name]]`.

**Important:** do not hallucinate links to pages that don't exist. Only link to files that are confirmed to exist on disk.

---

### Phase 8: Index Update

Phase 8 has two sub-steps with different trigger conditions. Run both sub-steps for each processed entry, but only Phase 8B fires for newly created pages.

#### Phase 8A — Always run (every processed entry, whether update or create)

1. Read `{vault}/index.md`.
2. **Recent Sources section:** prepend a new entry for the source page at the top of the "Recent Sources" list. Keep only the most recent 20 entries — remove any beyond position 20:
   ```
   - `{YYYY-MM-DD}` — [[sources/global/{filename}]] (ticket {source_ticket}, agent {agent}) — {first sentence or short summary of entry text}
   ```
3. Update the "Last updated" timestamp at the top of `index.md` to today's date.
4. Write the updated `index.md`.

Phase 8A fires after **both** Step 4 (update existing page) and Step 5 (create new page) in Phase 5. It must never be skipped for processed entries.

#### Phase 8B — New pages only (fired only when Step 5 created a new page)

1. Read `{vault}/index.md` (or use the version already in memory from Phase 8A if written in the same pass).
2. Find the correct section for the new page:
   - Global pages: under `## Global` → `### {Category plural title}` (e.g., `### Concepts`, `### Patterns`, `### Tools`, `### Decisions`, `### Gotchas`)
   - Project pages: under `## Projects` → `### {project-name}` → `#### {Category plural title}` (e.g., `#### Architecture`, `#### Domain`, `#### Decisions`, `#### Gotchas`)
3. If the `### {project-name}` block doesn't exist yet (new project): insert the full project block with all four subsections after the last existing project block under `## Projects`.
4. Add the new page as a list item under the correct subsection, maintaining alphabetical order:
   ```
   - [[wiki/concepts/slug|Title]] — one-line description
   ```
   or for decisions:
   ```
   - [[wiki/decisions/adr-NNN-slug|ADR-NNN: Title]] — one-line description
   ```
5. Write the updated `index.md`.

**Decision flow summary:**
- Step 4 fired (update) → run Phase 8A only
- Step 5 fired (create) → run Phase 8A then Phase 8B (in that order, merging both changes into a single write if possible)

---

### Phase 9: Log Append

Append a new block **at the top** of `{vault}/log.md` (reverse-chronological — newest first).

Format (from vault-schema.md Section 11):

```markdown
### {YYYY-MM-DD HH:MM} — ingest

- **Operation:** ingest
- **Trigger:** {manual | post-completion | dispatch}
- **Input:** {N} new entries from {source description} (e.g., "3 new entries from PA-007 developer, 1 from global")
- **Pages created:** {comma-separated wikilinks, or "none"}
- **Pages updated:** {comma-separated wikilinks, or "none"}
- **Contradictions flagged:** {comma-separated wikilinks with "(see warning callout)", or "none"}
- **Notes:** {any additional context, or omit line if nothing to add}
```

For a no-op run (no entries to process):
```markdown
### {YYYY-MM-DD HH:MM} — ingest

- **Operation:** ingest
- **Trigger:** {manual | post-completion | dispatch}
- **Input:** 0 new entries (all entries already stamped)
- **Pages created:** none
- **Pages updated:** none
- **Contradictions flagged:** none
- **Notes:** No-op — nothing to process.
```

---

### Phase 10: Stamp — Write `ingested_at` to Source Learnings

For each entry that was successfully processed (source page written + wiki page written or updated):

1. Read the source `learnings.json` file.
2. Find the entry by `id`.
3. Add `"ingested_at": "{ISO8601-timestamp}"` to the entry object. Do not delete any existing fields.
4. Write the updated JSON back to the file with consistent formatting (2-space indentation).

**Atomicity note:** process all entries for a single `learnings.json` file, then write the file once. Do not write the file N times for N entries — batch the stamps.

**Failure handling:** if a source page or wiki page write failed for a particular entry, do NOT stamp that entry. Only stamp entries that completed the full pipeline. This ensures failed entries will be retried on the next run.

---

### Phase 11: Report

After completing all phases, report to the user:

```
## Wiki Ingest Complete

**Processed:** {N} entries from {M} learnings files
**Source pages created:** {N}
**Wiki pages created:** {list of [[wikilinks]] with titles}
**Wiki pages updated:** {list of [[wikilinks]] with titles}
**Contradictions flagged:** {list of [[wikilinks]] or "none"}
**Entries stamped:** {N}

{If pages were created or updated, list them with one-line descriptions}
```

---

## Algorithm Summary (Quick Reference)

```
Phase 0: Pre-flight — config, vault check, read CLAUDE.md
Phase 1: Discovery — enumerate learnings files per scope/project flags
Phase 2: Filter — collect entries without ingested_at
         → early exit if nothing to process
Phase 3: Snapshot — write immutable source pages to sources/{scope}/
Phase 4: Classify — infer category, title, keywords per entry
Phase 5: Merge — for each entry:
           Step 1: title fuzzy match (Levenshtein ≤ 2 OR substring)
           Step 2: keyword + category match (≥3 keywords AND same category)
           → match found  → Step 4: update existing page
           → no match     → Step 5: create new page from template
Phase 6: Contradiction — detect conflicts, insert [!warning] callout, downgrade status
Phase 7: Cross-link — bidirectional wikilinks within scoped directories only
Phase 8: Index update — Phase 8A (every entry): prepend to Recent Sources, update timestamp
                       Phase 8B (new pages only): add page link in alphabetical order
Phase 9: Log append — prepend block to log.md
Phase 10: Stamp — write ingested_at to processed entries in learnings.json
Phase 11: Report — summary to user
```

---

## Edge Cases

### Empty learnings file or no new entries

Detected in Phase 2. Print the no-op message, append a no-op log entry, and stop. Do not create any files.

### Malformed JSON in learnings.json

If the file cannot be parsed as JSON, print: "Could not parse learnings file at {path}: {error}. Skipping this file." Continue with other files. Do not stamp any entries from the malformed file.

### Malformed entry (missing required fields)

If an entry is missing `id`, `text`, `source_ticket`, or `agent`, skip it. Print a warning: "Skipping malformed entry at index {N} in {path}: missing field(s) {list}."

### Vault not yet initialized (PA-002 not run)

Caught in Phase 0. Print the clear message pointing to PA-002 and stop. Do not create any vault directories.

### Template file missing

If `{vault}/templates/{category}.md` does not exist, print: "Template missing: {vault}/templates/{category}.md. Was PA-002 run successfully? Cannot create new {category} page." Skip creating the page but continue with other entries. Do not stamp the entry.

### Duplicate source filename

If a source page already exists at the computed path (idempotency guard), skip creation and log a warning. Continue with the wiki page merge step using the existing source wikilink.

### Decision ADR numbering conflict

If the computed `adr-NNN-` prefix conflicts with an existing file (unlikely but possible if files were manually created), increment NNN until a free slot is found.

### Project not in registry

If `--project {name}` is specified but the project does not appear in `registry.json`, print: "Project '{name}' not found in registry. Run `/plan-project {name}` first or check the spelling." and stop.

### Vault directory creation failure

If creating a required directory fails (e.g., permissions), print the error and stop the entire run. Do not stamp any entries — the user needs to fix the environment before entries are marked as processed.

---

## Idempotency Guarantee

Running `/pa-wiki-ingest` twice in a row with no new learning entries is always a no-op. This is guaranteed by:

1. Phase 2 filters out entries where `ingested_at` is already set
2. Phase 10 stamps entries only after successful processing
3. Phase 3 includes an existence check before creating source pages

The only observable side effect of a second run is a new no-op entry in `log.md`.

---

## Important Invariants

- **Sources are immutable.** Never modify a source page after creation.
- **Append-only on wiki pages.** When updating, add information — never delete existing content.
- **No hallucinated wikilinks.** Only link to pages confirmed to exist on disk.
- **Stamp only on success.** An entry is stamped only after both its source page and wiki page are written successfully.
- **Scoped grep only.** Cross-link search is limited to the target scope directory (`wiki/` for global, `projects/{name}/` for project). Do not search across scopes to avoid spurious cross-links.
- **Binary match criteria.** The merge algorithm uses strict binary criteria (Levenshtein ≤ 2 OR substring). Do not invent a confidence score.
- **Human-reviewed contradictions.** Never auto-resolve contradiction callouts. Surface them and wait for human or lint intervention.
