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

## How It Works

### Core Workflow
1. **`/plan-project`** — User describes a project (with a name). The skill asks clarifying questions, designs architecture, generates tickets under `.project-agent/projects/{name}/`, and creates any project-specific agents needed.
2. **`/assign-work [project-name]`** — Reads the board for the specified project (or prompts if multiple exist), finds tickets whose dependencies are satisfied, and dispatches them to subagents in isolated worktrees (up to 3 in parallel).
3. **`/check-status [project-name]`** — Displays board state. Without args, shows a summary of all projects. With a name, drills into that project.

### Quality & Integration
4. **`/review-board [project-name]`** — Quality gate for a specific project's completed tickets.
5. **`/merge-work [project-name]`** — Merges completed worktrees for a specific project.

### Ticket Management
6. **`/update-ticket`** — Modify tickets after planning: add context, reprioritize, split, block, reassign, or edit.

## Conventions

- Ticket IDs follow the pattern `PA-NNN` (e.g., `PA-001`, `PA-012`), scoped per project.
- Ticket statuses: `backlog` → `assigned` → `in-progress` → `review` → `done`. Also `blocked`.
- Agent categories in tickets map directly to agent IDs.
- All timestamps are ISO 8601 format.
- Agents work in isolated git worktrees — changes are merged back via `/merge-work`.
- All skills accept an optional `[project-name]` argument. If omitted and multiple projects exist, the skill prompts the user to choose.

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
