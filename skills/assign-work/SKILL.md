---
name: assign-work
description: >-
  Reads the project board, finds tickets ready for work (dependencies satisfied),
  assigns them to specialized agents, and launches subagents in isolated worktrees.
  Use when the user asks to "assign work", "start work", "kick off tickets",
  "run the board", or "dispatch agents".
---

# Assign Work

Dispatch ready tickets to specialized agents for autonomous implementation.

## File Locations

This system supports **multiple projects per workspace**. Resolve the target project:

1. If the user specified a project name (e.g., `/assign-work mobile-app`), use it.
2. If not, read `.project-agent/registry.json` from the cwd.
   - If only one project exists, use it.
   - If multiple exist, ask the user which one.
   - If none exist, tell the user to run `/plan-project` first.

Project data paths:
- Board: `{cwd}/.project-agent/projects/{name}/board.json`
- Tickets: `{cwd}/.project-agent/projects/{name}/tickets/`
- Project learnings: `{cwd}/.project-agent/projects/{name}/learnings.json`
- Workspace learnings: `{cwd}/.project-agent/learnings.json`
- Global learnings: `~/.claude/project-agent/learnings.json`
- Project-specific agents: `{cwd}/.project-agent/projects/{name}/agents/`

Default agent definitions use `@plugin/agents/` prefix in `definition_file` — resolve to the plugin's `agents/` directory.

## Workflow

### Step 0: Load Configuration

Read config from two levels and merge (workspace overrides global):
1. Global: `~/.claude/project-agent/config.json`
2. Workspace: `{cwd}/.project-agent/config.json`

If neither exists, use defaults: `max_concurrent_agents: 6`, `default_model: "sonnet"`, all agents enabled, `autonomous: false`, `auto_review: true`, `auto_merge: false`.

Use these settings throughout the workflow — especially `max_concurrent_agents` for the dispatch limit, agent `enabled` flags when matching tickets to agents, and `auto_review`/`auto_merge` for the orchestration loop.

**Determine execution mode.** If `/assign-work` was invoked from `/plan-project` Phase 7, the caller passes an `execution_mode` (`"autonomous"` or `"manual"`) which you should honor. Otherwise, determine it here:

1. If config `autonomous === true`, set `execution_mode = "autonomous"` and log `"Autonomous mode (from config) — no approval prompts."`.
2. Otherwise, after Step 4 (matching tickets to agents) but before Step 5, ask the user via `AskUserQuestion`:
   > **Question:** "How would you like to proceed with this run?"
   > **Options:**
   > 1. **Run autonomously** — dispatch, review, and merge without further approval prompts
   > 2. **Approve each step** — prompt me before dispatch, review, and merge
   
   Cache the answer for the rest of this skill run as `execution_mode`.

### Step 1: Read and Reconcile Board State

Read the board.json for the resolved project. If it has no tickets, tell the user to run `/plan-project` first.

**Before proceeding, reconcile board.json against the actual ticket files.** Board.json is a cache — ticket files are the source of truth. For each ticket in board.json:

1. Read the ticket file at `ticket_file`.
2. If the board says `backlog` or `in-progress` but the ticket has non-empty `## Handoff Notes` → update to `review`.
3. If the board says `backlog` or `in-progress` but all acceptance criteria are checked (`- [x]`) → update to `review`.
4. If the board says `review` but the ticket has a `## Review` section with `APPROVE` → update to `done`.
5. If an agent shows `busy` but its `current_ticket` is `done` or `backlog` → reset to `idle`.
6. Write any corrections to board.json and briefly note what was reconciled.

### Step 2: Find Ready Tickets

A ticket is **ready** if:
- Its `status` is `backlog`
- ALL tickets listed in its `dependencies` array have `status === "done"`

Sort ready tickets by:
1. Priority (P0 first, then P1, P2, P3)
2. Dependency depth (tickets that unblock the most other tickets first)

### Step 3: Check Agent Availability

Read the `agents` array in board.json. An agent is available if its `status` is `idle`. Do not assign more tickets to a busy agent.

### Step 4: Match Tickets to Agents

For each ready ticket, match its `category` field to an agent `id`:
- If a direct match exists (e.g., category `developer` matches agent `developer`), use it.
- If the category matches a project-specific agent (e.g., `frontend-dev`), use that.
- If no match, fall back to `developer` for implementation work or `architect` for design work.

### Step 5: Present Plan and Get Approval

**Always print the dispatch plan first**, regardless of execution mode — the user needs an audit trail:

```
## Ready to Assign — {project-name}

| Ticket | Title | Agent | Priority | Complexity |
|--------|-------|-------|----------|------------|
| PA-001 | ...   | architect | P0 | small |
| PA-004 | ...   | developer | P1 | medium |
| PA-005 | ...   | developer | P1 | medium |

Agents will work in isolated git worktrees. Up to 6 will run in parallel.
```

**If `execution_mode === "autonomous"`**, skip the approval prompt. Log `"Autonomous mode — dispatching {N} tickets."` and proceed directly to Step 6.

