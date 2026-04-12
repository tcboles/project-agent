---
name: triage
description: >-
  Fire-and-forget bug triage. Accepts a bug description, launches a background
  triage agent that investigates, creates a ticket, dispatches a fix agent, and
  verifies the result. Use when the user reports a bug, says "triage", "fix this
  bug", "this is broken", or rapid-fires issues.
---

# Triage

Accept a bug report and handle it end-to-end in the background.

## Workflow

### Step 1: Parse Bug Report

Extract the bug description from the user's input. The input can be:
- A detailed bug report: `/triage the OAuth callback doesn't redirect — it stays on /auth/callback with a blank screen`
- A quick note: `/triage login button broken`
- An error message: `/triage TypeError: Cannot read property 'id' of undefined in UserProfile`
- A screenshot reference: `/triage the checkout page is missing the price total — see screenshot`

Accept whatever the user provides. The triage agent will investigate further.

### Step 2: Resolve Project

1. If the user specified a project name, use it.
2. If not, read `.project-agent/registry.json`:
   - If one project exists, use it.
   - If multiple exist, use the most recently active project (most recent `updated_at` on any ticket).
   - If none exist, tell the user to run `/plan-project` first.

### Step 3: Load Config

Read config (global + workspace merge). Check triage-specific settings:
- `triage.auto_fix` (default `true`) — dispatch fix agent automatically
- `triage.auto_verify` (default `true`) — verify fix after agent completes
- `triage.default_priority` (default `"P1"`) — priority for new bug tickets
- `triage.max_concurrent_triage` (default `4`) — max background triage agents

### Step 4: Check Capacity

Count currently running triage agents (tickets with `type: "bug"` and `status: "in-progress"`). If at `max_concurrent_triage`, tell the user:
```
Triage queue is full ({N}/{max} active). Your bug has been logged as a ticket
in backlog and will be picked up when capacity frees. Run /check-status to monitor.
```
In this case, still create the ticket (Step 5 of the triage agent) but set status to `backlog` instead of dispatching.

### Step 5: Launch Triage Agent in Background

**This is the critical step for fire-and-forget.** Launch the triage agent using the Agent tool with `run_in_background: true` so the user can immediately continue working.

```
Agent({
  description: "Triage: {first 50 chars of bug description}",
  run_in_background: true,
  prompt: "
    ## Your Role
    {triage agent definition body from @plugin/agents/triage.md}

    ## Bug Report
    {user's bug description, verbatim}

    ## Project Context
    Project: {project name}
    Board: {cwd}/.project-agent/projects/{name}/board.json
    Tickets: {cwd}/.project-agent/projects/{name}/tickets/
    Next ticket ID: {next available ID from board.json}

    ## Config
    auto_fix: {value}
    auto_verify: {value}
    default_priority: {value}

    ## Learnings
    {All three tiers of learnings}

    ## Instructions
    1. Investigate this bug in the codebase at {cwd}.
    2. Create a ticket at the ticket path above with the next available ID.
    3. Add the ticket to board.json.
    4. If auto_fix is true AND your confidence in the root cause is medium or high,
       dispatch a fix agent using the Agent tool with isolation: worktree.
    5. If auto_fix is false OR confidence is low, set the ticket to backlog and stop.
    6. If you dispatched a fix agent and auto_verify is true, verify the fix
       (run tests, check acceptance criteria).
    7. Update the ticket and board.json with final status.
    8. Report your triage summary.
  "
})
```

### Step 6: Acknowledge to User

Immediately after launching the background agent, confirm to the user:

```
Bug triaged → background agent investigating.
Run /check-status to monitor progress.
```

Keep it to one line. The user is rapid-firing — don't interrupt their flow.

## Handling Multiple Rapid-Fire Bugs

The user may fire `/triage` multiple times in quick succession. Each invocation:
1. Launches its own independent background triage agent
2. Creates its own ticket with a unique ID
3. Dispatches its own fix agent in its own worktree
4. Reports back independently when done

There is no queue or batching. Each `/triage` is fully independent. The `max_concurrent_triage` config limits how many run simultaneously — excess bugs get ticketed but not auto-dispatched.

## Important

- **Always launch in background.** The whole point is fire-and-forget. Never block the user.
- **Always acknowledge immediately.** One line, then stop. Don't investigate inline.
- **Always create a ticket**, even if at capacity. The bug is logged regardless of whether it's auto-fixed.
- **The triage agent handles everything.** The skill just launches it and gets out of the way.
- **Respect the board.** New tickets integrate into the existing board.json — they show up in `/check-status` alongside planned tickets.
