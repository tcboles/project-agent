---
name: check-status
description: >-
  Shows current project board state — what's done, in progress, blocked, and
  queued. Use when the user asks to "check status", "show board", "what's the
  status", "project status", or "show tickets".
---

# Check Status

Display the current state of the project board.

## File Locations

This system supports **multiple projects per workspace**:
- Registry: `{cwd}/.project-agent/registry.json`
- Per-project board: `{cwd}/.project-agent/projects/{name}/board.json`
- Per-project tickets: `{cwd}/.project-agent/projects/{name}/tickets/`

## Project Resolution

1. If the user specified a project name (e.g., `/check-status mobile-app`), show that project.
2. If not, read `.project-agent/registry.json`:
   - If no registry exists, tell the user to run `/plan-project` first.
   - If one project exists, show it.
   - If multiple exist, show the **all-projects overview** first, then ask if they want to drill into one.

## All-Projects Overview

When multiple projects exist and no name was given:

```
## Workspace: {workspace name}

| Project | Status | Progress | In Progress | Blocked |
|---------|--------|----------|-------------|---------|
| mobile-app | active | 5/12 (42%) | 2 | 1 |
| marketing-site | active | 0/8 (0%) | 0 | 0 |

Run `/check-status {name}` to see details for a specific project.
```

## Single Project View

When showing a specific project:

### Reconcile Board State (CRITICAL — do this FIRST)

**Board.json is a cache, not the source of truth. Ticket files are the source of truth.** Before displaying anything, reconcile by reading every ticket file and comparing against board.json:

1. **Read each ticket file** referenced in board.json. Check the ticket's YAML frontmatter (`status`, `assigned_agent`) and content.
2. **Detect completed work on "backlog" tickets.** A ticket's board status is wrong if:
   - Board says `backlog` or `in-progress` BUT the ticket file has a non-empty `## Handoff Notes` section (agent finished work) → should be `review`
   - Board says `backlog` or `in-progress` BUT all acceptance criteria checkboxes are checked (`- [x]`) → should be `review`
   - Board says `review` BUT the ticket file has a `## Review` section with an `APPROVE` verdict → should be `done`
   - Board says `in-progress` BUT the agent listed in `assigned_agent` shows `idle` in the agents array → stale, reset to `backlog` or `review` based on whether handoff notes exist
3. **Detect stale agent states.** If an agent shows `busy` with a `current_ticket` but that ticket is `done` or `backlog`, reset the agent to `idle`.
4. **Update board.json** with any corrections found. Log what was reconciled so the user sees it:

```
## Board Reconciliation
The following tickets were out of sync and have been updated:
- PA-001: backlog → review (handoff notes found, work was completed)
- PA-003: in-progress → review (all acceptance criteria met)
- Agent "developer": busy → idle (assigned ticket already complete)
```

Only show the reconciliation section if changes were made.

### Compute Statistics

1. **Count tickets by status** (using the reconciled data): done, in-progress, review, assigned, backlog, blocked.
   - Identify blocked tickets: tickets in `backlog` whose dependencies include tickets that are NOT `done`.
   - Calculate completion percentage: `done / total * 100`.
   - Identify agent utilization: which agents are busy vs idle.

2. **Identify blockers.** For each blocked ticket, show which dependency tickets are holding it up and their current status.

3. **Display the board:**

```
## Project: {name}
**Progress:** {done}/{total} tickets complete ({percentage}%)

### In Progress
| ID | Title | Agent | Priority |
|----|-------|-------|----------|
| PA-001 | ... | developer | P0 |

### Review
| ID | Title | Agent | Priority |
|----|-------|-------|----------|

### Ready (can be assigned)
| ID | Title | Category | Priority | Complexity |
|----|-------|----------|----------|------------|

### Blocked
| ID | Title | Blocked By | Priority |
|----|-------|------------|----------|

### Done
| ID | Title | Completed |
|----|-------|-----------|

### Agent Status
| Agent | Status | Current Ticket |
|-------|--------|----------------|
```

4. **Suggest next action.** Based on the board state:
   - If there are ready tickets: suggest running `/assign-work {name}`
   - If all tickets are done: congratulate and suggest `/review-board {name}` or `/merge-work {name}`
   - If everything is blocked: explain the dependency chain and suggest manual intervention
   - If agents are busy: suggest waiting or checking back later

## Important

- Read the actual files — do not guess or use cached state.
- If a ticket file is referenced in board.json but doesn't exist, flag it as an error.
- Show relative timestamps (e.g., "2 hours ago") alongside ISO dates for readability.
