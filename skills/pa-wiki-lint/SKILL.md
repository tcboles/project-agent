---
name: pa-wiki-lint
description: >-
  Health-check the project-agent wiki vault for orphans, dead links, unresolved
  contradictions, stale stubs, outdated pages, and missing frontmatter. Use when
  the user says "lint the wiki", "check wiki health", "wiki lint", or wants to
  verify vault quality.
allowed-tools: [Bash, Read, Grep, Glob]
---

# PA Wiki Lint

Run a comprehensive health check on the project-agent wiki vault and print a
sectioned punch list of issues.

## Constants (tune here)

```
STUB_STALE_DAYS        = 7    # pages with status:stub older than this are flagged
CONTRADICTION_DAYS     = 14   # [!warning] Contradicts callouts older than this need review
PROPOSED_STALE_DAYS    = 30   # template pages with status:proposed older than this are flagged
```

## When to Use

- User says "lint the wiki", "check wiki health", `/pa-wiki-lint`
- After a batch of ingests to verify consistency
- Periodically to keep the vault healthy

## Arguments

- `--project {name}` — optional; scope lint to one project's pages only
- `--scope global|project|all` — optional; default `all`
  - `global` → only scan `wiki/`
  - `project` → only scan `projects/`
  - `all` → scan both (default)

## Configuration

1. Read global config from `~/.claude/project-agent/config.json` (if it exists).
2. Read workspace config from `{cwd}/.project-agent/config.json` (if it exists).
3. Merge (workspace overrides global).
4. Use `wiki.vault_path` (default: `~/projects/obsidian/project-agent`) as the vault root.
   Expand `~` to the actual home directory.

If `wiki.enabled` is `false`, print `Wiki memory is disabled in config.` and stop.

## Orphan Exemptions

The following pages are intentional hubs with no inbound links and are ALWAYS
exempt from orphan detection:

- `index.md` — master content catalog; it links out but nothing links in
- `log.md` — append-only log; never linked
- `CLAUDE.md` — schema spec; never linked
- Any page with `status: hub` in its frontmatter (escape hatch for future hubs)

This is the **explicit exemption list** approach. It is preferred over the
`status: hub` approach alone because `index.md`, `log.md`, and `CLAUDE.md` exist
at the vault root and would require frontmatter to be added just to silence
lint — that frontmatter would be incorrect (they are not wiki pages).

## Instructions

### Step 1: Resolve Vault Path and Arguments

1. Parse `--project` and `--scope` from the user's input (if provided).
2. Resolve the vault root path from config (expand `~`).
3. Verify the vault root exists. If not, print:
   ```
   Vault not found at {vault_path}. Run PA-002 scaffold or check wiki.vault_path in config.
   ```
   and stop.

### Step 2: Build Page Inventory

Collect all `.md` files that are subject to linting:

- **If scope=global or scope=all:** collect all `.md` files under `{vault}/wiki/`
- **If scope=project or scope=all:** collect all `.md` files under `{vault}/projects/`
  - If `--project {name}` was specified, restrict to `{vault}/projects/{name}/` only
- **Always exclude from lint scope (not wiki pages):**
  - `{vault}/index.md`
  - `{vault}/log.md`
  - `{vault}/CLAUDE.md`
  - `{vault}/templates/` (all files)
  - `{vault}/sources/` (all files — source pages have a different frontmatter schema)

Store the list as `wiki_pages` (absolute paths).

Also collect `{vault}/sources/` files separately as `source_pages` — used only
for dead-link resolution, not as lint targets themselves.

### Step 3: Read index.md

Read `{vault}/index.md`. Extract all wikilinks it contains using the pattern
`\[\[([^\]]+)\]\]`. Normalize each target: strip display names (the `|...` part),
resolve relative to vault root. Store as `index_linked_pages` (set of paths).

### Step 4: Extract All Wikilinks Across All Wiki Pages

For each page in `wiki_pages`:
- Read the file
- Extract all `[[...]]` wikilinks using pattern `\[\[([^\]|]+)(?=[\]|])`
- Normalize each target path relative to vault root (append `.md` if no extension)
- Build two maps:
  - `inbound_links[page]` = set of pages that link TO this page
  - `outbound_links[page]` = set of pages this page links TO

### Step 5: Run Checks

Run all checks. Accumulate results into per-category lists. Do NOT stop early.

---

#### Check A — Orphan Pages

For each page in `wiki_pages`:
1. If the page is in the exemption list (index.md, log.md, CLAUDE.md, or has `status: hub`), skip.
2. Check three conditions:
   - `inbound_links[page]` is empty (no other wiki page links to it)
   - The page is NOT in `index_linked_pages`
   - The page's frontmatter `sources:` list is empty OR the field is absent
3. If ALL THREE are true: flag as orphan.

