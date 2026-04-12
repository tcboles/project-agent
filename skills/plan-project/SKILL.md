---
name: plan-project
description: >-
  Plan a new project from scratch. Gathers context from the user, asks clarifying
  questions, designs architecture, generates tickets, and creates specialized
  agents as needed. Use when the user asks to "plan a project", "create a project
  plan", "break down a project", "start planning", or "plan this".
---

# Plan Project

Take a project from concept to a fully-ticketed, agent-ready implementation plan.

## File Locations

This system supports **multiple projects per workspace**. All project data lives in the **current working directory** under `.project-agent/`:

```
{cwd}/.project-agent/
├── registry.json                          # all projects in this workspace
├── learnings.json                         # workspace-level learnings
├── projects/
│   └── {project-name}/
│       ├── board.json                     # ticket registry for this project
│       ├── tickets/                       # PA-001.md, PA-002.md, etc.
│       ├── learnings.json                 # project-specific learnings
│       └── agents/                        # project-specific agent definitions
```

Additionally, global learnings are stored at `~/.claude/project-agent/learnings.json`.

Default agent definitions live in the plugin directory (`@plugin/agents/`).

## Phase 1: Gather Context

Read what the user has provided. You need a **project name** (required) plus:

- **What** the project is and what problem it solves
- **Tech stack** — languages, frameworks, databases, infrastructure
- **Features** — the main capabilities and user stories
- **Existing code** — is this greenfield or building on an existing repo?
- **Constraints** — timeline, third-party APIs, compliance, performance targets
- **Target users** — who will use this and how?

If the user didn't provide a project name, ask for one. It should be short, lowercase, hyphenated (e.g., `mobile-app`, `marketing-site`, `api-server`).

If the user's input is sparse or ambiguous, ask clarifying questions using AskUserQuestion. Batch your questions — ask up to 4 at once rather than one at a time. Focus on what you actually need to make planning decisions. Do NOT ask obvious questions that can be inferred from context.

If the user pointed to an existing codebase, launch Explore agents (up to 3 in parallel) to understand:
- Project structure, frameworks, and conventions
- Existing patterns for similar features
- Test infrastructure and coverage
- Build and deployment setup

## Phase 2: Design Architecture

Based on the gathered context, design the project architecture:

1. **Identify major components** — what are the main modules, services, or layers?
2. **Define data flow** — how do components communicate? What are the key interfaces?
3. **Sequence the work** — what must be built first? What can be parallelized?
4. **Identify risks** — what's the hardest part? Where might things go wrong?

Write a brief architecture summary (5-10 sentences) that will be stored in `board.json` as the project description. This gives all agents a shared mental model of the system.

## Phase 3: Determine Agents Needed

Start with the 4 default agents:
- **architect** — system design, interfaces, data models (read-only, no implementation)
- **developer** — feature implementation, bug fixes, refactoring
- **tester** — test writing, coverage, edge case identification
- **reviewer** — code review, quality checks, convention adherence

Evaluate whether the project needs specialized agents beyond these. Create additional agent definition files ONLY if:
- The project has a distinct domain requiring specialized knowledge (e.g., ML, mobile, embedded)
- There are two clearly different implementation domains (e.g., frontend and backend with different conventions)
- A specialized agent would produce meaningfully better results than the generic developer

For each new agent, create a markdown file in `{cwd}/.project-agent/projects/{name}/agents/` following the same format as the default agents. Include: name, description, tools, model, color, role description, focus areas, standards, output expectations, and constraints.

## Phase 4: Generate Tickets

Break the project into tickets. Each ticket must be:

- **Self-contained** — contains ALL context an agent needs to work autonomously
- **Appropriately scoped** — small enough for a single agent session (roughly 1-2 hours of focused work)
- **Explicitly ordered** — dependencies are listed by ticket ID
- **Categorized** — the `category` field maps to an agent ID

### Ticket Generation Rules

1. **Start with architecture tickets (P0).** The architect should define interfaces and structure before developers implement.
2. **Group by feature, not by layer.** A ticket should deliver a complete vertical slice where possible, not "all the models" or "all the routes."
3. **Make dependencies explicit.** If ticket B needs the interfaces from ticket A, list `PA-001` in B's dependencies.
4. **Include technical context.** Reference specific files, functions, and patterns from the codebase exploration. Don't be vague — "implement the API" is useless; "implement the /api/users endpoint using the existing Express router pattern in src/routes/" is actionable.
5. **Write clear acceptance criteria.** Use checkboxes. Each criterion should be verifiable — not "works well" but "returns 200 with user object matching the UserResponse interface."
6. **Assign complexity.** `small` (< 30 min), `medium` (30-90 min), `large` (90+ min). If a ticket is `large`, consider splitting it.
7. **Assign priority.** P0 = blocks everything, P1 = core functionality, P2 = important but not blocking, P3 = nice-to-have.

### Ticket ID Format

Use `PA-NNN` format starting from `PA-001`. Number sequentially in roughly the order they should be worked on. IDs are scoped per project (both `mobile-app` and `marketing-site` can have a `PA-001`).