**Otherwise (manual mode)**, ask: **"Ready to dispatch these tickets?"** using `AskUserQuestion`. Only proceed to Step 6 if the user approves. If they want changes (e.g., skip a ticket, change priority, reassign an agent), make those adjustments first and re-present.

### Step 5b: Wiki Query (Pre-Dispatch Hook)

**This step runs before launching agents. Gate it with: `if config.wiki.enabled && config.wiki.auto_query`.**

If both flags are true and the `/pa-wiki-query` skill is available, for each ready ticket:

1. **Build the query string.** Concatenate the ticket title, category, and top keywords extracted from the ticket description:
   - Take the ticket description text (first 500 characters is enough).
   - Strip stopwords: `the, a, an, is, of, in, to, for, and, or, that, this, with, on, at, from, by, be, are, was, were, it, its, not, but, if, as, so, do, we, you, he, she, they, them, their, have, has, had, will, would, can, could, should`.
   - Take up to 5 distinctive remaining terms.
   - Final query = `"{ticket.title} {ticket.category} {top5terms}"`.
2. **Invoke `/pa-wiki-query`** using the Skill tool:
   ```
   Skill: pa-wiki-query
   Args: --query "{query}" --limit 5 --scope all
   ```
   (Omit `--project` to search all scopes — the ticket may be relevant to global patterns.)
3. **Parse the output.** Locate `## Wiki Query Results` in the response. Read the `Results: {N}` header line. If `N === 0`, skip injection (nothing to inject). If `N > 0`:
   - Collect each `### Result N` block.
   - From each block, extract `- Path:`, `- Title:`, `- Category:`, and `- Excerpt:` fields using the pattern `^- (FieldName): (.+)$`.
   - For each result, read the file at `Path` to get the full page content (truncated to 300 characters of body after the frontmatter fence if the page is long — excerpt is usually sufficient).
4. **Build the `## Relevant Wiki Context` block** (see injection format in CLAUDE.md). Store it per-ticket for use when assembling the dispatch prompt in Step 6.

**If `config.wiki.enabled` is false OR `config.wiki.auto_query` is false**, skip this step entirely. Existing flow is unchanged.

**If the `/pa-wiki-query` skill is unavailable or returns an error**, skip silently — log a one-line note and continue. Never block dispatch over a wiki failure.

### Step 6: Dispatch Agents in Parallel

**IMPORTANT: Launch agents concurrently, not sequentially.** Prepare all ticket prompts first, update board.json for all tickets, then make **multiple Agent tool calls in a single message** so they run in parallel. This is how Claude Code parallelizes work — multiple tool calls in one response execute simultaneously.

For up to `max_concurrent_agents` tickets at a time (from config, default 6):

1. **Prepare all prompts first.** For each ticket, read:
   - The ticket file at the path specified in `ticket_file`
   - The agent definition file at the path specified in the matched agent's `definition_file`
   - All three tiers of learnings
   - Handoff notes from dependency tickets
2. **Update board.json for ALL tickets BEFORE launching any agents:**
   - Set ticket `status` to `in-progress`
   - Set ticket `assigned_agent` to the agent id
   - Set ticket `updated_at` to current ISO timestamp
   - Set agent `status` to `busy`
   - Set agent `current_ticket` to the ticket id
3. **Launch ALL agents in a single message.** Use multiple Agent tool calls in one response — this is critical for parallelism. Each Agent call uses these parameters:
   - `description`: The ticket title
   - `isolation`: `"worktree"` — each agent works in an isolated git worktree
   - `prompt`: Combine the agent definition (as behavioral instructions) with the full ticket content (as the task). Structure the prompt as:

```
## Your Role
{agent definition body — everything after the YAML frontmatter}

## Your Task
{full ticket markdown content}

## Context From Prior Agents
{If this ticket has dependencies, read each dependency ticket's ## Handoff Notes section
and include them here. This tells the agent what was actually built and where to find it.}

## Learnings
The following learnings were recorded by prior agents. Read them before starting work.

### Global Learnings (apply everywhere)
{entries from ~/.claude/project-agent/learnings.json}

### Workspace Learnings (apply to this codebase)
{entries from {cwd}/.project-agent/learnings.json}

### Project Learnings (apply to this project specifically)
{entries from {cwd}/.project-agent/projects/{name}/learnings.json}

## Relevant Wiki Context
{If config.wiki.enabled && config.wiki.auto_query AND Step 5b produced results for this ticket,
insert the ## Relevant Wiki Context block here. Format per CLAUDE.md "Wiki Context Injection Format".
If no results or wiki is disabled, omit this section entirely.}

## Working Directory
You are working in the project at {project root path}. Explore the codebase before making changes.

## When Done
1. Update the ticket's ## Handoff Notes section with: what files you changed, what you built,
   any deviations from the plan, and anything downstream agents need to know.
2. If you discovered something non-obvious, append it to the appropriate learnings file:
   - Global (~/.claude/project-agent/learnings.json): tool/platform issues that apply everywhere
   - Workspace (.project-agent/learnings.json): codebase-wide conventions and gotchas
   - Project (.project-agent/projects/{name}/learnings.json): project-specific discoveries
3. If you need input from another agent or the user, write to ## Questions in the ticket.
4. **You MUST end your response with a structured Agent Report** (see your role definition).
   The orchestrator parses this to determine next steps. Do not skip it.
```

