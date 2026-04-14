---
name: pa-patterns-capture
description: >-
  Capture a single template page directly into the wiki vault. The user provides
  a file path, directory path, or freeform description; Claude drafts a template
  page, shows it inline for approval, and writes the approved version with
  status: approved. This is a direct-write path for user-curated content that
  bypasses the /pa-wiki-ingest pipeline. Use when the user says "capture this
  pattern", "save this as a template", "add to wiki", or "store this template".
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob]
---

# PA Patterns Capture

Capture a user-curated template page directly into the wiki vault from a file path, directory path, or freeform description. Bypasses the ingest pipeline — the user approves the draft inline and it is written with `status: approved`.

## When to Use

- User says "capture this pattern", "save this as a template", "add to the wiki"
- User points at a file or directory they want documented as a reusable template
- User describes a pattern or scaffold in prose and wants it stored

## Arguments

```
/pa-patterns-capture [path-or-description]
```

- **File path** — read the file, detect language, extract a representative code snippet, draft a template
- **Directory path** — survey files, identify the most distinctive pattern, draft one template from it
- **Freeform description** (no path, or path doesn't exist) — draft a template from the description text alone
- **Binary asset path** (`.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`, `.pdf`) — asset is copied into the vault's assets directory, and a template page is drafted that embeds the asset via Obsidian wiki link syntax
- **Unsupported binary path** (`.mp4`, `.zip`, `.tar`, `.gz`, `.bin`, `.exe`, `.wasm`, etc.) — not supported; see Phase 1 for the user message

## Configuration

Load config via the standard two-level merge:

1. Read `~/.claude/project-agent/config.json` (global, if it exists)
2. Read `{cwd}/.project-agent/config.json` (workspace, if it exists)
3. Merge — workspace values override global

Honor these config fields:

- `wiki.enabled` — if `false`, print "Wiki memory is disabled (wiki.enabled=false). Enable it with `/pa-config set wiki.enabled true`." and stop.
- `wiki.patterns.enabled` — if `false`, print "Pattern library is disabled (wiki.patterns.enabled=false). Enable it with `/pa-config set wiki.patterns.enabled true`." and stop. Missing key defaults to `true`.
- `wiki.vault_path` — path to the vault (supports `~` expansion). Default: `~/projects/obsidian/project-agent`.

If `wiki.vault_path` does not exist on disk: print "Vault not found at {path}. Run `/pa-wiki-ingest` once to scaffold the vault, or set a different path with `/pa-config set wiki.vault_path <path>`." and stop.

## Instructions

---

### Phase 0: Pre-flight — Load Config

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

### Phase 1: Parse Argument and Detect Mode

Parse the argument provided after `/pa-patterns-capture`. Three modes are possible:

#### Binary asset check (do first)

Before anything else, check if the argument looks like a binary asset path by inspecting the file extension.

**Supported asset extensions:** `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`, `.pdf`

**Unsupported binary extensions:** `.mp4`, `.zip`, `.tar`, `.gz`, `.bin`, `.exe`, `.wasm` (and any other binary-format extension not in the supported set above)

- If the argument ends with a **supported** asset extension: set mode to **Asset mode** and proceed to mode detection below (do NOT stop — continue to Phase 2b after scope selection).
- If the argument ends with an **unsupported** binary extension: print:
  ```
  Binary files of this type are not supported by /pa-patterns-capture.
  Supported asset types: .png, .jpg, .jpeg, .gif, .svg, .webp, .pdf
  For other binary files, use /pa-patterns-capture with a freeform description of the asset's purpose.
  ```
  Stop.

#### Mode detection

1. **No argument provided** — prompt the user: "Please provide a file path, directory path, or freeform description. Example: `/pa-patterns-capture src/hooks/useDebounce.ts`". Stop.
2. **Asset mode already detected** (from the supported asset extension check above):
   a. Expand `~` in the path if present.
   b. Check if the path exists on disk using Bash `test -e {path}`.
   c. If it exists and `test -f {path}` → remain in **Asset mode**. Skip to Phase 3 (scope selection), then continue to Phase 2b.
   d. If the path does NOT exist → fall back to **Description mode** (treat the argument string as freeform text; note: "Asset path not found — treating as freeform description.").
3. **Argument looks like a path** (starts with `/`, `~`, `./`, `../`, or matches a filename with an extension):
   a. Expand `~` in the path if present.
   b. Check if the path exists on disk using Bash `test -e {path}`.
   c. If it exists:
      - `test -f {path}` → **File mode**
      - `test -d {path}` → **Directory mode**
   d. If the path does NOT exist → fall back to **Description mode** (treat the argument string as freeform text; note this in the output: "Path not found — treating as freeform description.").
4. **Argument does not look like a path** → **Description mode**.

Record the detected mode and the original argument string for use in later phases.

> **Execution order for Asset mode:** After mode detection confirms Asset mode, jump to Phase 3 (scope/project selection), then return to Phase 2b (asset ingest), then proceed to Phase 4 (draft template page). This mirrors how file/directory/description modes all flow through Phase 3 before content gathering.

---

### Phase 2: Gather Source Content

#### File Mode

1. Read the file. If the file is unreadable or empty, print a warning and fall back to Description mode using the file path as the description text.
2. Detect language from the file extension:
   | Extension | Language |
   |-----------|----------|
   | `.ts`, `.tsx` | `typescript` |
   | `.js`, `.jsx` | `javascript` |
   | `.py` | `python` |
   | `.sql` | `sql` |
   | `.sh`, `.bash` | `bash` |
   | `.yaml`, `.yml` | `yaml` |
   | `.json` | `json` |
   | `.go` | `go` |
   | `.rs` | `rust` |
   | `.rb` | `ruby` |
   | `.java` | `java` |
   | `.cs` | `csharp` |
   | `.md` | `markdown` |
   | `.html` | `html` |
   | `.css`, `.scss`, `.sass` | `css` |
   | `.toml` | `toml` |
   | other / no extension | `""` (empty) |
3. Extract a representative snippet: use the full file content if it is ≤ 150 lines. If the file is longer than 150 lines, use the first 100 lines. Note in the draft that the full file was truncated.
4. Record: `source_path` (the absolute path), `language` (detected), `snippet` (the extracted content).

#### Directory Mode

1. Use Glob to list all files in the directory recursively (up to depth 3, ignore `node_modules`, `.git`, `__pycache__`, `dist`, `build`, `.next`).
2. Prefer source files — filter to extensions that indicate code or configuration: `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.sql`, `.sh`, `.yaml`, `.yml`, `.go`, `.rs`, `.rb`, `.java`, `.cs`, `.md`.
3. If more than 10 files are found, limit to the 10 most recently modified (use Bash `ls -t` on the directory).
4. Pick the single most distinctive file using this priority order:
   a. A file with a name suggesting it is a shared utility, hook, helper, or base class (patterns: `use*.ts`, `*helper*`, `*util*`, `*base*`, `*mixin*`, `*middleware*`, `*service*`).
   b. The largest file by line count (most content usually means most notable).
   c. The first file alphabetically as a fallback.
5. Treat the selected file as **File mode** from step 1 above. Note the directory path and the selected file path in the draft context.

#### Description Mode

1. The source content is the user's input string.
2. No language is detected from a description — `language` defaults to `""`.
3. Record: `source_path` = null, `language` = `""`, `snippet` = null, `description_text` = the argument string.

---

### Phase 2b: Asset Preparation (Asset mode only)

This phase runs **after Phase 3** (scope/project selection) and **only** when the mode is Asset mode. It resolves the target filename and path for the asset, but does **not** copy the file yet — the actual copy happens in Phase 6 after user approval.

#### Resolve target assets directory

Based on scope from Phase 3:
- `scope=global` → `{vault}/assets/global/`
- `scope=project` → `{vault}/assets/projects/{name}/`

Record `target_assets_dir`.

#### Sanitize the filename

Starting from the source file's basename (e.g., `My Diagram (v2).PNG`):
1. Lowercase all characters.
2. Replace spaces with `-`.
3. Strip any character outside the set `[a-z0-9._-]`.
4. Preserve the file extension (the part after the final `.`).
5. Collapse consecutive hyphens to one. Strip leading/trailing hyphens from the stem.

Example: `My Diagram (v2).PNG` → `my-diagram-v2.png`

Record `sanitized_filename` (e.g., `my-diagram-v2.png`) and `asset_ext` (e.g., `png`).

#### Collision pre-check

Check if `{target_assets_dir}/{sanitized_filename}` already exists on disk.
- If it does NOT exist: plan to use `sanitized_filename` as-is. Record `final_asset_filename`.
- If it DOES exist: try `{stem}-2.{ext}`, then `{stem}-3.{ext}`, continuing sequentially until a free name is found. Record `final_asset_filename`.

Example: if `diagram.png` exists, try `diagram-2.png`, then `diagram-3.png`, etc.

Record:
- `final_asset_filename` — the bare filename to be used (no directory prefix)
- `asset_embed_path` — the vault-relative embed path:
  - `scope=global` → `assets/global/{final_asset_filename}`
  - `scope=project` → `assets/projects/{name}/{final_asset_filename}`

> **Note:** This is a pre-check at the time the draft is composed. A race condition (another process writing the same file before Phase 6) is theoretically possible but acceptable given the interactive nature of this skill.

After recording these, continue to Phase 4 (draft the template page using asset context).

---

### Phase 3: Determine Scope and Project

1. Default scope is `global`.
2. Check if `.project-agent/registry.json` exists in the current working directory.
3. If it does not exist: scope stays `global`, project stays `null`. Skip to Phase 4.
4. If it exists: read and parse the JSON. Extract the `projects` array.
   - Count only projects with `"status": "active"`.
   - If zero active projects: scope stays `global`, project stays `null`. Skip to Phase 4.
   - If one active project: ask the user via `AskUserQuestion`:
     ```
     Does this template apply globally (to all projects) or specifically to "{project-name}"?
     1. Global — available to all projects
     2. Project: {project-name} — scoped to this project only
     ```
     Map answer to scope/project. If the user picks Global: `scope=global, project=null`. If they pick the project: `scope=project, project="{name}"`.
   - If two or more active projects: ask the user via `AskUserQuestion`:
     ```
     Which scope should this template use?
     1. Global — available to all projects
     2. Project: {name1}
     3. Project: {name2}
     ... (one option per active project)
     ```
     Map the user's choice to the appropriate `scope` and `project` values.
5. Record: `scope` (`global` or `project`), `project` (null or a project name string).

---

### Phase 4: Draft the Template Page

Compose the full frontmatter block and body for the new template page. Use the content gathered in Phase 2 (or Phase 2b for asset mode) and scope/project from Phase 3.

#### Title Inference

- **File mode:** use the filename (without extension), converted to Title Case, with hyphens/underscores replaced by spaces. For example, `use-debounce.ts` → `Use Debounce Hook`.
- **Directory mode:** use the selected file's name (same rule) combined with the directory name if informative. For example, selected file `apiClient.ts` in `src/lib/` → `API Client Utility`.
- **Description mode:** extract the first noun phrase from the description text. Aim for 3–6 words in Title Case.
- **Asset mode:** use the sanitized filename stem (without extension), converted to Title Case, with hyphens replaced by spaces. For example, `diagram.png` → `Diagram`, `component-architecture.svg` → `Component Architecture`. If the resulting title is a single generic word (e.g., `Diagram`, `Image`), prepend a qualifier from the asset type: `{Ext} Asset: {Stem}` (e.g., `PNG Asset: Diagram`). The user can edit the title during approval.

If the inferred title seems wrong or generic, choose a more descriptive alternative.

#### Slug Generation

Lowercase the title. Replace spaces and punctuation with hyphens. Collapse consecutive hyphens to one. Strip leading and trailing hyphens. Truncate to 50 characters.

Example: `Use Debounce Hook` → `use-debounce-hook`

#### Frontmatter

**For file / directory / description mode:**

```yaml
---
type: wiki
scope: {global|project}
project: {null|"{name}"}
category: template
title: "{inferred title}"
created: {YYYY-MM-DD today}
updated: {YYYY-MM-DD today}
sources: []
tickets: []
agents: []
status: proposed
tags: []
assets: []
code_language: "{detected language, or empty string}"
applicable_domains: []
---
```

**For asset mode:**

```yaml
---
type: wiki
scope: {global|project}
project: {null|"{name}"}
category: template
title: "{inferred title}"
created: {YYYY-MM-DD today}
updated: {YYYY-MM-DD today}
sources: []
tickets: []
agents: []
status: proposed
tags: []
assets: ["{final_asset_filename}"]
code_language: ""
applicable_domains: []
---
```

Frontmatter rules:
- `status` is always `proposed` in the draft. It becomes `approved` when the user accepts in Phase 5.
- `code_language` is the lowercase language detected in Phase 2. For asset mode, `code_language` is always `""` (binary asset, not code).
- `assets`: for file/directory/description mode, starts as `[]`; for asset mode, contains `["{final_asset_filename}"]` — the bare filename only (no directory path).
- `applicable_domains`, `tags` start as empty arrays. Do not populate them — the user can edit if needed.
- `project` is the literal null keyword (not quoted) for global scope, or a quoted string for project scope.

#### Body

Fill in all five body sections using the source content:

**For file / directory / description mode:**

```markdown
## Purpose

{1–2 sentences describing what this template is for and when to use it. Infer from the code or description.}

## Template

{If file/directory mode: paste the extracted snippet inside a code fence with the detected language tag.}
{If description mode: draft a template scaffold based on the description. Use code fences if the description implies code; use plain markdown otherwise.}

## Usage Notes

{List the key placeholders or variables in the template. Describe what each one expects. If the template has no placeholders, explain the customization points.}

## Examples

{Provide one filled-in example showing the template in use. For file mode, use the source file's actual content as the example if it is short; otherwise write a brief illustrative example.}

## Related Pages

<!-- Add wikilinks to related wiki pages here once they exist -->
<!-- [[wiki/templates/related-slug|Related Title]] -->
```

**For asset mode:**

```markdown
## Purpose

Reference {asset type, e.g. "image"} for {use case inferred from the filename, or generic "reference material"}. {1 additional sentence if the filename suggests a more specific context.}

## Template

![[{asset_embed_path}]]

## Usage Notes

- Asset file: `{final_asset_filename}`
- Stored at: `{asset_embed_path}`
- To use this asset in other pages, embed it with: `![[{asset_embed_path}]]`
- To update the asset, copy the new file to `{target_assets_dir}` with the same filename.

## Examples

<!-- Add usage examples here — show which pages or contexts embed this asset. -->

## Related Pages

<!-- Add wikilinks to related wiki pages here once they exist -->
<!-- [[wiki/templates/related-slug|Related Title]] -->
```

**Mixed capture (asset mode + freeform description):** If the user provided both a description AND an asset path, the Purpose section uses the user's description text instead of the stub above. All other sections remain as in asset mode.

Record the complete draft (frontmatter + body) as `draft_content`.

---

### Phase 5: Inline Approval

Invoke the **Template Draft Approval Helper** from `pa-patterns-shared` with:

```
draft_content = <the full draft_content composed in Phase 4>
options       = "capture"
```

The helper renders the draft to the user, manages the edit loop (up to 3
iterations), and returns one of four verdicts. Handle each verdict as follows:

#### `verdict: "accepted"`

Use the `content` field returned by the helper (it already has `status: approved`
set). Proceed to Phase 6 with `draft_content = result.content`.

#### `verdict: "rejected"`

Print:
```
Draft discarded. No files written.
```
Stop. Do not write any files, do not update index.md or log.md.

> **Asset mode note:** The asset has not been copied at this point (copy happens
> in Phase 6 after approval). Rejection in Phase 5 leaves the vault and all
> asset directories completely untouched.

#### `verdict: "scope_change"`

For file/directory/description mode: return to Phase 3 and re-run scope
selection. Regenerate the frontmatter with the new scope/project. Re-invoke the
helper in Phase 5 with the updated `draft_content` (the helper's edit iteration
counter resets on each fresh invocation).

For asset mode: return to Phase 3, re-run scope selection, then re-run Phase 2b
with the new scope (this may produce a different `final_asset_filename` if there
is a collision in the new directory). Update `asset_embed_path` in the draft
accordingly. Re-invoke the helper in Phase 5 with the updated `draft_content`.

---

### Phase 6: Write the Page

The user has accepted. Finalize the content (status set to `approved`).

#### Resolve target directory

- `scope=global` → `{vault}/wiki/templates/`
- `scope=project` → `{vault}/projects/{project}/templates/`

Create the directory if it does not exist (use Bash `mkdir -p`).

#### Resolve filename

- Preferred filename: `{slug}.md`
- **Collision handling:** check if `{slug}.md` already exists in the target directory. If it does, try `{slug}-2.md`. If that also exists, try `{slug}-3.md`, continuing sequentially until a free name is found.
- Record the final filename and absolute path: `target_path`.

#### Copy the asset (asset mode only)

For asset mode, before writing the template page:
1. Create the target assets directory if it does not exist: `mkdir -p {target_assets_dir}`
2. Copy the source asset file to the resolved target path:
   ```bash
   cp "{source_path}" "{target_assets_dir}/{final_asset_filename}"
   ```
3. Record `asset_target_path` = `{target_assets_dir}/{final_asset_filename}`.

On copy failure: print "Failed to copy asset to {asset_target_path}: {error}. The vault was not modified." and stop. Do not write the template page, do not update index.md or log.md.

#### Write the file

Write `draft_content` (with `status: approved`) to `target_path` using the Write tool.

On failure (template page write): print "Failed to write {target_path}: {error}." and stop. Do not update index.md or log.md.
- If the asset was already copied successfully (asset mode): note "The asset was copied to {asset_target_path} but the template page could not be written. The vault has the asset file but no referencing page. You may need to clean up the asset manually or re-run the capture."

---

### Phase 7: Update Index and Log

Both updates are required. Write index.md and log.md only after the page write in Phase 6 succeeds.

#### Phase 7A — Update index.md

1. Read `{vault}/index.md`. If it does not exist, skip Phase 7A (not a fatal error — print a note).
2. Find the correct subsection:
   - `scope=global` → find `### Templates` under `## Global`
   - `scope=project` → find `#### Templates` under `## Projects` → `### {project-name}`. If the `### {project-name}` block does not exist yet, insert a new project block after the last existing project block under `## Projects`. The block format is:
     ```markdown
     ### {project-name}

     #### Architecture
     <!-- [[projects/{name}/architecture/slug|Title]] — one-line description -->

     #### Domain
     <!-- [[projects/{name}/domain/slug|Title]] — one-line description -->

     #### Decisions
     <!-- [[projects/{name}/decisions/adr-NNN-slug|ADR-NNN: Title]] — one-line description -->

     #### Gotchas
     <!-- [[projects/{name}/gotchas/slug|Title]] — one-line description -->

     #### Templates
     <!-- [[projects/{name}/templates/slug|Title]] — one-line description -->
     ```
3. Add a new entry under the resolved `### Templates` or `#### Templates` section, in alphabetical order by title:
   - Global: `- [[wiki/templates/{slug}|{title}]] — {one-line description inferred from Purpose section}`
   - Project: `- [[projects/{project}/templates/{slug}|{title}]] — {one-line description inferred from Purpose section}`
4. Update the `> Last updated:` timestamp at the top of `index.md` to today's date.
5. Write the updated `index.md`.

**Alphabetical insertion rule:** compare the new title alphabetically against existing titles in the `### Templates` / `#### Templates` block. Insert such that the list remains sorted A→Z. If the section has only comments (no existing list items), add the new entry after the comment placeholder.

#### Phase 7B — Prepend to log.md

Prepend a new block **at the top** of `{vault}/log.md` (reverse-chronological — newest first). Use the exact format from `pa-wiki-ingest` Phase 9:

For file / directory / description mode:
```markdown
### {YYYY-MM-DD HH:MM} — capture

- **Operation:** capture
- **Trigger:** manual
- **Input:** {mode: file | directory | description} — {source_path if applicable, or "freeform description"}
- **Pages created:** [[{vault-relative-path-to-new-page}|{title}]]
- **Pages updated:** none
- **Contradictions flagged:** none
- **Notes:** {scope} template; {slug}.md written to {target directory relative to vault}
```

For asset mode:
```markdown
### {YYYY-MM-DD HH:MM} — capture

- **Operation:** capture
- **Trigger:** manual
- **Input:** asset — {source_path}
- **Pages created:** [[{vault-relative-path-to-new-page}|{title}]]
- **Pages updated:** none
- **Contradictions flagged:** none
- **Notes:** {scope} template; {slug}.md written to {target directory relative to vault}; asset copied to {asset_embed_path}
```

If `log.md` does not exist yet, create it with a header and this entry:
```markdown
# Project-Agent Wiki — Activity Log

<!-- Reverse-chronological. Append new blocks at the top. -->

{new log entry block}
```

If `log.md` exists but starts with `No entries yet.` content, replace that placeholder with the new entry (keeping the file header).

On write failure: print a warning and continue — the log is informational, and the page has already been written successfully.

---

### Phase 8: Report to User

Print a short summary.

For file / directory / description mode:
```
## Pattern Captured

**Title:** {title}
**File:** {target_path}
**Scope:** {global | project:{name}}
**Status:** approved
**Source:** {source_path if file/dir mode, or "freeform description"}

This template page is now in the vault. It will appear in agent dispatch prompts
when /pa-wiki-query surfaces it for relevant tickets.

To view all templates: run /pa-wiki-status
To search the wiki: run /pa-wiki-query --query "{slug}"
```

For asset mode:
```
## Pattern Captured

**Title:** {title}
**File:** {target_path}
**Scope:** {global | project:{name}}
**Status:** approved
**Asset:** {asset_target_path}
**Embedded as:** ![[{asset_embed_path}]]

This template page is now in the vault with the embedded asset.
It will appear in agent dispatch prompts when /pa-wiki-query surfaces it for relevant tickets.

To view all templates: run /pa-wiki-status
To search the wiki: run /pa-wiki-query --query "{slug}"
```

---

## Algorithm Summary (Quick Reference)

```
Phase 0:  Pre-flight — config load, wiki.enabled check, wiki.patterns.enabled check, vault existence check
Phase 1:  Parse argument — detect mode
          → supported asset ext (.png/.jpg/.jpeg/.gif/.svg/.webp/.pdf) → asset mode
          → unsupported binary ext (.mp4/.zip/.tar etc.)               → friendly message, stop
          → path exists on disk                                         → file mode or directory mode
          → no valid path                                               → description mode
Phase 2:  Gather source content (skipped for asset mode — Phase 2b runs instead)
          → file mode: read file, detect language, extract snippet (≤150 lines)
          → directory mode: glob files, pick most distinctive, treat as file mode
          → description mode: use argument text as primary input
Phase 3:  Determine scope — check registry for active projects, ask user if needed
          (runs before Phase 2b for asset mode)
Phase 2b: Asset preparation (asset mode only, after Phase 3 — NO file writes yet)
          → resolve target assets dir ({vault}/assets/global/ or assets/projects/{name}/)
          → sanitize filename (lowercase, spaces→hyphens, strip non-[a-z0-9._-])
          → collision pre-check: suffix -2, -3, … until free name found
          → record final_asset_filename and asset_embed_path (no copy yet)
Phase 4:  Draft template page — infer title, slug, compose frontmatter + body
          → asset mode: assets:["{final_asset_filename}"], code_language:"", body has ![[embed]]
Phase 5:  Inline approval — invoke Template Draft Approval Helper (pa-patterns-shared)
          options = "capture"; helper manages the AskUserQuestion loop internally
          → verdict: accepted    → use returned content (status: approved), proceed to Phase 6
          → verdict: rejected    → clean exit; no files written (asset copy deferred to Phase 6)
          → verdict: scope_change → return to Phase 3 (asset mode: re-run Phase 2b with new scope)
Phase 6:  Write page — resolve target dir, handle slug collision (-2, -3, …)
          → asset mode: mkdir -p assets dir, cp source to final_asset_filename (then write page)
          → all modes: write template page markdown file
Phase 7:  Update index and log
          Phase 7A: add entry to index.md (correct scope subsection, alphabetical)
          Phase 7B: prepend block to log.md (asset mode includes asset copy note)
Phase 8:  Report to user (asset mode includes asset path and embed syntax in summary)
```

---

## Error Handling

| Situation | Behavior |
|-----------|----------|
| `wiki.enabled = false` | Print disabled message, stop. No files touched. |
| `wiki.patterns.enabled = false` | Print patterns-disabled message, stop. No files touched. |
| Vault path does not exist | Print vault-not-found message with setup instructions, stop. |
| Unsupported binary extension (`.zip`, `.mp4`, etc.) | Print friendly message listing supported asset types, stop. |
| Supported asset path provided but file does not exist | Fall back to description mode using the argument as text; note the fallback. |
| No argument provided | Prompt user for input, stop. |
| File path provided but unreadable | Fall back to description mode using the path as text; note the fallback. |
| File path does not exist | Fall back to description mode (per Phase 1 detection). |
| Directory has no readable source files | Fall back to description mode using the directory path as text. |
| Asset copy (`cp`) fails in Phase 6 | Print error, stop. No template page written. Vault is unmodified. |
| Asset filename collision | Try `-2`, `-3`, ... sequentially on the stem until a free name is found (Phase 2b). |
| Slug collision on template page write | Try `-2`, `-3`, ... sequentially until a free name is found (Phase 6). |
| User rejects draft (any mode) | Print "Draft discarded. No files written." and stop cleanly. No files are ever written before approval, including asset files. |
| index.md does not exist | Skip Phase 7A with a note. Phase 7B still runs. |
| log.md write fails | Print a warning. Continue — the captured page is already written. |
| Phase 6 write fails | Print error, stop. Do NOT update index.md or log.md. |
| Skill must NOT modify `{vault}/learnings/` or `{vault}/sources/` | These directories are the ingest pipeline's domain. Never write to them. |
| Skill must NOT modify `{vault}/assets/` except in Phase 6 (post-approval) | Asset files are only written when in asset mode and the user has accepted the draft. |

---

## Important Invariants

- **Direct write path.** This skill writes approved templates directly to `wiki/templates/` or `projects/{name}/templates/`. It does not create source pages in `sources/` and does not stamp any `learnings.json` entry. It is a parallel write path to ingest, not a replacement.
- **Never touch `{vault}/templates/` (root-level).** That directory contains the ingest scaffolds (`.md` files with `{{title}}` tokens). User-curated template wiki pages live under `wiki/templates/` or `projects/{name}/templates/` only.
- **User approval is required.** Never write a page without explicit user acceptance in Phase 5.
- **status: approved only on accept.** The draft is `proposed` until the user accepts. The written file is always `approved`.
- **Slug collision is sequential.** Use `-2`, `-3`, not hashes, to keep filenames human-readable and deterministic.
- **Asset filename collision is sequential.** Use `-2`, `-3` on the filename stem (before the extension) to avoid collisions within the scope's assets directory. Same reasoning as slug collision.
- **Asset filenames are bare in frontmatter.** The `assets:` array holds bare filenames only (e.g., `"diagram.png"`), never paths. The resolved path is always `{vault}/assets/{scope_dir}/{filename}`.
- **Copy, never move.** Asset ingest copies the source file to the vault. The original file at the user's source path is never deleted or modified.
- **Asset copy happens after user approval** (Phase 6, after Phase 5 accept). Phase 2b only resolves the target filename and detects collisions. No asset file is written until the user accepts the draft. If the user rejects the draft, no files are written at all — the vault is untouched.
- **Log is informational.** A log write failure must never prevent the page from being written or reported to the user.
- **No hallucinated wikilinks.** The Related Pages section starts with a comment placeholder. Do not link to wiki pages that are not confirmed to exist on disk.