## Phase 5: Write Files

Create the following directory and files:

1. **Create directories** if they don't exist:
   - `{cwd}/.project-agent/projects/{name}/tickets/`
   - `{cwd}/.project-agent/projects/{name}/agents/` (if project-specific agents are needed)

2. **`{cwd}/.project-agent/registry.json`** — Create or update the workspace registry:
```json
{
  "workspace": "workspace-name",
  "projects": [
    {
      "name": "project-name",
      "description": "Brief project description",
      "status": "active",
      "created_at": "ISO8601",
      "path": ".project-agent/projects/project-name"
    }
  ]
}
```
If the registry already exists, append the new project to the `projects` array.

3. **`{cwd}/.project-agent/projects/{name}/board.json`** — The project's ticket registry:
```json
{
  "project": {
    "name": "Project Name",
    "description": "Architecture summary from Phase 2",
    "tech_stack": ["TypeScript", "React", "PostgreSQL"],
    "created_at": "ISO8601 timestamp"
  },
  "agents": [
    {
      "id": "architect",
      "definition_file": "@plugin/agents/architect.md",
      "status": "idle",
      "current_ticket": null
    }
  ],
  "tickets": [
    {
      "id": "PA-001",
      "title": "Ticket title",
      "status": "backlog",
      "assigned_agent": null,
      "priority": "P0",
      "category": "architect",
      "dependencies": [],
      "created_at": "ISO8601",
      "updated_at": "ISO8601",
      "completed_at": null,
      "ticket_file": ".project-agent/projects/{name}/tickets/PA-001.md"
    }
  ]
}
```

The `definition_file` field uses `@plugin/` prefix for default agents (resolved to the plugin's `agents/` directory) or `.project-agent/projects/{name}/agents/` for project-specific agents.

4. **`{cwd}/.project-agent/projects/{name}/tickets/PA-NNN.md`** — One file per ticket.

5. **`{cwd}/.project-agent/projects/{name}/learnings.json`** — Initialize with `{"project": "Project Name", "learnings": []}`.

6. **`{cwd}/.project-agent/learnings.json`** — Create workspace learnings if it doesn't exist: `{"workspace": "workspace-name", "learnings": []}`.

7. **`~/.claude/project-agent/learnings.json`** — Create global learnings if it doesn't exist: `{"scope": "global", "learnings": []}`.

8. **New agent files** (if any) in `{cwd}/.project-agent/projects/{name}/agents/`.

## Phase 6: Present Plan to User

Show a summary table of the generated plan:

```
## Project: {name}
**Tech Stack:** {stack}
**Total Tickets:** {count} | **Agents:** {agent list}

### Ticket Plan
| ID | Title | Category | Priority | Deps | Complexity |
|----|-------|----------|----------|------|------------|
| PA-001 | ... | architect | P0 | — | small |
| PA-002 | ... | developer | P1 | PA-001 | medium |
```

Then show the dependency graph as a simple text visualization:
```
PA-001 (architect) → PA-002 (developer) → PA-005 (tester)
                   → PA-003 (developer) → PA-005
PA-004 (developer, no deps) → PA-006 (tester)
```

Ask the user to review and approve. If they want changes, iterate on the tickets before finalizing.

## Phase 7: Orchestrate the Board

Once the user approves the plan, **you own the board**. Drive it to completion by running the orchestration loop:

1. **Dispatch ready tickets** — follow the `/assign-work` workflow: reconcile the board, find tickets with satisfied dependencies, present what you're about to dispatch, get user approval, then launch agents.
2. **Wait for agents to complete** — update board.json as each agent finishes.
3. **Review completed work** — follow the `/review-board` workflow: run the reviewer agent against tickets in `review` status. Approved tickets move to `done`; rejected tickets go back to `backlog` with feedback.
4. **Loop** — after reviews, check if new tickets are now ready (their dependencies just moved to `done`). If so, go back to step 1. Continue until:
   - All tickets are `done` → proceed to step 5
   - All remaining tickets are `blocked` → stop and explain the blockers to the user
5. **Merge** — once all tickets are done, follow the `/merge-work` workflow: present the merge plan, get approval, merge worktrees in dependency order.

**At each checkpoint (dispatching agents, merging), present the plan and get user approval before proceeding.** The user should see what's about to happen but shouldn't need to manually invoke each skill.

If the user interrupts or the session ends, the board state is preserved. The user can resume by running `/assign-work` or `/check-status` to pick up where things left off.

## Important

- **Do not rush the question phase.** A poorly scoped project plan wastes more time than asking one more question.
- **Do not create tickets for trivial setup** (git init, npm install) unless the setup is genuinely complex.
- **Do not over-ticket.** 5-15 tickets is typical for a medium project. If you're generating 30+, your tickets are too granular.
- **Every ticket must be actionable by an agent in isolation.** If an agent would need to ask a question to proceed, the ticket is incomplete.
- **Reference the ticket template** in `templates/ticket.md` for the exact format, but don't copy it blindly — fill in real content.
