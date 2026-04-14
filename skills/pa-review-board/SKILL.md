---
name: pa-review-board
description: >-
  Quality gate for completed work. Runs the reviewer agent against all tickets
  in "review" status, producing review documents with verdicts. Tickets that pass
  move to "done"; tickets that fail go back to the developer. Use when the user
  asks to "review work", "review board", "quality check", or "run reviews".
---

# Review Board

Run automated code reviews on all completed tickets before promoting them to `done`.

## Project Resolution

1. If the user specified a project name (e.g., `/pa-review-board mobile-app`), use it.
2. If not, read `.project-agent/registry.json` from the cwd.
   - If only one project exists, use it.
   - If multiple exist, ask the user which one.
   - If none exist, tell the user to run `/pa-plan-project` first.

Project data paths:
- Board: `{cwd}/.project-agent/projects/{name}/board.json`
- Tickets: `{cwd}/.project-agent/projects/{name}/tickets/`

Default agent definitions (like `agents/reviewer.md`) live in the plugin directory.

## Workflow

### Step 1: Read Board State

Read the board.json for the resolved project. Identify all tickets with `status === "review"`. If none exist, tell the user there's nothing to review and suggest running `/pa-assign-work` or `/pa-check-status`.

### Step 2: Gather Context for Each Ticket

For each ticket in review:

1. **Read the ticket file** at the path in `ticket_file`.
2. **Read the handoff notes** — the `## Handoff Notes` section in the ticket. This tells you what files changed and what decisions were made.
3. **Read the reviewer agent definition** from `@plugin/agents/reviewer.md`.

### Step 2.5: Load Configuration

Read config from global (`~/.claude/project-agent/config.json`) and workspace (`{cwd}/.project-agent/config.json`), merge workspace over global. Check if `agents.reviewer.enabled` is `false` — if so, skip reviews and move tickets directly from `review` to `done`.

**Determine execution mode.** If `/pa-review-board` was invoked from `/pa-plan-project` Phase 7, the caller passes an `execution_mode`. Otherwise, read `autonomous` from config:
- If `autonomous === true` → `execution_mode = "autonomous"`
- Otherwise → `execution_mode = "manual"`

### Step 3: Present Review Plan and Get Approval

**Always print the review plan**, regardless of execution mode:

```
## Ready for Review — {project-name}

| Ticket | Title | Agent That Completed | Priority |
|--------|-------|----------------------|----------|
| PA-001 | ...   | developer            | P0       |
| PA-003 | ...   | developer            | P1       |

The reviewer agent will check each ticket against its acceptance criteria,
run tests, and produce a verdict (APPROVE, REQUEST_CHANGES, or BLOCK).
```

**If `execution_mode === "autonomous"`**, skip the approval prompt. Log `"Autonomous mode — running reviews on {N} tickets."` and proceed to Step 4.

**Otherwise (manual mode)**, ask: **"Ready to run reviews on these tickets?"** using `AskUserQuestion`. Only proceed if the user approves.

### Step 4: Dispatch Reviewer Agents in Parallel

**IMPORTANT: Launch all reviewer agents concurrently.** Prepare all prompts first, update board.json for all tickets, then make **multiple Agent tool calls in a single message** so they run in parallel.

For up to `max_concurrent_agents` tickets at a time (from config, default 6):

1. **Update board.json for ALL tickets BEFORE launching:**
   - Set ticket `assigned_agent` to `reviewer`
   - Set the reviewer agent `status` to `busy`
   - Set the reviewer agent `current_ticket` to the ticket id

2. **Launch the reviewer subagent** using the Agent tool:
   - `description`: `"Review PA-NNN: {ticket title}"`
   - `isolation`: `"worktree"` — reviewer needs to see the implementation branch
   - `prompt`: Structure as:

```
## Your Role
{reviewer agent definition body}

## Your Task
Review the implementation for this ticket:

{full ticket markdown content}

## What Changed
{handoff notes from the ticket, if present}

## Review Checklist
1. Do all acceptance criteria have corresponding working code?
2. Are there tests for the new code? Do they pass?
3. Are there security issues (OWASP top 10)?
4. Does the code follow project conventions?
5. Are there performance concerns?
6. Is the code readable and maintainable?

## Output
Write your review in the format specified in your role definition.
End with a clear verdict: APPROVE, REQUEST_CHANGES, or BLOCK.
```

### Step 5: Process Review Results

Parse the reviewer's `## Agent Report` block. The STATUS field contains the verdict: APPROVE, REQUEST_CHANGES, or BLOCK.

**If STATUS is APPROVE:**
- Set ticket `status` to `done`
- Set ticket `completed_at` to current ISO timestamp
- Set ticket `updated_at` to current ISO timestamp
- Append the review summary to the ticket's `## Review` section
- Reset `retry_count` to 0

**If STATUS is REQUEST_CHANGES:**
- Increment `retry_count` on the ticket
- Apply escalation protocol:
  - **retry_count 1-2:** Set ticket `status` to `backlog`, append review findings to `## Review Feedback`. The developer will be re-dispatched with this feedback.
  - **retry_count 3:** Set ticket `status` to `backlog`, but the next dispatch will use `model: "opus"` (escalated capability).
  - **retry_count 4+:** Set ticket `status` to `blocked`. Flag to user: "Ticket {id} has been reviewed {N} times without passing. Last findings: {summary}. Needs manual intervention."
- Set ticket `assigned_agent` to `null`

**If STATUS is BLOCK:**
- Set ticket `status` to `blocked`
- Append the review findings to the ticket
- If SECURITY_ISSUES is not "none", add `[SECURITY]` prefix to the blocker note
- Flag this to the user — blocked tickets need manual intervention

In all cases:
- Set the reviewer agent `status` to `idle`
- Set the reviewer agent `current_ticket` to `null`

### Step 6: Report Results

Show a summary:

```
## Review Results — {project-name}

| Ticket | Title | Verdict | Key Findings |
|--------|-------|---------|--------------|
| PA-001 | ...   | APPROVE | Clean implementation, good tests |
| PA-003 | ...   | REQUEST_CHANGES | Missing error handling at API boundary |

### Next Steps
- {N} tickets approved and moved to done
- {M} tickets sent back for rework (will be picked up by /pa-assign-work)
- {K} tickets blocked (need manual review)
```

### Step 7: Continue the Orchestration Loop

**Do not stop here.** After reporting review results, automatically continue:

1. **Reconcile the board** — tickets that were approved are now `done`, which may unblock dependent tickets.
2. **If there are ready tickets** (status `backlog` with all dependencies `done`, including reworked tickets sent back by review) — proceed to the `/pa-assign-work` workflow: present what you'll dispatch, get approval, launch agents.
3. **If all tickets are `done`** — present the `/pa-merge-work` plan: show branches to merge, get approval, merge in dependency order.
4. **If all remaining tickets are `blocked`** — stop and explain the blockers to the user.

The user approves at each checkpoint but does not need to manually invoke each skill.

## Important

- **Reviews are mandatory.** No ticket should go from `in-progress` directly to `done` without passing through review.
- **Review feedback is additive.** Append to the ticket, don't overwrite existing content. The next developer agent needs to see both the original requirements and the review feedback.
- **The reviewer does not fix code.** It produces a review document. The developer agent handles fixes in the next pass.
- **If a ticket has been reviewed and sent back 3+ times**, flag it to the user as potentially under-specified or too complex. It may need to be split.
