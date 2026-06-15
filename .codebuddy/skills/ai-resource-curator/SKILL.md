---
name: ai-resource-curator
description: Evaluate and install external AI skills, agents, MCP servers, plugins, and rules. Use when adding resources from Agent Skills, Claude, OpenCode, MCP, Cursor, or AI marketplaces.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from Agent Skills standard, Anthropic skills repo, OpenCode skills docs, MCP registry, and marketplace patterns
---

# AI Resource Curator

Use this skill when searching, selecting, adapting, or installing AI skills/resources.

## Source Priority

1. Official specs/docs: `agentskills.io`, OpenCode docs, Claude Code skills docs.
2. Official/reference repos: `anthropics/skills`, `modelcontextprotocol/servers`, MCP Registry.
3. Mature community marketplaces: large, maintained, licensed repos such as `wshobson/agents`.
4. Rule collections: Cursor rules and similar prompt libraries, used as inspiration only.

## Selection Criteria

- Relevant to this Godot/GDScript roguelike project.
- Clear license and maintainable source.
- Low context footprint through progressive disclosure.
- No secret requirements or unsafe default permissions.
- No broad autonomous side effects unless explicitly invoked.
- Does not duplicate existing subagents/commands unless it adds reusable procedural knowledge.

## Installation Rules

- Install project-local skill copies under `.codebuddy/skills/<name>/SKILL.md`, `.codex/skills/<name>/SKILL.md`, and `.opencode/skills/<name>/SKILL.md` when the skill is meant to be generally available.
- Keep the three platform skill directories synchronized for shared project skills; platform-specific skills must be explicitly justified and documented.
- Keep skill names lowercase hyphen-case and matching directory names.
- Keep `SKILL.md` concise; move large references into supporting files only when necessary.
- Adapt external ideas to project rules instead of blindly copying generic instructions.
- Document sources and rejection reasons in `docs/AI协作/AI技能资源评估.md` when doing a resource sweep.
- Do not install broad external vendor directories, hooks, plugin scaffolds, or bulk subagents. Extract only the useful procedure into a project-owned skill.

## Safety Checks

- Do not install unknown scripts, hooks, plugins, or MCP servers with write/network access without explicit justification.
- Do not store tokens, local absolute private paths, or user-level secrets in repo config.
- If a resource changes `.opencode/`, remind the user to restart OpenCode; if it changes `.codex/` or `.codebuddy/`, note that new sessions may be needed for those tools to reload project files.

## After Installation

- Update `CLAUDE.md`, `CODEX.md`, `OPENCODE.md`, `.codebuddy/`, `.codex/`, `.opencode/`, `docs/AI协作/README.md`, `docs/AI协作/工具适配指南.md`, `docs/AI导航.md`, and AI memory as needed.
- Run JSON validation, docs health check, and whitespace diff check.