7. **Parse the agent's structured output.** Every agent ends with an `## Agent Report` block. Parse the STATUS field:

   **If STATUS is SUCCESS:**
   - Set ticket `status` to `review`
   - Set ticket `updated_at` to current ISO timestamp

   **If STATUS is PARTIAL:**
   - Keep ticket `status` as `in-progress` (or set to `backlog` if you want to re-dispatch)
   - The agent did some work but not all — check handoff notes for what remains
   - Increment `retry_count` on the ticket

   **If STATUS is BLOCKED:**
   - Check the BLOCKERS field and the ticket's `## Questions` section
   - If the question targets another agent (`@architect`, `@developer`, etc.):
     - Dispatch that agent with the question as context
     - When the answer comes back, append it to `## Questions` and set ticket to `backlog` for re-dispatch
   - If the question targets `@user`:
     - Present the question to the user and wait for their answer
     - Append the answer to `## Questions` and set ticket to `backlog`
   - Set ticket `status` to `blocked`

   **If STATUS is FAILED:**
   - Check `retry_count` on the ticket and apply the escalation protocol:
     - **retry_count 0-1:** Re-dispatch with same model, include the failure reason in the prompt
     - **retry_count 2:** Escalate — re-dispatch with `model: "opus"` for more capability
     - **retry_count 3+:** Stop. Flag to the user: "Ticket {id} has failed {N} times. Last error: {blocker}. Needs manual intervention."
   - Increment `retry_count`
   - Set ticket `status` to `backlog` (for retry) or `blocked` (if escalation exhausted)

   **In all cases:**
   - Set agent `status` to `idle`
   - Set agent `current_ticket` to `null`
   - Set ticket `updated_at` to current ISO timestamp
   - If SECURITY_ISSUES is not "none", add a `[SECURITY]` note to the ticket

### Step 6b: Wiki Ingest (Post-Completion Hook)

**Run this after each agent completes and board.json is updated. Gate it with: `if config.wiki.enabled && config.wiki.auto_ingest`.**

For each ticket that just moved to `review` or `done` status:

1. **Check for new learnings.** Compare the entry count in each learnings.json tier (global, workspace, project) to the count captured before dispatch in Step 5b. If any tier has more entries now than it did before dispatch, new learnings were written.
   - If you did not capture pre-dispatch counts, use a simpler heuristic: check whether any learnings entry has a `created_at` timestamp after the dispatch time for this ticket. An entry with no `ingested_at` field is also a signal it is newly written.
2. **If new learnings exist**, invoke `/pa-wiki-ingest` using the Skill tool:
   ```
   Skill: pa-wiki-ingest
   Args: --ticket {ticket_id}
   ```
   This ingests only the entries linked to this ticket (PA-003 guarantees idempotency — re-running on already-ingested entries is safe).
3. **If no new learnings exist**, skip silently. The ingest is a no-op anyway per PA-003, but skipping avoids unnecessary skill invocations.

**If `config.wiki.enabled` is false OR `config.wiki.auto_ingest` is false**, skip this step entirely.

**If the `/pa-wiki-ingest` skill is unavailable or returns an error**, skip silently — log a one-line note and continue. Never block the orchestration loop over a wiki failure.

### Step 7: Report Results

After all dispatched agents complete, show:
- Which tickets were dispatched and to which agents
- Results from each agent (success, partial, or blocked)
- What tickets are now ready for the next wave

### Step 8: Continue the Orchestration Loop

**Do not stop here.** After reporting results, automatically continue:

1. **If there are tickets in `review` status** — proceed to the `/review-board` workflow: present the review plan, get approval, dispatch reviewer agents, process results.
2. **After reviews complete, reconcile the board** and check for newly ready tickets (dependencies satisfied by tickets that just moved to `done`).
3. **If there are ready tickets** — loop back to Step 1 of this skill (read board, find ready tickets, present plan, get approval, dispatch).
4. **If all tickets are `done`** — present the `/merge-work` plan: show branches to merge, get approval, merge in dependency order.
5. **If all remaining tickets are `blocked`** — stop and explain the blockers to the user.

The user approves at each checkpoint but does not need to manually invoke each skill.

## Important

- **Never dispatch more than `max_concurrent_agents` (from config) at once.** Worktrees and context have limits.
- **Always update board.json before AND after agent dispatch.** This keeps the board consistent even if an agent fails.
- **Read ticket files fresh every time.** Do not rely on cached content.
- **If no tickets are ready**, explain why (all done, all blocked, dependencies pending) and suggest next steps.
- **If the project doesn't use git**, skip worktree isolation and note this to the user.