**Format:** `{relative_path} — no inbound links, not in index, no sources`

**False-positive note:** Pages created during ingest but not yet back-linked will
appear here until the next ingest run. This is expected behavior, not a bug. The
hint line makes this clear.

---

#### Check B — Dead Wikilinks

For each `(source_page, target_path)` pair in `outbound_links`:
1. Resolve `target_path` to an absolute path relative to the vault root.
2. Check if the file exists on disk.
3. If not found: flag as dead link.

Check against BOTH `wiki_pages` AND `source_pages` — a wikilink to a source page
is valid.

**Format:** `{source_page} → [[{target}]] — target file does not exist`

---

#### Check C — Unresolved Contradiction Callouts

For each page in `wiki_pages`:
1. Search the file content for lines matching:
   `> [!warning] Contradicts`
2. For each match found, determine its age:
   - Read the page's `updated:` frontmatter field (YYYY-MM-DD format)
   - Compute days since `updated:` date
   - If `days_since_updated >= CONTRADICTION_DAYS` (default 14): flag
3. If the page has no `updated:` date but has a contradiction callout: flag unconditionally.

**Format:** `{page} — contradiction callout present, last updated {N} days ago (>{CONTRADICTION_DAYS} day threshold)`

**Rationale for using `updated:` as the age proxy:** We cannot know when a specific
callout was inserted without git blame. Using `updated:` is conservative: if the
page was updated recently, the contradiction may have just been added and should be
allowed time for review. If `updated:` is old, the contradiction has been sitting
unreviewed.

---

#### Check D — Stale Stubs

For each page in `wiki_pages`:
1. Read the `status:` frontmatter field.
2. If `status: stub`:
   - Read the `updated:` frontmatter field (YYYY-MM-DD format).
   - Compute days since `updated:`.
   - If `days_since_updated >= STUB_STALE_DAYS` (default 7): flag.
3. If `status: stub` but no `updated:` date: use `created:` date instead. If neither is present, flag unconditionally.

**Format:** `{page} — stub for {N} days (>{STUB_STALE_DAYS} day threshold), needs content`

---

#### Check E — Outdated Pages

This check requires ticket data. Only run if the registry and project boards are
accessible.

For each page in `wiki_pages`:
1. Read the `tickets:` frontmatter field (list of ticket IDs, e.g., `["PA-001", "PA-002"]`).
2. If `tickets:` is empty or absent: skip (no source tickets to check against).
3. Determine the project for this page:
   - If the page's `project:` frontmatter is a non-null string, use that project name.
   - If `project:` is null or absent (global-scope page), search all boards.
4. Load the relevant `board.json` from `{cwd}/.project-agent/projects/{project}/board.json`
   (or all boards if project is unset). Parse the `tickets[]` array.
5. For each ticket ID in the page's `tickets:` list:
   - Look up the entry in the board's `tickets[]` array by matching `id`.
   - Read the `status` field from the board entry.
6. If ALL source tickets have `status: done`:
   - Read the `completed_at` field from each board entry (NOT from the ticket file —
     `completed_at` lives in board.json, not in ticket file frontmatter).
   - Take the latest `completed_at` across all source ticket board entries.
   - Read the wiki page's `updated:` field.
   - If `wiki_page.updated < latest_ticket_completed_at`: flag as potentially stale.
7. Skip this check gracefully if board.json is not accessible or a ticket ID is not
   found in any board (e.g., different cwd, manually created page).

**Format:** `{page} — all source tickets done (latest: {date}), but page last updated {page_updated}. May contain stale claims.`

---

#### Check F — Missing Frontmatter Fields

Required frontmatter fields for all wiki pages (from vault-schema.md Section 5):
`type`, `scope`, `project`, `category`, `title`, `created`, `updated`, `sources`,
`tickets`, `agents`, `status`, `tags`

For each page in `wiki_pages`:
1. Parse the YAML frontmatter block (between the `---` delimiters at the top of the file).
2. Check for the presence of each required field.
3. For fields that are present, validate:
   - `type` must be `wiki`
   - `scope` must be `global` or `project`
   - `status` must be one of `stub`, `draft`, `proposed`, `approved`, `reviewed`, `hub`
   - `category` must be one of: `concept`, `pattern`, `tool`, `decision`, `gotcha`, `architecture`, `domain`, `template`
   - `project`: if `scope=global` must be `null`; if `scope=project` must be a non-null string
4. Flag any missing fields or invalid values.

**Format:** `{page} — missing fields: {field1}, {field2}` or `{page} — invalid status: "{value}" (must be stub|draft|proposed|approved|reviewed|hub)`

---

#### Check G — Template & Asset Checks

This section groups five sub-checks specific to `template` pages and the `assets/` directory.
Run all sub-checks regardless of whether earlier ones find issues. Skip any sub-check gracefully
if the relevant directory (`wiki/templates/`, `assets/`, etc.) does not exist on disk.

