---
name: pa-wiki-query
description: >-
  Search the project-agent wiki vault for pages matching a query. Returns ranked
  results with excerpts. Used directly by users and programmatically by /assign-work
  to inject relevant context into agent prompts. Use when someone asks "check the
  wiki", "what does the wiki say about...", or when dispatching agents that need
  prior knowledge about a topic.
allowed-tools: [Read, Grep, Glob, Edit, Bash]
---

# Project-Agent Wiki Query

Search the project-agent Obsidian vault for wiki pages matching a query and return ranked results with excerpts.

## Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--query "text"` | Yes | — | Search terms. Quoted string. |
| `--project {name}` | No | — | Project name. If provided, searches that project's wiki in addition to global wiki. |
| `--limit N` | No | `5` | Maximum number of results to return. |
| `--scope global\|project\|all` | No | `all` | Search scope. `global` = global wiki only. `project` = project wiki only (requires `--project`). `all` = both. |

**Parsing notes:**
- If `--scope project` is given but `--project` is omitted, treat as `--scope all` and search global only (no project name to search under).
- If `--scope all` is given with `--project`, search both global and the named project's wiki.
- If `--scope all` is given without `--project`, search global wiki only.

## Step 1: Load Configuration

1. Read `~/.claude/project-agent/config.json` (if it exists).
2. Read `{cwd}/.project-agent/config.json` (if it exists). Merge on top of global — workspace values override.
3. Extract `config.wiki.enabled` and `config.wiki.vault_path`.
4. If `config.wiki.enabled` is `false`, output:

```
## Wiki Query Results

Wiki memory is disabled (wiki.enabled = false in config).
Run `/config set wiki.enabled true` to enable it.
```

Then stop — do not search or log.

5. Resolve vault path: expand `~` to the user's home directory. Default: `~/projects/obsidian/project-agent`.
6. Verify the vault exists. If `{vault}/wiki/` does not exist, output the no-results response (Step 5) and log it (Step 6).

## Step 2: Build Search Paths

Based on `--scope` and `--project`:

| Scope | --project provided | Paths to search |
|-------|--------------------|-----------------|
| `global` | either | `{vault}/wiki/**/*.md` |
| `project` | yes | `{vault}/projects/{name}/**/*.md` |
| `project` | no | `{vault}/wiki/**/*.md` (fall back to global) |
| `all` | yes | `{vault}/wiki/**/*.md` AND `{vault}/projects/{name}/**/*.md` |
| `all` | no | `{vault}/wiki/**/*.md` |

## Step 3: Search and Rank

Extract the key terms from `--query` (individual words, ignore stop words like "the", "is", "how", "does", "a", "an", "of").

For each search path, run three tiers of Grep in order — assign a rank tier based on where the first match is found:

### Tier 1: Title Match (highest rank)
Grep for query terms in frontmatter `title:` field:
```
pattern: title:.*{term}
files: {search_path}
case-insensitive: true
output_mode: files_with_matches
```
Pages found here are **Tier 1**.

### Tier 2: Tag / Category / Metadata Match
Grep for query terms in frontmatter `tags:`, `category:`, and `scope:` fields:
```
pattern: (tags:|category:|scope:).*{term}
files: {search_path}
case-insensitive: true
output_mode: files_with_matches
```
Pages found here that are NOT already in Tier 1 are **Tier 2**.

### Tier 3: Body Match
Grep for query terms anywhere in the file body (excluding frontmatter — lines after the closing `---`):
```
pattern: {term}
files: {search_path}
case-insensitive: true
output_mode: files_with_matches
```
Pages found here that are NOT already in Tier 1 or Tier 2 are **Tier 3**.

### Within-Tier Ordering
Within each tier, order by number of distinct query terms matched (more terms = higher within the tier).

### Skip Source Pages
Filter out any file whose path contains `/sources/` OR `/templates/` — those are raw entries and templates, not wiki pages.

### Collect Candidates
After running all three tiers across all search paths, you have a ranked list of candidate files. Deduplicate (a file found in global AND project searches counts once; keep the higher tier ranking).

Take the top `--limit` candidates.

## Step 4: Read Matching Pages and Extract Excerpts

For each candidate page (up to `--limit`):

1. Read the file.
2. Parse frontmatter fields: `title`, `category`, `scope`, `project`, `tickets`, `tags`, `status`.
3. Determine result scope label:
   - `scope: global` → label as `global`
   - `scope: project` with a `project:` field → label as `project:{name}`
4. Extract a 2–3 sentence excerpt around the best match:
   - Find the first line in the body (after frontmatter) that contains one of the query terms (case-insensitive).
   - Take that line plus the two lines immediately following it (or preceding + following if the match line is not the first body line).
   - Clean up Markdown syntax (remove `##`, `>`, `[[...]]` link syntax, `-`) for readable prose. Keep the content, strip formatting markers.
   - If no body match exists (title-only or tag-only match), use the first 2–3 sentences of the page body instead.
5. Compute the absolute vault path to the file.

## Step 5: Format Output

**Output this exact structure** — both human-readable and machine-parseable for PA-006.

If there are matches:

