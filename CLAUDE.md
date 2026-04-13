# Project Agent System

This plugin provides project management skills for Claude Code. It breaks projects into tickets and dispatches them to specialized agents working in isolated git worktrees. Supports multiple projects per workspace.

## File Locations

### Multi-Project Structure

A workspace can have multiple projects. Each project gets its own namespace under `.project-agent/projects/`:

```
destinationtours/                         # workspace root (cwd)
├── mobile-app/                           # actual code
├── marketing-site/                       # actual code
├── .project-agent/
│   ├── registry.json                     # lists all projects in this workspace
│   ├── learnings.json                    # workspace-level learnings (shared across projects)
│   ├── projects/
│   │   ├── mobile-app/
│   │   │   ├── board.json                # ticket registry for this project
│   │   │   ├── tickets/                  # PA-001.md, PA-002.md, etc.
│   │   │   ├── learnings.json            # project-specific learnings
│   │   │   └── agents/                   # project-specific agent definitions
│   │   └── marketing-site/
│   │       ├── board.json
│   │       ├── tickets/
│   │       ├── learnings.json
│   │       └── agents/
```

### Three-Tier Learnings

Agents read learnings from all three tiers (most general → most specific):

1. **Global** (`~/.claude/project-agent/learnings.json`) — applies everywhere. Tool quirks, platform issues, general best practices discovered across all repos.
2. **Workspace** (`{cwd}/.project-agent/learnings.json`) — applies to this codebase. Shared conventions, build system quirks, environment setup notes.
3. **Project** (`{cwd}/.project-agent/projects/{name}/learnings.json`) — applies to one project. Framework-specific gotchas, test runner config, API patterns.

Agents append to the most specific tier that applies. Each learning entry includes:
```json
{
  "id": "L-001",
  "text": "The shared @dt/ui package needs pnpm build before other packages can import",
  "source_ticket": "PA-003",
  "agent": "developer",
  "created_at": "ISO8601"
}
```

### Registry

`.project-agent/registry.json` tracks all projects in the workspace:
```json
{
  "workspace": "destinationtours",
  "projects": [
    {
      "name": "mobile-app",
      "description": "React Native mobile app",
      "status": "active",
      "created_at": "ISO8601",
      "path": ".project-agent/projects/mobile-app"
    }
  ]
}
```

Default agent definitions (architect, developer, tester, reviewer) live in the plugin directory at `agents/`. The board references them with an `@plugin/` prefix in `definition_file`.

### Configuration

Settings are loaded from two levels (workspace overrides global):

1. **Global**: `~/.claude/project-agent/config.json`
2. **Workspace**: `{cwd}/.project-agent/config.json`

```json
{
  "max_concurrent_agents": 6,
  "default_model": "sonnet",
  "agents": {
    "architect": { "enabled": true, "model": null },
    "developer": { "enabled": true, "model": null },
    "tester": { "enabled": true, "model": null },
    "reviewer": { "enabled": true, "model": null }
  },
  "autonomous": false,
  "auto_review": true,
  "auto_merge": false,
  "ticket_id_prefix": "PA"
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `max_concurrent_agents` | `6` | Max agents dispatched in parallel per wave |
| `default_model` | `"sonnet"` | Model for agents unless overridden per-agent |
| `agents.{name}.enabled` | `true` | Set `false` to skip this agent type entirely |
| `agents.{name}.model` | `null` | Override model for a specific agent (`null` = use `default_model`) |
| `autonomous` | `false` | When `true`, skips all approval prompts (plan, dispatch, review, merge, recovery) for the session. Merge conflicts and `@user` questions from agents still pause. |
| `auto_review` | `true` | Automatically run reviews after agents complete |
| `auto_merge` | `false` | Automatically merge after all tickets are done (if `true`, skips the merge approval prompt) |
| `ticket_id_prefix` | `"PA"` | Prefix for ticket IDs (e.g., `PA-001`). Change to `MW` for marketing-website tickets |
| `triage.auto_fix` | `true` | Triage agent dispatches fix agents automatically |
| `triage.auto_verify` | `true` | Triage agent runs tests after fix |
| `triage.default_priority` | `"P1"` | Default priority for triaged bugs |
| `triage.max_concurrent_triage` | `4` | Max background triage agents simultaneously |

When reading config, load global first, then merge workspace config on top (workspace values override global). If no config file exists at either level, use the defaults above.

Use `/config` to view or change settings (e.g., `/config show`, `/config set max agents to 3`, `/config disable reviewer`).

## How It Works

### Core Workflow
1. **`/plan-project`** — User describes a project (with a name). The skill asks clarifying questions, designs architecture, generates tickets under `.project-agent/projects/{name}/`, and creates any project-specific agents needed.
2. **`/assign-work [project-name]`** — Reads the board for the specified project (or prompts if multiple exist), finds tickets whose dependencies are satisfied, and dispatches them to subagents in isolated worktrees (up to `max_concurrent_agents` in parallel, default 6).
3. **`/check-status [project-name]`** — Displays board state. Without args, shows a summary of all projects. With a name, drills into that project.

### Quality & Integration
4. **`/review-board [project-name]`** — Quality gate for a specific project's completed tickets.
5. **`/merge-work [project-name]`** — Merges completed worktrees for a specific project.

### Bug Triage
6. **`/triage [bug description]`** — Fire-and-forget bug triage. Launches a background triage agent that investigates the bug, creates a ticket, dispatches a fix agent in a worktree, verifies the fix, and reports back. User can rapid-fire multiple `/triage` commands without waiting.

### Ticket Management
7. **`/update-ticket`** — Modify tickets after planning: add context, reprioritize, split, block, reassign, or edit.

## Conventions

- Ticket IDs follow the pattern `PA-NNN` (e.g., `PA-001`, `PA-012`), scoped per project.
- Ticket statuses: `backlog` → `assigned` → `in-progress` → `review` → `done`. Also `blocked`.
- Agent categories in tickets map directly to agent IDs.
- All timestamps are ISO 8601 format.
- Agents work in isolated git worktrees — changes are merged back via `/merge-work`.
- All skills accept an optional `[project-name]` argument. If omitted and multiple projects exist, the skill prompts the user to choose.

## Source of Truth

**Ticket files are the source of truth, not board.json.** Board.json is a cache that can get stale (session ends mid-work, agent fails to write back, user works manually). Every skill that reads the board MUST reconcile first:

- If a ticket has `## Handoff Notes` content but board says `backlog` → it's actually `review`
- If all acceptance criteria are checked (`- [x]`) but board says `backlog` → it's actually `review`
- If `## Review` contains an `APPROVE` verdict but board says `review` → it's actually `done`
- If an agent shows `busy` but its ticket is `done` → the agent is actually `idle`

