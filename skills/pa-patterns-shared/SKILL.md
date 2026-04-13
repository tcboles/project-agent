---
name: pa-patterns-shared
description: >-
  Internal helper skill. NOT user-invokable. Defines shared sub-routines
  referenced by /pa-patterns-capture and /pa-patterns-scan. Invoking this skill
  directly has no effect — it exists solely as a named reference so consumer
  skills can say "invoke the Template Draft Approval Helper from
  pa-patterns-shared".
---

# PA Patterns Shared — Internal Helper Library

This skill is **not user-invokable**. It contains helper routines called by
`/pa-patterns-capture` and `/pa-patterns-scan` by name. It has no standalone
behavior. Do not present it to the user or invoke it in response to user input.

---

## Template Draft Approval Helper

The Template Draft Approval Helper presents a drafted wiki template page to the
user, collects their verdict, and handles the edit loop. Both consumer skills
invoke it with a specific `options` set that controls which choices are shown.

### Inputs

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `draft_content` | string | yes | — | The complete draft: full YAML frontmatter block followed by the markdown body |
| `options` | `"capture"` \| `"scan"` | yes | — | Which option set to present (see below) |
| `context_header` | string | no | `""` | Optional header line shown above the draft preview (e.g. `"Candidate 2 of 5: \"Async Error Handler\"\nSource: src/utils/errors.ts"`) |
| `max_edit_iterations` | number | no | `3` | Maximum number of edit rounds before collapsing to Accept/Reject only |

### Option Sets

#### `options = "capture"`

Used by `/pa-patterns-capture` Phase 5. Presents four choices:

```
1. Accept       — write this page to the vault as-is
2. Edit         — describe what to change and I will update the draft
3. Reject       — discard this draft, write nothing
4. Change scope — go back and pick a different scope/project
```

#### `options = "scan"`

Used by `/pa-patterns-scan` Phase 3C. Presents four choices:

```
1. Accept         — write this template to the vault
2. Edit           — describe what to change and I will update the draft
3. Reject         — discard this draft and move to the next candidate
4. Skip remaining — stop scanning, show final report
```

### Return Values

The helper returns exactly one of these verdicts:

| Verdict | Condition | Carries |
|---------|-----------|---------|
| `{verdict: "accepted", content: string}` | User chose Accept (option 1) | The final `draft_content` (possibly edited), with `status` set to `approved` in the frontmatter |
| `{verdict: "rejected"}` | User chose Reject (option 3) | — |
| `{verdict: "scope_change"}` | User chose Change Scope (option 4, `capture` only) | — |
| `{verdict: "skip_remaining"}` | User chose Skip Remaining (option 4, `scan` only) | — |

### Invocation Pattern

```
Invoke the Template Draft Approval Helper from pa-patterns-shared with:
  draft_content  = <the drafted page string>
  options        = "capture"   (or "scan")
  context_header = <optional header string>
```

---

### Approval Loop Specification

#### Step 1 — Render the draft

Display the draft to the user via `AskUserQuestion` using the following format:

```
{context_header, if non-empty, followed by a blank line}
Here is the drafted template page for "{title extracted from frontmatter}":

─────────────────────────────────────────────
{draft_content, verbatim}
─────────────────────────────────────────────

How would you like to proceed?
{option list for the chosen options set}
```

**Title extraction:** parse the `title:` line from the YAML frontmatter in
`draft_content`. Use it in the question header. If the title cannot be parsed,
use `"(untitled)"`.

**Section break rendering:** use a horizontal rule (`─────────` or `---`)
before and after `draft_content` to clearly delimit it from the surrounding
question text. Do not wrap or truncate the draft content.

#### Step 2 — Handle the user's choice

**Accept (option 1):**
1. Set `status: approved` in the YAML frontmatter of `draft_content`. Locate
   the `status: proposed` line and replace it with `status: approved`.
2. Return `{verdict: "accepted", content: <updated draft_content>}`.

**Edit (option 2):**
- Ask the user: `"What would you like to change?"`
- Apply the user's requested edits to `draft_content`. Edits may affect
  frontmatter fields (title, tags, applicable_domains, etc.) or any section of
  the body (Purpose, Template, Usage Notes, Examples, Related Pages).
- After applying edits, increment the edit iteration counter.
- If the iteration counter is **less than** `max_edit_iterations`: re-render the
  updated draft with the full option set and go back to Step 1.
- If the iteration counter **equals** `max_edit_iterations`: show a collapsed
  prompt:
  ```
  We've iterated {max_edit_iterations} times. Would you like to:
  1. Accept — keep the current draft as-is
  2. Reject — discard and start over
  ```
  - On Accept: set `status: approved` and return
    `{verdict: "accepted", content: <updated draft_content>}`.
  - On Reject: return `{verdict: "rejected"}`.

**Reject (option 3):**
Return `{verdict: "rejected"}`.

**Change Scope (option 4, `capture` set only):**
Return `{verdict: "scope_change"}`.

**Skip Remaining (option 4, `scan` set only):**
Return `{verdict: "skip_remaining"}`.

#### Edit iteration counter

- The counter starts at `0` before the first prompt.
- It increments by `1` each time the user chooses Edit and the helper processes
  the change (i.e., each round-trip that results in a revised draft).
- A scope-change return (`verdict: "scope_change"`) in `capture` mode is handled
  by the caller, not by the helper — the caller re-enters the helper fresh (with
  a reset counter) after re-running scope selection.
- The cap applies **per invocation** of the helper, not per skill run. If the
  caller re-invokes the helper (e.g., after a scope change), the counter resets.

---

### Important Notes for Consumer Skills

- The helper does **not** write any files. Writing is the caller's responsibility
  after receiving `verdict: "accepted"`.
- The helper does **not** copy asset files. Asset copy logic stays in
  `/pa-patterns-capture` Phase 6.
- The `content` field in an `accepted` verdict always has `status: approved` set.
  The caller must use this returned content (not its own copy of `draft_content`)
  when writing to the vault.
- The helper does not know about scan-specific state (candidate count, reject
  streak, rate cap). The caller tracks those and reacts to `rejected` /
  `skip_remaining` verdicts accordingly.
- The helper is stateless between invocations. Each call starts with a fresh
  edit iteration counter.