```
## Wiki Query Results

Query: "{query}"
Scope: {scope}
Project: {project | none}
Limit: {N}
Results: {count}

---

### Result 1
- Path: {absolute_path_to_file}
- Title: {title from frontmatter}
- Category: {category from frontmatter}
- Scope: {global | project:{name}}
- Tickets: [{PA-001, PA-003} | none]
- Tags: [{tag1, tag2} | none]
- Excerpt: "{2-3 sentence excerpt}"

### Result 2
- Path: {absolute_path_to_file}
- Title: {title from frontmatter}
- Category: {category from frontmatter}
- Scope: {global | project:{name}}
- Tickets: [{PA-001} | none]
- Tags: [{tag1} | none]
- Excerpt: "{2-3 sentence excerpt}"

...
```

If there are no matches (vault is empty, no pages found, or no pages match):

```
## Wiki Query Results

Query: "{query}"
Scope: {scope}
Project: {project | none}
Limit: {N}
Results: 0

No wiki pages matched "{query}".
The vault may be empty or the topic hasn't been documented yet.
Consider running /pa-wiki-ingest to populate the vault from learnings.
```

**Rules for the output format:**
- The `## Wiki Query Results` header is always the first line of output.
- Each result block starts with `### Result N` (N is 1-based).
- Each field within a result uses `- FieldName: value` format with exact field names as shown.
- `Tickets:` lists ticket IDs separated by `, ` inside brackets (e.g., `[PA-001, PA-003]`), or `none` if the frontmatter `tickets` array is empty.
- `Tags:` lists tags separated by `, ` inside brackets, or `none` if empty.
- `Excerpt:` value is always a quoted string on a single line.
- The `---` separator between the header block and results is always present when `Results > 0`.
- PA-006 parses this output by looking for `### Result N` headers and reading the `- FieldName: value` lines within each block.

## Step 6: Log the Query

Append a new entry to `{vault}/log.md` **at the top of the file** (reverse-chronological):

```markdown
### {YYYY-MM-DD HH:MM} — query

- **Operation:** query
- **Trigger:** {manual | dispatch}
- **Query:** "{query}"
- **Scope:** {scope}
- **Pages read:** {comma-separated wikilinks for pages returned, or "none"}
- **Answer surfaced:** {yes | no (gap noted)}
```

Rules:
- Use `manual` trigger if called by a user directly. Use `dispatch` trigger if called programmatically (e.g., by `/assign-work`).
- "Answer surfaced: yes" if `Results > 0`. "Answer surfaced: no (gap noted)" if `Results: 0`.
- Wikilinks use vault-relative paths: `[[wiki/concepts/slug|Title]]` or `[[projects/{name}/gotchas/slug|Title]]`.
- If `log.md` does not exist yet, create it with the entry as the only content.
- If `log.md` is not writeable or any error occurs writing the log, **do not fail the query** — skip the log write and continue. The query result is more important than the log.

## Output Format Reference (for PA-006)

PA-006 and other programmatic callers parse the output of this skill using the following contract:

**Locating results:** Search for lines matching `^### Result \d+$`. Each such line starts a new result block that continues until the next `### Result` line or end of output.

**Extracting fields:** Within a result block, each field is on its own line in the format `- FieldName: value`. Extract by matching `^- (Path|Title|Category|Scope|Tickets|Tags|Excerpt): (.+)$`.

**Checking for empty results:** If the output contains `Results: 0`, there are no pages to inject.

**Extracting page paths for injection:** Read the `- Path:` field from each result block. This is the absolute filesystem path to the wiki page. Use Read to load the page content for injection into the agent prompt.

**Sample parseable output:**

```
## Wiki Query Results

Query: "worktree isolation"
Scope: all
Project: none
Limit: 5
Results: 2

---

### Result 1
- Path: /Users/you/projects/obsidian/project-agent/wiki/concepts/worktree-isolation.md
- Title: Worktree Isolation
- Category: concept
- Scope: global
- Tickets: [PA-001, PA-003]
- Tags: [tool/git-worktree, category/concept]
- Excerpt: "Each agent works in an isolated git worktree branched from main. Changes are merged back via /merge-work. This prevents agents from conflicting on the same files."

### Result 2
- Path: /Users/you/projects/obsidian/project-agent/wiki/gotchas/worktree-branch-collision.md
- Title: Worktree Branch Collision
- Category: gotcha
- Scope: global
- Tickets: [PA-005]
- Tags: [tool/git-worktree, category/gotcha]
- Excerpt: "Two agents assigned to the same base branch will produce merge conflicts. Always branch from main, never from another agent's worktree branch."
```

## Edge Cases

| Situation | Behavior |
|-----------|----------|
| Vault path does not exist | Clean no-results output. Do not throw an error. |
| `wiki/` directory exists but is empty | Clean no-results output. |
| `--scope project` with no `--project` | Fall back to global scope only. |
| Page file exists but has no frontmatter | Use filename as title, category as `unknown`, skip tickets/tags. |
| Page frontmatter is malformed | Skip that page — do not include in results. |
| Grep finds a page but Read fails | Skip that page — do not include in results. |
| `log.md` write fails | Skip silently. Return results normally. |
| `--limit 0` or negative | Treat as `--limit 5` (default). |
| Query string is empty or whitespace-only | Output no-results with message: "No query provided. Use --query to specify search terms." Do not search or log. |

## Important

- **Do not hallucinate results.** If Grep returns nothing, output `Results: 0`. Never invent page paths, titles, or excerpts.
- **Source pages are not wiki pages.** Never include files from `{vault}/sources/` in results.
- **Template files are not results.** Never include files from `{vault}/templates/` in results.
- **Respect `--limit`.** Never return more results than requested.
- **Exact field names matter.** PA-006 parses `- Path:`, `- Title:`, etc. by exact string match. Do not alter the field names.