Skills update board.json with corrections before proceeding. This makes the system resilient to interruptions.

### Recovery
8. **`/recover [project-name]`** — Recover from an interrupted session. Performs deep reconciliation (resets stale agents, detects orphaned work, routes unanswered questions), presents a recovery report, and re-enters the orchestration loop.

## Wiki Memory Layer

The vault at `~/projects/obsidian/project-agent/` is a living knowledge base that distills agent learnings into structured, cross-referenced wiki pages. Raw `learnings.json` entries are promoted into the vault via the ingest pipeline: each entry is written as an immutable source page, then merged into (or used to create) a wiki page in the appropriate category and scope. Agents query the vault at dispatch time to carry forward known-good patterns and avoid repeating known failure modes. See the `/pa-wiki-*` skills for ingest, query, and lint operations.

## Rules for Agents

- Stay within the scope of the assigned ticket. Do not refactor unrelated code.
- Follow the target project's CLAUDE.md and coding conventions.
- Write tests for all new code.
- **Write Handoff Notes** — when done, update the ticket's `## Handoff Notes` section.
- **Record Learnings** — append to the appropriate tier:
  - Global (`~/.claude/project-agent/learnings.json`): tool/platform discoveries that apply everywhere
  - Workspace (`.project-agent/learnings.json`): codebase-wide conventions and gotchas
  - Project (`.project-agent/projects/{name}/learnings.json`): project-specific discoveries
- If blocked, document the blocker in the ticket notes rather than guessing.

## Structured Agent Output

Every agent MUST end their response with a structured `## Agent Report` block. The orchestrator parses this to determine next steps (retry, escalate, review, merge). Free-form text is not reliable for orchestration decisions.

See each agent's definition file for the exact format. The key field is STATUS: `SUCCESS`, `PARTIAL`, `BLOCKED`, `FAILED` (or `APPROVE`/`REQUEST_CHANGES`/`BLOCK` for the reviewer).

## Retry & Escalation Protocol

When an agent fails or a review sends a ticket back:

| Retry Count | Action |
|-------------|--------|
| 0-1 | Re-dispatch with same model, include failure/review feedback in prompt |
| 2 | Re-dispatch with same model, include all prior feedback |
| 3 | **Escalate** — re-dispatch with `model: "opus"` for more capability |
| 4+ | **Stop** — flag to user as needing manual intervention |

Retry count is tracked per ticket in board.json (`retry_count` field).

## Agent Collaboration

Agents can ask questions to other agents or the user via the ticket's `## Questions` section:

- `@architect: Is the UserProfile interface supposed to include avatarUrl?`
- `@user: The ticket says Redis but I only see PostgreSQL — which should I use?`

The orchestrator routes questions: dispatches the target agent with the question, or presents `@user` questions directly. After the answer is appended, the blocked ticket returns to `backlog` for re-dispatch.

## Typical Session Flow

```
/plan-project mobile-app    → generates .project-agent/projects/mobile-app/
/plan-project marketing-site → generates .project-agent/projects/marketing-site/
/assign-work mobile-app     → dispatches first wave for mobile app
/assign-work marketing-site → dispatches first wave for marketing site (can run in parallel)
/check-status               → overview of all projects
/check-status mobile-app    → drill into mobile app
/review-board mobile-app    → review completed mobile app tickets
/merge-work mobile-app      → integrate done tickets into main branch
```

### Autonomous Execution

After `/plan-project` finishes writing the plan, the skill asks how to proceed:

1. **Run autonomously** — dispatch, review, and merge without further approval prompts
2. **Approve each step** — prompt before each stage (default, current behavior)
3. **Refine the plan** — iterate on tickets first

Picking option 1 runs the full `/assign-work` → `/review-board` → `/merge-work` loop with no further blocking prompts. To make this the default, set `autonomous: true` in workspace or global config. Every skipped approval gate still prints its plan table to stdout, so the user has a full audit trail on scrollback. Merge conflicts and `@user` questions from agents still pause the loop — autonomous mode only skips approval prompts, not genuine human-required inputs.