---

##### G1 — Template Page Required Sections

For each page in `wiki_pages` where `category: template`:

1. Read the page body (everything after the closing `---` of the frontmatter).
2. Check for the presence of all five required section headings:
   - `## Purpose`
   - `## Template`
   - `## Usage Notes`
   - `## Examples`
   - `## Related Pages`
3. For each missing section heading, flag as WARNING (not error).

**Format:** `{page} — template page missing required sections: {section1}, {section2}`
**Hint:** `Add the missing sections per vault-schema.md Section 9`

---

##### G2 — Asset Existence Check

For each page in `wiki_pages` with a non-empty `assets:` frontmatter array:

1. Determine the page's scope (`global` or `project`) and project name (if scope=project).
2. For each filename in the `assets:` array:
   - If `scope=global`: resolve to `{vault}/assets/global/{filename}`
   - If `scope=project`: resolve to `{vault}/assets/projects/{project}/{filename}`
3. Check if the resolved file exists on disk.
4. If not found: flag as ERROR (not warning) — this is a broken asset reference.

**Format:** `{page} — missing asset: "{filename}" expected at {resolved_path}`
**Hint:** `Copy the asset file to the expected location or remove it from the assets: frontmatter`

---

##### G3 — Orphan Asset Detection

Walk the asset directories and find files with no referencing wiki page:

1. Collect all files under `{vault}/assets/global/` (if directory exists).
2. Collect all files under `{vault}/assets/projects/*/` (if directory exists).
3. Exclude `.gitkeep` files from all directories — they are intentional placeholders.
4. Build a set `all_referenced_assets`:
   - For each page in `wiki_pages` with a non-empty `assets:` array, and for each filename in that array, add the resolved absolute path to the set (using the same resolution logic as G2).
5. For each collected asset file: if its absolute path is NOT in `all_referenced_assets`, flag as WARNING.

**Format:** `{asset_path} — orphaned asset, not referenced by any wiki page`
**Hint:** `Either add this asset to a wiki page's assets: frontmatter, or delete the file`

---

##### G4 — Stale Proposed Template Check

For each page in `wiki_pages` where `category: template` AND `status: proposed`:

1. Read the `updated:` frontmatter field (YYYY-MM-DD format).
2. Compute days since `updated:` date using today's date.
3. If `days_since_updated >= PROPOSED_STALE_DAYS` (default 30): flag as WARNING.
4. If no `updated:` date is present but `created:` is present, use `created:` instead.
5. If neither date is present: flag unconditionally.

**Format:** `{page} — proposed template not reviewed for {N} days (>{PROPOSED_STALE_DAYS} day threshold)`
**Hint:** `Review and either approve (set status: approved) or update the content`

---

##### G5 — `code_language` Style Check

For each page in `wiki_pages` where `code_language:` is present and non-empty:

1. Check if the value contains any uppercase characters (`[A-Z]`).
2. Check if the value contains any whitespace characters.
3. If either condition is true: flag as WARNING.

**Format:** `{page} — code_language "{value}" contains uppercase or whitespace (spec requires lowercase, no spaces)`
**Hint:** `Use lowercase with no spaces, e.g. "typescript" not "TypeScript" or "type script"`

---

### Step 6: Print Punch List

Print a sectioned report. If a section has zero issues, print it with "No issues."
so the operator knows the check ran.

