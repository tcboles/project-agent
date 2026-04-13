---
name: config
description: >-
  View or modify project-agent configuration. Use when the user asks to
  "show config", "change config", "set max agents", "disable reviewer",
  "configure project agent", or any config-related request.
---

# Project Agent Configuration

View or modify project-agent settings.

## Config File Locations

1. **Global**: `~/.claude/project-agent/config.json` — applies across all workspaces
2. **Workspace**: `{cwd}/.project-agent/config.json` — overrides global for this workspace

Workspace values merge on top of global. If neither file exists, defaults apply.

## Default Configuration

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
  "ticket_id_prefix": "PA",
  "wiki": {
    "enabled": true,
    "vault_path": "~/projects/obsidian/project-agent",
    "auto_ingest": true,
    "auto_query": true,
    "auto_lint_interval": null
  }
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `max_concurrent_agents` | `6` | Max agents dispatched in parallel per wave |
| `default_model` | `"sonnet"` | Model for agents unless overridden per-agent |
| `agents.{name}.enabled` | `true` | Set `false` to skip this agent type entirely |
| `agents.{name}.model` | `null` | Override model for a specific agent (`null` = use `default_model`) |
| `autonomous` | `false` | When `true`, skips all approval prompts (plan, dispatch, review, merge, recovery). Merge conflicts and `@user` questions still pause. |
| `auto_review` | `true` | Automatically run reviews after agents complete |
| `auto_merge` | `false` | Automatically merge after all tickets are done (if `true`, skips the merge approval prompt) |
| `ticket_id_prefix` | `"PA"` | Prefix for ticket IDs (e.g., `PA-001`). Change to `MW` for marketing-website tickets |
| `triage.auto_fix` | `true` | Triage agent dispatches fix agents automatically |
| `triage.auto_verify` | `true` | Triage agent runs tests after fix |
| `triage.default_priority` | `"P1"` | Default priority for triaged bugs |
| `triage.max_concurrent_triage` | `4` | Max background triage agents simultaneously |
| `wiki.enabled` | `true` | Enable the wiki memory layer (ingest, query, lint) |
| `wiki.vault_path` | `"~/projects/obsidian/project-agent"` | Absolute path to the Obsidian vault on disk |
| `wiki.auto_ingest` | `true` | Automatically ingest learnings into the vault after each agent completes |
| `wiki.auto_query` | `true` | Automatically query the vault at agent dispatch time |
| `wiki.auto_lint_interval` | `null` | How often to run vault lint (e.g., `"daily"`); `null` disables scheduled lint |

## Operations

Parse the user's intent and execute one of:

### Show Config

Usage: `/config`, `/config show`

1. Read global config from `~/.claude/project-agent/config.json` (if it exists).
2. Read workspace config from `{cwd}/.project-agent/config.json` (if it exists).
3. Compute the merged result (workspace overrides global).
4. Display as a table showing each setting, its effective value, and where it comes from:

```
## Project Agent Config

| Setting | Value | Source |
|---------|-------|--------|
| max_concurrent_agents | 6 | global |
| default_model | sonnet | default |
| agents.architect.enabled | true | default |
| agents.architect.model | opus | workspace |
| agents.developer.enabled | true | default |
| agents.developer.model | sonnet | global |
| agents.tester.enabled | true | default |
| agents.tester.model | sonnet | default |
| agents.reviewer.enabled | false | workspace |
| agents.reviewer.model | sonnet | default |
| autonomous | false | default |
| auto_review | true | default |
| auto_merge | false | default |
| ticket_id_prefix | PA | default |
| wiki.enabled | true | default |
| wiki.vault_path | ~/projects/obsidian/project-agent | default |
| wiki.auto_ingest | true | default |
| wiki.auto_query | true | default |
| wiki.auto_lint_interval | null | default |
```

### Set a Value

Usage: `/config set max_concurrent_agents 3`, `/config set agents.reviewer.enabled false`, `/config disable reviewer`, `/config use opus for architect`

1. Parse the setting name and new value from the user's input. Handle natural language:
   - "disable reviewer" → `agents.reviewer.enabled = false`
   - "enable reviewer" → `agents.reviewer.enabled = true`
   - "set max agents to 3" → `max_concurrent_agents = 3`
   - "use opus for architect" → `agents.architect.model = "opus"`
   - "use opus" → `default_model = "opus"`
   - "turn off auto review" → `auto_review = false`
   - "run autonomously" / "enable autonomous" / "yolo mode" → `autonomous = true`
   - "disable autonomous" / "ask me each step" → `autonomous = false`
   - "set prefix to MW" → `ticket_id_prefix = "MW"`
2. Determine scope:
   - Default to **workspace** config (`{cwd}/.project-agent/config.json`)
   - If the user says "globally" or "for all projects", use **global** config (`~/.claude/project-agent/config.json`)
3. Read the target config file (or start with `{}` if it doesn't exist).
4. Set the value. Only write changed keys — don't copy all defaults into the file.
5. Write the updated config file. Create the directory if needed.
6. Show what changed:

```
Updated workspace config:
  agents.reviewer.enabled: true → false

Effective config now has reviewer disabled.
```

### Reset Config

Usage: `/config reset`, `/config reset workspace`

1. If "global" — delete `~/.claude/project-agent/config.json` (but keep `learnings.json`).
2. If "workspace" or unspecified — delete `{cwd}/.project-agent/config.json`.
3. Confirm what was reset and show the now-effective defaults.

## Important

- **Never delete learnings.json** when resetting config. Only remove the config file.
- **Validate values** before writing:
  - `max_concurrent_agents`: integer, 1-10
  - `default_model` / `agents.*.model`: must be `"sonnet"`, `"opus"`, or `"haiku"`
  - `agents.*.enabled`, `autonomous`, `auto_review`, `auto_merge`: boolean
  - `ticket_id_prefix`: 1-5 uppercase letters
  - `wiki.enabled`, `wiki.auto_ingest`, `wiki.auto_query`: boolean
  - `wiki.vault_path`: non-empty string (tilde expansion supported)
  - `wiki.auto_lint_interval`: `null` or a string (e.g., `"daily"`, `"weekly"`)
- If the user provides an invalid value, explain what's valid and ask them to try again.
- **Show effective config after every change** so the user can verify.
