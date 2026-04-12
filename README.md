# project-agent

Claude Code plugin for AI-driven project management. Break projects into tickets, dispatch specialized agents in isolated worktrees, and manage the full lifecycle with 6 skills. Supports multi-project workspaces and three-tier agent learnings.

## Installation

```bash
# Register the plugin source
claude plugin marketplace add tcboles/project-agent

# Install the plugin
claude plugin install project-agent@project-agent
```

Restart Claude Code after installing to pick up the new skills.

### Alternative Methods

Install from a local clone:

```bash
claude plugin marketplace add /path/to/project-agent
claude plugin install project-agent@project-agent
```

Try it for a single session without installing:

```bash
claude --plugin-dir /path/to/project-agent
```

## Quick Start

You provide the commands — Claude does the work. Each step is a single slash command.

```
/plan-project mobile-app
```

Claude asks clarifying questions about your project, designs the architecture, and generates a full board of dependency-ordered tickets. You review and approve the plan.

From there, you drive the board through its lifecycle:

```
/assign-work mobile-app      # dispatches ready tickets to agents in worktrees
/check-status mobile-app     # see what's done, in progress, or blocked
/review-board mobile-app     # run code reviews on completed tickets
/merge-work mobile-app       # merge finished worktrees into main
```

Run `/assign-work` again after each wave completes to dispatch the next batch of tickets whose dependencies are now satisfied. Repeat until the board is clear.

## Skills

### `/plan-project [name]`

The main entry point. Provide a project description and Claude will:

1. Ask clarifying questions about scope, tech stack, features, and constraints
2. Design the architecture and identify major components
3. Determine which agents are needed (creates project-specific agents if warranted)
4. Generate dependency-ordered tickets with full context for autonomous work
5. Present the plan for your approval before finalizing

### `/assign-work [project-name]`

Reads the board, finds tickets whose dependencies are satisfied, matches them to the right agent type, and launches up to 3 subagents in parallel. Each agent works in an isolated git worktree to prevent conflicts.

### `/check-status [project-name]`

Displays the board state. Without a project name, shows an overview of all projects in the workspace. With a name, drills into that project showing tickets grouped by status, agent utilization, blockers, and suggested next actions.

### `/review-board [project-name]`

Quality gate. Dispatches the reviewer agent against all tickets in "review" status. Approved tickets move to "done". Rejected tickets go back to "backlog" with review feedback attached so the next developer agent knows exactly what to fix.

### `/merge-work [project-name]`

Merges completed agent worktrees into the main branch. Merges in dependency order, runs tests after each merge, and handles conflicts (auto-resolve trivial ones, flag others for manual intervention). Creates a restore tag before starting.

### `/update-ticket [ticket-id] [operation]`

Modify tickets after planning without re-planning the entire project:

- **Add context**: `/update-ticket PA-003 add context: The API requires OAuth2 tokens`
- **Reprioritize**: `/update-ticket PA-003 priority P0`
- **Change status**: `/update-ticket PA-003 status blocked`
- **Split**: `/update-ticket PA-003 split`
- **Reassign**: `/update-ticket PA-003 category frontend-dev`
- **Edit**: `/update-ticket PA-003 edit`

## Agents

Four default agents ship with the plugin. `/plan-project` can create additional project-specific agents when needed.

| Agent | Role | Writes Code? |
|-------|------|:------------:|
| **architect** | System design, interfaces, data models, ADRs | No (design docs + types only) |
| **developer** | Feature implementation, bug fixes, refactoring | Yes |
| **tester** | Unit/integration/e2e tests, coverage, edge cases | Yes (tests only) |
| **reviewer** | Code review with severity-rated findings | No (review docs only) |

Each agent is defined as a markdown file with YAML frontmatter specifying its name, tools, model, and behavioral instructions. You can customize the defaults or create new agents for specific domains (e.g., `mobile-dev`, `ml-engineer`).

## Multi-Project Support

A single workspace can manage multiple projects. Each gets its own board, tickets, learnings, and agents:

```
my-workspace/
├── mobile-app/                     # your code
├── marketing-site/                 # your code
├── .project-agent/
│   ├── registry.json               # lists all projects
│   ├── learnings.json              # workspace learnings
│   ├── projects/
│   │   ├── mobile-app/
│   │   │   ├── board.json
│   │   │   ├── tickets/
│   │   │   ├── learnings.json
│   │   │   └── agents/
│   │   └── marketing-site/
│   │       ├── board.json
│   │       ├── tickets/
│   │       ├── learnings.json
│   │       └── agents/
```

All skills accept an optional `[project-name]` argument. If omitted and multiple projects exist, you'll be prompted to choose.

## Three-Tier Learnings

When agents discover something non-obvious about a codebase, they record it so future agents don't repeat the same mistakes. Learnings are scoped to three tiers:

| Tier | Location | Scope | Example |
|------|----------|-------|---------|
| **Global** | `~/.claude/project-agent/learnings.json` | All repos | "Claude worktrees need at least one commit in the repo" |
| **Workspace** | `{cwd}/.project-agent/learnings.json` | This codebase | "Shared `@dt/ui` package needs `pnpm build` before imports work" |
| **Project** | `{cwd}/.project-agent/projects/{name}/learnings.json` | One project | "Mobile app uses Expo Router v4, not React Navigation" |

Agents read all three tiers before starting work and append to the most specific tier that applies.

## Ticket Lifecycle

```
backlog → assigned → in-progress → review → done
                         ↓                    ↑
                      blocked          (via /review-board)
                         ↓
                   (manual unblock)
                         ↓
                      backlog → ...
```

Each ticket is a self-contained markdown file with:

- Full description and technical context
- Acceptance criteria (checkboxes)
- File paths involved
- Dependencies on other tickets
- Handoff notes (written by the completing agent for downstream agents)
- Review feedback (written by the reviewer agent)

## Handoff Notes

When an agent finishes a ticket, it writes a `## Handoff Notes` section documenting what was actually built: files changed, interfaces created, decisions made, and anything downstream agents need to know. This context is automatically included when dispatching dependent tickets, so agents build on real implementation details rather than guessing.

## How It Works Under the Hood

1. `/plan-project` generates `.project-agent/` with `board.json`, ticket files, and learnings
2. `/assign-work` reads the board, resolves dependencies, and launches subagents via Claude Code's Agent tool with `isolation: "worktree"`
3. Each agent receives: its role definition, the ticket content, handoff notes from dependencies, and all relevant learnings
4. Agents work autonomously in isolated worktrees, then report back
5. `/review-board` runs the reviewer agent for quality gating
6. `/merge-work` integrates worktrees back into main with conflict detection and test verification
7. A `PreToolUse` hook logs all Edit/Write/Bash operations to `.project-agent/activity.log` for observability

## Project Structure

```
project-agent/                    # plugin root
├── .claude-plugin/
│   ├── plugin.json               # plugin manifest
│   └── marketplace.json          # marketplace manifest
├── agents/
│   ├── architect.md              # default agents
│   ├── developer.md
│   ├── reviewer.md
│   └── tester.md
├── skills/
│   ├── plan-project/SKILL.md     # 6 skills
│   ├── assign-work/SKILL.md
│   ├── check-status/SKILL.md
│   ├── review-board/SKILL.md
│   ├── merge-work/SKILL.md
│   └── update-ticket/SKILL.md
├── hooks/
│   ├── hooks.json                # progress tracking hook config
│   └── track-progress.sh         # logs agent file operations
├── templates/
│   └── ticket.md                 # ticket template
└── CLAUDE.md                     # plugin instructions
```

## License

MIT