```
## Wiki Lint Report
Vault: {vault_path}
Scope: {all|global|project} {(project: {name}) if filtered}
Date: {ISO date}

---

### A. Orphan Pages (N)
> Pages with no inbound links, not listed in index.md, and no source citations.
> Exempt: index.md, log.md, CLAUDE.md, and pages with status:hub.
- wiki/concepts/some-page.md — no inbound links, not in index, no sources
  (Hint: run /pa-wiki-ingest to add back-links, or add to index.md manually)
...

### B. Dead Wikilinks (N)
> [[...]] references pointing to files that do not exist.
- wiki/patterns/foo.md → [[wiki/concepts/missing-page]] — target file does not exist
  (Hint: update the wikilink or create the missing page)
...

### C. Unresolved Contradiction Callouts (N)
> Pages with [!warning] Contradicts callouts that have not been resolved.
> Threshold: {CONTRADICTION_DAYS} days since last update.
- wiki/gotchas/some-gotcha.md — contradiction callout present, last updated 18 days ago (>14 day threshold)
  (Hint: resolve or dismiss the callout manually; see vault-schema.md Section 8)
...

### D. Stale Stubs (N)
> Pages with status:stub that have not been updated within {STUB_STALE_DAYS} days.
- wiki/concepts/worktree-isolation.md — stub for 12 days (>7 day threshold), needs content
  (Hint: run /pa-wiki-ingest to flesh out, or promote status to draft manually)
...

### E. Outdated Pages (N)
> Pages whose source tickets are all done but the page predates the latest ticket completion.
- projects/wiki-memory/architecture/ingest-flow.md — all source tickets done (latest: 2026-04-10), but page last updated 2026-03-28. May contain stale claims.
  (Hint: review for stale content and update, then bump updated: date)
...

### F. Missing Frontmatter (N)
> Pages missing required frontmatter fields or containing invalid field values.
- wiki/patterns/board-reconciliation.md — missing fields: tags, agents
  (Hint: add the missing fields; see vault-schema.md Section 5 for required fields)
...

### G. Template & Asset Checks (N)
> Template page structure, asset existence, orphaned files, stale proposals, and code_language style.
> Errors (E) are broken asset references. Warnings (W) are structural or style issues.

#### G1. Template Required Sections (N warnings)
- wiki/templates/my-template.md — template page missing required sections: ## Examples, ## Related Pages
  (Hint: Add the missing sections per vault-schema.md Section 9)
...

#### G2. Missing Assets (N errors)
- wiki/templates/my-template.md — missing asset: "diagram.png" expected at {vault}/assets/global/diagram.png
  (Hint: Copy the asset file to the expected location or remove it from the assets: frontmatter)
...

#### G3. Orphan Assets (N warnings)
- {vault}/assets/global/old-diagram.png — orphaned asset, not referenced by any wiki page
  (Hint: Either add this asset to a wiki page's assets: frontmatter, or delete the file)
...

#### G4. Stale Proposed Templates (N warnings)
- wiki/templates/my-template.md — proposed template not reviewed for 45 days (>30 day threshold)
  (Hint: Review and either approve (set status: approved) or update the content)
...

#### G5. code_language Style (N warnings)
- wiki/templates/my-template.md — code_language "TypeScript" contains uppercase or whitespace (spec requires lowercase, no spaces)
  (Hint: Use lowercase with no spaces, e.g. "typescript" not "TypeScript" or "type script")
...

---

Summary: {A+B+C+D+E+F+G} total issues
  {A} orphans | {B} dead links | {C} unresolved contradictions | {D} stale stubs | {E} outdated pages | {F} missing frontmatter
  {G1} template sections | {G2} missing assets (errors) | {G3} orphan assets | {G4} stale proposals | {G5} code_language style
```

If zero total issues:

```
## Wiki Lint Report — Clean
Vault: {vault_path}
Date: {ISO date}

All checks passed. No issues found.
  0 orphans | 0 dead links | 0 unresolved contradictions | 0 stale stubs | 0 outdated pages | 0 missing frontmatter
  0 template sections | 0 missing assets | 0 orphan assets | 0 stale proposals | 0 code_language style
```

### Step 7: Log to log.md

Append a lint entry at the TOP of `{vault}/log.md` using the format from
vault-schema.md Section 11:

```markdown
### {YYYY-MM-DD HH:MM} — lint

- **Operation:** lint
- **Trigger:** manual
- **Input:** scope={scope}{, project={name} if filtered}
- **Issues found:** {A} orphans, {B} dead links, {C} contradictions, {D} stale stubs, {E} outdated pages, {F} missing frontmatter, {G1} template sections, {G2} missing assets, {G3} orphan assets, {G4} stale proposals, {G5} code_language style
- **Issues fixed:** 0 (lint is read-only)
- **Issues requiring human review:** {list of contradiction callout pages with wikilinks, or "none"}
```

This is the ONLY write operation this skill performs.

## Important

- **Read-only** except for the log.md append.
- Run ALL checks before printing the report. Do not short-circuit.
- Never modify vault pages, even to fix obvious issues. Fixes belong in `/pa-wiki-ingest`.
- Parse frontmatter manually: look for the `---` block at the top of each file and
  extract key: value pairs. YAML arrays use `- item` format.
- When checking page ages, use today's date (ISO format) for delta calculations.
- If `log.md` does not exist, create it with just the lint entry block (no header needed).
- Be fault-tolerant: if a single page fails to parse, log a warning for that page and continue.
- **Exit behavior:** If any ERROR-level issues are found (Check G2 missing assets, or any other
  check that designates findings as errors), the lint run exits with a non-zero status. WARNING-level
  issues alone (Checks A, C, D, G1, G3, G4, G5, and most of B, E, F) result in a zero exit.
  Check B (dead wikilinks) and Check F (missing/invalid frontmatter) produce errors, not warnings,
  matching their existing behavior.
- **Missing directories:** If `{vault}/wiki/templates/`, `{vault}/assets/global/`, or
  `{vault}/assets/projects/` do not exist, skip the relevant G sub-checks silently. Do not
  flag their absence as an issue.
