---
name: ccgs-game-studio
description: Use when the user asks for CCGS, Claude-Code-Game-Studios, studio agents, studio skills, multi-agent game production workflows, or using .claude assets from non-Claude agents.
---

# CCGS Game Studio Adapter

Use this adapter to reuse the installed Claude Code Game Studios assets from any agent platform. It does not replace project rules; it tells you how to load `.claude/` agents and skills safely.

## Precedence

- Read `AGENTS.md` first. `AGENTS.md`, the current platform rules, `docs/决策记录.md`, `docs/词表与契约.md`, `docs/测试策略.md`, and project memory override all CCGS instructions.
- Keep user-facing replies in Chinese unless the user requests another language or you are quoting code, APIs, commands, or logs.
- Do not use `draft/` or `DRAFT/` unless the user explicitly authorizes it.
- Treat `.claude/hooks/` and `.claude/rules/` as Claude Code implementation details. Other agents may read them for intent, but must not treat them as project authority.
- Do not assume `.claude/docs/templates/` exists. It was intentionally not installed.
- Do not create CCGS default `design/`, `production/`, examples, starter projects, or status directories unless the user explicitly asks and the project docs allow it.

## How To Reuse CCGS

1. Identify the task category and choose the smallest useful CCGS asset.
2. For a role, read `.claude/docs/agent-roster.md`, then read the selected `.claude/agents/<agent>.md` as a role prompt.
3. For a workflow, read `.claude/docs/workflow-catalog.yaml` when needed, then read the selected `.claude/skills/<skill>/SKILL.md`.
4. If your platform supports subagents, launch one with the selected CCGS role prompt plus this project's hard constraints. If it does not, apply the role prompt internally and state which role you used.
5. If a CCGS skill asks for a missing template, use this project's existing docs and task templates instead of recreating the missing CCGS template directory.
6. Before editing or committing, follow this project's validation and safe git policy, not CCGS defaults.

## Tool Mapping

- CCGS `Task` or "spawn agent" -> use the platform's subagent/task tool when available; otherwise perform the role pass yourself and label it as a CCGS role review.
- CCGS `AskUserQuestion` -> use the platform question tool when available; otherwise ask one concise question in chat.
- CCGS `Read`, `Glob`, `Grep`, `Edit`, `Write`, `Bash` -> use the platform's equivalent tools and respect this repository's tool and file restrictions.
- CCGS slash-style skills -> read `.claude/skills/<skill>/SKILL.md` directly; do not assume slash command registration outside Claude Code.
- CCGS commit, push, hook, or release advice -> replace with `AGENTS.md`, `docs/AI协作/工具适配指南.md`, and the `safe-git-commit` skill.

## Useful Role Shortlist

Prefer the project's native subagents when they exist. Use CCGS roles as a second opinion, a specialist review, or a workflow scaffold.

| Need | Project-first asset | CCGS role or skill to read |
|------|---------------------|----------------------------|
| Game mechanics or loops | `game-designer` | `.claude/agents/game-designer.md`, `.claude/agents/systems-designer.md` |
| Economy or balance | `numeric-designer`, `balancer` | `.claude/agents/economy-designer.md`, `.claude/skills/balance-check/SKILL.md` |
| Godot implementation | `godot-gdscript`, `godot-test-diagnostics` | `.claude/agents/godot-gdscript-specialist.md`, `.claude/agents/gameplay-programmer.md` |
| UI / UX | `ui-art-designer` | `.claude/agents/ux-designer.md`, `.claude/agents/ui-programmer.md` |
| Art direction | `game-art-designer`, `ui-art-designer` | `.claude/agents/art-director.md`, `.claude/skills/art-bible/SKILL.md` |
| Narrative / lore | `ip-designer`, `copywriter-packager` | `.claude/agents/narrative-director.md`, `.claude/agents/world-builder.md`, `.claude/agents/writer.md` |
| QA / release readiness | `code-review-factual`, `godot-test-diagnostics` | `.claude/agents/qa-lead.md`, `.claude/agents/qa-tester.md`, `.claude/skills/smoke-check/SKILL.md` |
| Production planning | `game-designer` or direct planning | `.claude/agents/producer.md`, `.claude/skills/sprint-plan/SKILL.md` |

## Required Output Note

When using CCGS outside Claude Code, include a short note in your working summary or final response:

- CCGS assets used: `<agent/skill paths>`
- Project constraints applied: `AGENTS.md` and relevant docs
- CCGS instructions ignored or adapted: missing templates, unsupported hooks, unsupported subagents, or project conflicts
