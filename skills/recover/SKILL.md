---
name: recover
description: >-
  Recover an interrupted orchestration session. Reads the board state, recovers
  from stale agents and incomplete work, and picks up the orchestration loop
  from wherever it stopped. Use when the user asks to "recover project",
  "pick up where we left off", "restart work", or "recover board".
  Note: /resume is a built-in Claude Code command — this skill uses /recover instead.
---

# Recover

Recover from an interrupted session and continue the orchestration loop.

## Project Resolution

Same pattern as other skills:
1. If the user specified a project name, use it.
2. If not, read `.project-agent/registry.json` — one project uses it, multiple prompts the user.

## Workflow

### Step 1: Load Config

Read config from global and workspace levels (same as `/assign-work`).

### Step 2: Deep Reconciliation

This is a more thorough version of the standard board reconciliation, because we're recovering from an unknown interruption point.

1. **Read board.json** for the resolved project.
2. **Read every ticket file** and reconcile status (same rules as `/check-status`).
3. **Detect stale agents:** Any agent showing `busy` is suspect — the session that launched it is gone.
   - Read the agent's `current_ticket`. Check the ticket file:
     - If ticket has handoff notes → agent finished, update ticket to `review`, agent to `idle`
     - If ticket has no handoff notes → agent was interrupted mid-work. Reset ticket to `backlog`, agent to `idle`. Note this as a recovery action.
4. **Detect orphaned in-progress tickets:** Tickets in `in-progress` with no busy agent are stale.
   - If ticket has handoff notes → set to `review`
   - If ticket has no handoff notes → set to `backlog` (agent was interrupted, work is incomplete)
5. **Check for unanswered questions:** Read `## Questions` sections of blocked tickets. If there are unrouted questions, queue them for routing.
6. **Write all corrections to board.json.**

### Step 3: Present Recovery Report

Show the user what was recovered:

```
## Recovery Report — {project-name}

### Recovered State
| Action | Ticket | Details |
|--------|--------|---------|
| Agent reset | PA-003 | developer was busy but session died — ticket reset to backlog |
| Status updated | PA-001 | Had handoff notes but was in-progress — moved to review |
| Already done | PA-002 | Review approved — moved to done |

### Current Board State
- Done: {N}
- Review: {N} (ready for /review-board)
- Backlog: {N} ({M} ready, {K} waiting on deps)
- Blocked: {N}

### Pending Questions
- PA-005: @architect: "Should the cache TTL be configurable?" — needs routing

### Recommended Next Action
{Based on board state — same logic as /check-status suggestions}
```

### Step 4: Get Approval and Continue

Ask the user: **"Ready to resume the orchestration loop?"** using AskUserQuestion.

If approved, determine where to re-enter the loop:

1. **If there are tickets in `review`** → start with the `/review-board` workflow
2. **If there are ready tickets in `backlog`** → start with the `/assign-work` workflow
3. **If there are blocked tickets with unanswered questions** → route the questions first (dispatch target agents or ask user), then check for ready tickets
4. **If all tickets are `done`** → proceed to `/merge-work` workflow
5. **If all remaining tickets are `blocked` with no questions to route** → report blockers and stop

Continue the full orchestration loop from there (assign → review → assign → merge), same as `/plan-project` Phase 7.

## Important

- **Always do deep reconciliation.** The standard reconciliation in other skills only checks ticket content. Resume also checks agent states, orphaned work, and unanswered questions.
- **Don't discard partial work.** If a ticket was in-progress and has some handoff notes, preserve them. The next agent will build on the partial work.
- **Be transparent about recovery.** Show the user exactly what was in a bad state and what you corrected. Don't silently fix things.
- **Respect retry counts.** If a ticket was already at retry_count 3, don't reset it. The escalation history matters.
