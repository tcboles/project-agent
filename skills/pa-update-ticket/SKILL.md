---
name: pa-update-ticket
description: >-
  Modify tickets after planning — add context, reprioritize, split, block, or
  close tickets. Use when the user asks to "update ticket", "change ticket",
  "split ticket", "block ticket", "reprioritize", or "add context to ticket".
---

# Update Ticket

Modify existing tickets on the board without re-planning the entire project.

## Project Resolution

Ticket IDs are scoped per project. If the user specifies a project name, use it. Otherwise:

1. Read `.project-agent/registry.json` from the cwd.
2. If only one project exists, use it.
3. If multiple exist, search all projects for the ticket ID. If found in exactly one, use that project. If found in multiple (same ID in different projects), ask the user to specify.

Project data paths:
- Board: `{cwd}/.project-agent/projects/{name}/board.json`
- Tickets: `{cwd}/.project-agent/projects/{name}/tickets/`

## Supported Operations

The user will specify a ticket ID (e.g., `PA-003`) and an operation. Parse their intent and execute one of these:

### Add Context

Add information to an existing ticket. Append to the `## Notes` section of the ticket file.

Usage: `/pa-update-ticket PA-003 add context: The API requires OAuth2 bearer tokens, see docs at...`

1. Read the ticket file.
2. Append the new context to the `## Notes` section.
3. Update `updated_at` in board.json.

### Reprioritize

Change a ticket's priority.

Usage: `/pa-update-ticket PA-003 priority P0`

1. Update `priority` in both the ticket frontmatter and board.json.
2. Update `updated_at` in board.json.
3. Show how this affects the dispatch order (what gets picked up next by `/pa-assign-work`).

### Change Status

Manually set a ticket's status.

Usage: `/pa-update-ticket PA-003 status blocked`

1. Update `status` in both the ticket frontmatter and board.json.
2. If setting to `blocked`, ask the user for the reason and add it to `## Notes`.
3. If setting to `done`, set `completed_at` to current timestamp.
4. If setting to `backlog`, clear `assigned_agent`.
5. Update `updated_at` in board.json.

### Split Ticket

Break a large ticket into smaller ones.

Usage: `/pa-update-ticket PA-003 split`

1. Read the original ticket thoroughly.
2. Ask the user how they want it split (or propose a split based on the acceptance criteria).
3. Create new ticket files with the next available IDs (e.g., `PA-015`, `PA-016`).
4. Each new ticket inherits:
   - The original's dependencies
   - A subset of the original's acceptance criteria
   - The original's technical context (copy relevant parts, don't duplicate everything)
5. Add the new tickets to board.json.
6. Set the original ticket's status to `done` with a note: `"Split into PA-015, PA-016"`.
7. Update any tickets that depended on the original to depend on ALL split tickets instead.
8. Show the user the new tickets for approval.

### Reassign Category

Change which agent type should handle a ticket.

Usage: `/pa-update-ticket PA-003 category frontend-dev`

1. Update `category` in both the ticket frontmatter and board.json.
2. Verify the target agent exists (check both `@plugin/agents/` and `.project-agent/projects/{name}/agents/`). If not, warn the user.
3. Update `updated_at` in board.json.

### Edit Description

Open the ticket for full editing. Read the ticket, show its contents, and ask the user what to change.

Usage: `/pa-update-ticket PA-003 edit`

1. Read and display the ticket contents.
2. Ask the user what sections to modify.
3. Apply the changes to the ticket file.
4. Update `updated_at` in board.json.

## Workflow

1. **Parse the user's input.** Extract the ticket ID, optional project name, and operation.
2. **Resolve the project** using the project resolution logic above.
3. **Validate the ticket exists.** Read board.json, find the ticket. If it doesn't exist, list available ticket IDs.
4. **Execute the operation.** Follow the steps for the specific operation above.
5. **Update board.json.** Always update `updated_at` on the modified ticket.
6. **Confirm the change.** Show the user what was modified.

## Important

- **Never modify tickets that are `in-progress`.** An agent is currently working on them. Warn the user and suggest waiting for the agent to finish, or manually setting the ticket to `blocked` first.
- **Maintain consistency.** When changing dependencies or splitting tickets, verify the dependency graph is still valid (no circular deps, no orphaned deps).
- **Log changes.** Append a line to the ticket's `## Notes` section documenting the change: `[2026-04-12] Reprioritized from P2 to P0 — user request`.
