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

When showing a specific project, read its board.json and render:

1. **Compute statistics.**
   - Count tickets by status: done, in-progress, review, assigned, backlog, blocked.
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
