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

**Do NOT dispatch agents yet.** Present the user with a summary of what you're about to do:

```
## Ready to Assign — {project-name}

| Ticket | Title | Agent | Priority | Complexity |
|--------|-------|-------|----------|------------|
| PA-001 | ...   | architect | P0 | small |
| PA-004 | ...   | developer | P1 | medium |
| PA-005 | ...   | developer | P1 | medium |

Agents will work in isolated git worktrees. Up to 3 will run in parallel.
```

Then ask: **"Ready to dispatch these tickets?"** using AskUserQuestion. Only proceed to Step 6 if the user approves. If they want changes (e.g., skip a ticket, change priority, reassign an agent), make those adjustments first and re-present.

### Step 6: Dispatch Agents (Up to 3 in Parallel)

For each ticket being dispatched:

1. **Read the ticket file** at the path specified in `ticket_file`.
2. **Read the agent definition file** at the path specified in the matched agent's `definition_file`.
3. **Read all three tiers of learnings** and combine relevant entries.
4. **Update board.json BEFORE launching:**
   - Set ticket `status` to `in-progress`
   - Set ticket `assigned_agent` to the agent id
   - Set ticket `updated_at` to current ISO timestamp
   - Set agent `status` to `busy`
   - Set agent `current_ticket` to the ticket id
5. **Launch the subagent** using the Agent tool with these parameters:
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

## Working Directory
You are working in the project at {project root path}. Explore the codebase before making changes.

## When Done
1. Update the ticket's ## Handoff Notes section with: what files you changed, what you built,
   any deviations from the plan, and anything downstream agents need to know.
2. If you discovered something non-obvious, append it to the appropriate learnings file:
   - Global (~/.claude/project-agent/learnings.json): tool/platform issues that apply everywhere
   - Workspace (.project-agent/learnings.json): codebase-wide conventions and gotchas
   - Project (.project-agent/projects/{name}/learnings.json): project-specific discoveries
3. Summarize what you did and whether all acceptance criteria are met.
4. If you encounter a blocker, describe it clearly so it can be addressed.
```

7. **After agent completes**, update board.json:
   - Set ticket `status` to `review` (if the agent reports success) or `blocked` (if the agent reports a blocker)
   - Set ticket `updated_at` to current ISO timestamp
   - Set agent `status` to `idle`
   - Set agent `current_ticket` to `null`
   - If the agent reported blockers, add them to the ticket's notes

### Step 7: Report Results

After all dispatched agents complete, show:
- Which tickets were dispatched and to which agents
- Results from each agent (success, partial, or blocked)
- What tickets are now ready for the next wave
- Suggest running `/check-status {name}` for the full board view

## Important

- **Never dispatch more than 3 agents at once.** Worktrees and context have limits.
- **Always update board.json before AND after agent dispatch.** This keeps the board consistent even if an agent fails.
- **Read ticket files fresh every time.** Do not rely on cached content.
- **If no tickets are ready**, explain why (all done, all blocked, dependencies pending) and suggest next steps.
- **If the project doesn't use git**, skip worktree isolation and note this to the user.
